import CNCDesign
import CNCKit
import SwiftData
import SwiftUI

/// Search tab: alarm/error decoder (offline) first. The on-device assistant
/// is added in a later step.
struct AskView: View {
    @State private var query = ""
    @Query(filter: #Predicate<Machine> { $0.isActive }) private var activeMachines: [Machine]

    private let suggestions = ["ALARM:9", "ALARM:2", "error:22", "error:20"]

    var body: some View {
        let results = AlarmDecoder.decode(query)
        NavigationStack {
            List {
                if query.isEmpty {
                    Section("Try") {
                        ForEach(suggestions, id: \.self) { s in
                            Button(s) { query = s }
                        }
                    }
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
                ForEach(results) { message in
                    Section {
                        AlarmCard(message: message, hasHomingSwitches: activeMachines.first?.hasHomingSwitches ?? true)
                    }
                }
            }
            .navigationTitle("Ask")
            .searchable(text: $query, prompt: Text("Alarm code, e.g. ALARM:9"))
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
