import Foundation
import Testing
@testable import CNCKit

private func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }

@Suite("Feeds calculator (hand-verified)")
struct FeedsTests {
    let hardwood = CuttingMaterial.byID("hardwood")!

    @Test func uncappedPocketing() {
        // Vc 350 m/min, 6.35 mm: ideal = 350000 / (π·6.35) ≈ 17544.9 RPM (< 24000)
        // chip = 0.025 × 6.35 = 0.15875 → clamped to 0.18 max? No: 0.15875 < 0.18, kept.
        // feed = 17544.9 × 2 × 0.15875 × 1.0
        let input = FeedsInput(material: hardwood, toolDiameterMm: 6.35, flutes: 2, toolMaterial: .carbide, operation: .pocketing, maxSpindleRpm: 24000)
        let r = FeedsCalculator.calculate(input)
        let ideal = 350_000 / (Double.pi * 6.35)
        #expect(near(r.spindleRpm, ideal))
        #expect(!r.cappedByMaxRpm)
        #expect(near(r.chipLoadMmPerTooth, 0.15875))
        #expect(near(r.feedRateMmPerMin, ideal * 2 * 0.15875))
        #expect(near(r.plungeRateMmPerMin, r.feedRateMmPerMin * 0.3))
        #expect(near(r.recommendedMaxDocMm, 0.35 * 6.35))
    }

    @Test func feedIsRecomputedFromCappedRpm() {
        let input = FeedsInput(material: hardwood, toolDiameterMm: 3.175, flutes: 2, toolMaterial: .carbide, operation: .slotting, maxSpindleRpm: 10000)
        let r = FeedsCalculator.calculate(input)
        #expect(r.cappedByMaxRpm)
        #expect(r.spindleRpm == 10000)
        // chip = 0.025 × 3.175 = 0.079375 (inside 0.03…0.18); slotting × 0.8
        #expect(near(r.feedRateMmPerMin, 10000 * 2 * 0.079375 * 0.8))
    }

    @Test func hssHalvesSpeedAndDrillingUsesFeedPerRev() {
        let al = CuttingMaterial.byID("aluminum_6061")!
        let input = FeedsInput(material: al, toolDiameterMm: 5, flutes: 2, toolMaterial: .hss, operation: .drilling, maxSpindleRpm: 30000)
        let r = FeedsCalculator.calculate(input)
        let ideal = 150_000 / (Double.pi * 5)
        #expect(near(r.spindleRpm, ideal))
        #expect(near(r.feedRateMmPerMin, ideal * 0.1)) // 0.02 × 5 = 0.1 mm/rev
        let reasons = FeedsExplainer.reasons(input: input, result: r)
        #expect(reasons.contains(.hssSlower))
        #expect(reasons.contains(.drillingFormula))
    }

    @Test func catalogKeepsPersistedIDs() {
        // Ids are stored in recipes, logs and stock: originals must never disappear.
        let original = ["aluminum_6061", "brass", "mild_steel_1018", "stainless_303_304", "acrylic_cast",
                        "hdpe_delrin", "mdf", "plywood", "hardwood", "softwood"]
        for id in original { #expect(CuttingMaterial.byID(id) != nil) }
        #expect(CuttingMaterial.catalog.count == 21)
        #expect(Set(CuttingMaterial.catalog.map(\.id)).count == 21)
    }
}

@Suite("Workshop calculators")
struct CalculatorTests {
    @Test func tapDrillMatchesPublishedCharts() {
        let m6 = ThreadSpec.catalog.first { $0.designation == "M6 x 1.0" }!
        #expect(near(m6.recommendedTapDrillMm, 5.0))
        let threeEighths = ThreadSpec.catalog.first { $0.designation == "3/8-16" }!
        #expect(near(threeEighths.recommendedTapDrillMm, 7.9375)) // = 5/16"
    }

    @Test func boltCircle() {
        let holes = BoltCircle.holes(centerX: 0, centerY: 0, radius: 10, count: 4)
        #expect(holes.count == 4)
        #expect(near(holes[1].xMm, 0, 1e-9) && near(holes[1].yMm, 10))
        #expect(BoltCircle.holes(centerX: 0, centerY: 0, radius: 5, count: 1).isEmpty)
    }

