import Foundation

/// Resolved arc geometry with the start→end sweep already normalized for
/// direction (negative for clockwise, positive for counter-clockwise).
public struct ArcGeometry: Sendable, Hashable {
    public let center: GPoint
    public let radius: Double
    public let startAngle: Double
    public let endAngle: Double

    public var sweepRadians: Double { abs(endAngle - startAngle) }
}

public enum Tessellator {
    public static let defaultArcSegments = 24

    /// Arc geometry for a move, or nil when it is not an I/J arc.
    public static func arcGeometry(of move: GCodeMove) -> ArcGeometry? {
        guard move.isArc, let center = move.arcCenter else { return nil }
        let startAngle = atan2(move.start.y - center.y, move.start.x - center.x)
        var endAngle = atan2(move.end.y - center.y, move.end.x - center.x)
        let clockwise = move.type == .arcClockwise
        let fullCircle = abs(move.start.x - move.end.x) < 1e-9 && abs(move.start.y - move.end.y) < 1e-9
        if fullCircle {
            // Same start and end point in the plane: a complete circle.
            endAngle = startAngle + (clockwise ? -2 * .pi : 2 * .pi)
        } else {
            if clockwise, endAngle > startAngle { endAngle -= 2 * .pi }
            if !clockwise, endAngle < startAngle { endAngle += 2 * .pi }
        }
        let radius = hypot(move.start.x - center.x, move.start.y - center.y)
        return ArcGeometry(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle)
    }

    /// Exact point at fraction `t` (0…1) along a move.
    public static func point(along move: GCodeMove, at t: Double) -> GPoint {
        guard let arc = arcGeometry(of: move) else {
            return GPoint(
                x: lerp(move.start.x, move.end.x, t),
                y: lerp(move.start.y, move.end.y, t),
                z: lerp(move.start.z, move.end.z, t)
            )
        }
        let angle = lerp(arc.startAngle, arc.endAngle, t)
        return GPoint(
            x: arc.center.x + arc.radius * cos(angle),
            y: arc.center.y + arc.radius * sin(angle),
            z: lerp(move.start.z, move.end.z, t)
        )
    }

    /// Polyline for drawing: arcs subdivided, everything else two points.
    public static func polyline(for move: GCodeMove, arcSegments: Int = defaultArcSegments) -> [GPoint] {
        guard arcGeometry(of: move) != nil else { return [move.start, move.end] }
        return (0...arcSegments).map { point(along: move, at: Double($0) / Double(arcSegments)) }
    }

    /// Polyline truncated at `progress` (0…1), for simulation reveal.
    public static func polyline(for move: GCodeMove, upTo progress: Double, arcSegments: Int = defaultArcSegments) -> [GPoint] {
        if progress >= 1 { return polyline(for: move, arcSegments: arcSegments) }
        if progress <= 0 { return [move.start] }
        guard arcGeometry(of: move) != nil else { return [move.start, point(along: move, at: progress)] }
        let steps = max(1, Int((Double(arcSegments) * progress).rounded(.up)))
        return (0...steps).map { point(along: move, at: min(progress, Double($0) / Double(arcSegments))) }
    }

    /// 3D length: exact helical length for arcs, straight distance otherwise.
    public static func length(of move: GCodeMove) -> Double {
        let dz = move.end.z - move.start.z
        guard let arc = arcGeometry(of: move) else {
            let dx = move.end.x - move.start.x
            let dy = move.end.y - move.start.y
            return (dx * dx + dy * dy + dz * dz).squareRoot()
        }
        let planar = arc.radius * arc.sweepRadians
        return (planar * planar + dz * dz).squareRoot()
    }

    @inline(__always)
    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
}
