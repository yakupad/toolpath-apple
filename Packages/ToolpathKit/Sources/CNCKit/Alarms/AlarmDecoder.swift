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
        alarm(1, "Hard limit triggered",
              "A limit switch was hit during motion. Machine position is likely lost.",
              lost: true,
              homing: ["Check whether the gantry really reached the end of travel, or a switch triggered from noise or a loose wire."],
              ["Unlock ($X), jog away from the switch, then re-home before cutting.",
               "If it happened mid-job, check the file's bounds against your work zero — the job may be larger than the space you left."]),
        alarm(2, "Soft limit",
              "A move in the program targets a position outside the machine's configured travel. Position is kept; it is safe to unlock.",
              lost: false,
              homing: ["Home the machine first — soft limits only work after homing."],
              ["Check where you set work zero: the job may extend past the end of travel from that point.",
               "Compare the file's size (Job › Stats) with your machine's travel.",
               "Verify $130–$132 (max travel) match your machine."]),
        alarm(3, "Reset while in motion",
              "The controller was reset during a move, so steps may have been lost.",
              lost: true,
              ["Re-home (or re-zero X, Y and Z) before continuing.",
               "To resume a job, restart from a safe line above the stock — never mid-cut."]),
        alarm(4, "Probe fail: probe already triggered",
              "The probe was not in the expected state before the probing cycle started.",
              lost: false,
              ["Make sure the touch plate is not already touching the bit, and the magnet clip is on the bit, not the plate.",
               "Check the probe wiring for a short."]),
        alarm(5, "Probe fail: no contact",
              "The probe did not touch the plate within the programmed travel.",
              lost: false,
              ["Start the probe closer to the plate.",
               "Confirm the clip is attached and the plate is on the work surface under the bit.",
               "Test the circuit: touch the plate to the bit — the controller should report a probe trigger."]),
        alarm(6, "Homing fail: reset during homing",
              "The homing cycle was interrupted by a reset.",
              lost: true,
              ["Run homing again and let it finish."]),
        alarm(7, "Homing fail: door opened",
              "The safety door input was triggered during homing.",
              lost: true,
              ["Close the enclosure door (or check the door switch wiring) and home again."]),
        alarm(8, "Homing fail: could not clear switch",
              "After touching a limit switch the axis could not pull off far enough to release it.",
              lost: true,
              homing: ["Increase the homing pull-off ($27), e.g. to 2–3 mm.",
                       "Check the switch for a stuck lever or wiring that holds it closed."],
              []),
        alarm(9, "Homing fail: switch not found",
              "An axis could not find its limit switch within the search distance.",
              lost: true,
              homing: ["Check the switch connectors on the controller — an unplugged switch is the most common cause.",
                       "Make sure max travel ($130–$132) is at least your machine's real travel.",
                       "Watch which axis moves during homing; that is the one with the problem."],
              ["If your machine has no homing switches, disable homing ($22=0)."]),
        alarm(10, "E-stop or second switch not found",
              "On grblHAL/FluidNC this is the emergency stop. On GRBL 1.1h dual-axis machines, the second limit switch for squaring was not found.",
              lost: true,
              ["Release the E-stop, then reset and re-home.",
               "On dual-motor gantries, check the second Y (or X) switch and its wiring."]),
    ]

    public static let errors: [ControllerMessage] = [
        error(1, "Missing letter", "A G-code word is missing its letter."),
        error(2, "Bad number", "A number is missing or badly formatted.",
              ["Look for a stray character or a missing value on the reported line.",
               "Re-export from CAM with the GRBL post processor."]),
        error(3, "Unknown $ command", "The '$' system command is not recognized."),
        error(4, "Negative value", "A negative value was given where a positive one is required."),
        error(5, "Homing disabled", "Homing is not enabled in settings ($22).",
              ["Enable homing with $22=1 if your machine has homing switches."]),
        error(6, "Step pulse too short", "Step pulse time must be greater than 3 µs."),
        error(7, "Settings read failed", "Settings memory could not be read; defaults were restored.",
              ["Re-enter your machine's settings ($100+ steps/mm, $110+ max rates, $130+ travel)."]),
        error(8, "Not idle", "This '$' command can only run while the controller is idle."),
        error(9, "Locked", "G-code is locked out during an alarm or jog.",
              ["Clear the alarm first ($X to unlock, or home), then send again."]),
        error(10, "Soft limits need homing", "Soft limits cannot be enabled without homing."),
        error(11, "Line too long", "A line exceeds the maximum length and was not executed."),
        error(12, "Step rate too high", "A setting exceeds the maximum supported step rate."),
        error(13, "Safety door open", "The safety door was detected open."),
        error(14, "Line too long for storage", "Build info or startup line exceeds the storage limit."),
        error(15, "Jog beyond travel", "A jog target exceeds machine travel and was ignored.",
              ["Jog in the other direction or re-home so the controller knows where it is."]),
        error(16, "Invalid jog command", "Jog command has no '=' or contains prohibited G-code."),
        error(17, "Laser mode needs PWM", "Laser mode requires a PWM spindle output."),
        error(20, "Unsupported G-code", "The block contains a G-code command the controller does not support.",
              ["Re-export with a GRBL post processor — commands like G41/G42 cutter compensation or canned cycles are not supported.",
               "Check the reported line in Job › G-code text."]),
        error(21, "Conflicting commands", "Two commands from the same modal group are on one line."),
        error(22, "Feed rate not set", "A cutting move was sent before any feed rate (F).",
              ["Add an F value before the first G1/G2/G3, or re-export from CAM.",
               "Toolpath flags this before you run: look for a 'No feed rate' warning."]),
        error(23, "Integer required", "A command requires an integer value."),
        error(24, "Two axis commands", "Two commands on one line both need XYZ words."),
        error(25, "Repeated word", "A G-code word is repeated on one line."),
        error(26, "Missing axis words", "The command needs X, Y or Z words but none were found."),
        error(27, "Line number out of range", "N line number is outside 1–9,999,999."),
        error(28, "Missing P or L", "The command is missing a required P or L value."),
        error(29, "Unsupported work offset", "Only G54–G59 are supported."),
        error(30, "G53 needs G0 or G1", "G53 requires G0 or G1 motion mode."),
        error(31, "Unused axis words", "Axis words were given while motion is cancelled (G80)."),
        error(32, "Arc without axis words", "A G2/G3 arc has no axis words in the selected plane."),
        error(33, "Invalid motion target", "An arc or probe target is impossible (e.g. the arc cannot be generated).",
              ["Re-export with arc output limited to the XY plane, or disable arcs in the post (output lines instead)."]),
        error(34, "Arc radius error", "An R-format arc had a geometry error.",
              ["Prefer I/J arc output in your CAM post instead of R."]),
        error(35, "Arc missing offset", "An I/J arc is missing its offset word in the selected plane."),
        error(36, "Leftover words", "Unused G-code words remain on the line."),
        error(37, "Tool length offset axis", "G43.1 cannot apply an offset to this axis."),
        error(38, "Tool number too high", "Tool number exceeds the supported maximum."),
    ]
}
