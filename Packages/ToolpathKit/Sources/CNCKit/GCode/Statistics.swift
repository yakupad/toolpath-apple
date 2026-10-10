import Foundation

/// Deterministic statistics computed straight from a parsed document.
public struct GCodeStatistics: Sendable, Hashable {
    /// G-code doesn't encode the controller's rapid rate, so the machining
    /// time estimate assumes this unless a machine profile provides one.
    public static let defaultRapidRateMmPerMin = 3000.0

    public let bounds: GBounds
    public let travelDistanceMm: Double
    public let cutDistanceMm: Double
    public let rapidCount: Int
    public let cutCount: Int
    public let arcCount: Int
    /// Estimate: rapids at the assumed rapid rate, cuts at their feed rate.
    public let estimatedMachiningTimeMinutes: Double
    /// nil when no cutting move has a nonzero feed rate.
    public let minFeedRate: Double?
    public let maxFeedRate: Double?

    public init(document: GCodeDocument, rapidRateMmPerMin: Double = defaultRapidRateMmPerMin) {
        var travel = 0.0, cut = 0.0, minutes = 0.0
        var rapids = 0, cuts = 0, arcs = 0
        var minFeed: Double?, maxFeed: Double?

        for move in document.moves {
            let length = Tessellator.length(of: move)
            if move.isRapid {
                rapids += 1
                travel += length
                minutes += length / rapidRateMmPerMin
                continue
            }
            cuts += 1
            if move.isArc { arcs += 1 }
            cut += length
            if move.feedRate > 0 {
                minutes += length / move.feedRate
                minFeed = min(minFeed ?? move.feedRate, move.feedRate)
                maxFeed = max(maxFeed ?? move.feedRate, move.feedRate)
            }
        }

        bounds = document.bounds
        travelDistanceMm = travel
        cutDistanceMm = cut
        rapidCount = rapids
        cutCount = cuts
        arcCount = arcs
        estimatedMachiningTimeMinutes = minutes
        minFeedRate = minFeed
        maxFeedRate = maxFeed
    }
}
