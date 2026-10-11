import CoreGraphics
import CNCKit
import Foundation

/// Orthographic orbit camera. Deliberately not a 3D engine: the toolpath is
/// wireframe geometry, so yaw/pitch + projection is all we need.
public struct OrbitCamera: Sendable, Hashable {
    /// Rotation around Z (radians).
    public var yaw: Double
    /// Elevation above the XY plane (radians). π/2 = straight down.
    public var pitch: Double
    /// Multiplier on the fit-to-view scale.
    public var zoom: Double
    /// Screen-space pan in points.
    public var pan: CGSize
    /// Visual Z exaggeration (parsed coordinates are never changed).
    public var zScale: Double

    public init(yaw: Double, pitch: Double, zoom: Double = 1, pan: CGSize = .zero, zScale: Double = 6) {
        self.yaw = yaw
        self.pitch = pitch
        self.zoom = zoom
        self.pan = pan
        self.zScale = zScale
    }

    public static let isometric = OrbitCamera(yaw: -.pi / 4, pitch: 37.5 * .pi / 180)
    public static let top = OrbitCamera(yaw: 0, pitch: .pi / 2, zScale: 1)

    public enum Preset: String, CaseIterable, Sendable {
        case isometric, top, front, right, left, back, bottom

        public var camera: OrbitCamera {
            switch self {
            case .isometric: .isometric
            case .top: OrbitCamera(yaw: 0, pitch: .pi / 2)
            case .bottom: OrbitCamera(yaw: 0, pitch: -.pi / 2)
            case .front: OrbitCamera(yaw: 0, pitch: 0)
            case .back: OrbitCamera(yaw: .pi, pitch: 0)
            case .right: OrbitCamera(yaw: -.pi / 2, pitch: 0)
            case .left: OrbitCamera(yaw: .pi / 2, pitch: 0)
            }
        }
    }

    /// Rotates a model point (already centered) into view space: x right,
    /// y up on screen, depth toward the viewer.
    @inline(__always)
    public func rotate(x: Double, y: Double, z: Double) -> (x: Double, y: Double, depth: Double) {
        let cy = cos(yaw), sy = sin(yaw)
        let rx = x * cy - y * sy
        let ry = x * sy + y * cy
        let zz = z * zScale
        let cp = cos(pitch), sp = sin(pitch)
        // Looking from -Y toward +Y, tilted down by `pitch`.
        let screenY = ry * sp + zz * cp
        let depth = -ry * cp + zz * sp
        return (rx, screenY, depth)
    }

    public static func lerp(_ a: OrbitCamera, _ b: OrbitCamera, _ t: Double) -> OrbitCamera {
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        // Shortest way around for yaw.
        var dyaw = (b.yaw - a.yaw).truncatingRemainder(dividingBy: 2 * .pi)
        if dyaw > .pi { dyaw -= 2 * .pi }
        if dyaw < -.pi { dyaw += 2 * .pi }
        return OrbitCamera(
            yaw: a.yaw + dyaw * t,
            pitch: mix(a.pitch, b.pitch),
            zoom: mix(a.zoom, b.zoom),
            pan: CGSize(width: mix(a.pan.width, b.pan.width), height: mix(a.pan.height, b.pan.height)),
            zScale: mix(a.zScale, b.zScale)
        )
    }
}

/// Maps model space to screen space for one frame.
public struct Projection: Sendable {
    public let camera: OrbitCamera
    public let size: CGSize
    let center: GPoint
    let scale: Double
    /// Screen point the job's center maps to (center of the unobscured area).
    let origin: CGPoint
    // Precomputed rotation terms: point() runs for every vertex every frame.
    let cy: Double, sy: Double, cp: Double, sp: Double, zScale: Double

    /// Fits the job's footprint (not the machine bed) into the part of the
    /// viewport not covered by `insets` (toolbars, bottom panel).
    public init(camera: OrbitCamera, size: CGSize, bounds: GBounds, padding: Double = 32, insets: EdgeInsetsValue = .zero) {
        self.camera = camera
        self.size = size
        self.center = bounds.center
        let visible = CGSize(width: max(size.width - insets.leading - insets.trailing, 1),
                             height: max(size.height - insets.top - insets.bottom, 1))
        self.origin = CGPoint(x: insets.leading + visible.width / 2, y: insets.top + visible.height / 2)
        self.cy = cos(camera.yaw); self.sy = sin(camera.yaw)
        self.cp = cos(camera.pitch); self.sp = sin(camera.pitch)
        self.zScale = camera.zScale
        let corners: [GPoint] = [
            GPoint(x: bounds.minX, y: bounds.minY, z: bounds.minZ), GPoint(x: bounds.maxX, y: bounds.minY, z: bounds.minZ),
            GPoint(x: bounds.minX, y: bounds.maxY, z: bounds.minZ), GPoint(x: bounds.maxX, y: bounds.maxY, z: bounds.minZ),
            GPoint(x: bounds.minX, y: bounds.minY, z: bounds.maxZ), GPoint(x: bounds.maxX, y: bounds.minY, z: bounds.maxZ),
            GPoint(x: bounds.minX, y: bounds.maxY, z: bounds.maxZ), GPoint(x: bounds.maxX, y: bounds.maxY, z: bounds.maxZ),
        ]
        var minX = Double.infinity, maxX = -Double.infinity, minY = Double.infinity, maxY = -Double.infinity
        for c in corners {
            let r = camera.rotate(x: c.x - bounds.center.x, y: c.y - bounds.center.y, z: c.z - bounds.center.z)
            minX = min(minX, r.x); maxX = max(maxX, r.x)
            minY = min(minY, r.y); maxY = max(maxY, r.y)
        }
        let w = max(maxX - minX, 1e-6), h = max(maxY - minY, 1e-6)
        let fit = min((visible.width - padding * 2) / w, (visible.height - padding * 2) / h)
        self.scale = max(fit, 1e-6) * camera.zoom
    }

    @inline(__always)
    public func point(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
        let dx = x - center.x, dy = y - center.y, dz = (z - center.z) * zScale
        let rx = dx * cy - dy * sy
        let ry = dx * sy + dy * cy
        let screenY = ry * sp + dz * cp
        return CGPoint(
            x: origin.x + rx * scale + camera.pan.width,
            y: origin.y - screenY * scale + camera.pan.height
        )
    }

    public func point(_ p: GPoint) -> CGPoint { point(p.x, p.y, p.z) }

    /// Millimeters per screen point at the current zoom.
    public var pointsPerMillimeter: Double { scale }
}

/// Platform-neutral edge insets (CoreGraphics only).
public struct EdgeInsetsValue: Sendable, Hashable {
    public var top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat
    public init(top: CGFloat = 0, leading: CGFloat = 0, bottom: CGFloat = 0, trailing: CGFloat = 0) {
        self.top = top; self.leading = leading; self.bottom = bottom; self.trailing = trailing
    }
    public static let zero = EdgeInsetsValue()
}
