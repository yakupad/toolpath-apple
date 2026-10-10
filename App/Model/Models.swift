import CNCKit
import Foundation
import SwiftData

// CloudKit-compatible SwiftData models: every attribute has a default, no
// unique constraints, cross-model references are plain UUIDs (no required
// relationships). Synced through the user's private iCloud database.

@Model
final class JobFile {
    var id: UUID = UUID()
    var name: String = ""
    /// Raw G-code text. Stored externally so large files don't bloat the store.
    @Attribute(.externalStorage) var content: String = ""
    var importedAt: Date = Date.now
    var lastOpenedAt: Date = Date.now
    // Cached analysis summary for lists and widgets.
    var safetyScore: Int = 100
    var dangerCount: Int = 0
    var cautionCount: Int = 0
    var estimatedMinutes: Double = 0
    var toolCount: Int = 0
    var widthMm: Double = 0
    var heightMm: Double = 0
    var tagsRaw: String = ""

    init(name: String, content: String) {
        self.name = name
        self.content = content
    }
}

@Model
final class Machine {
    var id: UUID = UUID()
    var name: String = ""
    var presetID: String = ""
    var travelX: Double = 300
    var travelY: Double = 180
    var travelZ: Double = 45
    var minSpindleRpm: Double = 0
    var maxSpindleRpm: Double = 24_000
    var rapidRate: Double = 3_000
    var controllerRaw: String = ControllerKind.grbl.rawValue
    var hasHomingSwitches: Bool = true
    var checkTravelFromOrigin: Bool = false
    var isActive: Bool = false
    var spindleHours: Double = 0
    var createdAt: Date = Date.now

    init(name: String) { self.name = name }

    var envelope: MachineEnvelope {
        MachineEnvelope(maxX: travelX, maxY: travelY, minZ: -travelZ, maxZ: travelZ)
    }

    var context: MachineContext {
        MachineContext(envelope: envelope, minSpindleRpm: minSpindleRpm, maxSpindleRpm: maxSpindleRpm,
                       rapidRateMmPerMin: rapidRate, hasHomingSwitches: hasHomingSwitches)
    }

    var controller: ControllerKind {
        get { ControllerKind(rawValue: controllerRaw) ?? .grbl }
        set { controllerRaw = newValue.rawValue }
    }
}

@Model
final class Tool {
    var id: UUID = UUID()
    var nickname: String = ""
    var diameterMm: Double = 6.35
    var flutes: Int = 2
    var materialRaw: String = ToolMaterial.carbide.rawValue
    var shapeRaw: String = ToolShape.flat.rawValue
    var fluteLengthMm: Double = 0
    var vAngleDegrees: Double = 60
    var cuttingMinutes: Double = 0
    var createdAt: Date = Date.now

    init(nickname: String, diameterMm: Double, flutes: Int, shape: ToolShape = .flat, material: ToolMaterial = .carbide) {
        self.nickname = nickname
        self.diameterMm = diameterMm
        self.flutes = flutes
        self.shapeRaw = shape.rawValue
        self.materialRaw = material.rawValue
    }

    var shape: ToolShape {
        get { ToolShape(rawValue: shapeRaw) ?? .flat }
        set { shapeRaw = newValue.rawValue }
    }

    var material: ToolMaterial {
        get { ToolMaterial(rawValue: materialRaw) ?? .carbide }
        set { materialRaw = newValue.rawValue }
    }
}

@Model
final class JobLog {
    var id: UUID = UUID()
    var date: Date = Date.now
    var jobFileID: UUID?
    var jobName: String = ""
    var materialID: String = ""
    var toolID: UUID?
    var machineID: UUID?
    var recipeID: UUID?
    var outcomeRaw: String = JobOutcome.clean.rawValue
    var notes: String = ""
    var durationMinutes: Double = 0
    var cost: Double = 0

    init(jobName: String, outcome: JobOutcome) {
        self.jobName = jobName
        self.outcomeRaw = outcome.rawValue
    }

    var outcome: JobOutcome { JobOutcome(rawValue: outcomeRaw) ?? .other }
}

@Model
final class Recipe {
    var id: UUID = UUID()
    var name: String = ""
    var materialID: String = ""
    var toolID: UUID?
    var operationRaw: String = CutOperation.pocketing.rawValue
    var spindleRpm: Double = 0
    var feedRate: Double = 0
    var plungeRate: Double = 0
    var depthOfCut: Double = 0
    var stepoverFraction: Double = 0.4
    /// Logs before this date ran with different settings.
    var settingsChangedAt: Date = Date.now
    var createdAt: Date = Date.now

    init(name: String) { self.name = name }
}

@Model
final class StockItem {
    var id: UUID = UUID()
    var name: String = ""
    var materialID: String = ""
    var thicknessMm: Double = 0
    var widthMm: Double = 0
    var lengthMm: Double = 0
    var unitCost: Double = 0
    var quantity: Int = 0
    var lowStockThreshold: Int = 1

    init(name: String) { self.name = name }
}

enum AppSchema {
    static let models: [any PersistentModel.Type] = [JobFile.self, Machine.self, Tool.self, JobLog.self, Recipe.self, StockItem.self]
}
