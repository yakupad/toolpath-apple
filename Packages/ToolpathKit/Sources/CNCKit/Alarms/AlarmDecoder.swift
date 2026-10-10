import Foundation

/// Offline decoder for GRBL 1.1 / grblHAL / FluidNC alarm and error codes.
/// Text is curated from the published GRBL 1.1 message tables; the "steps"
/// are conservative shop-floor checks, ordered most-likely first.
public enum ControllerMessageKind: String, Sendable, Codable {
    case alarm
    case error
}

public struct ControllerMessage: Sendable, Hashable, Identifiable {
    public var id: String { "\(kind.rawValue):\(code)" }
    public let kind: ControllerMessageKind
    public let code: Int
    public let title: String
    public let meaning: String
    /// Whether machine position is probably lost (re-home before cutting).
    public let positionLost: Bool
    public let steps: [String]
    /// Steps that only apply when the machine has homing switches.
    public let homingSteps: [String]

    /// Steps tailored to the machine: homing-related checks are dropped
    /// when the user's machine has no homing switches.
    public func steps(machineHasHomingSwitches: Bool) -> [String] {
        machineHasHomingSwitches ? homingSteps + steps : steps
    }
}

public enum AlarmDecoder {
    /// Parses free text such as "ALARM:9", "alarm 2", "error:22", "Error 9",
    /// "E22" or a bare "9" (treated as an alarm) — including OCR output from
    /// a photo of a sender's screen.
    public static func decode(_ text: String) -> [ControllerMessage] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // A bare number ("9") is ambiguous: offer the alarm first, then the error.
        if let code = Int(trimmed) {
            return [lookup(.alarm, code), lookup(.error, code)].compactMap { $0 }
        }
        // Labelled codes only, so coordinates in OCR'd screens don't match.
        let pattern = /\b(alarm|error|err|e)\s*[:#]?\s*(\d{1,3})\b/
        var results: [ControllerMessage] = []
        for match in trimmed.matches(of: pattern) {
            guard let code = Int(match.output.2) else { continue }
            let kind: ControllerMessageKind = match.output.1 == "alarm" ? .alarm : .error
            if let message = lookup(kind, code), !results.contains(message) {
                results.append(message)
            }
        }
        return results
    }

    public static func lookup(_ kind: ControllerMessageKind, _ code: Int) -> ControllerMessage? {
        (kind == .alarm ? alarms : errors).first { $0.code == code }
    }

    static func alarm(_ code: Int, _ title: String, _ meaning: String, lost: Bool, homing: [String] = [], _ steps: [String]) -> ControllerMessage {
        ControllerMessage(kind: .alarm, code: code, title: title, meaning: meaning, positionLost: lost, steps: steps, homingSteps: homing)
    }

    static func error(_ code: Int, _ title: String, _ meaning: String, _ steps: [String] = []) -> ControllerMessage {
        ControllerMessage(kind: .error, code: code, title: title, meaning: meaning, positionLost: false, steps: steps, homingSteps: [])
    }

