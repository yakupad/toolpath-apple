import CNCDesign
import CNCKit
import SwiftData
import SwiftUI

/// Lathe speeds and feeds: RPM from surface speed and diameter, capped by
/// the lathe, feed per revolution and depth of cut by operation.
struct TurningView: View {
    @Query(filter: #Predicate<Machine> { $0.isActive }) private var activeMachines: [Machine]
    @Query(sort: \CustomMaterial.createdAt) private var customMaterials: [CustomMaterial]

    @AppStorage("turning.material") private var materialID = "aluminum_6061"
    @State private var diameter = 25.0
    @State private var toolMaterial: ToolMaterial = .carbide
    @State private var operation: TurningOperation = .roughing
    @State private var pitch = 1.5

    private var maxRpm: Double {
        activeMachines.first.map { $0.kind == .lathe ? $0.maxSpindleRpm : 3_000 } ?? 3_000
    }

    private var input: TurningInput {
        TurningInput(material: CuttingMaterial.resolve(materialID, custom: customMaterials) ?? CuttingMaterial.catalog[0],
                     diameterMm: diameter, toolMaterial: toolMaterial, operation: operation,
                     maxSpindleRpm: maxRpm, threadPitchMm: pitch)
    }

    var body: some View {
        let r = TurningCalculator.calculate(input)
        Form {
            Section("Material") {
                Picker("Material", selection: $materialID) { MaterialOptions() }
            }
            Section("Cut") {
                Picker("Operation", selection: $operation) {
                    Text("Rough").tag(TurningOperation.roughing)
                    Text("Finish").tag(TurningOperation.finishing)
                    Text("Face").tag(TurningOperation.facing)
                    Text("Groove").tag(TurningOperation.grooving)
                    Text("Thread").tag(TurningOperation.threading)
                }
                .pickerStyle(.segmented)
                NumberField(title: "Diameter", value: $diameter, unit: "mm")
                if operation == .threading {
                    NumberField(title: "Thread pitch", value: $pitch, unit: "mm")
                }
                Picker("Tool", selection: $toolMaterial) {
                    Text("Carbide insert").tag(ToolMaterial.carbide)
                    Text("HSS").tag(ToolMaterial.hss)
                }
                .pickerStyle(.segmented)
            }
            Section {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                    GridRow {
                        ValueLabel("Spindle", value: Int(r.spindleRpm.rounded()).formatted(), unit: "rpm", size: 26)
                        ValueLabel("Feed", value: r.feedPerRevMm.formatted(.number.precision(.fractionLength(2...3))), unit: "mm/rev", size: 26)
                    }
                    GridRow {
                        ValueLabel("Feed", value: Int(r.feedMmPerMin.rounded()).formatted(), unit: "mm/min", size: 20)
                        if r.depthOfCutMm > 0 {
                            ValueLabel("Depth / pass", value: r.depthOfCutMm.formatted(.number.precision(.fractionLength(1...2))), unit: "mm", size: 20)
                        } else {
                            ValueLabel("Surface speed", value: Int(r.surfaceSpeedMPerMin.rounded()).formatted(), unit: "m/min", size: 20)
                        }
                    }
                }
                .animation(.snappy, value: r)
            } header: {
                Label("Starting point · calculated", systemImage: "checkmark.seal")
            }
            Section("Why these numbers") {
                Text("Surface speed \(Int(r.surfaceSpeedMPerMin.rounded())) m/min on Ø\(diameter.formatted()) mm gives the spindle speed.")
                    .font(.subheadline)
                if r.cappedByMaxRpm {
                    Text("Capped at your lathe's \(Int(maxRpm).formatted()) RPM — the ideal speed for this small diameter is \(Int(r.idealRpm.rounded()).formatted()) RPM. Feed is recalculated from the capped speed.")
                        .font(.subheadline)
                }
                if toolMaterial == .hss {
                    Text("HSS turns at about 40% of carbide's surface speed.").font(.subheadline)
                }
                switch operation {
                case .facing:
                    Text("When facing, the diameter shrinks to zero: use G96 constant surface speed with a G50 RPM limit.").font(.subheadline)
                case .threading:
                    Text("The feed per revolution equals the thread pitch. A low speed leaves room to stop at a shoulder.").font(.subheadline)
                case .grooving:
                    Text("Grooving and parting load the whole tool width: low speed, light feed, plenty of coolant or air.").font(.subheadline)
                default:
                    EmptyView()
                }
                Text("Conservative values for hobby lathes. Test, then adjust in small steps.")
                    .font(.footnote).foregroundStyle(TP.Palette.textSecondary)
            }
        }
        .navigationTitle("Turning")
    }
}
