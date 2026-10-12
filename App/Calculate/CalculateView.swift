import CNCDesign
import CNCKit
import SwiftData
import SwiftUI

struct CalculateView: View {
    /// Screenshot runs can open a calculator directly with `-screen feeds|turning`.
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    NavigationLink { FeedsView() } label: {
                        Label("Feeds & Speeds", systemImage: "gauge.with.dots.needle.67percent")
                    }
                    NavigationLink { TurningView() } label: {
                        Label("Turning (lathe)", systemImage: "circle.circle")
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
            .task {
                if path.isEmpty, let screen = DebugFlags.value("-screen") {
                    try? await Task.sleep(for: .milliseconds(150))
                    path = [screen]
                }
            }
            .navigationDestination(for: String.self) { screen in
                if screen == "turning" { TurningView() } else { FeedsView() }
            }
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
    @Query(sort: \CustomMaterial.createdAt) private var customMaterials: [CustomMaterial]

    @State private var materialID = "hardwood"
    @State private var diameter = 6.35
    @State private var flutes = 2
    @State private var toolMaterial: ToolMaterial = .carbide
    @State private var operation: CutOperation = .pocketing
    @State private var savedRecipe = false

    private var input: FeedsInput {
        FeedsInput(material: CuttingMaterial.resolve(materialID, custom: customMaterials) ?? CuttingMaterial.catalog[0],
                   toolDiameterMm: diameter, flutes: flutes, toolMaterial: toolMaterial,
                   operation: operation, maxSpindleRpm: activeMachines.first?.maxSpindleRpm ?? 24_000)
    }

    var body: some View {
        let result = FeedsCalculator.calculate(input)
        Form {
            Section("Material") {
                Picker("Material", selection: $materialID) {
                    MaterialOptions()
                }
                NavigationLink { CustomMaterialsList() } label: {
                    Label("Your own materials", systemImage: "plus.circle")
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
            Section("Operation") {
                Picker("Operation", selection: $operation) {
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
        .onAppear { Telemetry.log(.feedsCalculated) }
        .onChange(of: input) { savedRecipe = false }
    }

    private func saveRecipe(_ result: FeedsResult) {
        guard store.isPro || recipes.count < Store.Limit.recipes else {
            router.showPaywall = true
            return
        }
        let recipe = Recipe(name: "\(CuttingMaterial.name(for: materialID, custom: customMaterials)) · \(diameter.formatted()) mm")
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
