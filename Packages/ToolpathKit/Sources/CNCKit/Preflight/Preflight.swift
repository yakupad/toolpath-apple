import Foundation

/// What we know about the user's machine, for tailoring checks.
public struct MachineContext: Sendable, Hashable {
    public var envelope: MachineEnvelope
    public var minSpindleRpm: Double
    public var maxSpindleRpm: Double
    public var rapidRateMmPerMin: Double
    public var hasHomingSwitches: Bool

    public init(envelope: MachineEnvelope = .defaultHobby, minSpindleRpm: Double = 0, maxSpindleRpm: Double = 24_000, rapidRateMmPerMin: Double = GCodeStatistics.defaultRapidRateMmPerMin, hasHomingSwitches: Bool = true) {
        self.envelope = envelope
        self.minSpindleRpm = minSpindleRpm
        self.maxSpindleRpm = maxSpindleRpm
        self.rapidRateMmPerMin = rapidRateMmPerMin
        self.hasHomingSwitches = hasHomingSwitches
    }
}

public enum ZeroCorner: Sendable, Hashable {
    case lowerLeft, lowerRight, upperLeft, upperRight, center
    /// Work zero isn't at a corner or center of the toolpath.
    case custom(x: Double, y: Double)
}

public enum ZReference: Sendable, Hashable {
    /// Z0 on top of the stock (cuts go negative).
    case stockTop
    /// Z0 on the bed / spoilboard (cuts stay positive).
    case bedSurface
}

public enum PreflightSection: Int, Sendable, CaseIterable, Comparable {
    case setup, tooling, machine, safety
    public static func < (l: Self, r: Self) -> Bool { l.rawValue < r.rawValue }
}

public struct PreflightItem: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        case resolveDangers(count: Int)
        case zeroXY(ZeroCorner, width: Double, height: Double)
        case zeroZ(ZReference)
        case stockThickness(minimumMm: Double)
        case clampClearance(marginMm: Double)
        case toolLoaded(toolNumber: Int?, sourceLine: Int?)
        case toolChange(toolNumber: Int, sourceLine: Int, atSeconds: Double?)
        case spindleSpeed(rpm: Double, outOfRange: Bool)
        case fitsMachine(fits: Bool, width: Double, height: Double, depth: Double)
        case travelHeight(mm: Double)
        case airCut
        case personalProtection
        case dustCollection
    }

    public let id: String
    public let kind: Kind
    public let section: PreflightSection
    /// Critical items must be checked before Start unlocks.
    public let isCritical: Bool
    /// Items that need the user's attention (e.g. out-of-range RPM).
    public let isWarning: Bool
}

/// Generates the pre-run checklist from the file, the machine and the
/// analysis. Pure and deterministic — the same input always yields the same
/// list, in the same order.
public enum PreflightGenerator {
    public static let clampMarginMm = 10.0

    public static func items(document: GCodeDocument, findings: [Finding], machine: MachineContext) -> [PreflightItem] {
        var items: [PreflightItem] = []
        func add(_ id: String, _ kind: PreflightItem.Kind, _ section: PreflightSection, critical: Bool = false, warning: Bool = false) {
            items.append(PreflightItem(id: id, kind: kind, section: section, isCritical: critical, isWarning: warning))
        }

        let dangers = findings.filter { $0.severity == .danger }.count
        if dangers > 0 {
            add("dangers", .resolveDangers(count: dangers), .setup, critical: true, warning: true)
        }

        let cut = document.cuttingBounds ?? document.bounds
        add("zero-xy", .zeroXY(zeroCorner(of: cut), width: cut.width, height: cut.height), .setup, critical: true)

        let reference: ZReference = cut.minZ < -GCodeAnalyzer.epsilon ? .stockTop : .bedSurface
        add("zero-z", .zeroZ(reference), .setup, critical: true)
        let thickness = reference == .stockTop ? -cut.minZ : max(cut.maxZ, 0)
        if thickness > 0 {
            add("stock", .stockThickness(minimumMm: thickness), .setup, critical: true)
        }
        add("clamps", .clampClearance(marginMm: clampMarginMm), .setup)

        // Tooling
        let timeline = GCodeTimeline(document: document, rapidRateMmPerMin: machine.rapidRateMmPerMin)
        if let first = document.toolChanges.first {
            add("tool-\(first.toolNumber)", .toolLoaded(toolNumber: first.toolNumber, sourceLine: first.sourceLine), .tooling, critical: true)
            for change in document.toolChanges.dropFirst() {
                let at = change.firstMoveIndex.flatMap { timeline.startTime(ofMove: $0) }
                add("change-\(change.toolNumber)-\(change.sourceLine)",
                    .toolChange(toolNumber: change.toolNumber, sourceLine: change.sourceLine, atSeconds: at),
                    .tooling, critical: true)
            }
        } else {
            add("tool", .toolLoaded(toolNumber: nil, sourceLine: nil), .tooling, critical: true)
        }

        // Machine
        if let rpm = document.moves.map(\.spindleSpeed).max(), rpm > 0 {
            let outOfRange = rpm > machine.maxSpindleRpm || (machine.minSpindleRpm > 0 && rpm < machine.minSpindleRpm)
            add("rpm", .spindleSpeed(rpm: rpm, outOfRange: outOfRange), .machine, warning: outOfRange)
        }
        let all = document.bounds
        let fits = machine.envelope.fits(width: all.width, height: all.height, depth: all.depth)
        add("fit", .fitsMachine(fits: fits, width: all.width, height: all.height, depth: all.depth), .machine, critical: !fits, warning: !fits)
        if let travel = travelHeight(of: document) {
            add("travel-z", .travelHeight(mm: travel), .machine, warning: travel < GCodeAnalyzer.safeClearanceZ)
        }

        // Safety
        add("air-cut", .airCut, .safety)
        add("ppe", .personalProtection, .safety, critical: true)
        add("dust", .dustCollection, .safety)

        return items.sorted { $0.section < $1.section }
    }

    /// Where work zero sits relative to the cutting footprint.
    public static func zeroCorner(of b: GBounds) -> ZeroCorner {
        let tolerance = max(1.0, 0.02 * max(b.width, b.height))
        func near(_ v: Double) -> Bool { abs(v) <= tolerance }
        switch (near(b.minX), near(b.maxX), near(b.minY), near(b.maxY)) {
        case (true, _, true, _): return .lowerLeft
        case (_, true, true, _): return .lowerRight
        case (true, _, _, true): return .upperLeft
        case (_, true, _, true): return .upperRight
        default:
            let c = b.center
            return near(c.x) && near(c.y) ? .center : .custom(x: b.minX, y: b.minY)
        }
    }

    /// Lowest Z used for rapid XY travel — the height clamps must stay under.
    public static func travelHeight(of document: GCodeDocument) -> Double? {
        document.moves
            .filter { $0.isRapid && ($0.start.x != $0.end.x || $0.start.y != $0.end.y) && $0.index > 0 }
            .map { min($0.start.z, $0.end.z) }
            .min()
    }
}
