import CNCKit
import Foundation
import SwiftData

/// Backup, CSV export, import (Toolpath backups and the old CNC Maker
/// Assistant JSON files) and delete-all. The user's data is theirs: it can
/// always be taken out in an open format.
@MainActor
enum DataTransfer {
    // MARK: Backup format (versioned, plain Codable)

    struct Backup: Codable {
        var format = "toolpath-backup"
        var version = 1
        var exportedAt = Date.now
        var machines: [MachineDTO] = []
        var tools: [ToolDTO] = []
        var jobs: [JobDTO] = []
        var logs: [LogDTO] = []
        var recipes: [RecipeDTO] = []
        var stock: [StockDTO] = []
        /// Optional so backups made before custom materials still import.
        var materials: [MaterialDTO]? = []
    }

    struct MaterialDTO: Codable {
        var id: UUID, name: String, baseMaterialID: String, speedFactor: Double, chipLoadFactor: Double
    }

    struct MachineDTO: Codable {
        var id: UUID, name: String, presetID: String
        var travelX: Double, travelY: Double, travelZ: Double
        var minSpindleRpm: Double, maxSpindleRpm: Double, rapidRate: Double
        var controller: String, hasHomingSwitches: Bool, isActive: Bool, spindleHours: Double
    }

    struct ToolDTO: Codable {
        var id: UUID, nickname: String, diameterMm: Double, flutes: Int
        var material: String, shape: String, cuttingMinutes: Double
    }

    struct JobDTO: Codable {
        var id: UUID, name: String, content: String, importedAt: Date
    }

    struct LogDTO: Codable {
        var id: UUID, date: Date, jobName: String, materialID: String
        var toolID: UUID?, machineID: UUID?, recipeID: UUID?
        var outcome: String, notes: String, durationMinutes: Double, cost: Double
    }

    struct RecipeDTO: Codable {
        var id: UUID, name: String, materialID: String, toolID: UUID?, operation: String
        var spindleRpm: Double, feedRate: Double, plungeRate: Double, depthOfCut: Double, stepoverFraction: Double
        var settingsChangedAt: Date
    }

    struct StockDTO: Codable {
        var id: UUID, name: String, materialID: String
        var thicknessMm: Double, widthMm: Double, lengthMm: Double, unitCost: Double, quantity: Int
    }

    // MARK: Export

