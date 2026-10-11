import Testing
@testable import CNCKit

@Suite("Lathe parser")
struct LatheParserTests {
    let parser = LatheParser()

    @Test func diameterModeHalvesXAndMapsAxes() throws {
        let doc = parser.parse("G21 G97 S1000 M3\nG0 X20 Z2\nG1 Z-10 F100", fileName: "t.nc")
        #expect(doc.kind == .lathe)
        let cut = try #require(doc.moves.last)
        #expect(cut.start == GPoint(x: 2, y: 10, z: 0))
        #expect(cut.end == GPoint(x: -10, y: 10, z: 0))
        #expect(cut.feedRate == 100)
        #expect(cut.spindleOn)
    }

    @Test func radiusModeAndIncrementalWords() throws {
        let doc = parser.parse("G8\nG0 X10 Z0\nG1 U-2 W-5 F50", fileName: "t.nc")
        let cut = try #require(doc.moves.last)
        #expect(cut.end == GPoint(x: -5, y: 8, z: 0))
    }

    @Test func diameterIncrementalUIsAlsoADiameter() throws {
        let doc = parser.parse("G0 X20 Z0\nG1 U-4 F50", fileName: "t.nc")
        #expect(doc.moves.last?.end.y == 8)
    }

    @Test func feedPerRevAndConstantSurfaceSpeedAreConvertedToMmPerMin() throws {
        // r = 11 mm, Vc = 150 m/min → 2170 RPM, capped by G50 S2000; 0.2 mm/rev × 2000 = 400 mm/min.
        let doc = parser.parse("G50 S2000\nG96 S150 M3\nG95\nG0 X22 Z2\nG1 Z-20 F0.2", fileName: "t.nc")
        let cut = try #require(doc.moves.last)
        #expect(cut.spindleSpeed == 2000)
        #expect(abs(cut.feedRate - 400) < 0.001)
    }

    @Test func cssRpmFollowsDiameterBelowTheLimit() throws {
        // r = 25 mm, Vc = 100 m/min → 636.6 RPM, below the G50 limit.
        let doc = parser.parse("G50 S3000\nG96 S100 M3\nG95\nG0 X50 Z1\nG1 Z-5 F0.1", fileName: "t.nc")
        let cut = try #require(doc.moves.last)
        #expect(abs(cut.spindleSpeed - 100_000 / (2 * .pi * 25)) < 0.01)
    }

    @Test func machineMaxRpmCapsCss() throws {
        let doc = LatheParser(machineMaxRpm: 3000).parse("G96 S200 M3\nG0 X4 Z1\nG1 Z-5 F100", fileName: "t.nc")
        #expect(doc.moves.last?.spindleSpeed == 3000)
    }

    @Test func arcsWithIKAndWithRAgree() throws {
        let ik = parser.parse("G0 X0 Z0\nG3 X20 Z-10 I0 K-10 F50", fileName: "a.nc")
        let rForm = parser.parse("G0 X0 Z0\nG3 X20 Z-10 R10 F50", fileName: "b.nc")
        let a = try #require(ik.moves.last?.arcCenter)
        let b = try #require(rForm.moves.last?.arcCenter)
        #expect(a == GPoint(x: -10, y: 0, z: 0))
        #expect(abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9)
        #expect(ik.moves.last?.isArc == true)
    }

    @Test func toolWordsSelectTheTurretStation() {
        let doc = parser.parse("T0101\nG0 X20 Z2\nT0303\nG0 X30 Z2", fileName: "t.nc")
        #expect(doc.toolChanges.map(\.toolNumber) == [1, 3])
        #expect(doc.moves.last?.toolNumber == 3)
    }

    @Test func referenceReturnsDoNotMoveAlongThePath() {
        let doc = parser.parse("G0 X20 Z2\nG28 U0 W0\nG50 X100 Z100\nG0 X10", fileName: "t.nc")
        #expect(doc.moves.count == 2)
        #expect(doc.moves.last?.start == GPoint(x: 2, y: 10, z: 0))
    }

