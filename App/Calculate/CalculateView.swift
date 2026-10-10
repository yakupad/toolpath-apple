import CNCDesign
import CNCKit
import SwiftData
import SwiftUI

struct CalculateView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { FeedsView() } label: {
                        Label("Feeds & Speeds", systemImage: "gauge.with.dots.needle.67percent")
                    }
                    NavigationLink { QuoteView() } label: {
                        Label("Quote a job", systemImage: "doc.text")
                    }
                }
                Section("Workshop calculators") {
                    NavigationLink { VBitView() } label: { Label("V-bit depth", systemImage: "chevron.down") }
                    NavigationLink { ChipThinningView() } label: { Label("Chip thinning", systemImage: "circle.lefthalf.filled") }
                    NavigationLink { ScallopView() } label: { Label("Scallop height", systemImage: "water.waves") }
                    NavigationLink { BoltCircleView() } label: { Label("Bolt circle", systemImage: "circle.dotted") }
                    NavigationLink { TapDrillView() } label: { Label("Tap drill", systemImage: "screwdriver") }
                    NavigationLink { UnitsView() } label: { Label("Units", systemImage: "arrow.left.arrow.right") }
                }
            }
            .navigationTitle("Calculate")
        }
    }
}

struct FeedsView: View {
    @Query(filter: #Predicate<Machine> { $0.isActive }) private var activeMachines: [Machine]
    @Query(sort: \Tool.createdAt) private var tools: [Tool]
    @Environment(\.modelContext) private var context
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Query private var recipes: [Recipe]

    @State private var materialID = "hardwood"
    @State private var diameter = 6.35
    @State private var flutes = 2
    @State private var toolMaterial: ToolMaterial = .carbide
    @State private var operation: CutOperation = .pocketing
    @State private var savedRecipe = false

    private var input: FeedsInput {
        FeedsInput(material: CuttingMaterial.byID(materialID) ?? CuttingMaterial.catalog[0],
                   toolDiameterMm: diameter, flutes: flutes, toolMaterial: toolMaterial,
                   operation: operation, maxSpindleRpm: activeMachines.first?.maxSpindleRpm ?? 24_000)
    }

    var body: some View {
        let result = FeedsCalculator.calculate(input)
        Form {
            Section("Material") {
                Picker("Material", selection: $materialID) {
                    ForEach(CuttingMaterial.catalog) { Text($0.title).tag($0.id) }
                }
            }
            Section("Tool") {
                if !tools.isEmpty {
                    Menu("From your library") {
                        ForEach(tools) { tool in
                            Button(tool.nickname) {
                                diameter = tool.diameterMm
                                flutes = tool.flutes
                                toolMaterial = tool.material
                            }
                        }
                    }
                }
                LabeledContent("Diameter") {
                    TextField("mm", value: $diameter, format: .number.precision(.fractionLength(0...3)))
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }
                Stepper("Flutes: \(flutes)", value: $flutes, in: 1...6)
                Picker("Tool material", selection: $toolMaterial) {
                    Text("Carbide").tag(ToolMaterial.carbide)
                    Text("HSS").tag(ToolMaterial.hss)
                }
                .pickerStyle(.segmented)
            }
            Section("CutOperation") {
                Picker("CutOperation", selection: $operation) {
                    Text("Pocket").tag(CutOperation.pocketing)
                    Text("Slot").tag(CutOperation.slotting)
                    Text("Profile").tag(CutOperation.profiling)
                    Text("Drill").tag(CutOperation.drilling)
                }
                .pickerStyle(.segmented)
            }
            Section {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                    GridRow {
                        ValueLabel("Spindle", value: Int(result.spindleRpm.rounded()).formatted(), unit: "rpm", size: 26)
                        ValueLabel("Feed", value: Int(result.feedRateMmPerMin.rounded()).formatted(), unit: "mm/min", size: 26)
                    }
                    GridRow {
                        ValueLabel("Plunge", value: Int(result.plungeRateMmPerMin.rounded()).formatted(), unit: "mm/min", size: 20)
                        ValueLabel("Depth / pass", value: result.recommendedMaxDocMm.formatted(.number.precision(.fractionLength(1))), unit: "mm", size: 20)
                    }
                    GridRow {
                        ValueLabel("Stepover", value: (result.recommendedStepoverFraction * 100).formatted(.number.precision(.fractionLength(0))), unit: "%", size: 20)
                        ValueLabel("Chip load", value: result.chipLoadMmPerTooth.formatted(.number.precision(.fractionLength(3))), unit: "mm", size: 20)
                    }
                }
                .animation(.snappy, value: result)
            } header: {
                Label("Starting point · calculated", systemImage: "checkmark.seal")
            }
            Section("Why these numbers") {
                ForEach(FeedsExplainer.reasons(input: input, result: result), id: \.self) { reason in
                    Text(FeedsExplainer.text(reason)).font(.subheadline)
                }
            }
            Section {
                Button(savedRecipe ? "Saved to recipes" : "Save as recipe") { saveRecipe(result) }
                    .disabled(savedRecipe)
            }
        }
        .navigationTitle("Feeds & Speeds")
        .onChange(of: input) { savedRecipe = false }
    }

    private func saveRecipe(_ result: FeedsResult) {
        guard store.isPro || recipes.count < Store.Limit.recipes else {
            router.showPaywall = true
            return
        }
        let recipe = Recipe(name: "\(CuttingMaterial.byID(materialID).map { String(localized: $0.titleResource) } ?? materialID) · \(diameter.formatted()) mm")
        recipe.materialID = materialID
        recipe.operationRaw = operation.rawValue
        recipe.spindleRpm = result.spindleRpm
        recipe.feedRate = result.feedRateMmPerMin
        recipe.plungeRate = result.plungeRateMmPerMin
        recipe.depthOfCut = result.recommendedMaxDocMm
        recipe.stepoverFraction = result.recommendedStepoverFraction
        context.insert(recipe)
        savedRecipe = true
    }
}

extension CuttingMaterial {
    var titleResource: LocalizedStringResource {
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
        default: LocalizedStringResource(stringLiteral: id)
        }
    }
}
