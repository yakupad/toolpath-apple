import CNCDesign
import CNCKit
import SwiftData
import SwiftUI

struct LibraryView: View {
    @Query private var machines: [Machine]
    @Query private var tools: [Tool]
    @Query private var recipes: [Recipe]
    @Query private var stock: [StockItem]
    @Query private var logs: [JobLog]
    @Query private var customMaterials: [CustomMaterial]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { MachinesList().navigationTitle("Machines") } label: {
                        LibraryRow(title: "Machines", systemImage: "cube.transparent", count: machines.count)
                    }
                    NavigationLink { ToolsList().navigationTitle("Tools") } label: {
                        LibraryRow(title: "Tools", systemImage: "wrench.adjustable", count: tools.count)
                    }
                    NavigationLink { RecipesList() } label: {
                        LibraryRow(title: "Cut recipes", systemImage: "list.bullet.rectangle", count: recipes.count)
                    }
                    NavigationLink { CustomMaterialsList() } label: {
                        LibraryRow(title: "Materials", systemImage: "square.stack.3d.down.right", count: customMaterials.count)
                    }
                    NavigationLink { StockList() } label: {
                        LibraryRow(title: "Stock", systemImage: "shippingbox", count: stock.count)
                    }
                }
                Section {
                    NavigationLink { MaintenanceView() } label: {
                        LibraryRow(title: "Maintenance", systemImage: "drop", count: nil)
                    }
                    NavigationLink { HistoryList().navigationTitle("History") } label: {
                        LibraryRow(title: "Job history", systemImage: "clock.arrow.circlepath", count: logs.count)
                    }
                }
            }
            .navigationTitle("Library")
        }
    }
}

struct LibraryRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let count: Int?

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            if let count { Text("\(count)").font(.tpValue(15, weight: .regular)).foregroundStyle(TP.Palette.textSecondary) }
        }
        .frame(minHeight: 36)
    }
}

struct MachinePreset: Identifiable, Hashable {
    let id: String
    let name: String
    let x: Double, y: Double, z: Double
    let maxRpm: Double
    let minRpm: Double

    /// Popular hobby machines, smallest first. Approximate travel and spindle
    /// ranges, used only to prefill a profile the user can edit.
    static let all: [MachinePreset] = [
        .init(id: "3018", name: "Genmitsu 3018", x: 300, y: 180, z: 45, maxRpm: 10_000, minRpm: 0),
        .init(id: "carveraair", name: "Makera Carvera Air", x: 300, y: 200, z: 120, maxRpm: 15_000, minRpm: 3_000),
        .init(id: "carvera", name: "Makera Carvera", x: 360, y: 240, z: 140, maxRpm: 15_000, minRpm: 3_000),
        .init(id: "4040", name: "Genmitsu 4040", x: 400, y: 400, z: 78, maxRpm: 10_000, minRpm: 0),
        .init(id: "foxalienmasuter", name: "FoxAlien Masuter Pro", x: 400, y: 400, z: 55, maxRpm: 10_000, minRpm: 0),
        .init(id: "twotreesttc450", name: "Two Trees TTC450", x: 460, y: 460, z: 80, maxRpm: 10_000, minRpm: 0),
        .init(id: "bobscnce4", name: "BobsCNC E4", x: 610, y: 610, z: 85, maxRpm: 30_000, minRpm: 10_000),
        .init(id: "lead1010", name: "OpenBuilds LEAD 1010", x: 730, y: 810, z: 90, maxRpm: 30_000, minRpm: 10_000),
        .init(id: "xcarve1000", name: "X-Carve 1000", x: 750, y: 750, z: 65, maxRpm: 30_000, minRpm: 10_000),
        .init(id: "longmillmk2_30x30", name: "LongMill MK2 30×30", x: 792, y: 845, z: 120, maxRpm: 30_000, minRpm: 10_000),
        .init(id: "onefinitywoodworker", name: "Onefinity Woodworker", x: 816, y: 816, z: 133, maxRpm: 30_000, minRpm: 10_000),
        .init(id: "shapeoko4xl", name: "Shapeoko 4 XL", x: 838, y: 432, z: 100, maxRpm: 30_000, minRpm: 10_000),
        .init(id: "shapeoko4xxl", name: "Shapeoko 4 XXL", x: 838, y: 838, z: 100, maxRpm: 30_000, minRpm: 10_000),
        .init(id: "onefinityjourneyman", name: "Onefinity Journeyman", x: 1220, y: 816, z: 133, maxRpm: 30_000, minRpm: 10_000),
        .init(id: "shapeoko5pro4x2", name: "Shapeoko 5 Pro 4×2", x: 1229, y: 610, z: 120, maxRpm: 24_000, minRpm: 10_000),
        .init(id: "longmillmk2_48x30", name: "LongMill MK2 48×30", x: 1270, y: 845, z: 120, maxRpm: 30_000, minRpm: 10_000),
        .init(id: "shapeoko5pro4x4", name: "Shapeoko 5 Pro 4×4", x: 1229, y: 1229, z: 120, maxRpm: 24_000, minRpm: 10_000),
    ]
}

