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
    /// `kind` picks lathe wording for the shared categories.
    public static func explain(_ group: FindingGroup, kind: MachineKind = .mill) -> Explanation {
        let f = group.first
        let line = f.sourceLine
        let count = group.count
        let start = f.startZ.formatted(.number.precision(.fractionLength(0...2)))
        let end = f.endZ.formatted(.number.precision(.fractionLength(0...2)))
        let safe = GCodeAnalyzer.safeClearanceZ.formatted()
        // Lathe positions: X as a diameter, Z axial.
        let xDia = (f.end.y * 2).formatted(.number.precision(.fractionLength(0...2)))
        let zPos = f.end.x.formatted(.number.precision(.fractionLength(0...2)))

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
        case .missingSpindleStart where kind == .lathe:
            return Explanation(
                title: String(localized: "Spindle is off while cutting", bundle: .module),
                whatHappened: String(localized: "\(count) cutting moves run before any M3/M4 spindle start. The first is on line \(line).", bundle: .module),
                whyItMatters: String(localized: "A tool fed into a stationary part rubs and chips. With feed per revolution (G95) the axis may not move at all and the program appears to hang.", bundle: .module),
                howToFix: String(localized: "Add M3 with a speed (G97 S… or G96 S… with a G50 limit) before the first cut, or enable spindle output in your post processor.", bundle: .module)
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
        case .latheRapidIntoStock:
            return Explanation(
                title: String(localized: "Rapid move into uncut stock", bundle: .module),
                whatHappened: count > 1
                    ? String(localized: "\(count) rapid moves pass through material that hasn't been cut yet. The first is on line \(line), ending at X\(xDia) Z\(zPos).", bundle: .module)
                    : String(localized: "Line \(line) is a rapid (G0) that passes through uncut stock, ending at X\(xDia) Z\(zPos).", bundle: .module),
                whyItMatters: String(localized: "At rapid speed the insert hits the spinning part head-on. It usually breaks the insert and can pull the part out of the chuck.", bundle: .module),
                howToFix: String(localized: "Check the X and Z zero and the stock diameter. Approach the part from outside the stock diameter and in front of the face, then feed in with G1.", bundle: .module)
            )
        case .chuckCollision:
            return Explanation(
                title: String(localized: "Tool travels toward the chuck", bundle: .module),
                whatHappened: f.severity == .danger
                    ? String(localized: "\(count) moves reach the chuck jaws you set. The first is on line \(line), at Z\(zPos).", bundle: .module)
                    : String(localized: "\(count) rapid moves go more than 5 mm past the deepest cut, toward the chuck. The first is on line \(line), at Z\(zPos).", bundle: .module),
                whyItMatters: String(localized: "The jaws stick out further than the part. Hitting them breaks the tool holder or the jaws and can throw the part.", bundle: .module),
                howToFix: String(localized: "Make the stock stick out further, or shorten the toolpath in CAM. Set the chuck position in the job so Toolpath can check it exactly.", bundle: .module)
            )
        case .cssWithoutSpeedLimit:
            return Explanation(
                title: String(localized: "Constant surface speed without an RPM limit", bundle: .module),
                whatHappened: String(localized: "Line \(line) cuts in G96 (constant surface speed) but the program never sets a maximum RPM with G50 S or G96 D.", bundle: .module),
                whyItMatters: String(localized: "In G96 the spindle speeds up as the tool moves toward the centre. Near X0 it heads for full speed, which can fling a lightly held part out of the chuck.", bundle: .module),
                howToFix: String(localized: "Add G50 S… (Fanuc style) or G96 D… (LinuxCNC) with a safe maximum before the first G96 cut, below what your chuck and part are rated for.", bundle: .module)
            )
        case .crossesCenterline:
            return Explanation(
                title: String(localized: "Tool crosses the centreline", bundle: .module),
                whatHappened: String(localized: "\(count) cutting moves go past X0 to the other side of the spindle axis. The first is on line \(line), at X\(xDia).", bundle: .module),
                whyItMatters: String(localized: "Past the centre the tool cuts with the wrong side of the insert and can be pulled under the part. Facing usually stops at or just past X0.", bundle: .module),
                howToFix: String(localized: "Check whether the program expects diameter or radius X values, and that facing ends at X0 or a little past it.", bundle: .module)
            )
        case .exceedsSwing:
            return Explanation(
                title: String(localized: "Larger than the lathe can swing", bundle: .module),
                whatHappened: String(localized: "\(count) moves go beyond your lathe's maximum diameter. The first is on line \(line), at X\(xDia).", bundle: .module),
                whyItMatters: String(localized: "The carriage or tool post will hit the bed or cover, or the part won't fit at all.", bundle: .module),
                howToFix: String(localized: "Check the stock diameter and that X values are diameters, not radii (G7/G8).", bundle: .module)
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
