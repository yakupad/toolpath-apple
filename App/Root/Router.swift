import CNCKit
import CNCRender
import Foundation
import Observation
import SwiftData
import UniformTypeIdentifiers

enum AppTab: Hashable {
    case workshop, jobs, calculate, library, ask
}

/// App-wide navigation state (the coordinator in MVVM-C terms).
@MainActor
@Observable
final class Router {
    var tab: AppTab = .workshop
    var jobsPath: [UUID] = []
    var isImporting = false
    var showSettings = false
    var showPaywall = false
    var importError: String?
    /// Files opened from outside (Files, AirDrop, Finder) before a model
    /// context was available.
    var pendingURLs: [URL] = []

    let analyses = AnalysisStore()

    func importFile(at url: URL) {
        pendingURLs.append(url)
    }

    /// Reads the files, saves them as jobs and opens the last one.
    func consumePending(into context: ModelContext) {
        guard !pendingURLs.isEmpty else { return }
        let urls = pendingURLs
        pendingURLs.removeAll()
        var lastID: UUID?
        for url in urls {
            do {
                let job = try JobImporter.makeJob(from: url)
                context.insert(job)
                Telemetry.log(.jobImported)
                analyses.load(job, machine: nil)
                lastID = job.id
            } catch {
                importError = error.localizedDescription
            }
        }
        try? context.save()
        if let lastID { open(job: lastID) }
    }

    func open(job id: UUID) {
        guard tab != .jobs else {
            jobsPath = [id]
            return
        }
        // Switch tabs first: on macOS the sidebar tab's navigation stack
        // resets a path set before it is on screen.
        tab = .jobs
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            jobsPath = [id]
        }
    }
}

enum JobImporter {
    static let contentTypes: [UTType] = [UTType("com.yakupad.toolpath.gcode") ?? .plainText, .plainText, .text]
    static let maxBytes = 50 * 1024 * 1024

    enum ImportError: LocalizedError {
        case tooLarge, unreadable
        var errorDescription: String? {
            switch self {
            case .tooLarge: String(localized: "This file is larger than 50 MB.")
            case .unreadable: String(localized: "This file couldn't be read as G-code text.")
            }
        }
    }

    static func makeJob(from url: URL) throws -> JobFile {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard data.count <= maxBytes else { throw ImportError.tooLarge }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ImportError.unreadable
        }
        return JobFile(name: url.lastPathComponent, content: text)
    }

    static func sampleJob() -> JobFile {
        JobFile(name: "sample_sign.nc", content: SampleProgram.sign)
    }

    static func latheSampleJob() -> JobFile {
        JobFile(name: "sample_lathe.nc", content: SampleProgram.lathe)
    }
}

/// Result of analyzing one job — computed off the main actor, cached by id.
struct JobAnalysis: Sendable {
    let document: GCodeDocument
    let findings: [Finding]
    let groups: [FindingGroup]
    let statistics: GCodeStatistics
    let geometry: ToolpathGeometry
    let timeline: GCodeTimeline
    let score: Int
    var kind: MachineKind { document.kind }

    /// How to read a lathe program, when the job is one.
    struct LatheOptions: Sendable {
        var diameterMode = true
        var maxRpm: Double?
        var setup = LatheSetup()
    }

    /// A file is a lathe program when it clearly looks like one, or when the
    /// active machine is a lathe and the file has no Y axis at all.
    static func isLathe(content: String, machineKind: MachineKind?) -> Bool {
        if LatheDetector.isLikelyLathe(content) { return true }
        guard machineKind == .lathe else { return false }
        return !LatheDetector.hasYAxis(content)
    }

    static func make(content: String, name: String, rapidRate: Double, envelope: MachineEnvelope?, lathe: LatheOptions? = nil) -> JobAnalysis {
        let document: GCodeDocument
        let findings: [Finding]
        if let lathe {
            document = LatheParser(diameterMode: lathe.diameterMode, machineMaxRpm: lathe.maxRpm).parse(content, fileName: name)
            findings = LatheAnalyzer().analyze(document, setup: lathe.setup)
        } else {
            document = GCodeParser().parse(content, fileName: name)
            findings = GCodeAnalyzer().analyze(document, machineEnvelope: envelope)
        }
        return JobAnalysis(
            document: document,
            findings: findings,
            groups: FindingGroup.group(findings),
            statistics: GCodeStatistics(document: document, rapidRateMmPerMin: rapidRate),
            geometry: ToolpathGeometry(document: document, findings: findings),
            timeline: GCodeTimeline(document: document, rapidRateMmPerMin: rapidRate),
            score: SafetyScore.compute(findings)
        )
    }

    var dangerCount: Int { groups.filter { $0.severity == .danger }.reduce(0) { $0 + $1.count } }
    var cautionCount: Int { groups.filter { $0.severity == .caution }.reduce(0) { $0 + $1.count } }
}

@MainActor
@Observable
final class AnalysisStore {
    private(set) var results: [UUID: JobAnalysis] = [:]
    private var inFlight: Set<UUID> = []

    func analysis(for job: JobFile, machine: Machine?) -> JobAnalysis? {
        if let cached = results[job.id] { return cached }
        load(job, machine: machine)
        return nil
    }

    func load(_ job: JobFile, machine: Machine?) {
        let rapidRate = machine?.rapidRate ?? GCodeStatistics.defaultRapidRateMmPerMin
        let envelope = machine?.checkTravelFromOrigin == true ? machine?.envelope : nil
        let id = job.id
        guard !inFlight.contains(id) else { return }
        inFlight.insert(id)
        let content = job.content, name = job.name
        let machineKind = machine?.kind
        let latheOptions = JobAnalysis.LatheOptions(
            diameterMode: machine?.kind == .lathe ? machine?.latheDiameterMode ?? true : true,
            maxRpm: machine?.kind == .lathe ? machine?.maxSpindleRpm : nil,
            setup: LatheSetup(maxDiameter: machine?.kind == .lathe ? machine?.maxTurningDiameter : nil, chuckZ: job.chuckZ)
        )
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                let lathe = JobAnalysis.isLathe(content: content, machineKind: machineKind) ? latheOptions : nil
                return JobAnalysis.make(content: content, name: name, rapidRate: rapidRate, envelope: envelope, lathe: lathe)
            }.value
            results[id] = result
            inFlight.remove(id)
            // Cache the summary on the model for lists and widgets.
            job.safetyScore = result.score
            job.dangerCount = result.dangerCount
            job.cautionCount = result.cautionCount
            job.estimatedMinutes = result.statistics.estimatedMachiningTimeMinutes
            job.toolCount = max(result.document.toolChanges.count, 1)
            job.kindRaw = result.kind.rawValue
            let bounds = result.document.cuttingBounds ?? result.document.bounds
            job.widthMm = bounds.width
            job.heightMm = bounds.height
            job.isAnalyzed = true
        }
    }

    func invalidate(_ id: UUID) { results[id] = nil }

    /// Machine settings changed: re-analyze on next open.
    func invalidateAll() { results.removeAll() }
}