    @Test func g71RoughingExpandsToPassesThatStopAtTheProfile() throws {
        let program = """
        G21 G95 G97 S1200 M3
        T0101
        G0 X26 Z2
        G71 U1 R0.5
        G71 P10 Q50 U0 W0 F0.2
        N10 G0 X10
        N20 G1 Z-10
        N30 X20 Z-20
        N40 Z-30
        N50 X26
        G70 P10 Q50
        G0 X40 Z10
        """
        let doc = parser.parse(program, fileName: "g71.nc")
        // Profile blocks are not executed in line order, only through the cycles.
        let cuts = doc.moves.filter { !$0.isRapid && $0.start.y == $0.end.y && $0.end.x < $0.start.x }
        // Passes at r = 12, 11, … 6 (start r = 13, depth 1, deepest profile r = 5).
        let passRadii = Set(cuts.map(\.end.y)).filter { $0 > 5.5 && $0 < 13 }
        #expect(passRadii == [12, 11, 10, 9, 8, 7, 6])
        // At r = 9 the pass stops on the taper between Z-10/r5 and Z-20/r10.
        let pass9 = try #require(cuts.first { $0.end.y == 9 })
        #expect(abs(pass9.end.x - -18) < 1e-9)
        // At r = 12 it runs to the shoulder at Z-30.
        let pass12 = try #require(cuts.first { $0.end.y == 12 })
        #expect(abs(pass12.end.x - -30) < 1e-9)
        // G70 finish pass follows the exact profile.
        #expect(doc.moves.contains { !$0.isRapid && $0.start == GPoint(x: -10, y: 5, z: 0) && $0.end == GPoint(x: -20, y: 10, z: 0) })
        #expect(doc.moves.last?.end == GPoint(x: 10, y: 20, z: 0))
    }

    @Test func fanucG76ThreadReachesTheMinorDiameterInPasses() throws {
        let program = """
        G97 S500 M3
        G0 X22 Z5
        G76 P010060 Q50 R0.02
        G76 X18.16 Z-20 P920 Q300 F1.5
        """
        let doc = parser.parse(program, fileName: "thread.nc")
        let threadPasses = doc.moves.filter { !$0.isRapid && $0.start.y == $0.end.y && $0.end.x == -20 }
        #expect(threadPasses.count >= 4)
        #expect(threadPasses.allSatisfy { $0.end.y >= 18.16 / 2 - 1e-9 && $0.end.y < 11 })
        #expect(abs((threadPasses.map(\.end.y).min() ?? 0) - 9.08) < 1e-9)
        // Threading feed = lead × RPM.
        #expect(threadPasses.first?.feedRate == 1.5 * 500)
        #expect(doc.moves.last?.end == GPoint(x: 5, y: 11, z: 0))
    }

    @Test func linuxCncG76ThreadsInward() throws {
        let doc = parser.parse("G7 G97 S400 M3\nG0 X20 Z2\nG76 P1.5 Z-15 I-0.5 J0.2 K0.9 R2", fileName: "t.nc")
        let passes = doc.moves.filter { !$0.isRapid && $0.end.x == -15 }
        #expect(!passes.isEmpty)
        // Drive line r = 10, peak 9.5, full depth 0.9 → deepest pass at r = 8.6.
        #expect(abs((passes.map(\.end.y).min() ?? 0) - 8.6) < 1e-9)
    }

    @Test func detectsLathePrograms() {
        #expect(LatheDetector.isLikelyLathe("G18 G96 S150\nG0 X20 Z2\nG1 Z-10"))
        #expect(LatheDetector.isLikelyLathe("T0101\nG0 X20 Z2\nG1 U-2 W-3"))
        #expect(!LatheDetector.isLikelyLathe("G21 G90\nG0 X10 Y10 Z5\nG1 Z-1 F300"))
    }
}
