import Testing
@testable import CNCKit

@Suite("Lathe analyzer")
struct LatheAnalyzerTests {
    func findings(_ program: String, setup: LatheSetup = LatheSetup()) -> [Finding] {
        LatheAnalyzer().analyze(LatheParser().parse(program, fileName: "t.nc"), setup: setup)
    }

    static let roughing = """
    G21 G95 G50 S2500
    G96 S180 M3
    T0101
    G0 X26 Z2
    G71 U1 R0.5
    G71 P10 Q50 U0.4 W0.1 F0.2
    N10 G0 X10
    N20 G1 Z-10
    N30 X20 Z-20
    N40 Z-30
    N50 X26
    G70 P10 Q50
    G0 X40 Z10
    M5
    """

    @Test func roughingCycleIsClean() {
        // Rapids between passes run over material that is already gone.
        #expect(findings(Self.roughing).isEmpty)
    }

    @Test func rapidThroughUncutStockIsDanger() {
        let f = findings("G97 S1000 M3\nG0 X32 Z2\nG1 X30 F0.2\nG1 Z-20\nG0 X20 Z-10")
        #expect(f.contains { $0.category == .latheRapidIntoStock && $0.severity == .danger && $0.sourceLine == 5 })
    }

    @Test func cssWithoutLimitIsFlaggedAndDangerNearCentre() {
        let caution = findings("G96 S150 M3\nG95\nG0 X40 Z1\nG1 Z-10 F0.2\nX42")
        #expect(caution.contains { $0.category == .cssWithoutSpeedLimit && $0.severity == .caution })
        let danger = findings("G96 S150 M3\nG95\nG0 X40 Z0\nG1 X0 F0.1")
        #expect(danger.contains { $0.category == .cssWithoutSpeedLimit && $0.severity == .danger })
        let limited = findings("G50 S2000\nG96 S150 M3\nG95\nG0 X40 Z0\nG1 X0 F0.1")
        #expect(!limited.contains { $0.category == .cssWithoutSpeedLimit })
    }

    @Test func chuckPositionIsChecked() {
        let program = "G97 S800 M3\nG0 X20 Z2\nG1 Z-32 F0.1\nX24\nG0 Z2"
        #expect(findings(program, setup: LatheSetup(chuckZ: -30)).contains { $0.category == .chuckCollision && $0.severity == .danger })
        #expect(!findings(program, setup: LatheSetup(chuckZ: -40)).contains { $0.category == .chuckCollision })
    }

    @Test func centrelineAndSwing() {
        let facing = "G97 S800 M3\nG0 X30 Z0\nG1 X-0.4 F0.1\nG0 Z2"
        #expect(!findings(facing).contains { $0.category == .crossesCenterline })
        #expect(findings("G97 S800 M3\nG0 X30 Z0\nG1 X-4 F0.1\nG0 Z2").contains { $0.category == .crossesCenterline })
        #expect(findings(facing, setup: LatheSetup(maxDiameter: 25)).contains { $0.category == .exceedsSwing })
    }

    @Test func latheExplanationsUseDiameterAndZ() {
        let group = FindingGroup.group(findings("G97 S1000 M3\nG0 X32 Z2\nG1 X30 F0.2\nG1 Z-20\nG0 X20 Z-10"))[0]
        let text = Explainer.explain(group, kind: .lathe).whatHappened
        #expect(text.contains("X20") && text.contains("Z-10"))
    }
}