    public static let alarms: [ControllerMessage] = [
        alarm(1, String(localized: "Hard limit triggered", bundle: .module),
              String(localized: "A limit switch was hit during motion. Machine position is likely lost.", bundle: .module),
              lost: true,
              homing: [String(localized: "Check whether the gantry really reached the end of travel, or a switch triggered from noise or a loose wire.", bundle: .module)],
              [String(localized: "Unlock ($X), jog away from the switch, then re-home before cutting.", bundle: .module),
               String(localized: "If it happened mid-job, check the file's bounds against your work zero — the job may be larger than the space you left.", bundle: .module)]),
        alarm(2, String(localized: "Soft limit", bundle: .module),
              String(localized: "A move in the program targets a position outside the machine's configured travel. Position is kept; it is safe to unlock.", bundle: .module),
              lost: false,
              homing: [String(localized: "Home the machine first — soft limits only work after homing.", bundle: .module)],
              [String(localized: "Check where you set work zero: the job may extend past the end of travel from that point.", bundle: .module),
               String(localized: "Compare the file's size (Job › Stats) with your machine's travel.", bundle: .module),
               String(localized: "Verify $130–$132 (max travel) match your machine.", bundle: .module)]),
        alarm(3, String(localized: "Reset while in motion", bundle: .module),
              String(localized: "The controller was reset during a move, so steps may have been lost.", bundle: .module),
              lost: true,
              [String(localized: "Re-home (or re-zero X, Y and Z) before continuing.", bundle: .module),
               String(localized: "To resume a job, restart from a safe line above the stock — never mid-cut.", bundle: .module)]),
        alarm(4, String(localized: "Probe fail: probe already triggered", bundle: .module),
              String(localized: "The probe was not in the expected state before the probing cycle started.", bundle: .module),
              lost: false,
              [String(localized: "Make sure the touch plate is not already touching the bit, and the magnet clip is on the bit, not the plate.", bundle: .module),
               String(localized: "Check the probe wiring for a short.", bundle: .module)]),
        alarm(5, String(localized: "Probe fail: no contact", bundle: .module),
              String(localized: "The probe did not touch the plate within the programmed travel.", bundle: .module),
              lost: false,
              [String(localized: "Start the probe closer to the plate.", bundle: .module),
               String(localized: "Confirm the clip is attached and the plate is on the work surface under the bit.", bundle: .module),
               String(localized: "Test the circuit: touch the plate to the bit — the controller should report a probe trigger.", bundle: .module)]),
        alarm(6, String(localized: "Homing fail: reset during homing", bundle: .module),
              String(localized: "The homing cycle was interrupted by a reset.", bundle: .module),
              lost: true,
              [String(localized: "Run homing again and let it finish.", bundle: .module)]),
        alarm(7, String(localized: "Homing fail: door opened", bundle: .module),
              String(localized: "The safety door input was triggered during homing.", bundle: .module),
              lost: true,
              [String(localized: "Close the enclosure door (or check the door switch wiring) and home again.", bundle: .module)]),
        alarm(8, String(localized: "Homing fail: could not clear switch", bundle: .module),
              String(localized: "After touching a limit switch the axis could not pull off far enough to release it.", bundle: .module),
              lost: true,
              homing: [String(localized: "Increase the homing pull-off ($27), e.g. to 2–3 mm.", bundle: .module),
                       String(localized: "Check the switch for a stuck lever or wiring that holds it closed.", bundle: .module)],
              []),
        alarm(9, String(localized: "Homing fail: switch not found", bundle: .module),
              String(localized: "An axis could not find its limit switch within the search distance.", bundle: .module),
              lost: true,
              homing: [String(localized: "Check the switch connectors on the controller — an unplugged switch is the most common cause.", bundle: .module),
                       String(localized: "Make sure max travel ($130–$132) is at least your machine's real travel.", bundle: .module),
                       String(localized: "Watch which axis moves during homing; that is the one with the problem.", bundle: .module)],
              [String(localized: "If your machine has no homing switches, disable homing ($22=0).", bundle: .module)]),
        alarm(10, String(localized: "E-stop or second switch not found", bundle: .module),
              String(localized: "On grblHAL/FluidNC this is the emergency stop. On GRBL 1.1h dual-axis machines, the second limit switch for squaring was not found.", bundle: .module),
              lost: true,
              [String(localized: "Release the E-stop, then reset and re-home.", bundle: .module),
               String(localized: "On dual-motor gantries, check the second Y (or X) switch and its wiring.", bundle: .module)]),
    ]

