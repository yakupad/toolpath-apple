import CNCDesign
import CNCKit
import SwiftData
import SwiftUI

struct OutcomeView: View {
    let job: JobFile
    let minutes: Double
    let machine: Machine?
    let onDone: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var outcome: JobOutcome = .clean
    @State private var materialID = CuttingMaterial.catalog[0].id
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(TP.Palette.success)
                            .symbolEffect(.bounce, options: .nonRepeating)
                        Text("Job finished").font(.title2.bold())
                        Text("\(job.name) · \(Int(minutes.rounded())) min").foregroundStyle(TP.Palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                Section("How did it cut?") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(JobOutcome.allCases, id: \.self) { option in
                            Button {
                                outcome = option
                            } label: {
                                HStack {
                                    Circle().fill(option.color).frame(width: 12, height: 12)
                                    Text(option.title).font(.headline)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 14)
                                .frame(minHeight: TP.Metric.targetWorkshop)
                                .background(outcome == option ? option.color.opacity(0.15) : TP.Palette.cardRaised, in: .rect(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(outcome == option ? option.color : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .sensoryFeedback(.selection, trigger: outcome)
                }
                Section("Material") {
                    Picker("Material", selection: $materialID) {
                        ForEach(CuttingMaterial.catalog) { Text($0.title).tag($0.id) }
                    }
                }
                Section("Note") {
                    TextField("Optional", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle("Log job")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss(); onDone() }
                }
            }
        }
    }

    private func save() {
        let log = JobLog(jobName: job.name, outcome: outcome)
        log.jobFileID = job.id
        log.materialID = materialID
        log.machineID = machine?.id
        log.durationMinutes = minutes
        log.notes = notes
        context.insert(log)
        machine?.spindleHours += minutes / 60
        try? context.save()
        dismiss()
        onDone()
    }
}

extension JobOutcome {
    var title: LocalizedStringKey {
        switch self {
        case .clean: "Clean"
        case .chatter: "Chatter"
        case .brokenTool: "Broke a tool"
        case .roughFinish: "Rough finish"
        case .burning: "Burn marks"
        case .other: "Other"
        }
    }

    var color: Color {
        switch self {
        case .clean: TP.Palette.success
        case .chatter: TP.Palette.caution
        case .brokenTool: TP.Palette.danger
        case .roughFinish: TP.Viewer.arcCCW
        case .burning: TP.Palette.accent
        case .other: TP.Palette.textTertiary
        }
    }
}

extension CuttingMaterial {
    var title: LocalizedStringKey {
        switch id {
        case "aluminum_6061": "Aluminum (6061)"
        case "brass": "Brass"
        case "mild_steel_1018": "Mild steel (1018)"
        case "stainless_303_304": "Stainless steel (303/304)"
        case "acrylic_cast": "Acrylic (cast)"
        case "hdpe_delrin": "HDPE / Delrin"
        case "mdf": "MDF"
        case "plywood": "Plywood"
        case "hardwood": "Hardwood (oak, maple)"
        case "softwood": "Softwood (pine)"
        default: LocalizedStringKey(id)
        }
    }
}
