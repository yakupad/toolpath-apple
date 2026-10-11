import CNCDesign
import CNCKit
import FoundationModels
import SwiftData
import SwiftUI

/// Search tab: alarm decoder and knowledge notes (offline, deterministic)
/// first; the on-device assistant for everything else.
struct AskView: View {
    @State private var query = ""
    @State private var assistant = AssistantModel()
    @State private var showAssistant = false
    @Query(filter: #Predicate<Machine> { $0.isActive }) private var activeMachines: [Machine]

    private let suggestions = ["ALARM:9", "Burn marks on MDF", "Chatter in aluminum", "error:22"]

    var body: some View {
        let alarms = AlarmDecoder.decode(query)
        let notes = query.count > 2 ? Knowledge.base.search(query, limit: 3) : []
        NavigationStack {
            List {
                if query.isEmpty {
                    Section("Try") {
                        ForEach(suggestions, id: \.self) { s in
                            Button(s) { query = s }
                        }
                    }
                }
                ForEach(alarms) { message in
                    Section {
                        AlarmCard(message: message, hasHomingSwitches: activeMachines.first?.hasHomingSwitches ?? true)
                    }
                }
                if !notes.isEmpty {
                    Section("From the workshop notes") {
                        ForEach(notes) { note in
                            DisclosureGroup {
                                Text(note.body).font(.subheadline)
                            } label: {
                                Label(note.title, systemImage: "book.closed")
                            }
                        }
                    }
                }
                if !query.isEmpty {
                    Section {
                        Button {
                            showAssistant = true
                            assistant.send(query, maxSpindleRpm: activeMachines.first?.maxSpindleRpm ?? 24_000)
                        } label: {
                            Label("Ask the assistant: “\(query)”", systemImage: "sparkles")
                        }
                    } footer: {
                        if AssistantModel.isOnDeviceModelAvailable {
                            Text("Runs on your device with Apple Intelligence. Cutting numbers always come from the calculator.")
                        } else {
                            Text("Answers come from the built-in workshop library. Cutting numbers always come from the calculator.")
                        }
                    }
                }
                if !assistant.messages.isEmpty {
                    Section {
                        Button("Continue conversation") { showAssistant = true }
                    }
                }
            }
            .navigationTitle("Ask")
            .searchable(text: $query, prompt: Text("Alarm code or question"))
            .navigationDestination(isPresented: $showAssistant) {
                AssistantView(model: assistant, maxSpindleRpm: activeMachines.first?.maxSpindleRpm ?? 24_000)
            }
        }
    }
}

struct AssistantView: View {
    let model: AssistantModel
    let maxSpindleRpm: Double
    @Environment(Store.self) private var store
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            if case let .unavailable(reason) = AssistantModel.availability {
                CloudAssistantBanner(quota: model.cloudQuota ?? store.cloudQuota, reason: Self.text(for: reason))
            }
            conversation
        }
        .onChange(of: model.cloudQuota) { _, quota in
            if let quota { store.updateCloudQuota(quota) }
        }
        .navigationTitle("Assistant")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New chat", systemImage: "square.and.pencil") { model.reset() }
                    .disabled(model.messages.isEmpty)
            }
        }
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(model.messages) { message in
                            MessageBubble(message: message).id(message.id)
                        }
                        if let error = model.errorText {
                            Text(error).font(.footnote).foregroundStyle(TP.Palette.danger)
                        }
                        if model.needsUpgrade {
                            UpgradeCard().id("upgrade")
                        }
                    }
                    .padding(TP.Metric.gutter)
                }
                .onChange(of: model.messages.last?.text) {
                    if let id = model.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            HStack(spacing: 10) {
                TextField("Ask about your machine…", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .rect(cornerRadius: 24))
                    .onSubmit(send)
                Button(action: send) {
                    Image(systemName: model.isResponding ? "ellipsis" : "arrow.up")
                        .font(.headline)
                        .frame(width: 48, height: 48)
                        .foregroundStyle(TP.Palette.onAccent)
                        .background(TP.Palette.accent, in: .circle)
                        .symbolEffect(.variableColor.iterative, isActive: model.isResponding)
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || model.isResponding)
                .accessibilityLabel(Text("Send"))
            }
            .padding(TP.Metric.gutter)
        }
    }

    private func send() {
        model.send(draft, maxSpindleRpm: maxSpindleRpm)
        draft = ""
    }

    static func text(for reason: SystemLanguageModel.Availability.UnavailableReason) -> LocalizedStringKey {
        switch reason {
        case .deviceNotEligible: "Apple Intelligence isn't available on this device or in your region."
        case .appleIntelligenceNotEnabled: "Turn on Apple Intelligence in Settings to use the on-device assistant."
        case .modelNotReady: "The on-device model is still downloading. Try again in a little while."
        @unknown default: "The on-device assistant isn't available right now."
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 6) {
                if !message.toolsUsed.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(message.toolsUsed, id: \.self) { name in
                            Label(Self.label(for: name), systemImage: Self.icon(for: name))
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(TP.Palette.success.opacity(0.14), in: .capsule)
                                .foregroundStyle(TP.Palette.success)
                        }
                    }
                }
                if message.text.isEmpty {
                    ProgressView().padding(.vertical, 4)
                } else {
                    Text(LocalizedStringKey(message.text))
                        .textSelection(.enabled)
                }
            }
            .padding(12)
            .background(message.role == .user ? TP.Palette.accent.opacity(0.9) : TP.Palette.card,
                        in: .rect(cornerRadius: 18))
            .foregroundStyle(message.role == .user ? TP.Palette.onAccent : TP.Palette.textPrimary)
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }

    static func label(for tool: String) -> LocalizedStringKey {
        switch tool {
        case "calculate_feeds_and_speeds": "Calculator"
        case "decode_controller_alarm": "Alarm table"
        case "cloud_assistant": "Cloud assistant"
        default: "Workshop notes"
        }
    }

    static func icon(for tool: String) -> String {
        switch tool {
        case "calculate_feeds_and_speeds": "gauge.with.dots.needle.67percent"
        case "decode_controller_alarm": "exclamationmark.triangle"
        case "cloud_assistant": "cloud"
        default: "book.closed"
        }
    }
}

struct AlarmCard: View {
    let message: ControllerMessage
    let hasHomingSwitches: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("\(message.kind == .alarm ? "ALARM" : "error"):\(message.code)")
                    .font(.tpValue(15, weight: .bold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(TP.Palette.caution.opacity(0.15), in: .rect(cornerRadius: 8))
                    .foregroundStyle(TP.Palette.caution)
                Text(message.title).font(.headline)
            }
            Text(message.meaning).font(.subheadline)
            if message.positionLost {
                Label("Position may be lost — re-home or re-zero before cutting.", systemImage: "location.slash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TP.Palette.danger)
            }
            let steps = message.steps(machineHasHomingSwitches: hasHomingSwitches)
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)").font(.tpValue(13, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(TP.Palette.cardRaised, in: .circle)
                    Text(step).font(.subheadline)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
