import Foundation

public enum FindingSeverity: Int, Sendable, Codable, CaseIterable, Comparable {
    case info = 0
    case caution = 1
    case danger = 2

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum FindingCategory: String, Sendable, Codable, CaseIterable {
    case rapidIntoStock
    case lowZClearance
    case missingSpindleStart
    case zeroFeedRate
    case exceedsMachineLimits
    // Lathe
    case latheRapidIntoStock
    case chuckCollision
    case cssWithoutSpeedLimit
    case crossesCenterline
    case exceedsSwing
}

/// A fact computed deterministically by `GCodeAnalyzer` — never guessed.
/// Numbers live in typed fields so explanations can be localized.
public struct Finding: Sendable, Hashable, Identifiable {
    public let id: String
    public let category: FindingCategory
    public let severity: FindingSeverity
    public let moveIndex: Int
    public let sourceLine: Int
    public let startZ: Double
    public let endZ: Double
    public let end: GPoint
}

/// Deterministic safety checks over a parsed document. The only source of
/// truth for "is this move dangerous".
public struct GCodeAnalyzer: Sendable {
    public static let stockTopZ = 0.0
    public static let safeClearanceZ = 1.0
    static let epsilon = 0.01

    public init() {}

    /// `machineEnvelope` is opt-in: G-code X/Y is usually relative to a work
    /// offset (often centered on the part), so an origin-anchored bounds
    /// check false-positives on ordinary files unless the user's zero really
    /// sits near machine home.
    public func analyze(_ document: GCodeDocument, machineEnvelope: MachineEnvelope? = nil) -> [Finding] {
        var findings: [Finding] = []
        var counter = 0
        func add(_ category: FindingCategory, _ severity: FindingSeverity, _ move: GCodeMove, startZ: Double) {
            counter += 1
            findings.append(Finding(
                id: "\(category.rawValue)-\(counter)",
                category: category,
                severity: severity,
                moveIndex: move.index,
                sourceLine: move.sourceLine,
                startZ: startZ,
                endZ: move.end.z,
                end: move.end
            ))
        }

        for move in document.moves {
            if let envelope = machineEnvelope,
               !envelope.contains(x: move.end.x, y: move.end.y, z: move.end.z) {
                add(.exceedsMachineLimits, .danger, move, startZ: move.start.z)
            }

            if move.isRapid {
                // Move 0's start is the parser's synthetic (0,0,0), not a
                // measured position — judge it only by where it ends.
                let referenceStartZ = move.index == 0 ? move.end.z : move.start.z
                let minZ = min(referenceStartZ, move.end.z)
                // A rapid that ends higher than it started is a retract.
                let endsAtOrBelowStart = move.end.z <= referenceStartZ

                if endsAtOrBelowStart, move.end.z < Self.stockTopZ - Self.epsilon {
                    add(.rapidIntoStock, .danger, move, startZ: move.start.z)
                } else if minZ < Self.safeClearanceZ - Self.epsilon,
                          move.start.x != move.end.x || move.start.y != move.end.y {
                    add(.lowZClearance, .caution, move, startZ: minZ)
                }
                continue
            }

            if !move.spindleOn {
                add(.missingSpindleStart, .danger, move, startZ: move.start.z)
            }
            if move.feedRate <= 0 {
                add(.zeroFeedRate, .caution, move, startZ: move.start.z)
            }
        }
        return findings
    }
}

/// A finding category collapsed across all the moves it hit, for display.
public struct FindingGroup: Sendable, Hashable, Identifiable {
    public var id: FindingCategory { category }
    public let category: FindingCategory
    public let severity: FindingSeverity
    public let findings: [Finding]
    public var count: Int { findings.count }
    public var first: Finding { findings[0] }

    /// Groups findings by category, most severe first, then by first line.
    public static func group(_ findings: [Finding]) -> [FindingGroup] {
        Dictionary(grouping: findings, by: \.category)
            .map { FindingGroup(category: $0.key, severity: $0.value.map(\.severity).max() ?? .info, findings: $0.value) }
            .sorted { lhs, rhs in
                lhs.severity != rhs.severity ? lhs.severity > rhs.severity : lhs.first.sourceLine < rhs.first.sourceLine
            }
    }
}

/// Deterministic 0–100 summary of a finding list. Each distinct danger
/// category costs 25 (plus 2 per extra occurrence, capped), cautions cost
/// less. Never below 0. Not a guarantee — a quick read of "how worried
/// should I be".
public enum SafetyScore {
    public static func compute(_ findings: [Finding]) -> Int {
        var score = 100.0
        for group in FindingGroup.group(findings) {
            let extra = Double(min(group.count - 1, 10))
            switch group.severity {
            case .danger: score -= 25 + extra * 2
            case .caution: score -= 6 + extra * 0.5
            case .info: score -= 1
            }
        }
        return Int(max(0, score).rounded())
    }

    public enum Band: Sendable { case good, check, danger }

    public static func band(for score: Int, hasDanger: Bool) -> Band {
        if hasDanger { return .danger }
        return score >= 85 ? .good : .check
    }
}
