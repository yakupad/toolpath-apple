import CNCDesign
import CNCKit
import SwiftData
import SwiftUI

// MARK: Recipes

struct RecipesList: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]

    var body: some View {
        List {
            if recipes.isEmpty {
                ContentUnavailableView("No recipes yet", systemImage: "list.bullet.rectangle",
                                       description: Text("Save one from Feeds & Speeds. Log jobs with it and Toolpath suggests adjustments from what actually happened."))
            }
            ForEach(recipes) { recipe in
                NavigationLink { RecipeDetailView(recipe: recipe) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recipe.name).font(.headline)
                        Text("\(Int(recipe.spindleRpm).formatted()) rpm · \(Int(recipe.feedRate).formatted()) mm/min · \(recipe.depthOfCut.formatted(.number.precision(.fractionLength(1)))) mm")
                            .font(.subheadline).foregroundStyle(TP.Palette.textSecondary)
                    }
                }
            }
            .onDelete { offsets in offsets.forEach { context.delete(recipes[$0]) } }
        }
        .navigationTitle("Cut recipes")
    }
}

struct RecipeDetailView: View {
    @Bindable var recipe: Recipe
    @Query(sort: \JobLog.date) private var allLogs: [JobLog]

    private var logs: [JobLog] { allLogs.filter { $0.recipeID == recipe.id } }
    private var currentLogs: [JobLog] { logs.filter { $0.date >= recipe.settingsChangedAt } }

    var body: some View {
        let advice = RecipeAdvisor.suggest(for: currentLogs.map(\.outcome))
        List {
            Section {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow {
                        ValueLabel("Spindle", value: Int(recipe.spindleRpm).formatted(), unit: "rpm", size: 20)
                        ValueLabel("Feed", value: Int(recipe.feedRate).formatted(), unit: "mm/min", size: 20)
                    }
                    GridRow {
                        ValueLabel("Depth / pass", value: recipe.depthOfCut.formatted(.number.precision(.fractionLength(1))), unit: "mm", size: 20)
                        ValueLabel("Stepover", value: Int(recipe.stepoverFraction * 100).formatted(), unit: "%", size: 20)
                    }
                }
            }
            Section("Track record") {
                if logs.isEmpty {
                    Text("No jobs logged with this recipe yet. Pick it when you log a job.")
                        .font(.subheadline).foregroundStyle(TP.Palette.textSecondary)
                } else {
                    HStack(spacing: 6) {
                        ForEach(logs.suffix(12)) { log in
                            RoundedRectangle(cornerRadius: 5).fill(log.outcome.color).frame(height: 36)
                        }
                    }
                }
            }
            Section("Suggestion") {
                AdviceView(advice: advice)
                if advice.changesAnything {
                    Button("Apply to recipe") { apply(advice) }
                }
            }
            Section("History") {
                ForEach(logs.reversed()) { log in
                    HStack {
                        Text(log.date.formatted(date: .abbreviated, time: .omitted))
                        Text(log.jobName).foregroundStyle(TP.Palette.textSecondary).lineLimit(1)
                        Spacer()
                        Text(log.outcome.title).foregroundStyle(log.outcome.color)
                    }
                    .font(.subheadline)
                }
            }
        }
        .navigationTitle(recipe.name)
    }

    private func apply(_ advice: RecipeAdjustment) {
        withAnimation {
            recipe.feedRate *= advice.feedFactor
            recipe.plungeRate *= advice.feedFactor
            recipe.depthOfCut *= advice.depthFactor
            recipe.stepoverFraction *= advice.stepoverFactor
            recipe.spindleRpm *= advice.rpmFactor
            recipe.settingsChangedAt = .now
        }
    }
}

struct AdviceView: View {
    let advice: RecipeAdjustment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(TP.Palette.textSecondary)
        }
    }

    private var title: LocalizedStringKey {
        switch advice.reason {
        case .stable: "Stable — keep these settings"
        case .chatter: "Chatter keeps showing up"
        case .brokenTool: "A tool broke with these settings"
        case .roughFinish: "Finish is rough"
        case .burning: "Burn marks — the bit is rubbing"
        case .notEnoughData: "Not enough runs yet"
        }
    }

    private var detail: LocalizedStringKey {
        func pct(_ factor: Double) -> Int { Int(((factor - 1) * 100).rounded()) }
        switch advice.reason {
        case let .stable(runs): return "Your last \(runs) runs were clean."
        case let .chatter(count): return "\(count) of your last 3 runs chattered. Lower feed \(pct(advice.feedFactor))% and depth \(pct(advice.depthFactor))%. Also check stickout and workholding."
        case .brokenTool: return "Lower feed \(pct(advice.feedFactor))% and depth \(pct(advice.depthFactor))%, and check the zero and clamps before the next run."
        case let .roughFinish(count): return "\(count) of your last 3 runs were rough. Lower stepover \(pct(advice.stepoverFactor))% and feed \(pct(advice.feedFactor))%."
        case let .burning(count): return "\(count) of your last 3 runs burned. Lower spindle speed \(pct(advice.rpmFactor))% so each tooth takes a bigger chip."
        case .notEnoughData: return "Log a few jobs with this recipe and Toolpath will suggest adjustments."
        }
    }
}

