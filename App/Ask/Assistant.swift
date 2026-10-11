import CNCDesign
import CNCKit
import Foundation
import FoundationModels
import Observation

/// Bundled knowledge notes (same content the original app embedded).
enum Knowledge {
    static let base: KnowledgeBase = {
        let urls = Bundle.main.urls(forResourcesWithExtension: "md", subdirectory: nil) ?? []
        let files = urls.compactMap { url -> (String, String)? in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return (url.lastPathComponent, text)
        }
        return KnowledgeBase(markdownFiles: files.sorted { $0.0 < $1.0 })
    }()
}

// MARK: Tools — the model only extracts inputs; every number comes from CNCKit.

struct FeedsSpeedsTool: FoundationModels.Tool {
    let name = "calculate_feeds_and_speeds"
    let description = "Calculates conservative spindle RPM, feed rate, plunge rate, depth of cut and stepover for a cut. Always use this for any cutting numbers; never estimate them yourself."
    let maxSpindleRpm: Double

    @Generable
    struct Arguments {
        @Guide(description: "Workpiece material id", .anyOf(CuttingMaterial.catalog.map(\.id)))
        var material: String
        @Guide(description: "Tool diameter in millimeters (1/8 inch = 3.175, 1/4 inch = 6.35)")
        var toolDiameterMm: Double
        @Guide(description: "Number of flutes", .range(1...6))
        var flutes: Int
        @Guide(description: "Operation", .anyOf(["slotting", "profiling", "pocketing", "drilling"]))
        var operation: String
        @Guide(description: "True for carbide, false for high-speed steel")
        var carbide: Bool
    }

    func call(arguments: Arguments) async throws -> String {
        guard let material = CuttingMaterial.byID(arguments.material) else { return "Unknown material." }
        let input = FeedsInput(material: material,
                               toolDiameterMm: arguments.toolDiameterMm,
                               flutes: arguments.flutes,
                               toolMaterial: arguments.carbide ? .carbide : .hss,
                               operation: CutOperation(rawValue: arguments.operation) ?? .pocketing,
                               maxSpindleRpm: maxSpindleRpm)
        let r = FeedsCalculator.calculate(input)
        return """
        Spindle: \(Int(r.spindleRpm.rounded())) RPM\(r.cappedByMaxRpm ? " (capped at the machine maximum; feed recalculated)" : "")
        Feed: \(Int(r.feedRateMmPerMin.rounded())) mm/min
        Plunge: \(Int(r.plungeRateMmPerMin.rounded())) mm/min
        Max depth per pass: \(String(format: "%.1f", r.recommendedMaxDocMm)) mm
        Stepover: \(Int(r.recommendedStepoverFraction * 100))% of diameter
        Chip load: \(String(format: "%.3f", r.chipLoadMmPerTooth)) mm/tooth
        These are conservative starting points to test.
        """
    }
}

struct AlarmLookupTool: FoundationModels.Tool {
    let name = "decode_controller_alarm"
    let description = "Explains a GRBL, grblHAL or FluidNC alarm or error code, e.g. 'ALARM:9' or 'error:22'."

    @Generable
    struct Arguments {
        @Guide(description: "The code as written, for example 'ALARM:2' or 'error 22'")
        var code: String
    }

    func call(arguments: Arguments) async throws -> String {
        let messages = AlarmDecoder.decode(arguments.code)
        guard !messages.isEmpty else { return "No matching alarm or error code." }
        return messages.map { m in
            "\(m.kind == .alarm ? "ALARM" : "error"):\(m.code) — \(m.title). \(m.meaning) Steps: \(m.steps(machineHasHomingSwitches: true).joined(separator: " "))"
        }.joined(separator: "\n")
    }
}

struct KnowledgeSearchTool: FoundationModels.Tool {
    let name = "search_knowledge_base"
    let description = "Searches curated CNC notes on materials, tooling, troubleshooting, G-code and safety. Use it for any how/why question and base your answer on what it returns."

    @Generable
    struct Arguments {
        @Guide(description: "A short search query, e.g. 'chatter causes' or 'MDF burn marks'")
        var query: String
    }

    func call(arguments: Arguments) async throws -> String {
        let hits = Knowledge.base.search(arguments.query, limit: 3)
        guard !hits.isEmpty else { return "Nothing relevant in the knowledge base." }
        return hits.map { "## \($0.title)\n\($0.body)" }.joined(separator: "\n\n")
    }
}

// MARK: Conversation

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    var text: String
    var toolsUsed: [String] = []
}

