import CNCDesign
import CNCKit
import SwiftUI

/// Draws a toolpath with SwiftUI Canvas: grid, envelope, moves grouped into
/// one path per style (a handful of strokes per frame, even for 100k moves),
/// optional simulation reveal and a focused (flagged) move.
public struct ToolpathCanvas: View, @preconcurrency Animatable {
    let geometry: ToolpathGeometry
    let camera: OrbitCamera
    let filter: MoveFilter
    /// Fraction of moves drawn (0…1), for the import "draw-on" animation.
    var drawProgress: Double
    /// Simulation cursor: moves after it are hidden, its move is truncated.
    let cursor: SimulationPoint?
    /// A flagged move to emphasize (others are dimmed).
    let focusedMove: Int?
    let showGrid: Bool
    let insets: EdgeInsetsValue

    public var animatableData: Double {
        get { drawProgress }
        set { drawProgress = newValue }
    }

    public init(
        geometry: ToolpathGeometry,
        camera: OrbitCamera,
        filter: MoveFilter = MoveFilter(),
        drawProgress: Double = 1,
        cursor: SimulationPoint? = nil,
        focusedMove: Int? = nil,
        showGrid: Bool = true,
        insets: EdgeInsetsValue = .zero
    ) {
        self.insets = insets
        self.geometry = geometry
        self.camera = camera
        self.filter = filter
        self.drawProgress = drawProgress
        self.cursor = cursor
        self.focusedMove = focusedMove
        self.showGrid = showGrid
    }

