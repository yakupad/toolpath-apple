import Foundation
import Testing
@testable import CNCKit

/// Parity with the original Dart implementation's end-to-end fixture suite:
/// same files, same expected numbers.
func fixture(_ name: String) throws -> String {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try String(contentsOf: url, encoding: .utf8)
}

func load(_ name: String) throws -> (GCodeDocument, [Finding]) {
    let document = GCodeParser().parse(try fixture(name), fileName: name)
    return (document, GCodeAnalyzer().analyze(document))
}

@Suite("rectangular_pocket_centered.nc")
struct RectangularPocketTests {
    @Test func parsesEveryMotionLineIgnoringToolAndSpindleWords() throws {
        let (document, _) = try load("rectangular_pocket_centered.nc")
        #expect(document.moves.count == 13)
    }

    @Test func noFalsePositivesOnCenteredWorkCoordinates() throws {
        let (_, findings) = try load("rectangular_pocket_centered.nc")
        #expect(findings.filter { $0.severity == .danger }.isEmpty)
        #expect(findings.filter { $0.severity == .caution }.isEmpty)
        #expect(SafetyScore.compute(findings) == 100)
    }

    @Test func statisticsForKnownRectangle() throws {
        let (document, _) = try load("rectangular_pocket_centered.nc")
        let stats = GCodeStatistics(document: document)
        #expect(stats.cutCount == 10)
        #expect(stats.rapidCount == 3)
        #expect(abs(stats.cutDistanceMm - 324) < 0.5)
        #expect(stats.minFeedRate == 300)
        #expect(stats.maxFeedRate == 600)
        #expect(stats.estimatedMachiningTimeMinutes > 0)
    }

    @Test func detectsToolAndSpindleSpeed() throws {
        let (document, _) = try load("rectangular_pocket_centered.nc")
        #expect(document.toolChanges.map(\.toolNumber) == [1])
        #expect(document.toolChanges.first?.sourceLine == 5)
        #expect(document.moves.allSatisfy { $0.toolNumber == 1 })
        #expect(document.moves.last?.spindleSpeed == 12000)
    }

    @Test func machineLimitsCheckIsOptIn() throws {
        let (document, findings) = try load("rectangular_pocket_centered.nc")
        #expect(!findings.contains { $0.category == .exceedsMachineLimits })
        let withEnvelope = GCodeAnalyzer().analyze(document, machineEnvelope: .defaultHobby)
        #expect(withEnvelope.contains { $0.category == .exceedsMachineLimits })
    }
}

@Suite("circular_pocket_arcs.nc")
struct CircularPocketTests {
    @Test func resolvesArcCentersWithoutDangers() throws {
        let (document, findings) = try load("circular_pocket_arcs.nc")
        #expect(document.moves.filter { $0.arcCenter != nil }.count == 4)
        #expect(findings.filter { $0.severity == .danger }.isEmpty)
    }

    @Test func countsArcsSeparately() throws {
        let (document, _) = try load("circular_pocket_arcs.nc")
        let stats = GCodeStatistics(document: document)
        #expect(stats.arcCount == 4)
        #expect(stats.cutDistanceMm > 0)
    }
}

@Suite("rapid_into_stock_danger.nc")
struct RapidIntoStockTests {
    @Test func flagsExactlyTheRapidPlunge() throws {
        let (document, findings) = try load("rapid_into_stock_danger.nc")
        let dangers = findings.filter { $0.severity == .danger }
        try #require(dangers.count == 1)
        #expect(dangers[0].category == .rapidIntoStock)
        let move = document.moves[dangers[0].moveIndex]
        #expect(move.type == .rapid)
        #expect(move.end.z == -1)
        #expect(move.end.x == 40)
    }

    @Test func safeRetractIsNotFlagged() throws {
        let (document, findings) = try load("rapid_into_stock_danger.nc")
        let dangerIndexes = Set(findings.filter { $0.severity == .danger }.map(\.moveIndex))
        let retract = try #require(document.moves.first { $0.end.z == 10 && $0.start.z < 10 })
        #expect(!dangerIndexes.contains(retract.index))
    }
}

@Suite("Other fixtures")
struct OtherFixtureTests {
    @Test func missingSpindleStartFlagsOnlyCuttingMoves() throws {
        let (document, findings) = try load("missing_spindle_start.nc")
        let spindle = findings.filter { $0.category == .missingSpindleStart }
        #expect(spindle.count == 3)
        #expect(spindle.allSatisfy { !document.moves[$0.moveIndex].isRapid })
    }