@MainActor
@Observable
final class AssistantModel {
    private(set) var messages: [ChatMessage] = []
    private(set) var isResponding = false
    private(set) var errorText: String?
    /// Latest cloud allowance reported by the API.
    private(set) var cloudQuota: ToolpathAPI.Quota?
    /// Set when the cloud allowance ran out: the view offers Pro or a pack.
    private(set) var needsUpgrade = false
    private var session: LanguageModelSession?

    static var availability: SystemLanguageModel.Availability { SystemLanguageModel.default.availability }
    static var isOnDeviceModelAvailable: Bool {
        if case .available = availability { true } else { false }
    }

    func send(_ text: String, maxSpindleRpm: Double, hasHomingSwitches: Bool = true) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isResponding else { return }
        guard Self.isOnDeviceModelAvailable else {
            askCloud(trimmed, hasHomingSwitches: hasHomingSwitches)
            return
        }
        messages.append(ChatMessage(role: .user, text: trimmed))
        messages.append(ChatMessage(role: .assistant, text: ""))
        let index = messages.count - 1
        let session = self.session ?? makeSession(maxSpindleRpm: maxSpindleRpm)
        self.session = session
        let entriesBefore = session.transcript.count
        isResponding = true
        errorText = nil

        Task {
            do {
                for try await snapshot in session.streamResponse(to: trimmed) {
                    messages[index].text = snapshot.content
                }
                messages[index].toolsUsed = Self.toolNames(in: session.transcript, after: entriesBefore)
            } catch {
                errorText = String(localized: "The on-device assistant couldn't answer: \(error.localizedDescription)")
                if messages[index].text.isEmpty { messages.remove(at: index) }
            }
            isResponding = false
        }
    }

    func reset() {
        messages = []
        session = nil
        needsUpgrade = false
    }

    /// Without Apple Intelligence (unsupported device or region): the cloud
    /// assistant while the user has questions left, grounded in the same
    /// workshop notes; otherwise the built-in library answers.
    private func askCloud(_ question: String, hasHomingSwitches: Bool) {
        let history = messages.suffix(6).map { ToolpathAPI.Turn(role: $0.role == .user ? "user" : "assistant", text: $0.text) }
        messages.append(ChatMessage(role: .user, text: question))
        messages.append(ChatMessage(role: .assistant, text: ""))
        let index = messages.count - 1
        isResponding = true
        errorText = nil
        let notes = Knowledge.base.search(OfflineAnswer.expand(question), limit: 3).map { "## \($0.title)\n\($0.body)" }

        Task {
            do {
                let reply = try await ToolpathAPI.ask(question: question, history: history, context: notes,
                                                      locale: Locale.current.identifier)
                messages[index] = ChatMessage(role: .assistant, text: reply.answer, toolsUsed: ["cloud_assistant"])
                cloudQuota = reply.quota
                needsUpgrade = false
            } catch let ToolpathAPI.APIError.quotaExhausted(quota) {
                cloudQuota = quota ?? cloudQuota
                needsUpgrade = true
                messages[index] = OfflineAnswer.compose(for: question, hasHomingSwitches: hasHomingSwitches)
            } catch {
                // Offline or the service is busy: the library still answers.
                messages[index] = OfflineAnswer.compose(for: question, hasHomingSwitches: hasHomingSwitches)
            }
            isResponding = false
        }
    }

    private func makeSession(maxSpindleRpm: Double) -> LanguageModelSession {
        LanguageModelSession(
            tools: [FeedsSpeedsTool(maxSpindleRpm: maxSpindleRpm), AlarmLookupTool(), KnowledgeSearchTool()],
            instructions: """
            You are Toolpath's workshop assistant for hobby CNC routers and desktop mills (3018, Shapeoko, Onefinity, LongMill, X-Carve).
            Be brief and practical: short paragraphs or numbered steps someone can follow at the machine.
            Never invent cutting numbers. For RPM, feed, depth or stepover always call calculate_feeds_and_speeds and repeat its numbers exactly.
            For alarm or error codes call decode_controller_alarm.
            For how/why questions call search_knowledge_base and base your answer on it. If it has nothing relevant, say you are not sure.
            Prefer conservative advice, and mention eye and ear protection or workholding when relevant.
            Answer in the language the user writes in.
            """
        )
    }

    private static func toolNames(in transcript: Transcript, after index: Int) -> [String] {
        var names: [String] = []
        for entry in transcript.dropFirst(index) {
            if case let .toolCalls(calls) = entry {
                for call in calls where !names.contains(call.toolName) { names.append(call.toolName) }
            }
        }
        return names
    }
}