// MARK: Stock

struct StockList: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StockItem.name) private var items: [StockItem]

    var body: some View {
        let value = items.reduce(0) { $0 + $1.unitCost * Double($1.quantity) }
        let currency = Locale.current.currency?.identifier ?? "USD"
        List {
            Section {
                HStack {
                    ValueLabel("Stock value", value: value.formatted(.currency(code: currency)))
                    Spacer()
                    ValueLabel("Running low", value: items.filter { $0.quantity <= $0.lowStockThreshold }.count.formatted())
                }
            }
            ForEach(items) { item in
                NavigationLink { StockEditView(item: item) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.headline)
                            Text("\(item.thicknessMm.formatted()) mm · \(Int(item.widthMm))×\(Int(item.lengthMm)) · \(item.unitCost.formatted(.currency(code: currency)))")
                                .font(.subheadline).foregroundStyle(TP.Palette.textSecondary)
                        }
                        Spacer()
                        Text("× \(item.quantity)")
                            .font(.tpValue(17))
                            .foregroundStyle(item.quantity <= item.lowStockThreshold ? TP.Palette.caution : TP.Palette.textPrimary)
                    }
                }
            }
            .onDelete { offsets in offsets.forEach { context.delete(items[$0]) } }
        }
        .navigationTitle("Stock")
        .toolbar {
            Button("Add stock", systemImage: "plus") {
                let item = StockItem(name: String(localized: "New stock"))
                item.materialID = "plywood"
                item.quantity = 1
                context.insert(item)
            }
        }
    }
}

struct StockEditView: View {
    @Bindable var item: StockItem
    var body: some View {
        let currency = Locale.current.currency?.identifier ?? "USD"
        Form {
            TextField("Name", text: $item.name)
            Picker("Material", selection: $item.materialID) {
                ForEach(CuttingMaterial.catalog) { Text($0.title).tag($0.id) }
            }
            NumberField(title: "Thickness", value: $item.thicknessMm)
            NumberField(title: "Width", value: $item.widthMm)
            NumberField(title: "Length", value: $item.lengthMm)
            NumberField(title: "Cost per piece", value: $item.unitCost, unit: currency)
            Stepper("Quantity: \(item.quantity)", value: $item.quantity, in: 0...999)
            Stepper("Warn at: \(item.lowStockThreshold)", value: $item.lowStockThreshold, in: 0...99)
        }
        .navigationTitle(item.name)
    }
}

// MARK: Maintenance

struct MaintenanceView: View {
    @Environment(\.modelContext) private var context
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Query(filter: #Predicate<Machine> { $0.isActive }) private var activeMachines: [Machine]
    @Query(sort: \MaintenanceTask.intervalHours) private var allTasks: [MaintenanceTask]

    var body: some View {
        Group {
            if let machine = activeMachines.first {
                let tasks = allTasks.filter { $0.machineID == machine.id }
                    .sorted { $0.hoursUntilDue(machineHours: machine.spindleHours) < $1.hoursUntilDue(machineHours: machine.spindleHours) }
                List {
                    Section {
                        ValueLabel("\(machine.name) · spindle hours", value: machine.spindleHours.formatted(.number.precision(.fractionLength(1))), unit: "h", size: 34)
                    } footer: {
                        Text("Counted from logged jobs.")
                    }
                    if !store.isPro {
                        Section {
                            Button("Unlock maintenance reminders with Pro") { router.showPaywall = true }
                        }
                    }
                    Section("Schedule") {
                        ForEach(tasks) { task in
                            let due = task.hoursUntilDue(machineHours: machine.spindleHours)
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.name).font(.headline)
                                    Text("Every \(Int(task.intervalHours)) h").font(.caption).foregroundStyle(TP.Palette.textSecondary)
                                }
                                Spacer()
                                Text(due <= 0 ? String(localized: "Due now") : String(localized: "in \(due.formatted(.number.precision(.fractionLength(1)))) h"))
                                    .font(.subheadline.weight(due <= 2 ? .semibold : .regular))
                                    .foregroundStyle(due <= 2 ? TP.Palette.caution : TP.Palette.textSecondary)
                                Button("Done") {
                                    task.lastDoneAtHours = machine.spindleHours
                                    task.lastDoneDate = .now
                                }
                                .buttonStyle(.bordered)
                                .disabled(!store.isPro)
                            }
                        }
                    }
                }
                .onAppear {
                    if tasks.isEmpty { MaintenanceTask.defaults(for: machine).forEach(context.insert) }
                }
            } else {
                ContentUnavailableView("No active machine", systemImage: "cube.transparent",
                                       description: Text("Add your machine in Library › Machines."))
            }
        }
        .navigationTitle("Maintenance")
    }
}
