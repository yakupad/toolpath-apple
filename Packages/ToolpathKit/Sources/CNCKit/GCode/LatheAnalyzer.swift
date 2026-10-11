import Foundation

/// What the analyzer knows about the lathe and the setup.
public struct LatheSetup: Sendable, Hashable {
    /// Largest diameter the machine can turn (swing), if known.
    public var maxDiameter: Double?
    /// Axial position of the chuck jaws in program coordinates (negative,
    /// e.g. -45 when 45 mm of stock sticks out of the jaws), if known.
    public var chuckZ: Double?

    public init(maxDiameter: Double? = nil, chuckZ: Double? = nil) {
        self.maxDiameter = maxDiameter
        self.chuckZ = chuckZ
    }
}

/// Deterministic safety checks for lathe programs (document.kind == .lathe,
/// points in (axial, radius) form). Tracks how much stock is left along the
/// part so rapids between roughing passes aren't mistaken for crashes.
public struct LatheAnalyzer: Sendable {
    static let tolerance = 0.05
    static let binSize = 0.1

    public init() {}

    public func analyze(_ document: GCodeDocument, setup: LatheSetup = LatheSetup()) -> [Finding] {
        var findings: [Finding] = []
        func add(_ category: FindingCategory, _ severity: FindingSeverity, _ move: GCodeMove) {
            findings.append(Finding(id: "\(category.rawValue)-\(findings.count + 1)", category: category, severity: severity,
                                    moveIndex: move.index, sourceLine: move.sourceLine,
                                    startZ: move.start.x, endZ: move.end.x, end: move.end))
        }
        let cuts = document.moves.filter(\.isCutting)
        guard !cuts.isEmpty else { return findings }

        // Stock model: a cylinder from the face (Z0, or the highest cut) back
        // past the deepest cut, as wide as the widest cut.
        let stockRadius = cuts.flatMap { [$0.start.y, $0.end.y] }.max() ?? 0
        let faceZ = min(0, cuts.flatMap { [$0.start.x, $0.end.x] }.max() ?? 0)
        let deepestCut = cuts.flatMap { [$0.start.x, $0.end.x] }.min() ?? 0
        let binCount = max(Int(((faceZ - deepestCut) / Self.binSize).rounded(.up)) + 1, 1)
        var surface = [Double](repeating: stockRadius, count: binCount)
        func bin(_ z: Double) -> Int? {
            guard z <= faceZ + 1e-9, z >= deepestCut - 1e-9 else { return nil }
            return min(max(Int(((faceZ - z) / Self.binSize).rounded()), 0), binCount - 1)
        }
        func samples(_ move: GCodeMove) -> [GPoint] {
            let length = Tessellator.length(of: move)
            let steps = min(max(Int(length / (Self.binSize / 2)), 1), 20_000)
            return (0...steps).map { Tessellator.point(along: move, at: Double($0) / Double(steps)) }
        }

        var flaggedCss = false
        if let line = document.lathe?.cssWithoutLimitLine, let move = cuts.first(where: { $0.sourceLine >= line }) {
            let nearCentre = (document.lathe?.minimumCssRadius ?? .infinity) < 3
            add(.cssWithoutSpeedLimit, nearCentre ? .danger : .caution, move)
            flaggedCss = true
        }
        _ = flaggedCss

        for move in document.moves {
            if let maxDiameter = setup.maxDiameter, max(abs(move.end.y), abs(move.start.y)) * 2 > maxDiameter + Self.tolerance {
                add(.exceedsSwing, .danger, move)
            }
            if let chuckZ = setup.chuckZ, min(move.start.x, move.end.x) < chuckZ + 0.5 {
                add(.chuckCollision, .danger, move)
            } else if setup.chuckZ == nil, move.isRapid, move.end.x < deepestCut - 5 {
                add(.chuckCollision, .caution, move)
            }

            if move.isRapid {
                // Skip the synthetic start point of the very first move.
                let points = move.index == 0 ? [move.end] : samples(move)
                if points.contains(where: { p in
                    guard let b = bin(p.x), p.x < faceZ - Self.tolerance else { return false }
                    return p.y < surface[b] - Self.tolerance && p.y > -Self.tolerance
                }) {
                    add(.latheRapidIntoStock, .danger, move)
                }
                continue
            }

            if !move.spindleOn { add(.missingSpindleStart, .danger, move) }
            if move.feedRate <= 0 { add(.zeroFeedRate, .caution, move) }
            if min(move.start.y, move.end.y) < -0.5 { add(.crossesCenterline, .caution, move) }
            for p in samples(move) {
                if let b = bin(p.x) { surface[b] = min(surface[b], max(p.y, 0)) }
            }
        }
        return findings
    }
}
