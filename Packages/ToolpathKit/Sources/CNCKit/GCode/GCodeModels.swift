import Foundation

/// A machine position in millimeters. Inch programs are converted by the
/// parser so the rest of the app only deals with one unit.
public struct GPoint: Sendable, Hashable, Codable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = GPoint(x: 0, y: 0, z: 0)
}

public enum MoveType: String, Sendable, Codable, CaseIterable {
    case rapid
    case linear
    case arcClockwise
    case arcCounterClockwise
}

/// One motion segment between two consecutive positions, already resolved to
/// absolute machine-space millimeters by the parser.
public struct GCodeMove: Sendable, Hashable {
    /// Position of this move within `GCodeDocument.moves`.
    public let index: Int
    /// 1-based line number in the original file, for UI references.
    public let sourceLine: Int
    public let type: MoveType
    public let start: GPoint
    public let end: GPoint
    /// Active feed rate in mm/min. Irrelevant for rapids.
    public let feedRate: Double
    /// Whether the spindle was on (M3/M4) when this move ran.
    public let spindleOn: Bool
    /// Last programmed spindle speed (S word), 0 if none seen yet.
    public let spindleSpeed: Double
    /// Tool number active for this move (last T word before an M6), if any.
    public let toolNumber: Int?
    /// Arc center, only set for arc moves programmed with I/J.
    public let arcCenter: GPoint?

    public init(
        index: Int,
        sourceLine: Int,
        type: MoveType,
        start: GPoint,
        end: GPoint,
        feedRate: Double,
        spindleOn: Bool,
        spindleSpeed: Double = 0,
        toolNumber: Int? = nil,
        arcCenter: GPoint? = nil
    ) {
        self.index = index
        self.sourceLine = sourceLine
        self.type = type
        self.start = start
        self.end = end
        self.feedRate = feedRate
        self.spindleOn = spindleOn
        self.spindleSpeed = spindleSpeed
        self.toolNumber = toolNumber
        self.arcCenter = arcCenter
    }

    public var isRapid: Bool { type == .rapid }
    public var isArc: Bool { type == .arcClockwise || type == .arcCounterClockwise }
    public var isCutting: Bool { !isRapid }
    public var deltaZ: Double { end.z - start.z }
    /// A move with no X/Y travel (a pure plunge or retract).
    public var isZOnly: Bool { start.x == end.x && start.y == end.y && start.z != end.z }
}

/// Axis-aligned bounding box across every move start/end.
public struct GBounds: Sendable, Hashable {
    public var minX: Double, maxX: Double
    public var minY: Double, maxY: Double
    public var minZ: Double, maxZ: Double

    public init(minX: Double, maxX: Double, minY: Double, maxY: Double, minZ: Double, maxZ: Double) {
        self.minX = minX; self.maxX = maxX
        self.minY = minY; self.maxY = maxY
        self.minZ = minZ; self.maxZ = maxZ
    }

    public static let zero = GBounds(minX: 0, maxX: 0, minY: 0, maxY: 0, minZ: 0, maxZ: 0)

    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }
    public var depth: Double { maxZ - minZ }
    public var center: GPoint { GPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2, z: (minZ + maxZ) / 2) }
}

/// A tool change detected in the program (`T<n> M6`, or `M6 T<n>`).
public struct ToolChange: Sendable, Hashable {
    public let toolNumber: Int
    public let sourceLine: Int
    /// Index of the first move that runs with this tool, if any.
    public let firstMoveIndex: Int?
}

/// Result of deterministically parsing a G-code file.
public struct GCodeDocument: Sendable {
    public let fileName: String
    public let totalLines: Int
    public let moves: [GCodeMove]
    public let toolChanges: [ToolChange]
    public let bounds: GBounds
    public let rapidCount: Int
    public let cuttingCount: Int
    public let hasAnySpindleOn: Bool

    public init(fileName: String, totalLines: Int, moves: [GCodeMove], toolChanges: [ToolChange] = []) {
        self.fileName = fileName
        self.totalLines = totalLines
        self.moves = moves
        self.toolChanges = toolChanges
        self.bounds = GCodeDocument.bounds(of: moves)
        let rapids = moves.lazy.filter(\.isRapid).count
        self.rapidCount = rapids
        self.cuttingCount = moves.count - rapids
        self.hasAnySpindleOn = moves.contains(where: \.spindleOn)
    }

    static func bounds(of moves: [GCodeMove]) -> GBounds {
        guard let first = moves.first else { return .zero }
        var b = GBounds(minX: first.start.x, maxX: first.start.x,
                        minY: first.start.y, maxY: first.start.y,
                        minZ: first.start.z, maxZ: first.start.z)
        func consider(_ p: GPoint) {
            if p.x < b.minX { b.minX = p.x }
            if p.x > b.maxX { b.maxX = p.x }
            if p.y < b.minY { b.minY = p.y }
            if p.y > b.maxY { b.maxY = p.y }
            if p.z < b.minZ { b.minZ = p.z }
            if p.z > b.maxZ { b.maxZ = p.z }
        }
        for move in moves {
            consider(move.start)
            consider(move.end)
        }
        return b
    }

    /// Bounds of cutting moves only — the region that actually touches stock.
    public var cuttingBounds: GBounds? {
        let cuts = moves.filter(\.isCutting)
        guard !cuts.isEmpty else { return nil }
        return GCodeDocument.bounds(of: cuts)
    }
}