    public var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            guard !geometry.isEmpty, size.width > 1, size.height > 1 else { return }
            // Lathe parts are drawn true to scale: the depth exaggeration that
            // makes shallow mill cuts readable would stretch the stock rings.
            var camera = camera
            if geometry.latheStock != nil { camera.zScale = 1 }
            let projection = Projection(camera: camera, size: size, bounds: geometry.bounds, insets: insets)
            if let stock = geometry.latheStock {
                drawLathe(stock, in: &context, projection)
            } else if showGrid {
                drawGrid(in: &context, projection)
            }
            drawMoves(in: &context, projection)
        }
        .background(TP.Viewer.background)
        .accessibilityLabel(Text("Toolpath preview", bundle: .module))
    }

    // MARK: Grid

    private func drawGrid(in context: inout GraphicsContext, _ p: Projection) {
        let b = geometry.bounds
        let margin = max(b.width, b.height) * 0.15 + 10
        let minX = ((b.minX - margin) / 10).rounded(.down) * 10
        let maxX = ((b.maxX + margin) / 10).rounded(.up) * 10
        let minY = ((b.minY - margin) / 10).rounded(.down) * 10
        let maxY = ((b.maxY + margin) / 10).rounded(.up) * 10
        let z = 0.0

        var major = Path(), minor = Path()
        let minorCount = Int((maxX - minX) + (maxY - minY))
        let drawMinor = minorCount < 400 && p.pointsPerMillimeter > 3

        var x = minX
        while x <= maxX + 0.001 {
            let isMajor = Int(x.rounded()) % 10 == 0
            if isMajor || drawMinor {
                var line = Path()
                line.move(to: p.point(x, minY, z))
                line.addLine(to: p.point(x, maxY, z))
                if isMajor { major.addPath(line) } else { minor.addPath(line) }
            }
            x += drawMinor ? 1 : 10
        }
        var y = minY
        while y <= maxY + 0.001 {
            let isMajor = Int(y.rounded()) % 10 == 0
            if isMajor || drawMinor {
                var line = Path()
                line.move(to: p.point(minX, y, z))
                line.addLine(to: p.point(maxX, y, z))
                if isMajor { major.addPath(line) } else { minor.addPath(line) }
            }
            y += drawMinor ? 1 : 10
        }
        context.stroke(minor, with: .color(TP.Viewer.gridMinor), lineWidth: 0.6)
        context.stroke(major, with: .color(TP.Viewer.gridMajor), lineWidth: 1.2)
    }

    // MARK: Lathe

    /// Spindle axis, the stock as a translucent section on both sides of the
    /// axis, rings at its ends (visible in 3D) and a faint mirror of the path
    /// so the turned silhouette reads at a glance.
    private func drawLathe(_ stock: ToolpathGeometry.LatheStock, in context: inout GraphicsContext, _ p: Projection) {
        let r = stock.radius
        var section = Path()
        section.move(to: p.point(stock.faceZ, r, 0))
        section.addLine(to: p.point(stock.backZ, r, 0))
        section.addLine(to: p.point(stock.backZ, -r, 0))
        section.addLine(to: p.point(stock.faceZ, -r, 0))
        section.closeSubpath()
        context.fill(section, with: .color(TP.Viewer.stock))
        context.stroke(section, with: .color(TP.Viewer.gridMajor), lineWidth: 1)

        var rings = Path()
        for z in [stock.faceZ, stock.backZ] {
            for step in 0...48 {
                let a = Double(step) / 48 * 2 * .pi
                let point = p.point(z, r * cos(a), r * sin(a))
                if step == 0 { rings.move(to: point) } else { rings.addLine(to: point) }
            }
        }
        context.stroke(rings, with: .color(TP.Viewer.gridMajor), lineWidth: 1)

        var axis = Path()
        axis.move(to: p.point(stock.backZ - 10, 0, 0))
        axis.addLine(to: p.point(stock.faceZ + 15, 0, 0))
        context.stroke(axis, with: .color(TP.Viewer.gridMajor), style: StrokeStyle(lineWidth: 1, dash: [10, 4, 2, 4]))

        var mirror = Path()
        for segment in geometry.segments where !geometry.moves[segment.moveIndex].isRapid {
            let pts = geometry.points[segment.range]
            guard let first = pts.first else { continue }
            mirror.move(to: p.point(first.x, -first.y, first.z))
            for q in pts.dropFirst() { mirror.addLine(to: p.point(q.x, -q.y, q.z)) }
        }
        context.stroke(mirror, with: .color(TP.Viewer.gridMajor.opacity(0.8)), lineWidth: 1)
    }

    // MARK: Moves

    private func drawMoves(in context: inout GraphicsContext, _ p: Projection) {
        let total = geometry.segments.count
        let limit = cursor.map { $0.moveIndex + 1 } ?? max(1, Int((Double(total) * drawProgress).rounded(.up)))
        let points = geometry.points
        let paths = ToolpathPathBuilder.build(geometry: geometry, projection: p, filter: filter, limit: limit, cursor: cursor)

        let dim = focusedMove != nil
        for kind in StrokeStyleKind.allCases {
            guard let path = paths[kind] else { continue }
            let (color, width, dash, opacity) = Self.style(for: kind)
            context.stroke(
                path,
                with: .color(color.opacity(dim && kind != .danger && kind != .caution ? opacity * 0.35 : opacity)),
                style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash)
            )
        }

        if let focusedMove, geometry.segments.indices.contains(focusedMove) {
            let segment = geometry.segments[focusedMove]
            var path = Path()
            path.move(to: p.point(points[segment.range.lowerBound]))
            for i in segment.range.dropFirst() { path.addLine(to: p.point(points[i])) }
            let color = segment.style == .caution ? TP.Viewer.caution : TP.Viewer.danger
            context.stroke(path, with: .color(color.opacity(0.35)), style: StrokeStyle(lineWidth: 12, lineCap: .round))
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }

        if let cursor {
            let c = p.point(cursor.position)
            let rect = CGRect(x: c.x - 7, y: c.y - 7, width: 14, height: 14)
            context.fill(Path(ellipseIn: rect), with: .color(TP.Viewer.toolHead))
            context.stroke(Path(ellipseIn: rect), with: .color(TP.Viewer.background), lineWidth: 3)
            context.stroke(Path(ellipseIn: rect.insetBy(dx: -8, dy: -8)), with: .color(TP.Palette.accent.opacity(0.5)), lineWidth: 2)
        }
    }

    static func style(for kind: StrokeStyleKind) -> (Color, CGFloat, [CGFloat], Double) {
        switch kind {
        case .rapid: (TP.Viewer.rapid, 1.2, [5, 5], 0.65)
        case .cut: (TP.Viewer.cut, 2.6, [], 1)
        case .arcCW: (TP.Viewer.arcCW, 2.6, [], 1)
        case .arcCCW: (TP.Viewer.arcCCW, 2.6, [], 1)
        case .zOnly: (TP.Viewer.cut, 1, [3, 3], 0.45)
        case .caution: (TP.Viewer.caution, 3, [], 1)
        case .danger: (TP.Viewer.danger, 3.4, [], 1)
        }
    }
}
