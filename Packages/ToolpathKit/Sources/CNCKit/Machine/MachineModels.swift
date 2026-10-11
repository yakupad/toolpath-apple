import Foundation

/// Milling machines (routers, mills) and lathes read G-code differently: a
/// lathe works in the X/Z plane, X usually being a diameter.
public enum MachineKind: String, Sendable, Codable, CaseIterable {
    case mill
    case lathe
}

/// Machine travel limits in millimeters.
public struct MachineEnvelope: Sendable, Hashable, Codable {
    public var maxX: Double
    public var maxY: Double
    public var minZ: Double
    public var maxZ: Double

    public init(maxX: Double, maxY: Double, minZ: Double, maxZ: Double) {
        self.maxX = maxX
        self.maxY = maxY
        self.minZ = minZ
        self.maxZ = maxZ
    }

    /// Placeholder for a typical 3018/Shapeoko-class machine.
    public static let defaultHobby = MachineEnvelope(maxX: 300, maxY: 180, minZ: -80, maxZ: 80)

    public var travelZ: Double { maxZ - minZ }

    /// Origin-anchored check (work zero at machine 0,0). Only meaningful when
    /// the user's work offset really sits near machine home — opt-in.
    public func contains(x: Double, y: Double, z: Double) -> Bool {
        x >= 0 && x <= maxX && y >= 0 && y <= maxY && z >= minZ && z <= maxZ
    }

    /// Offset-independent check: does the job's footprint fit the travel at
    /// all, wherever the work zero is placed?
    public func fits(width: Double, height: Double, depth: Double) -> Bool {
        width <= maxX && height <= maxY && depth <= travelZ
    }
}

public enum ToolMaterial: String, Sendable, Codable, CaseIterable {
    case carbide
    case hss

    /// HSS cuts at roughly half the surface speed of carbide.
    public var speedMultiplier: Double { self == .carbide ? 1.0 : 0.5 }
}

public enum ToolShape: String, Sendable, Codable, CaseIterable {
    case flat
    case ball
    case vBit
    case compression
    case drill
}

public enum ControllerKind: String, Sendable, Codable, CaseIterable {
    case grbl
    case grblHAL
    case fluidNC
    case other
}
