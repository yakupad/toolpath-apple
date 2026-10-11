import Foundation

public enum TurningOperation: String, Sendable, Codable, CaseIterable {
    case roughing, finishing, facing, grooving, threading

    /// Surface speed relative to roughing: finishing runs a little faster,
    /// grooving and threading much slower.
    var speedFactor: Double {
        switch self {
        case .roughing, .facing: 1.0
        case .finishing: 1.2
        case .grooving: 0.6
        case .threading: 0.35
        }
    }

    /// Conservative hobby-lathe feed per revolution before material scaling.
    var baseFeedPerRev: Double {
        switch self {
        case .roughing: 0.15
        case .finishing: 0.05
        case .facing: 0.10
        case .grooving: 0.03
        case .threading: 0
        }
    }
}

public struct TurningInput: Sendable, Hashable {
    public var material: CuttingMaterial
    /// Diameter being cut, in mm.
    public var diameterMm: Double
    public var toolMaterial: ToolMaterial
    public var operation: TurningOperation
    public var maxSpindleRpm: Double
    /// Thread pitch for threading, in mm.
    public var threadPitchMm: Double

    public init(material: CuttingMaterial, diameterMm: Double, toolMaterial: ToolMaterial, operation: TurningOperation,
                maxSpindleRpm: Double, threadPitchMm: Double = 1.0) {
        self.material = material
        self.diameterMm = diameterMm
        self.toolMaterial = toolMaterial
        self.operation = operation
        self.maxSpindleRpm = maxSpindleRpm
        self.threadPitchMm = threadPitchMm
    }
}

public struct TurningResult: Sendable, Hashable {
    public let surfaceSpeedMPerMin: Double
    public let idealRpm: Double
    public let spindleRpm: Double
    public let cappedByMaxRpm: Bool
    public let feedPerRevMm: Double
    public let feedMmPerMin: Double
    /// Depth of cut per pass (radius), 0 when it doesn't apply.
    public let depthOfCutMm: Double
}

/// Deterministic turning starting points for hobby lathes. Same approach as
/// `FeedsCalculator`: one conservative surface speed per material, RPM from
/// the diameter, capped by the machine, feed recomputed from the capped RPM.
public enum TurningCalculator {
    /// Carbide insert surface speed for turning, m/min.
    public static func surfaceSpeed(for material: CuttingMaterial) -> Double {
        switch material.id {
        case "aluminum_6061": 200
        case "brass": 150
        case "copper": 120
        case "mild_steel_1018": 100
        case "stainless_303_304": 70
        case "acrylic_cast", "polycarbonate", "solid_surface": 120
        case "machinable_wax": 100
        default:
            switch material.category {
            case .metalNonFerrous: 150
            case .metalFerrous: 90
            case .plastic: 140
            case .wood: 250
            case .composite: 60
            case .foam: 150
            }
        }
    }

    static func feedFactor(for material: CuttingMaterial) -> Double {
        if material.id == "stainless_303_304" { return 0.6 }
        switch material.category {
        case .metalFerrous: return 0.8
        case .composite: return 0.6
        case .wood: return 1.2
        case .foam: return 1.5
        default: return 1.0
        }
    }

    static func roughingDepth(for material: CuttingMaterial) -> Double {
        switch material.id {
        case "stainless_303_304": return 0.3
        case "mild_steel_1018": return 0.5
        case "copper": return 0.8
        default:
            switch material.category {
            case .metalNonFerrous, .plastic: return 1.0
            case .metalFerrous, .composite: return 0.3
            case .wood: return 1.5
            case .foam: return 3.0
            }
        }
    }

    /// HSS turns at roughly 40% of carbide's surface speed.
    static let hssSpeedFactor = 0.4

    public static func calculate(_ input: TurningInput) -> TurningResult {
        let toolFactor = input.toolMaterial == .carbide ? 1.0 : hssSpeedFactor
        let vc = surfaceSpeed(for: input.material) * toolFactor * input.operation.speedFactor
        let diameter = max(input.diameterMm, 0.5)
        let ideal = vc * 1000 / (.pi * diameter)
        let capped = input.maxSpindleRpm > 0 && ideal > input.maxSpindleRpm
        let rpm = capped ? input.maxSpindleRpm : ideal
        let feedPerRev = input.operation == .threading
            ? input.threadPitchMm
            : input.operation.baseFeedPerRev * feedFactor(for: input.material)
        let depth: Double
        switch input.operation {
        case .roughing: depth = roughingDepth(for: input.material)
        case .facing: depth = roughingDepth(for: input.material) / 2
        case .finishing: depth = input.material.category == .composite ? 0.1 : 0.2
        case .grooving, .threading: depth = 0
        }
        return TurningResult(surfaceSpeedMPerMin: rpm * .pi * diameter / 1000, idealRpm: ideal, spindleRpm: rpm,
                             cappedByMaxRpm: capped, feedPerRevMm: feedPerRev, feedMmPerMin: feedPerRev * rpm,
                             depthOfCutMm: depth)
    }
}
