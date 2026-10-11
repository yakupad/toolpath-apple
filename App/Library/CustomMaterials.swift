import CNCDesign
import CNCKit
import SwiftData
import SwiftUI

/// Picker rows for every material: the curated catalog, then the user's own.
struct MaterialOptions: View {
    @Query(sort: \CustomMaterial.createdAt) private var custom: [CustomMaterial]

    var body: some View {
        Section {
            ForEach(CuttingMaterial.catalog) { Text($0.title).tag($0.id) }
        }
        if !custom.isEmpty {
            Section("Your materials") {
                ForEach(custom) { Text($0.name).tag($0.materialID) }
            }
        }
    }
}

extension CuttingMaterial {
    /// Resolves catalog ids and "custom:<uuid>" ids alike.
    static func resolve(_ id: String, custom: [CustomMaterial]) -> CuttingMaterial? {
        byID(id) ?? custom.first { $0.materialID == id }?.cuttingMaterial
    }

    static func name(for id: String, custom: [CustomMaterial]) -> String {
        if let material = byID(id) { return String(localized: material.titleResource) }
        return custom.first { $0.materialID == id }?.name ?? id
    }
}

struct CustomMaterialsList: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CustomMaterial.createdAt) private var materials: [CustomMaterial]
    @State private var editing: CustomMaterial?

    var body: some View {
        List {
            Section {
                ForEach(materials) { material in
                    Button { editing = material } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(material.name).font(.headline).foregroundStyle(TP.Palette.textPrimary)
                            Text("Based on \(CuttingMaterial.name(for: material.baseMaterialID, custom: []))")
                                .font(.caption).foregroundStyle(TP.Palette.textSecondary)
                        }
                    }
                }
                .onDelete { offsets in offsets.forEach { context.delete(materials[$0]) } }
            } footer: {
                Text("Your own materials use the starting values of the material they're based on, so feeds and speeds stay conservative.")
            }
        }
        .overlay {
            if materials.isEmpty {
                ContentUnavailableView("No materials yet", systemImage: "square.stack.3d.down.right",
                                       description: Text("Add walnut, a plastic you use often, or anything not in the list."))
            }
        }
        .navigationTitle("Materials")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add material", systemImage: "plus") {
                    let material = CustomMaterial(name: "", baseMaterialID: "hardwood")
                    context.insert(material)
                    editing = material
                }
            }
        }
        .sheet(item: $editing) { material in
            NavigationStack { CustomMaterialEditor(material: material) }
        }
    }
}

struct CustomMaterialEditor: View {
    @Bindable var material: CustomMaterial
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    var body: some View {
        let base = CuttingMaterial.byID(material.baseMaterialID) ?? CuttingMaterial.catalog[0]
        let tuned = material.cuttingMaterial ?? base
        Form {
            Section {
                TextField("Name, e.g. Walnut", text: $material.name)
                Picker("Behaves like", selection: $material.baseMaterialID) {
                    ForEach(CuttingMaterial.catalog) { Text($0.title).tag($0.id) }
                }
            } footer: {
                Text("Pick the closest material you know. Toolpath uses its conservative starting values.")
            }
            Section {
                DisclosureGroup("Advanced") {
                    VStack(alignment: .leading) {
                        Text("Cutting speed: \(Int((material.speedFactor * 100).rounded()))% · \(Int(tuned.cuttingSpeedMPerMin.rounded())) m/min")
                        Slider(value: $material.speedFactor, in: CuttingMaterial.customFactorRange, step: 0.05)
                    }
                    VStack(alignment: .leading) {
                        Text("Chip load: \(Int((material.chipLoadFactor * 100).rounded()))%")
                        Slider(value: $material.chipLoadFactor, in: CuttingMaterial.customFactorRange, step: 0.05)
                    }
                    Button("Reset to base values") {
                        material.speedFactor = 1
                        material.chipLoadFactor = 1
                    }
                }
            } footer: {
                Text("Limited to 50–150% of the base material. Raise values only after a successful test cut.")
            }
        }
        .navigationTitle(material.name.isEmpty ? String(localized: "New material") : material.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .disabled(material.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onDisappear {
            // A sheet closed without a name leaves nothing behind.
            if material.name.trimmingCharacters(in: .whitespaces).isEmpty { context.delete(material) }
        }
    }
}