    @Test func scallopRoundTrip() {
        let h = ScallopHeight.height(toolRadius: 3, stepover: 1)
        #expect(near(h, 3 - (9 - 0.25).squareRoot()))
        #expect(near(ScallopHeight.stepover(toolRadius: 3, targetHeight: h), 1))
        #expect(ScallopHeight.height(toolRadius: 3, stepover: 7) == 3)
    }

    @Test func vBitDepthForWidth() {
        // 90° bit: depth equals half the width.
        #expect(near(VBit.depth(forWidth: 6, includedAngleDegrees: 90), 3))
        #expect(near(VBit.width(atDepth: 3, includedAngleDegrees: 90), 6))
        // 60° bit: depth = 3 / tan 30° ≈ 5.196
        #expect(near(VBit.depth(forWidth: 6, includedAngleDegrees: 60), 3 / tan(Double.pi / 6)))
    }

    @Test func chipThinning() {
        #expect(ChipThinning.feedFactor(toolDiameter: 6, radialEngagement: 3) == 1)
        // ae = 10% of D: 6 / (2·√(6·0.6 − 0.36)) = 6 / (2·1.8) ≈ 1.667
        #expect(near(ChipThinning.feedFactor(toolDiameter: 6, radialEngagement: 0.6), 6 / (2 * (3.6 - 0.36).squareRoot())))
    }

    @Test func quoteCoversFeesAndMargin() {
        let q = QuoteCalculator.quote(QuoteInput(materialCost: 8.9, machineMinutes: 43, machineHourlyRate: 12,
                                                 laborMinutes: 40, laborHourlyRate: 20,
                                                 feePercent: 0.065, feeFixed: 0.2, targetMargin: 0.6))
        let base = 8.9 + 12.0 / 60 * 43 + 20.0 / 60 * 40
        #expect(near(q.profitPerUnit, base * 0.6, 1e-9))
        #expect(near(q.suggestedUnitPrice - q.fees, base * 1.6, 1e-9))
    }

    @Test func units() {
        #expect(UnitConverter.inchToMm(1) == 25.4)
        #expect(near(UnitConverter.mmToThou(25.4), 1000))
    }
}

@Suite("Alarm decoder")
struct AlarmTests {
    @Test func decodesLabelledCodes() {
        #expect(AlarmDecoder.decode("ALARM:9").first?.title == "Homing fail: switch not found")
        #expect(AlarmDecoder.decode("error:22").first?.code == 22)
        #expect(AlarmDecoder.decode("Grbl says: Error 9").first?.kind == .error)
    }

    @Test func bareNumberOffersAlarmThenError() {
        let r = AlarmDecoder.decode(" 2 ")
        #expect(r.map(\.kind) == [.alarm, .error])
    }

    @Test func ignoresCoordinatesInScreenText() {
        let screen = "MPos: X120.000 Y45.500 Z-3.000  Line 1204  ALARM:2"
        let r = AlarmDecoder.decode(screen)
        #expect(r.count == 1)
        #expect(r.first?.code == 2)
    }

    @Test func homingStepsOnlyWithSwitches() {
        let a9 = AlarmDecoder.lookup(.alarm, 9)!
        #expect(a9.steps(machineHasHomingSwitches: false).count < a9.steps(machineHasHomingSwitches: true).count)
    }

    @Test func fullTables() {
        #expect(AlarmDecoder.alarms.map(\.code) == Array(1...10))
        #expect(AlarmDecoder.errors.count == 36)
    }
}

@Suite("Pre-flight")
struct PreflightTests {
    @Test func centeredPocketChecklist() throws {
        let (document, findings) = try load("rectangular_pocket_centered.nc")
        let items = PreflightGenerator.items(document: document, findings: findings, machine: MachineContext())
        #expect(items.contains { $0.kind == .zeroXY(.center, width: 50, height: 30) })
        #expect(items.contains { $0.kind == .zeroZ(.stockTop) })
        #expect(items.contains { $0.kind == .stockThickness(minimumMm: 2) })
        #expect(items.contains { $0.kind == .toolLoaded(toolNumber: 1, sourceLine: 5) })
        #expect(items.contains { $0.kind == .spindleSpeed(rpm: 12000, outOfRange: false) })
        #expect(!items.contains { if case .resolveDangers = $0.kind { true } else { false } })
        #expect(items.map(\.section) == items.map(\.section).sorted())
    }

