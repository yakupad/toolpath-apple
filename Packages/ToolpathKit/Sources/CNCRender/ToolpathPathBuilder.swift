import CNCKit
import CoreGraphics
import SwiftUI

/// Builds one Path per stroke style for a frame. Points that land within a
/// fraction of a screen point of the previous emitted point are skipped, so
/// dense files (100k+ moves, tiny arc segments) stay cheap to draw without
/// visibly changing the result.
public enum ToolpathPathBuilder {
    public static let minimumStep: CGFloat = 0.6

    public static func build(
        geometry: ToolpathGeometry,
        projection p: Projection,
        filter: MoveFilter,
        limit: Int,
        cursor: SimulationPoint?
    ) -> [StrokeStyleKind: Path] {
        let kinds = StrokeStyleKind.allCases.count
        // CGMutablePath is a reference type: appending never copies.
        let paths = (0..<kinds).map { _ in CGMutablePath() }
        var last = [CGPoint?](repeating: nil, count: kinds)
        var used = [Bool](repeating: false, count: kinds)
        let points = geometry.points
        let minSq = minimumStep * minimumStep

        @inline(__always) func far(_ a: CGPoint?, _ b: CGPoint) -> Bool {
            guard let a else { return true }
            let dx = a.x - b.x, dy = a.y - b.y
            return dx * dx + dy * dy >= minSq
        }

        for segment in geometry.segments.prefix(min(limit, geometry.segments.count)) {
            let move = geometry.moves[segment.moveIndex]
            guard filter.allows(move) else { continue }
            let k = segment.style.rawValue
            let path = paths[k]
            used[k] = true

            if let cursor, cursor.moveIndex == segment.moveIndex, cursor.moveProgress < 1 {
                let partial = Tessellator.polyline(for: move, upTo: cursor.moveProgress)
                let s0 = p.point(partial[0])
                if far(last[k], s0) { path.move(to: s0); last[k] = s0 }
                for q in partial.dropFirst() {
                    let s = p.point(q)
                    if far(last[k], s) { path.addLine(to: s); last[k] = s }
                }
                continue
            }

            let lower = segment.range.lowerBound, upper = segment.range.upperBound
            let s0 = p.point(points[lower])
            if far(last[k], s0) { path.move(to: s0); last[k] = s0 }
            if upper - lower > 2 {
                for i in (lower + 1)..<(upper - 1) {
                    let s = p.point(points[i])
                    if far(last[k], s) { path.addLine(to: s); last[k] = s }
                }
            }
            // Always land on the end point so joins stay closed.
            let end = p.point(points[upper - 1])
            if last[k] != end { path.addLine(to: end); last[k] = end }
        }

        var result = [StrokeStyleKind: Path]()
        for kind in StrokeStyleKind.allCases where used[kind.rawValue] {
            result[kind] = Path(paths[kind.rawValue])
        }
        return result
    }
}