struct MachinesList: View {
    @Environment(\.modelContext) private var context
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Query(sort: \Machine.createdAt) private var machines: [Machine]

    var body: some View {
        List {
            ForEach(machines) { machine in
                NavigationLink { MachineEditView(machine: machine) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(machine.name).font(.headline)
                            Text("\(Int(machine.travelX)) × \(Int(machine.travelY)) × \(Int(machine.travelZ)) mm · \(Int(machine.spindleHours * 10) / 10) h")
                                .font(.subheadline).foregroundStyle(TP.Palette.textSecondary)
                        }
                        Spacer()
                        if machine.isActive {
                            Text("Active").font(.caption.bold()).foregroundStyle(TP.Palette.accentText)
                        }
                    }
                }
                .swipeActions(edge: .leading) {
                    Button("Use") { activate(machine) }.tint(.orange)
                }
            }
            .onDelete { offsets in offsets.forEach { context.delete(machines[$0]) } }

            Menu {
                ForEach(MachinePreset.all) { preset in
                    Button(preset.name) { add(preset) }
                }
                Button("Other / DIY") { add(nil) }
            } label: {
                Label("Add machine", systemImage: "plus.circle.fill")
            }
        }
    }

    private func add(_ preset: MachinePreset?) {
        guard store.isPro || machines.count < Store.Limit.machines else {
            router.showPaywall = true
            return
        }
        let machine = Machine(name: preset?.name ?? String(localized: "My machine"))
        if let preset {
            machine.presetID = preset.id
            machine.travelX = preset.x
            machine.travelY = preset.y
            machine.travelZ = preset.z
            machine.maxSpindleRpm = preset.maxRpm
            machine.minSpindleRpm = preset.minRpm
        }
        context.insert(machine)
        if machines.allSatisfy({ !$0.isActive }) { machine.isActive = true }
    }

    private func activate(_ machine: Machine) {
        for m in machines { m.isActive = m.id == machine.id }
    }
}

struct MachineEditView: View {
    @Bindable var machine: Machine
    @Environment(Router.self) private var router

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $machine.name)
                Picker("Controller", selection: Binding(get: { machine.controller }, set: { machine.controller = $0 })) {
                    Text("GRBL").tag(ControllerKind.grbl)
                    Text("grblHAL").tag(ControllerKind.grblHAL)
                    Text("FluidNC").tag(ControllerKind.fluidNC)
                    Text("Other").tag(ControllerKind.other)
                }
                Toggle("Homing switches", isOn: $machine.hasHomingSwitches)
            }
            Section("Travel") {
                NumberField(title: "X", value: $machine.travelX)
                NumberField(title: "Y", value: $machine.travelY)
                NumberField(title: "Z", value: $machine.travelZ)
            }
            Section("Spindle & motion") {
                NumberField(title: "Min RPM", value: $machine.minSpindleRpm, unit: "rpm")
                NumberField(title: "Max RPM", value: $machine.maxSpindleRpm, unit: "rpm")
                NumberField(title: "Rapid rate", value: $machine.rapidRate, unit: "mm/min")
            }
            Section {
                NavigationLink { MachineMonitorView(machine: machine) } label: {
                    Label("Live monitor (beta)", systemImage: "dot.radiowaves.left.and.right")
                }
            } footer: {
                Text("For Wi-Fi controllers (FluidNC, grblHAL). Read-only.")
            }
            Section {
                Toggle("Check files against travel", isOn: $machine.checkTravelFromOrigin)
            } footer: {
                Text("Only turn this on if your work zero usually sits near machine home. Most CAM files are relative to the part, which this check can't see.")
            }
        }
        .navigationTitle(machine.name)
        .onDisappear { router.analyses.invalidateAll() }
    }
}

