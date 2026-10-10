import Foundation

/// How a logged job actually went. Stable raw values — persisted.
public enum JobOutcome: String, Sendable, Codable, CaseIterable {
    case clean
    case chatter
    case brokenTool
    case roughFinish
    case burning
    case other
}

/// A deterministic tweak to a recipe's settings, derived from logged outcomes.
public struct RecipeAdjustment: Sendable, Hashable {
    public enum Reason: Sendable, Hashable {
        /// Recent jobs were all clean — keep the settings.
        case stable(cleanRuns: Int)
        case chatter(count: Int)
        case brokenTool
        case roughFinish(count: Int)
        case burning(count: Int)
        /// Not enough history to suggest anything.
        case notEnoughData
    }

    public let reason: Reason
    public let feedFactor: Double
    public let depthFactor: Double
    public let stepoverFactor: Double
    public let rpmFactor: Double

    public var changesAnything: Bool {
        feedFactor != 1 || depthFactor != 1 || stepoverFactor != 1 || rpmFactor != 1
    }

    static func keep(_ reason: Reason) -> RecipeAdjustment {
        RecipeAdjustment(reason: reason, feedFactor: 1, depthFactor: 1, stepoverFactor: 1, rpmFactor: 1)
    }
}

/// Suggests changes from the most recent outcomes logged *since the last
/// settings change*. Always conservative: problems reduce load; nothing here
/// ever increases depth of cut.
public enum RecipeAdvisor {
    public static let window = 3

    /// `outcomes` oldest → newest, only runs at the recipe's current settings.
    public static func suggest(for outcomes: [JobOutcome]) -> RecipeAdjustment {
        let recent = Array(outcomes.suffix(window))
        guard !recent.isEmpty else { return .keep(.notEnoughData) }
        func count(_ o: JobOutcome) -> Int { recent.filter { $0 == o }.count }

        if count(.brokenTool) > 0 {
            return RecipeAdjustment(reason: .brokenTool, feedFactor: 0.85, depthFactor: 0.75, stepoverFactor: 1, rpmFactor: 1)
        }
        if count(.chatter) >= 2 {
            return RecipeAdjustment(reason: .chatter(count: count(.chatter)), feedFactor: 0.9, depthFactor: 0.8, stepoverFactor: 1, rpmFactor: 1)
        }
        if count(.burning) >= 2 {
            // Burning means rubbing: take a bigger chip by slowing the spindle.
            return RecipeAdjustment(reason: .burning(count: count(.burning)), feedFactor: 1, depthFactor: 1, stepoverFactor: 1, rpmFactor: 0.9)
        }
        if count(.roughFinish) >= 2 {
            return RecipeAdjustment(reason: .roughFinish(count: count(.roughFinish)), feedFactor: 0.95, depthFactor: 1, stepoverFactor: 0.8, rpmFactor: 1)
        }
        if recent.count == window, recent.allSatisfy({ $0 == .clean }) {
            return .keep(.stable(cleanRuns: recent.count))
        }
        return .keep(.notEnoughData)
    }
}
