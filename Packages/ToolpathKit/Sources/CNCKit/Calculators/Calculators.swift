import Foundation

public enum UnitConverter {
    public static let mmPerInch = 25.4
    public static func mmToInch(_ mm: Double) -> Double { mm / mmPerInch }
    public static func inchToMm(_ inch: Double) -> Double { inch * mmPerInch }
    public static func mmToThou(_ mm: Double) -> Double { mmToInch(mm) * 1000 }
    public static func thouToMm(_ thou: Double) -> Double { inchToMm(thou / 1000) }
    public static func mmPerMinToInchPerMin(_ v: Double) -> Double { mmToInch(v) }
    public static func inchPerMinToMmPerMin(_ v: Double) -> Double { inchToMm(v) }
}

public struct BoltHole: Sendable, Hashable {
    public let index: Int
    public let xMm: Double
    public let yMm: Double
}

public enum BoltCircle {
    /// Evenly spaced holes on a full circle. Fewer than 2 holes → empty.
    public static func holes(centerX: Double, centerY: Double, radius: Double, count: Int, startAngleDegrees: Double = 0) -> [BoltHole] {
        guard count >= 2 else { return [] }
        let step = 360.0 / Double(count)
        return (0..<count).map { i in
            let angle = (startAngleDegrees + Double(i) * step) * .pi / 180
            return BoltHole(index: i, xMm: centerX + radius * cos(angle), yMm: centerY + radius * sin(angle))
        }
    }
}

public enum ScallopHeight {
    /// Cusp height left by a ball-nose of `toolRadius` at `stepover`.
    public static func height(toolRadius r: Double, stepover s: Double) -> Double {
        if s >= 2 * r { return r }
        let half = s / 2
        return r - (r * r - half * half).squareRoot()
    }

    /// Stepover that leaves `targetHeight`, clamped to the tool diameter.
    public static func stepover(toolRadius r: Double, targetHeight h: Double) -> Double {
        let clamped = min(max(h, 0), r)
        return min(2 * (2 * r * clamped - clamped * clamped).squareRoot(), 2 * r)
    }
}

public enum VBit {
    /// Depth needed for a V-bit of `includedAngle` degrees to cut `width`.
    public static func depth(forWidth width: Double, includedAngleDegrees angle: Double) -> Double {
        let half = angle / 2 * .pi / 180
        guard tan(half) > 0 else { return 0 }
        return (width / 2) / tan(half)
    }

    /// Line width a V-bit cuts at `depth`.
    public static func width(atDepth depth: Double, includedAngleDegrees angle: Double) -> Double {
        2 * depth * tan(angle / 2 * .pi / 180)
    }
}

public enum ChipThinning {
    /// When radial engagement `ae` is below half the diameter, the actual chip
    /// is thinner than the programmed feed per tooth. Returns the factor to
    /// multiply feed by to restore the target chip load (1 at ae ≥ D/2).
    public static func feedFactor(toolDiameter d: Double, radialEngagement ae: Double) -> Double {
        guard d > 0, ae > 0, ae < d / 2 else { return 1 }
        return d / (2 * (d * ae - ae * ae).squareRoot())
    }
}

public enum ThreadStandard: String, Sendable, Codable { case metric, unc }

public struct ThreadSpec: Sendable, Hashable, Identifiable {
    public var id: String { designation }
    public let designation: String
    public let standard: ThreadStandard
    public let majorDiameterMm: Double
    public let pitchMm: Double

    /// ~75% thread engagement: major diameter − pitch.
    public var recommendedTapDrillMm: Double { majorDiameterMm - pitchMm }

    static func unc(_ name: String, _ majorInch: Double, _ tpi: Double) -> ThreadSpec {
        ThreadSpec(designation: name, standard: .unc, majorDiameterMm: majorInch * 25.4, pitchMm: 25.4 / tpi)
    }

    static func metric(_ name: String, _ major: Double, _ pitch: Double) -> ThreadSpec {
        ThreadSpec(designation: name, standard: .metric, majorDiameterMm: major, pitchMm: pitch)
    }

    public static let catalog: [ThreadSpec] = [
        metric("M2 x 0.4", 2, 0.4), metric("M2.5 x 0.45", 2.5, 0.45), metric("M3 x 0.5", 3, 0.5),
        metric("M4 x 0.7", 4, 0.7), metric("M5 x 0.8", 5, 0.8), metric("M6 x 1.0", 6, 1.0),
        metric("M8 x 1.25", 8, 1.25), metric("M10 x 1.5", 10, 1.5), metric("M12 x 1.75", 12, 1.75),
        unc("#4-40", 0.112, 40), unc("#6-32", 0.138, 32), unc("#8-32", 0.164, 32),
        unc("#10-24", 0.190, 24), unc("#10-32", 0.190, 32), unc("1/4-20", 0.25, 20),
        unc("5/16-18", 0.3125, 18), unc("3/8-16", 0.375, 16), unc("1/2-13", 0.5, 13),
    ]
}

/// Deterministic job quote: costs → price at a target margin.
public struct QuoteInput: Sendable, Hashable, Codable {
    public var materialCost: Double
    public var machineMinutes: Double
    public var machineHourlyRate: Double
    public var laborMinutes: Double
    public var laborHourlyRate: Double
    /// Marketplace fee as a fraction of the sale price (0.065 = 6.5%).
    public var feePercent: Double
    public var feeFixed: Double
    /// Profit as a fraction of total cost (0.6 = 60% markup).
    public var targetMargin: Double
    public var quantity: Int

    public init(materialCost: Double, machineMinutes: Double, machineHourlyRate: Double, laborMinutes: Double = 0, laborHourlyRate: Double = 0, feePercent: Double = 0, feeFixed: Double = 0, targetMargin: Double = 0.5, quantity: Int = 1) {
        self.materialCost = materialCost
        self.machineMinutes = machineMinutes
        self.machineHourlyRate = machineHourlyRate
        self.laborMinutes = laborMinutes
        self.laborHourlyRate = laborHourlyRate
        self.feePercent = feePercent
        self.feeFixed = feeFixed
        self.targetMargin = targetMargin
        self.quantity = quantity
    }
}

public struct QuoteResult: Sendable, Hashable {
    public let materialCost: Double
    public let machineCost: Double
    public let laborCost: Double
    /// Fees at the suggested price.
    public let fees: Double
    public let totalCost: Double
    public let suggestedUnitPrice: Double
    public let profitPerUnit: Double
}

public enum QuoteCalculator {
    public static func quote(_ input: QuoteInput) -> QuoteResult {
        let machine = input.machineHourlyRate / 60 * input.machineMinutes
        let labor = input.laborHourlyRate / 60 * input.laborMinutes
        let base = input.materialCost + machine + labor
        let wanted = base * (1 + max(input.targetMargin, 0))
        // price - fee% * price - fixed = wanted  →  price = (wanted + fixed) / (1 - fee%)
        let feeRate = min(max(input.feePercent, 0), 0.9)
        let price = (wanted + input.feeFixed) / (1 - feeRate)
        let fees = price * feeRate + input.feeFixed
        return QuoteResult(
            materialCost: input.materialCost,
            machineCost: machine,
            laborCost: labor,
            fees: fees,
            totalCost: base + fees,
            suggestedUnitPrice: price,
            profitPerUnit: price - base - fees
        )
    }
}
