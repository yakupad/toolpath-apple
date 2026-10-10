import Foundation

/// A point along the simulated toolpath at a moment in time.
public struct SimulationPoint: Sendable, Hashable {
    public let position: GPoint
    public let moveIndex: Int
    public let moveProgress: Double
}

/// Precomputed time axis for a document. Uses the same time assumptions as
/// `GCodeStatistics` so the simulation clock and the estimate always agree.
/// `position(at:)` is a binary search — O(log n) even for 100k+ moves.
public struct GCodeTimeline: Sendable {
    public struct Timing: Sendable, Hashable {
        public let moveIndex: Int
        public let startSeconds: Double
        public let durationSeconds: Double
        public var endSeconds: Double { startSeconds + durationSeconds }
    }

    public let timings: [Timing]
    public let totalDurationSeconds: Double
    private let moves: [GCodeMove]

    public init(document: GCodeDocument, rapidRateMmPerMin: Double = GCodeStatistics.defaultRapidRateMmPerMin) {
        var result: [Timing] = []
        result.reserveCapacity(document.moves.count)
        var elapsed = 0.0
        for move in document.moves {
            let rate = move.isRapid ? rapidRateMmPerMin : move.feedRate
            let duration = rate > 0 ? Tessellator.length(of: move) / rate * 60 : 0
            result.append(Timing(moveIndex: move.index, startSeconds: elapsed, durationSeconds: duration))
            elapsed += duration
        }
        timings = result
        totalDurationSeconds = elapsed
        moves = document.moves
    }

    public var isEmpty: Bool { timings.isEmpty }

    /// Start time of the move with the given index (e.g. a tool change).
    public func startTime(ofMove index: Int) -> Double? {
        timings.indices.contains(index) ? timings[index].startSeconds : nil
    }

    public func position(at seconds: Double) -> SimulationPoint {
        guard let first = moves.first else {
            return SimulationPoint(position: .zero, moveIndex: 0, moveProgress: 0)
        }
        let clamped = min(max(seconds, 0), totalDurationSeconds)
        if clamped <= 0 {
            return SimulationPoint(position: first.start, moveIndex: 0, moveProgress: 0)
        }
        var low = 0, high = timings.count - 1
        while low < high {
            let mid = (low + high) / 2
            if timings[mid].endSeconds < clamped { low = mid + 1 } else { high = mid }
        }
        let timing = timings[low]
        let move = moves[low]
        let progress = timing.durationSeconds > 0
            ? min(max((clamped - timing.startSeconds) / timing.durationSeconds, 0), 1)
            : 1
        return SimulationPoint(
            position: Tessellator.point(along: move, at: progress),
            moveIndex: move.index,
            moveProgress: progress
        )
    }
}
