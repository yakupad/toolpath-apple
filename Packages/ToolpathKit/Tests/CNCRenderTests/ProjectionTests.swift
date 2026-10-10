import CoreGraphics
import Testing
@testable import CNCKit
@testable import CNCRender

@Suite("Projection")
struct ProjectionTests {
    let bounds = GBounds(minX: 0, maxX: 100, minY: 0, maxY: 50, minZ: -5, maxZ: 5)

    @Test func topViewMapsXRightAndYUp() {
        let p = Projection(camera: .top, size: CGSize(width: 400, height: 400), bounds: bounds)
        let left = p.point(0, 25, 0), right = p.point(100, 25, 0)
        let low = p.point(50, 0, 0), high = p.point(50, 50, 0)
        #expect(right.x > left.x)
        #expect(high.y < low.y) // screen y grows downward
    }

    @Test func fitKeepsFootprintInsideViewport() {
        let size = CGSize(width: 390, height: 500)
        let p = Projection(camera: .isometric, size: size, bounds: bounds)
        for x in [0.0, 100] {
            for y in [0.0, 50] {
                for z in [-5.0, 5] {
                    let s = p.point(x, y, z)
                    #expect(s.x >= 0 && s.x <= size.width && s.y >= 0 && s.y <= size.height)
                }
            }
        }
    }

    @Test func cameraLerpTakesShortestYaw() {
        let a = OrbitCamera(yaw: 3.0, pitch: 0), b = OrbitCamera(yaw: -3.0, pitch: 0)
        let mid = OrbitCamera.lerp(a, b, 0.5)
        #expect(abs(abs(mid.yaw) - .pi) < 0.2)
    }

    @Test func geometryStylesFlaggedMovesAsDanger() {
        let doc = GCodeParser().parse("M3 S9000\nG0 Z5\nG0 X10 Z-2\nG1 X20 F300", fileName: "t")
        let findings = GCodeAnalyzer().analyze(doc)
        let geometry = ToolpathGeometry(document: doc, findings: findings)
        #expect(geometry.segments[1].style == .danger)
        #expect(geometry.segments[2].style == .cut)
    }
}