    public static let errors: [ControllerMessage] = [
        error(1, String(localized: "Missing letter", bundle: .module), String(localized: "A G-code word is missing its letter.", bundle: .module)),
        error(2, String(localized: "Bad number", bundle: .module), String(localized: "A number is missing or badly formatted.", bundle: .module),
              [String(localized: "Look for a stray character or a missing value on the reported line.", bundle: .module),
               String(localized: "Re-export from CAM with the GRBL post processor.", bundle: .module)]),
        error(3, String(localized: "Unknown $ command", bundle: .module), String(localized: "The '$' system command is not recognized.", bundle: .module)),
        error(4, String(localized: "Negative value", bundle: .module), String(localized: "A negative value was given where a positive one is required.", bundle: .module)),
        error(5, String(localized: "Homing disabled", bundle: .module), String(localized: "Homing is not enabled in settings ($22).", bundle: .module),
              [String(localized: "Enable homing with $22=1 if your machine has homing switches.", bundle: .module)]),
        error(6, String(localized: "Step pulse too short", bundle: .module), String(localized: "Step pulse time must be greater than 3 µs.", bundle: .module)),
        error(7, String(localized: "Settings read failed", bundle: .module), String(localized: "Settings memory could not be read; defaults were restored.", bundle: .module),
              [String(localized: "Re-enter your machine's settings ($100+ steps/mm, $110+ max rates, $130+ travel).", bundle: .module)]),
        error(8, String(localized: "Not idle", bundle: .module), String(localized: "This '$' command can only run while the controller is idle.", bundle: .module)),
        error(9, String(localized: "Locked", bundle: .module), String(localized: "G-code is locked out during an alarm or jog.", bundle: .module),
              [String(localized: "Clear the alarm first ($X to unlock, or home), then send again.", bundle: .module)]),
        error(10, String(localized: "Soft limits need homing", bundle: .module), String(localized: "Soft limits cannot be enabled without homing.", bundle: .module)),
        error(11, String(localized: "Line too long", bundle: .module), String(localized: "A line exceeds the maximum length and was not executed.", bundle: .module)),
        error(12, String(localized: "Step rate too high", bundle: .module), String(localized: "A setting exceeds the maximum supported step rate.", bundle: .module)),
        error(13, String(localized: "Safety door open", bundle: .module), String(localized: "The safety door was detected open.", bundle: .module)),
        error(14, String(localized: "Line too long for storage", bundle: .module), String(localized: "Build info or startup line exceeds the storage limit.", bundle: .module)),
        error(15, String(localized: "Jog beyond travel", bundle: .module), String(localized: "A jog target exceeds machine travel and was ignored.", bundle: .module),
              [String(localized: "Jog in the other direction or re-home so the controller knows where it is.", bundle: .module)]),
        error(16, String(localized: "Invalid jog command", bundle: .module), String(localized: "Jog command has no '=' or contains prohibited G-code.", bundle: .module)),
        error(17, String(localized: "Laser mode needs PWM", bundle: .module), String(localized: "Laser mode requires a PWM spindle output.", bundle: .module)),
        error(20, String(localized: "Unsupported G-code", bundle: .module), String(localized: "The block contains a G-code command the controller does not support.", bundle: .module),
              [String(localized: "Re-export with a GRBL post processor — commands like G41/G42 cutter compensation or canned cycles are not supported.", bundle: .module),
               String(localized: "Check the reported line in Job › G-code text.", bundle: .module)]),
        error(21, String(localized: "Conflicting commands", bundle: .module), String(localized: "Two commands from the same modal group are on one line.", bundle: .module)),
        error(22, String(localized: "Feed rate not set", bundle: .module), String(localized: "A cutting move was sent before any feed rate (F).", bundle: .module),
              [String(localized: "Add an F value before the first G1/G2/G3, or re-export from CAM.", bundle: .module),
               String(localized: "Toolpath flags this before you run: look for a 'No feed rate' warning.", bundle: .module)]),
        error(23, String(localized: "Integer required", bundle: .module), String(localized: "A command requires an integer value.", bundle: .module)),
        error(24, String(localized: "Two axis commands", bundle: .module), String(localized: "Two commands on one line both need XYZ words.", bundle: .module)),
        error(25, String(localized: "Repeated word", bundle: .module), String(localized: "A G-code word is repeated on one line.", bundle: .module)),
        error(26, String(localized: "Missing axis words", bundle: .module), String(localized: "The command needs X, Y or Z words but none were found.", bundle: .module)),
        error(27, String(localized: "Line number out of range", bundle: .module), String(localized: "N line number is outside 1–9,999,999.", bundle: .module)),
        error(28, String(localized: "Missing P or L", bundle: .module), String(localized: "The command is missing a required P or L value.", bundle: .module)),
        error(29, String(localized: "Unsupported work offset", bundle: .module), String(localized: "Only G54–G59 are supported.", bundle: .module)),
        error(30, String(localized: "G53 needs G0 or G1", bundle: .module), String(localized: "G53 requires G0 or G1 motion mode.", bundle: .module)),
        error(31, String(localized: "Unused axis words", bundle: .module), String(localized: "Axis words were given while motion is cancelled (G80).", bundle: .module)),
        error(32, String(localized: "Arc without axis words", bundle: .module), String(localized: "A G2/G3 arc has no axis words in the selected plane.", bundle: .module)),
        error(33, String(localized: "Invalid motion target", bundle: .module), String(localized: "An arc or probe target is impossible (e.g. the arc cannot be generated).", bundle: .module),
              [String(localized: "Re-export with arc output limited to the XY plane, or disable arcs in the post (output lines instead).", bundle: .module)]),
        error(34, String(localized: "Arc radius error", bundle: .module), String(localized: "An R-format arc had a geometry error.", bundle: .module),
              [String(localized: "Prefer I/J arc output in your CAM post instead of R.", bundle: .module)]),
        error(35, String(localized: "Arc missing offset", bundle: .module), String(localized: "An I/J arc is missing its offset word in the selected plane.", bundle: .module)),
        error(36, String(localized: "Leftover words", bundle: .module), String(localized: "Unused G-code words remain on the line.", bundle: .module)),
        error(37, String(localized: "Tool length offset axis", bundle: .module), String(localized: "G43.1 cannot apply an offset to this axis.", bundle: .module)),
        error(38, String(localized: "Tool number too high", bundle: .module), String(localized: "Tool number exceeds the supported maximum.", bundle: .module)),
    ]
}
