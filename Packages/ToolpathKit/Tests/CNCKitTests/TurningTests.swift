import Testing
@testable import CNCKit

@Suite("Turning calculator and lathe pre-flight")
struct TurningTests {
    let aluminum = CuttingMaterial.byID("aluminum_6061")!

    @Test func rpmFromSurfaceSpeedAndDiameter() {
        // Vc 200 m/min on Ø25 → 2546.5 RPM, under a 3000 RPM limit.
        let r = TurningCalculator.calculate(TurningInput(material: aluminum, diameterMm: 25, toolMaterial: .carbide, operation: .roughing, maxSpindleRpm: 3000))
        #expect(abs(r.spindleRpm - 200_000 / (.pi * 25)) < 0.01)
        #expect(!r.cappedByMaxRpm)
        #expect(r.feedPerRevMm == 0.15)
        #expect(abs(r.feedMmPerMin - 0.15 * r.spindleRpm) < 1e-9)
        #expect(r.depthOfCutMm == 1.0)
    }

    @Test func smallDiameterIsCappedAndFeedFollowsCappedRpm() {
        let r = TurningCalculator.calculate(TurningInput(material: aluminum, diameterMm: 6, toolMaterial: .carbide, operation: .finishing, maxSpindleRpm: 3000))
        #expect(r.cappedByMaxRpm && r.spindleRpm == 3000)
        #expect(abs(r.feedMmPerMin - 0.05 * 3000) < 1e-9)
        #expect(r.surfaceSpeedMPerMin < 240 * 1.0001)
    }

    @Test func threadingFeedIsThePitchAndSlow() {
        let steel = CuttingMaterial.byID("mild_steel_1018")!
        let r = TurningCalculator.calculate(TurningInput(material: steel, diameterMm: 20, toolMaterial: .hss, operation: .threading, maxSpindleRpm: 3000, threadPitchMm: 1.5))
        #expect(r.feedPerRevMm == 1.5)
        // 100 × 0.4 (HSS) × 0.35 = 14 m/min on Ø20 → ~223 RPM.
        #expect(abs(r.spindleRpm - 14_000 / (.pi * 20)) < 0.01)
    }

    @Test func latheProgramsGetALatheChecklist() {
        let doc = LatheParser().parse(LatheAnalyzerTests.roughing, fileName: "t.nc")
        let items = PreflightGenerator.items(document: doc, findings: [], machine: MachineContext(maxSpindleRpm: 3000))
        let kinds = items.map(\.kind)
        #expect(kinds.contains(.latheZero))
        #expect(kinds.contains(.stickout(minimumMm: 35)))
        // Widest cut: the stock OD Ø26 plus the 0.4 mm X finish allowance of the G71.
        #expect(kinds.contains { if case let .stockDiameter(d) = $0 { abs(d - 26.4) < 1e-9 } else { false } })
        #expect(kinds.contains(.chuckKeyRemoved))
        #expect(!kinds.contains { if case .zeroXY = $0 { true } else { false } })
    }
}