    @Test func zeroFeedStopsOnceFeedIsSet() throws {
        let (document, findings) = try load("zero_feed_rate.nc")
        let zero = findings.filter { $0.category == .zeroFeedRate }
        #expect(!zero.isEmpty)
        let last = try #require(document.moves.last)
        #expect(last.feedRate == 400)
        #expect(!zero.contains { $0.moveIndex == last.index })
    }

    @Test func inchIncrementalProgramClosesSquare() throws {
        let (document, findings) = try load("inch_relative_program.nc")
        let cuts = document.moves.filter { !$0.isRapid }
        let first = try #require(cuts.first), last = try #require(cuts.last)
        #expect(abs(last.end.x - first.start.x) < 1e-9)
        #expect(abs(last.end.y - first.start.y) < 1e-9)
        let stats = GCodeStatistics(document: document)
        #expect(abs(stats.cutDistanceMm - (4 * 25.4 + 13.97)) < 0.01)
        #expect(findings.filter { $0.severity == .danger }.isEmpty)
    }

    @Test func oversizedFileOnlyFlaggedWhenOptedIn() throws {
        let (document, findings) = try load("oversized_for_envelope.nc")
        #expect(findings.isEmpty)
        let limited = GCodeAnalyzer().analyze(document, machineEnvelope: .defaultHobby)
        #expect(limited.contains { $0.category == .exceedsMachineLimits })
    }
}

@Suite("Parser edge cases")
struct ParserEdgeCaseTests {
    @Test func firstMoveCombinedXYZRapidIsNotLowClearance() {
        let doc = GCodeParser().parse("M3 S10000\nG0 X-25 Y-15 Z10\nG1 Z-1 F300", fileName: "t")
        let findings = GCodeAnalyzer().analyze(doc)
        #expect(!findings.contains { $0.category == .lowZClearance })
    }

    @Test func genuineFirstMovePlungeIsCaught() {
        let doc = GCodeParser().parse("G0 X10 Y10 Z-2", fileName: "t")
        #expect(GCodeAnalyzer().analyze(doc).contains { $0.category == .rapidIntoStock })
    }

    @Test func leadingDotAndSignedNumbers() {
        let doc = GCodeParser().parse("G90\nG0 X.5 Y-.25 Z+2", fileName: "t")
        let move = doc.moves[0]
        #expect(move.end == GPoint(x: 0.5, y: -0.25, z: 2))
    }

    @Test func commentsAreIgnored() {
        let doc = GCodeParser().parse("(G0 X99) G0 X1 ; G1 X50\n; full comment", fileName: "t")
        #expect(doc.moves.count == 1)
        #expect(doc.moves[0].end.x == 1)
        #expect(doc.totalLines == 2)
    }

    @Test func toolChangesWithoutM6UseTWords() {
        let doc = GCodeParser().parse("T1\nM3 S9000\nG1 X1 F100\nT2\nG1 X2", fileName: "t")
        #expect(doc.toolChanges.map(\.toolNumber) == [1, 2])
        #expect(doc.toolChanges[1].firstMoveIndex == 1)
    }

    @Test func timelineAgreesWithStatistics() throws {
        let (document, _) = try load("rectangular_pocket_centered.nc")
        let stats = GCodeStatistics(document: document)
        let timeline = GCodeTimeline(document: document)
        #expect(abs(timeline.totalDurationSeconds - stats.estimatedMachiningTimeMinutes * 60) < 1e-6)
        let end = timeline.position(at: .infinity)
        #expect(end.position == document.moves.last?.end)
    }

    @Test func largeSyntheticFileParsesQuickly() {
        var lines = ["G21 G90", "M3 S12000", "G0 Z5"]
        for i in 0..<100_000 { lines.append("G1 X\(i % 300).5 Y\((i * 7) % 180).25 Z-1 F800") }
        let source = lines.joined(separator: "\n")
        let clock = ContinuousClock()
        var count = 0
        let elapsed = clock.measure {
            let doc = GCodeParser().parse(source, fileName: "big")
            count = doc.moves.count + GCodeAnalyzer().analyze(doc).count
        }
        #expect(count >= 100_000)
        // Debug builds are slow; this only guards against pathological regressions.
        #expect(elapsed < .seconds(10))
    }
}
