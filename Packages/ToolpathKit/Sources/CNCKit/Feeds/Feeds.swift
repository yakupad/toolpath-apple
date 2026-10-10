import Foundation

public enum MaterialCategory: String, Sendable, Codable, CaseIterable {
    case metalNonFerrous, metalFerrous, plastic, wood
}

/// A curated, conservative starting point per workpiece material. All values
/// assume carbide tooling; `ToolMaterial.speedMultiplier` adjusts for HSS.
public struct CuttingMaterial: Sendable, Hashable, Identifiable, Codable {
    /// Stable identifier — persisted and used in tool schemas, never the display name.
    public let id: String
    public let category: MaterialCategory
    /// Surface speed Vc (m/min) for carbide — one conservative value.
    public let cuttingSpeedMPerMin: Double
    /// Chip load per tooth = coefficient × diameter, clamped to the range.
    public let chipLoadCoefficient: Double
    public let chipLoadClampMinMm: Double
    public let chipLoadClampMaxMm: Double
    /// Max depth of cut per pass as a multiple of tool diameter.
    public let maxDocMultiplier: Double

    public static let catalog: [CuttingMaterial] = [
        .init(id: "aluminum_6061", category: .metalNonFerrous, cuttingSpeedMPerMin: 300, chipLoadCoefficient: 0.020, chipLoadClampMinMm: 0.02, chipLoadClampMaxMm: 0.15, maxDocMultiplier: 0.25),
        .init(id: "brass", category: .metalNonFerrous, cuttingSpeedMPerMin: 250, chipLoadCoefficient: 0.018, chipLoadClampMinMm: 0.02, chipLoadClampMaxMm: 0.12, maxDocMultiplier: 0.25),
        .init(id: "mild_steel_1018", category: .metalFerrous, cuttingSpeedMPerMin: 80, chipLoadCoefficient: 0.012, chipLoadClampMinMm: 0.015, chipLoadClampMaxMm: 0.08, maxDocMultiplier: 0.15),
        .init(id: "stainless_303_304", category: .metalFerrous, cuttingSpeedMPerMin: 50, chipLoadCoefficient: 0.010, chipLoadClampMinMm: 0.01, chipLoadClampMaxMm: 0.06, maxDocMultiplier: 0.10),
        .init(id: "acrylic_cast", category: .plastic, cuttingSpeedMPerMin: 200, chipLoadCoefficient: 0.020, chipLoadClampMinMm: 0.02, chipLoadClampMaxMm: 0.15, maxDocMultiplier: 0.30),
        .init(id: "hdpe_delrin", category: .plastic, cuttingSpeedMPerMin: 250, chipLoadCoefficient: 0.025, chipLoadClampMinMm: 0.02, chipLoadClampMaxMm: 0.18, maxDocMultiplier: 0.35),
        .init(id: "mdf", category: .wood, cuttingSpeedMPerMin: 400, chipLoadCoefficient: 0.030, chipLoadClampMinMm: 0.03, chipLoadClampMaxMm: 0.20, maxDocMultiplier: 0.40),
        .init(id: "plywood", category: .wood, cuttingSpeedMPerMin: 400, chipLoadCoefficient: 0.030, chipLoadClampMinMm: 0.03, chipLoadClampMaxMm: 0.20, maxDocMultiplier: 0.40),
        .init(id: "hardwood", category: .wood, cuttingSpeedMPerMin: 350, chipLoadCoefficient: 0.025, chipLoadClampMinMm: 0.03, chipLoadClampMaxMm: 0.18, maxDocMultiplier: 0.35),
        .init(id: "softwood", category: .wood, cuttingSpeedMPerMin: 450, chipLoadCoefficient: 0.035, chipLoadClampMinMm: 0.04, chipLoadClampMaxMm: 0.25, maxDocMultiplier: 0.45),
    ]

    public static func byID(_ id: String) -> CuttingMaterial? { catalog.first { $0.id == id } }
}

public enum Operation: String, Sendable, Codable, CaseIterable {
    case slotting, profiling, pocketing, drilling

    /// Radial engagement: full-width slotting runs hotter per tooth, a light
    /// contour can take a heavier bite. Unused for drilling.
    public var engagementMultiplier: Double {
        switch self {
        case .slotting: 0.8
        case .pocketing: 1.0
        case .profiling: 1.3
        case .drilling: 1.0
        }
    }
}

public struct FeedsInput: Sendable, Hashable, Codable {
    public var material: CuttingMaterial
    public var toolDiameterMm: Double
    public var flutes: Int
    public var toolMaterial: ToolMaterial
    public var operation: Operation
    /// RPM is capped here and the feed recomputed from the capped value.
    public var maxSpindleRpm: Double

    public init(material: CuttingMaterial, toolDiameterMm: Double, flutes: Int, toolMaterial: ToolMaterial, operation: Operation, maxSpindleRpm: Double) {
        self.material = material
        self.toolDiameterMm = toolDiameterMm
        self.flutes = flutes
        self.toolMaterial = toolMaterial
        self.operation = operation
        self.maxSpindleRpm = maxSpindleRpm
    }
}

public struct FeedsResult: Sendable, Hashable, Codable {
    public let spindleRpm: Double
    public let idealRpm: Double
    public let feedRateMmPerMin: Double
    public let plungeRateMmPerMin: Double
    public let chipLoadMmPerTooth: Double
    public let recommendedMaxDocMm: Double
    /// Suggested radial stepover for pocketing/profiling, as a fraction of diameter.
    public let recommendedStepoverFraction: Double
    /// True when the ideal RPM exceeded the machine max and feed was recomputed.
    public let cappedByMaxRpm: Bool
    /// True when the chip load hit the material's clamp (tiny or large tools).
    public let chipLoadClamped: Bool
}

/// The one deterministic source of truth for feed/speed math.
public enum FeedsCalculator {
    static let plungeRateFraction = 0.3
    static let drillFeedPerRevCoefficient = 0.02
    static let drillFeedPerRevRange = 0.02...0.3

    public static func calculate(_ input: FeedsInput) -> FeedsResult {
        let material = input.material
        let diameter = max(input.toolDiameterMm, 0.01)
        let vc = material.cuttingSpeedMPerMin * input.toolMaterial.speedMultiplier
        let idealRpm = vc * 1000 / (.pi * diameter)
        let rpm = min(idealRpm, input.maxSpindleRpm)

        let rawChip = material.chipLoadCoefficient * diameter
        let chipLoad = clamp(rawChip, material.chipLoadClampMinMm...material.chipLoadClampMaxMm)

        let feed: Double
        if input.operation == .drilling {
            feed = rpm * clamp(drillFeedPerRevCoefficient * diameter, drillFeedPerRevRange)
        } else {
            feed = rpm * Double(max(input.flutes, 1)) * chipLoad * input.operation.engagementMultiplier
        }

        let stepover: Double = switch input.operation {
        case .slotting: 1.0
        case .pocketing: 0.4
        case .profiling: 0.25
        case .drilling: 0
        }

        return FeedsResult(
            spindleRpm: rpm,
            idealRpm: idealRpm,
            feedRateMmPerMin: feed,
            plungeRateMmPerMin: feed * plungeRateFraction,
            chipLoadMmPerTooth: chipLoad,
            recommendedMaxDocMm: material.maxDocMultiplier * diameter,
            recommendedStepoverFraction: stepover,
            cappedByMaxRpm: rpm < idealRpm,
            chipLoadClamped: rawChip != chipLoad
        )
    }

    static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