struct ToolsList: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Tool.createdAt) private var tools: [Tool]

    var body: some View {
        List {
            ForEach(tools) { tool in
                NavigationLink { ToolEditView(tool: tool) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tool.nickname).font(.headline)
                        Text("\(tool.diameterMm.formatted()) mm · \(tool.flutes) flute · \(tool.material == .carbide ? "Carbide" : "HSS") · \(Int(tool.cuttingMinutes / 60)) h")
                            .font(.subheadline).foregroundStyle(TP.Palette.textSecondary)
                    }
                }
            }
            .onDelete { offsets in offsets.forEach { context.delete(tools[$0]) } }
            Menu {
                Button("1/8\" flat, 2 flute") { context.insert(Tool(nickname: "1/8\" flat 2F", diameterMm: 3.175, flutes: 2)) }
                Button("1/4\" flat, 2 flute") { context.insert(Tool(nickname: "1/4\" flat 2F", diameterMm: 6.35, flutes: 2)) }
                Button("60° V-bit") { context.insert(Tool(nickname: "60° V-bit", diameterMm: 12.7, flutes: 2, shape: .vBit)) }
                Button("1/8\" ball nose") { context.insert(Tool(nickname: "1/8\" ball nose", diameterMm: 3.175, flutes: 2, shape: .ball)) }
                Button("Custom") { context.insert(Tool(nickname: String(localized: "New tool"), diameterMm: 6, flutes: 2)) }
            } label: {
                Label("Add tool", systemImage: "plus.circle.fill")
            }
        }
    }
}

struct ToolEditView: View {
    @Bindable var tool: Tool
    var body: some View {
        Form {
            TextField("Name", text: $tool.nickname)
            NumberField(title: "Diameter", value: $tool.diameterMm)
            Stepper("Flutes: \(tool.flutes)", value: $tool.flutes, in: 1...6)
            Picker("Shape", selection: Binding(get: { tool.shape }, set: { tool.shape = $0 })) {
                Text("Flat").tag(ToolShape.flat)
                Text("Ball").tag(ToolShape.ball)
                Text("V-bit").tag(ToolShape.vBit)
                Text("Compression").tag(ToolShape.compression)
                Text("Drill").tag(ToolShape.drill)
            }
            Picker("Material", selection: Binding(get: { tool.material }, set: { tool.material = $0 })) {
                Text("Carbide").tag(ToolMaterial.carbide)
                Text("HSS").tag(ToolMaterial.hss)
            }
            .pickerStyle(.segmented)
        }
        .navigationTitle(tool.nickname)
    }
}

struct HistoryList: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \JobLog.date, order: .reverse) private var logs: [JobLog]

    var body: some View {
        List {
            if logs.isEmpty {
                ContentUnavailableView("No jobs logged yet", systemImage: "clock.arrow.circlepath",
                                       description: Text("Finish a job run to log how it went."))
            }
            ForEach(logs) { log in
                HStack(spacing: 12) {
                    Circle().fill(log.outcome.color).frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(log.jobName).font(.headline)
                        Text("\(log.date.formatted(date: .abbreviated, time: .omitted)) · \(Int(log.durationMinutes)) min")
                            .font(.subheadline).foregroundStyle(TP.Palette.textSecondary)
                    }
                }
            }
            .onDelete { offsets in offsets.forEach { context.delete(logs[$0]) } }
        }
    }
}
