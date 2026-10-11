import Foundation

/// A parsed GRBL 1.1 / grblHAL / FluidNC real-time status report, e.g.
/// `<Run|MPos:12.000,4.500,-1.000|FS:800,12000|Ln:1204|WCO:0.000,0.000,0.000>`.
/// Read-only monitoring uses only the `?` query, which never moves the machine.
public struct ControllerStatus: Sendable, Hashable {
    public enum State: String, Sendable, Hashable {
        case idle = "Idle", run = "Run", hold = "Hold", jog = "Jog", alarm = "Alarm"
        case door = "Door", check = "Check", home = "Home", sleep = "Sleep", tool = "Tool"
        case unknown
    }

    public var state: State
    /// Sub-state such as Hold:0 or Door:1.
    public var subState: Int?
    public var machinePosition: GPoint?
    public var workPosition: GPoint?
    public var workOffset: GPoint?
    public var feed: Double?
    public var spindle: Double?
    /// Line number being executed, when the sender numbers lines (`Ln:`).
    public var lineNumber: Int?
    /// Active pins, e.g. "XYZP" for limit/probe inputs.
    public var pins: String?

    /// Work position, derived from MPos − WCO when only MPos is reported.
    public var resolvedWorkPosition: GPoint? {
        if let workPosition { return workPosition }
        guard let m = machinePosition else { return nil }
        guard let o = workOffset else { return m }
        return GPoint(x: m.x - o.x, y: m.y - o.y, z: m.z - o.z)
    }

    public static func parse(_ line: String) -> ControllerStatus? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("<"), trimmed.hasSuffix(">") else { return nil }
        let body = trimmed.dropFirst().dropLast()
        var fields = body.split(separator: "|").map(String.init)
        guard !fields.isEmpty else { return nil }

        let stateField = fields.removeFirst()
        let stateParts = stateField.split(separator: ":")
        var status = ControllerStatus(state: State(rawValue: String(stateParts[0])) ?? .unknown)
        if stateParts.count > 1 { status.subState = Int(stateParts[1]) }

        for field in fields {
            guard let colon = field.firstIndex(of: ":") else { continue }
            let key = field[..<colon]
            let value = String(field[field.index(after: colon)...])
            let numbers = value.split(separator: ",").compactMap { Double($0) }
            switch key {
            case "MPos": status.machinePosition = point(numbers)
            case "WPos": status.workPosition = point(numbers)
            case "WCO": status.workOffset = point(numbers)
            case "FS":
                status.feed = numbers.first
                status.spindle = numbers.count > 1 ? numbers[1] : nil
            case "F": status.feed = numbers.first
            case "Ln": status.lineNumber = Int(value)
            case "Pn": status.pins = value
            default: break
            }
        }
        return status
    }

    static func point(_ n: [Double]) -> GPoint? {
        n.count >= 3 ? GPoint(x: n[0], y: n[1], z: n[2]) : nil
    }

    public init(state: State) { self.state = state }
}

/// Unsolicited controller messages worth surfacing (alarms, errors).
public enum ControllerEvent: Sendable, Hashable {
    case alarm(Int)
    case error(Int)
    case message(String)

    public static func parse(_ line: String) -> ControllerEvent? {
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.uppercased().hasPrefix("ALARM:"), let n = Int(t.dropFirst(6)) { return .alarm(n) }
        if t.lowercased().hasPrefix("error:"), let n = Int(t.dropFirst(6)) { return .error(n) }
        if t.hasPrefix("[MSG:"), t.hasSuffix("]") { return .message(String(t.dropFirst(5).dropLast())) }
        return nil
    }
}
