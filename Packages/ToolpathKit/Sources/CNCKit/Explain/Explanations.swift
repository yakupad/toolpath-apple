import Foundation

/// Level-0 explanations: hand-written, deterministic, offline, free. Each
/// finding category has a title, what happened, why it matters and how to
/// fix it, filled with the finding's real numbers. Localized through the
/// package's String Catalog.
public struct Explanation: Sendable, Hashable {
    public let title: String
    public let whatHappened: String
    public let whyItMatters: String
    public let howToFix: String
}

public enum Explainer {
    public static func explain(_ group: FindingGroup) -> Explanation {
        let f = group.first
        let line = f.sourceLine
        let count = group.count
        let start = f.startZ.formatted(.number.precision(.fractionLength(0...2)))
        let end = f.endZ.formatted(.number.precision(.fractionLength(0...2)))
        let safe = GCodeAnalyzer.safeClearanceZ.formatted()

        switch group.category {
        case .rapidIntoStock:
            return Explanation(
                title: String(localized: "Rapid move plunges into stock", bundle: .module),
                whatHappened: count > 1
                    ? String(localized: "\(count) rapid moves go below the stock top. The first is on line \(line), dropping from Z\(start) to Z\(end).", bundle: .module)
                    : String(localized: "Line \(line) is a rapid (G0) that drops from Z\(start) to Z\(end), below the stock top.", bundle: .module),
                whyItMatters: String(localized: "Rapids run at full machine speed and ignore the feed rate. Driving the bit into material this way usually snaps it and can throw the workpiece.", bundle: .module),
                howToFix: String(localized: "Check your Z zero first. If it is right, set a safe retract height in your CAM and re-export so plunges use a G1 feed.", bundle: .module)
            )
        case .lowZClearance:
            return Explanation(
                title: String(localized: "Low clearance on rapid moves", bundle: .module),
                whatHappened: String(localized: "\(count) rapid moves travel sideways at only Z\(start), below \(safe) mm. The first is on line \(line).", bundle: .module),
                whyItMatters: String(localized: "At that height the bit can catch clamps, screws, tabs or an uneven stock surface while moving at full speed.", bundle: .module),
                howToFix: String(localized: "Raise the clearance or retract height in your CAM (5 mm is a common start), or keep clamps well outside the toolpath.", bundle: .module)
            )
        case .missingSpindleStart:
            return Explanation(
                title: String(localized: "Spindle is off while cutting", bundle: .module),
                whatHappened: String(localized: "\(count) cutting moves run before any M3/M4 spindle start. The first is on line \(line).", bundle: .module),
                whyItMatters: String(localized: "A stationary bit pushed into material breaks almost instantly. Machines with a manual router need it switched on by hand before Start.", bundle: .module),
                howToFix: String(localized: "If your router is switched by hand, turn it on before starting and confirm it here. Otherwise add M3 with a speed (e.g. M3 S18000) before the first cut, or enable spindle output in your post processor.", bundle: .module)
            )
        case .zeroFeedRate:
            return Explanation(
                title: String(localized: "No feed rate set", bundle: .module),
                whatHappened: String(localized: "\(count) cutting moves run without a feed rate (F). The first is on line \(line).", bundle: .module),
                whyItMatters: String(localized: "GRBL refuses these moves with error 22; other controllers may use an unexpected default speed.", bundle: .module),
                howToFix: String(localized: "Add an F value before the first cutting move, or re-export from CAM with feed rates enabled.", bundle: .module)
            )
        case .exceedsMachineLimits:
            return Explanation(
                title: String(localized: "Moves outside machine travel", bundle: .module),
                whatHappened: String(localized: "\(count) moves end outside your machine's travel, measured from machine zero. The first is on line \(line).", bundle: .module),
                whyItMatters: String(localized: "The machine will hit a hard limit or stall partway through the job.", bundle: .module),
                howToFix: String(localized: "Move your work zero so the whole job fits, or scale the design down. This check assumes your zero is near machine home.", bundle: .module)
            )
        }
    }
}

/// Rule-based "why" for a feeds result. Each reason is a fact about the
/// calculation, never advice the formula didn't produce.
public enum FeedsReason: Sendable, Hashable {
    case cappedByMaxRpm(ideal: Double, machineMax: Double)
    case chipLoadClamped
    case hssSlower
    case engagement(CutOperation)
    case drillingFormula
    case conservativeStart
}

public enum FeedsExplainer {
    public static func reasons(input: FeedsInput, result: FeedsResult) -> [FeedsReason] {
        var reasons: [FeedsReason] = []
        if result.cappedByMaxRpm {
            reasons.append(.cappedByMaxRpm(ideal: result.idealRpm, machineMax: input.maxSpindleRpm))
        }
        if result.chipLoadClamped { reasons.append(.chipLoadClamped) }
        if input.toolMaterial == .hss { reasons.append(.hssSlower) }
        if input.operation == .drilling {
            reasons.append(.drillingFormula)
        } else if input.operation != .pocketing {
            reasons.append(.engagement(input.operation))
        }
        reasons.append(.conservativeStart)
        return reasons
    }

    public static func text(_ reason: FeedsReason) -> String {
        switch reason {
        case let .cappedByMaxRpm(ideal, max):
            let i = Int(ideal.rounded()).formatted(), m = Int(max.rounded()).formatted()
            return String(localized: "The ideal speed for this bit is \(i) RPM, above your machine's \(m). The feed was recalculated from \(m) RPM so each tooth still takes the intended chip.", bundle: .module)
        case .chipLoadClamped:
            return String(localized: "The chip load was held inside the safe range for this material, so very small or very large bits don't get an unrealistic bite.", bundle: .module)
        case .hssSlower:
            return String(localized: "High-speed steel bits run at about half the surface speed of carbide, so the RPM is lower.", bundle: .module)
        case let .engagement(op):
            return op == .slotting
                ? String(localized: "Slotting engages the full bit width, so the chip load is reduced by 20% to control heat and deflection.", bundle: .module)
                : String(localized: "A light profiling pass engages less of the bit, so it can take a 30% heavier chip.", bundle: .module)
        case .drillingFormula:
            return String(localized: "Drilling uses feed per revolution instead of chip load per tooth.", bundle: .module)
        case .conservativeStart:
            return String(localized: "These are starting points for a typical hobby machine. Make a test cut, listen, and log how it went — your recipe learns from it.", bundle: .module)
        }
    }
}
