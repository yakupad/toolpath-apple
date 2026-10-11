import CoreGraphics
import Testing
@testable import CNCKit
@testable import CNCRender

@Suite("Render performance")
struct RenderPerformanceTests {
    @Test func hundredThousandMovesBuildQuickly() {
        var lines = ["G21 G90", "M3 S12000", "G0 Z5", "G1 Z-1 F300"]
        for i in 0..<100_000 {
            let a = Double(i) * 0.01
            lines.append("G1 X\(String(format: "%.3f", 60 + 50 * cos(a) * (1 + Double(i) / 200_000))) Y\(String(format: "%.3f", 60 + 50 * sin(a))) F800")
        }
        let doc = GCodeParser().parse(lines.joined(separator: "\n"), fileName: "big")
        let geometry = ToolpathGeometry(document: doc, findings: [])
        let projection = Projection(camera: .isometric, size: CGSize(width: 1200, height: 900), bounds: geometry.bounds)
        let clock = ContinuousClock()
        var count = 0
        let elapsed = clock.measure {
            let paths = ToolpathPathBuilder.build(geometry: geometry, projection: projection, filter: MoveFilter(), limit: .max, cursor: nil)
            count = paths.count
        }
        #expect(count > 0)
        print("100k-move frame build:", elapsed)
        #expect(elapsed < .seconds(2))
    }
}
