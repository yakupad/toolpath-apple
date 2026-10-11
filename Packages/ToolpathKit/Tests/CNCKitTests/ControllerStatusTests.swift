import Testing
@testable import CNCKit

@Suite("Controller status")
struct ControllerStatusTests {
    @Test func parsesRunningReport() throws {
        let s = try #require(ControllerStatus.parse("<Run|MPos:12.000,4.500,-1.000|FS:800,12000|Ln:1204|WCO:2.000,1.000,-0.500>"))
        #expect(s.state == .run)
        #expect(s.machinePosition == GPoint(x: 12, y: 4.5, z: -1))
        #expect(s.feed == 800 && s.spindle == 12000)
        #expect(s.lineNumber == 1204)
        #expect(s.resolvedWorkPosition == GPoint(x: 10, y: 3.5, z: -0.5))
    }

    @Test func parsesHoldSubstateAndWorkPosition() throws {
        let s = try #require(ControllerStatus.parse("<Hold:0|WPos:1.0,2.0,3.0|F:500|Pn:XZ>"))
        #expect(s.state == .hold && s.subState == 0)
        #expect(s.resolvedWorkPosition == GPoint(x: 1, y: 2, z: 3))
        #expect(s.feed == 500)
        #expect(s.pins == "XZ")
    }

    @Test func rejectsNonStatusLines() {
        #expect(ControllerStatus.parse("ok") == nil)
        #expect(ControllerStatus.parse("Grbl 1.1h ['$' for help]") == nil)
    }

    @Test func parsesEvents() {
        #expect(ControllerEvent.parse("ALARM:9") == .alarm(9))
        #expect(ControllerEvent.parse("error:22") == .error(22))
        #expect(ControllerEvent.parse("[MSG:Caution: Unlocked]") == .message("Caution: Unlocked"))
        #expect(ControllerEvent.parse("ok") == nil)
    }
}