    @Test func dangersBecomeACriticalItem() throws {
        let (document, findings) = try load("rapid_into_stock_danger.nc")
        let items = PreflightGenerator.items(document: document, findings: findings, machine: MachineContext())
        let item = try #require(items.first)
        #expect(item.kind == .resolveDangers(count: 1))
        #expect(item.isCritical)
    }

    @Test func oversizedJobDoesNotFitSmallMachine() throws {
        let (document, findings) = try load("oversized_for_envelope.nc")
        let small = MachineContext(envelope: MachineEnvelope(maxX: 100, maxY: 100, minZ: -40, maxZ: 40))
        let items = PreflightGenerator.items(document: document, findings: findings, machine: small)
        #expect(items.contains { if case .fitsMachine(false, _, _, _) = $0.kind { true } else { false } })
    }

    @Test func zeroCornerInference() {
        #expect(PreflightGenerator.zeroCorner(of: GBounds(minX: 0, maxX: 100, minY: 0, maxY: 50, minZ: -3, maxZ: 5)) == .lowerLeft)
        #expect(PreflightGenerator.zeroCorner(of: GBounds(minX: -100, maxX: 0, minY: -50, maxY: 0, minZ: -3, maxZ: 5)) == .upperRight)
        #expect(PreflightGenerator.zeroCorner(of: GBounds(minX: 20, maxX: 120, minY: 20, maxY: 70, minZ: -3, maxZ: 5)) == .custom(x: 20, y: 20))
    }

    @Test func toolChangeTimingFromTimeline() {
        let src = "T1 M6\nM3 S10000\nG0 Z5\nG1 Z-1 F300\nG1 X100 F600\nT2 M6\nG1 X0 F600"
        let doc = GCodeParser().parse(src, fileName: "t")
        let items = PreflightGenerator.items(document: doc, findings: GCodeAnalyzer().analyze(doc), machine: MachineContext())
        let change = items.compactMap { item -> Double? in
            if case let .toolChange(2, 6, at) = item.kind { return at } else { return nil }
        }.first
        // Z5 rapid (5 mm @ 3000) + Z-1 plunge (6 mm @ 300) + X100 (100 mm @ 600)
        let expected = 5.0 / 3000 * 60 + 6.0 / 300 * 60 + 100.0 / 600 * 60
        #expect(change.map { near($0, expected) } == true)
    }
}

@Suite("Recipe advisor")
struct RecipeTests {
    @Test func brokenToolWins() {
        #expect(RecipeAdvisor.suggest(for: [.clean, .chatter, .brokenTool]).reason == .brokenTool)
    }

    @Test func twoChatterRunsReduceFeedAndDepth() {
        let a = RecipeAdvisor.suggest(for: [.chatter, .clean, .chatter])
        #expect(a.reason == .chatter(count: 2))
        #expect(a.feedFactor == 0.9 && a.depthFactor == 0.8)
    }

    @Test func stableAfterThreeCleanRuns() {
        let a = RecipeAdvisor.suggest(for: [.chatter, .clean, .clean, .clean])
        #expect(a.reason == .stable(cleanRuns: 3))
        #expect(!a.changesAnything)
    }

    @Test func neverIncreasesDepth() {
        for outcome in JobOutcome.allCases {
            let a = RecipeAdvisor.suggest(for: [outcome, outcome, outcome])
            #expect(a.depthFactor <= 1)
        }
    }
}

@Suite("Explanations")
struct ExplanationTests {
    @Test func everyCategoryExplainsWithLineNumber() throws {
        let (_, findings) = try load("rapid_into_stock_danger.nc")
        let group = try #require(FindingGroup.group(findings).first)
        let e = Explainer.explain(group)
        #expect(e.title == "Rapid move plunges into stock")
        #expect(e.whatHappened.contains("\(group.first.sourceLine)"))
        #expect(!e.howToFix.isEmpty)
    }

    @Test func safetyScoreOrdersFiles() throws {
        let (_, clean) = try load("rectangular_pocket_centered.nc")
        let (_, risky) = try load("rapid_into_stock_danger.nc")
        #expect(SafetyScore.compute(clean) > SafetyScore.compute(risky))
    }
}