    static func backupFile(context: ModelContext) throws -> URL {
        var backup = Backup()
        backup.machines = try context.fetch(FetchDescriptor<Machine>()).map {
            MachineDTO(id: $0.id, name: $0.name, presetID: $0.presetID, travelX: $0.travelX, travelY: $0.travelY,
                       travelZ: $0.travelZ, minSpindleRpm: $0.minSpindleRpm, maxSpindleRpm: $0.maxSpindleRpm,
                       rapidRate: $0.rapidRate, controller: $0.controllerRaw, hasHomingSwitches: $0.hasHomingSwitches,
                       isActive: $0.isActive, spindleHours: $0.spindleHours)
        }
        backup.tools = try context.fetch(FetchDescriptor<Tool>()).map {
            ToolDTO(id: $0.id, nickname: $0.nickname, diameterMm: $0.diameterMm, flutes: $0.flutes,
                    material: $0.materialRaw, shape: $0.shapeRaw, cuttingMinutes: $0.cuttingMinutes)
        }
        backup.jobs = try context.fetch(FetchDescriptor<JobFile>()).map {
            JobDTO(id: $0.id, name: $0.name, content: $0.content, importedAt: $0.importedAt)
        }
        backup.logs = try context.fetch(FetchDescriptor<JobLog>()).map {
            LogDTO(id: $0.id, date: $0.date, jobName: $0.jobName, materialID: $0.materialID, toolID: $0.toolID,
                   machineID: $0.machineID, recipeID: $0.recipeID, outcome: $0.outcomeRaw, notes: $0.notes,
                   durationMinutes: $0.durationMinutes, cost: $0.cost)
        }
        backup.recipes = try context.fetch(FetchDescriptor<Recipe>()).map {
            RecipeDTO(id: $0.id, name: $0.name, materialID: $0.materialID, toolID: $0.toolID, operation: $0.operationRaw,
                      spindleRpm: $0.spindleRpm, feedRate: $0.feedRate, plungeRate: $0.plungeRate,
                      depthOfCut: $0.depthOfCut, stepoverFraction: $0.stepoverFraction, settingsChangedAt: $0.settingsChangedAt)
        }
        backup.stock = try context.fetch(FetchDescriptor<StockItem>()).map {
            StockDTO(id: $0.id, name: $0.name, materialID: $0.materialID, thicknessMm: $0.thicknessMm,
                     widthMm: $0.widthMm, lengthMm: $0.lengthMm, unitCost: $0.unitCost, quantity: $0.quantity)
        }
        backup.materials = try context.fetch(FetchDescriptor<CustomMaterial>()).map {
            MaterialDTO(id: $0.id, name: $0.name, baseMaterialID: $0.baseMaterialID,
                        speedFactor: $0.speedFactor, chipLoadFactor: $0.chipLoadFactor)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let url = FileManager.default.temporaryDirectory.appending(path: "Toolpath-backup-\(Date.now.formatted(.iso8601.year().month().day())).json")
        try encoder.encode(backup).write(to: url, options: .atomic)
        return url
    }

    static func jobLogCSV(context: ModelContext) throws -> URL {
        let logs = try context.fetch(FetchDescriptor<JobLog>(sortBy: [SortDescriptor(\.date)]))
        func field(_ s: String) -> String { "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" }
        var rows = ["date,job,material,outcome,minutes,cost,notes"]
        for log in logs {
            rows.append([log.date.formatted(.iso8601), field(log.jobName), log.materialID, log.outcomeRaw,
                         String(format: "%.1f", log.durationMinutes), String(format: "%.2f", log.cost), field(log.notes)]
                .joined(separator: ","))
        }
        let url = FileManager.default.temporaryDirectory.appending(path: "Toolpath-job-history.csv")
        try rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: Import

    struct ImportSummary {
        var machines = 0, tools = 0, jobs = 0, logs = 0, recipes = 0, stock = 0, materials = 0
        var total: Int { machines + tools + jobs + logs + recipes + stock + materials }
    }

    enum ImportError: LocalizedError {
        case unrecognized
        var errorDescription: String? {
            String(localized: "This file isn't a Toolpath backup or a CNC Maker Assistant export.")
        }
    }

    /// Imports a Toolpath backup or any of the old app's JSON files. Records
    /// already present (same id) are skipped, so importing twice is safe.
    static func importFile(at url: URL, into context: ModelContext) throws -> ImportSummary {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ImportError.unrecognized }

        if object["format"] as? String == "toolpath-backup" {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try importBackup(try decoder.decode(Backup.self, from: data), into: context)
        }
        var summary = ImportSummary()
        if object["profiles"] != nil || object["tools"] != nil {
            importLegacyLibrary(object, into: context, summary: &summary)
        } else if let entries = object["entries"] as? [[String: Any]] {
            if entries.contains(where: { $0["outcome"] != nil }) {
                importLegacyLog(entries, into: context, summary: &summary)
            } else {
                importLegacyStock(entries, into: context, summary: &summary)
            }
        } else if let imports = object["imports"] as? [[String: Any]] {
            for item in imports {
                guard let name = item["fileName"] as? String, let content = item["content"] as? String else { continue }
                context.insert(JobFile(name: name, content: content))
                summary.jobs += 1
            }
        } else {
            throw ImportError.unrecognized
        }
        try context.save()
        return summary
    }

    private static func existingIDs<T: PersistentModel>(_ type: T.Type, _ id: KeyPath<T, UUID>, in context: ModelContext) -> Set<UUID> {
        Set(((try? context.fetch(FetchDescriptor<T>())) ?? []).map { $0[keyPath: id] })
    }

    private static func importBackup(_ b: Backup, into context: ModelContext) throws -> ImportSummary {
        var s = ImportSummary()
        let materials = existingIDs(CustomMaterial.self, \.id, in: context)
        for m in b.materials ?? [] where !materials.contains(m.id) {
            let x = CustomMaterial(name: m.name, baseMaterialID: m.baseMaterialID)
            x.id = m.id; x.speedFactor = m.speedFactor; x.chipLoadFactor = m.chipLoadFactor
            context.insert(x); s.materials += 1
        }
        let machines = existingIDs(Machine.self, \.id, in: context)
        for m in b.machines where !machines.contains(m.id) {
            let x = Machine(name: m.name)
            x.id = m.id; x.presetID = m.presetID; x.travelX = m.travelX; x.travelY = m.travelY; x.travelZ = m.travelZ
            x.minSpindleRpm = m.minSpindleRpm; x.maxSpindleRpm = m.maxSpindleRpm; x.rapidRate = m.rapidRate
            x.controllerRaw = m.controller; x.hasHomingSwitches = m.hasHomingSwitches; x.spindleHours = m.spindleHours
            x.isActive = m.isActive && machines.isEmpty
            context.insert(x); s.machines += 1
        }
        let tools = existingIDs(Tool.self, \.id, in: context)
        for t in b.tools where !tools.contains(t.id) {
            let x = Tool(nickname: t.nickname, diameterMm: t.diameterMm, flutes: t.flutes)
            x.id = t.id; x.materialRaw = t.material; x.shapeRaw = t.shape; x.cuttingMinutes = t.cuttingMinutes
            context.insert(x); s.tools += 1
        }
        let jobs = existingIDs(JobFile.self, \.id, in: context)
        for j in b.jobs where !jobs.contains(j.id) {
            let x = JobFile(name: j.name, content: j.content)
            x.id = j.id; x.importedAt = j.importedAt
            context.insert(x); s.jobs += 1
        }
        let logs = existingIDs(JobLog.self, \.id, in: context)
        for l in b.logs where !logs.contains(l.id) {
            let x = JobLog(jobName: l.jobName, outcome: JobOutcome(rawValue: l.outcome) ?? .other)
            x.id = l.id; x.date = l.date; x.materialID = l.materialID; x.toolID = l.toolID; x.machineID = l.machineID
            x.recipeID = l.recipeID; x.notes = l.notes; x.durationMinutes = l.durationMinutes; x.cost = l.cost
            context.insert(x); s.logs += 1
        }
        let recipes = existingIDs(Recipe.self, \.id, in: context)
        for r in b.recipes where !recipes.contains(r.id) {
            let x = Recipe(name: r.name)
            x.id = r.id; x.materialID = r.materialID; x.toolID = r.toolID; x.operationRaw = r.operation
            x.spindleRpm = r.spindleRpm; x.feedRate = r.feedRate; x.plungeRate = r.plungeRate
            x.depthOfCut = r.depthOfCut; x.stepoverFraction = r.stepoverFraction; x.settingsChangedAt = r.settingsChangedAt
            context.insert(x); s.recipes += 1
        }
        let stock = existingIDs(StockItem.self, \.id, in: context)
        for st in b.stock where !stock.contains(st.id) {
            let x = StockItem(name: st.name)
            x.id = st.id; x.materialID = st.materialID; x.thicknessMm = st.thicknessMm; x.widthMm = st.widthMm
            x.lengthMm = st.lengthMm; x.unitCost = st.unitCost; x.quantity = st.quantity
            context.insert(x); s.stock += 1
        }
        try context.save()
        return s
    }

    /// Old app: machine_library.json ({profiles, tools, activeProfileId}).
    private static func importLegacyLibrary(_ object: [String: Any], into context: ModelContext, summary: inout ImportSummary) {
        let active = object["activeProfileId"] as? String
        let hasActive = ((try? context.fetch(FetchDescriptor<Machine>())) ?? []).contains(where: \.isActive)
        for p in object["profiles"] as? [[String: Any]] ?? [] {
            let m = Machine(name: p["name"] as? String ?? String(localized: "My machine"))
            m.travelX = p["maxX"] as? Double ?? m.travelX
            m.travelY = p["maxY"] as? Double ?? m.travelY
            if let minZ = p["minZ"] as? Double, let maxZ = p["maxZ"] as? Double { m.travelZ = max(abs(minZ), maxZ) }
            m.maxSpindleRpm = p["maxSpindleRpm"] as? Double ?? m.maxSpindleRpm
            m.isActive = !hasActive && (p["id"] as? String) == active
            context.insert(m); summary.machines += 1
        }
        for t in object["tools"] as? [[String: Any]] ?? [] {
            let tool = Tool(nickname: t["nickname"] as? String ?? String(localized: "New tool"),
                            diameterMm: t["diameterMm"] as? Double ?? 6.35,
                            flutes: t["flutes"] as? Int ?? 2,
                            material: (t["toolMaterial"] as? String) == "hss" ? .hss : .carbide)
            context.insert(tool); summary.tools += 1
        }
    }

    /// Old app: job_log.json ({entries:[{timestamp, outcome, ...}]}).
    private static func importLegacyLog(_ entries: [[String: Any]], into context: ModelContext, summary: inout ImportSummary) {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for e in entries {
            let outcome: JobOutcome = switch e["outcome"] as? String {
            case "success": .clean
            case "chatter": .chatter
            case "brokenTool": .brokenTool
            case "poorFinish": .roughFinish
            default: .other
            }
            let log = JobLog(jobName: e["sourceFileName"] as? String ?? String(localized: "Imported job"), outcome: outcome)
            if let ts = e["timestamp"] as? String { log.date = iso.date(from: ts) ?? ISO8601DateFormatter().date(from: ts) ?? log.date }
            log.materialID = e["materialId"] as? String ?? ""
            log.notes = [e["notes"] as? String, e["toolDescription"] as? String, e["machineDescription"] as? String]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            log.durationMinutes = e["durationMinutes"] as? Double ?? 0
            log.cost = e["estimatedCost"] as? Double ?? 0
            context.insert(log); summary.logs += 1
        }
    }

    /// Old app: material_inventory.json ({entries:[{materialId, description, remainingQuantity}]}).
    private static func importLegacyStock(_ entries: [[String: Any]], into context: ModelContext, summary: inout ImportSummary) {
        for e in entries {
            let item = StockItem(name: e["description"] as? String ?? String(localized: "New stock"))
            item.materialID = e["materialId"] as? String ?? ""
            item.quantity = Int((e["remainingQuantity"] as? Double ?? 0).rounded())
            context.insert(item); summary.stock += 1
        }
    }

    // MARK: Delete

    static func deleteAll(context: ModelContext) throws {
        try context.delete(model: JobFile.self)
        try context.delete(model: Machine.self)
        try context.delete(model: Tool.self)
        try context.delete(model: JobLog.self)
        try context.delete(model: Recipe.self)
        try context.delete(model: StockItem.self)
        try context.delete(model: MaintenanceTask.self)
        try context.delete(model: CustomMaterial.self)
        try context.save()
    }
}
