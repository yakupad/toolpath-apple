import CNCKit
import Foundation

/// How a move is drawn. Red is only ever used for flagged moves.
public enum StrokeStyleKind: Int, Sendable, CaseIterable {
    case rapid, cut, arcCW, arcCCW, zOnly, caution, danger
}

/// Move visibility toggles (G0/G1/G2/G3 + pure Z moves).
public struct MoveFilter: Sendable, Hashable {
    public var showRapid = true
    public var showLinear = true
    public var showArcCW = true
    public var showArcCCW = true
    public var showZOnly = true

    public init() {}

    func allows(_ move: GCodeMove) -> Bool {
        if move.isZOnly, !showZOnly { return false }
        return switch move.type {
        case .rapid: showRapid
        case .linear: showLinear
        case .arcClockwise: showArcCW
        case .arcCounterClockwise: showArcCCW
        }
    }
}

/// Tessellated, render-ready geometry for a document. Built once (off the
/// main actor); every frame only re-projects the flat point buffer.
public struct ToolpathGeometry: Sendable {
    public struct Segment: Sendable {
        public let moveIndex: Int
        public let range: Range<Int>
        public let style: StrokeStyleKind
    }

    public let points: [GPoint]
    public let segments: [Segment]
    public let bounds: GBounds
    public let moves: [GCodeMove]

    public init(document: GCodeDocument, findings: [Finding], arcSegments: Int = Tessellator.defaultArcSegments) {
        var severity: [Int: FindingSeverity] = [:]
        for f in findings { severity[f.moveIndex] = max(severity[f.moveIndex] ?? .info, f.severity) }

        var pts: [GPoint] = []
        pts.reserveCapacity(document.moves.count * 2)
        var segs: [Segment] = []
        segs.reserveCapacity(document.moves.count)
        for move in document.moves {
            let polyline = Tessellator.polyline(for: move, arcSegments: arcSegments)
            let start = pts.count
            pts.append(contentsOf: polyline)
            let style: StrokeStyleKind
            switch severity[move.index] {
            case .danger?: style = .danger
            case .caution?: style = .caution
            default:
                if move.isZOnly { style = .zOnly }
                else {
                    switch move.type {
                    case .rapid: style = .rapid
                    case .linear: style = .cut
                    case .arcClockwise: style = .arcCW
                    case .arcCounterClockwise: style = .arcCCW
                    }
                }
            }
            segs.append(Segment(moveIndex: move.index, range: start..<pts.count, style: style))
        }
        points = pts
        segments = segs
        bounds = document.bounds
        moves = document.moves
    }

    public var isEmpty: Bool { segments.isEmpty }
}
