import AppIntents
import CNCKit
import SwiftUI

/// Workpiece materials exposed to Shortcuts and Siri. Raw values are the
/// persisted CuttingMaterial ids — never renumber or rename them.
enum MaterialOption: String, AppEnum {
    case aluminum = "aluminum_6061"
    case brass
    case mildSteel = "mild_steel_1018"
    case stainless = "stainless_303_304"
    case acrylic = "acrylic_cast"
    case hdpe = "hdpe_delrin"
    case mdf
    case plywood
    case hardwood
    case softwood
    case copper
    case polycarbonate
    case abs
    case nylon
    case pvcFoam = "pvc_foam"
    case solidSurface = "solid_surface"
    case machinableWax = "machinable_wax"
    case fr4 = "fr4_pcb"
    case carbonFiber = "carbon_fiber"
    case xpsFoam = "foam_xps"
    case bamboo

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Material"
    static let caseDisplayRepresentations: [MaterialOption: DisplayRepresentation] = [
        .aluminum: "Aluminum",
        .brass: "Brass",
        .mildSteel: "Mild steel",
        .stainless: "Stainless steel",
        .acrylic: "Acrylic",
        .hdpe: "HDPE / Delrin",
        .mdf: "MDF",
        .plywood: "Plywood",
        .hardwood: "Hardwood",
        .softwood: "Softwood",
        .copper: "Copper",
        .polycarbonate: "Polycarbonate",
        .abs: "ABS",
        .nylon: "Nylon",
        .pvcFoam: "PVC foam board",
        .solidSurface: "Solid surface",
        .machinableWax: "Machinable wax",
        .fr4: "FR4 / PCB",
        .carbonFiber: "Carbon fiber / G10",
        .xpsFoam: "XPS foam",
        .bamboo: "Bamboo",
    ]
}

struct DecodeAlarmIntent: AppIntent {
    static let title: LocalizedStringResource = "Decode a CNC Alarm"
    static let description = IntentDescription("Explains a GRBL, grblHAL or FluidNC alarm or error code and what to check. Works offline.")

    @Parameter(title: "Code", description: "For example ALARM:9 or error:22", requestValueDialog: "Which alarm or error code?")
    var code: String

    static var parameterSummary: some ParameterSummary {
        Summary("Decode \(\.$code)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let message = AlarmDecoder.decode(code).first else {
            return .result(dialog: "I couldn't find that code. Try something like ALARM:9 or error:22.") { EmptyView() }
        }
        let first = message.steps(machineHasHomingSwitches: true).first ?? ""
        return .result(dialog: "\(message.title). \(first)") {
            AlarmCard(message: message, hasHomingSwitches: true).padding()
        }
    }
}

struct FeedsSpeedsIntent: AppIntent {
    static let title: LocalizedStringResource = "Calculate Feeds and Speeds"
    static let description = IntentDescription("Conservative starting RPM and feed rate for a cut, from Toolpath's calculator.")

    @Parameter(title: "Material")
    var material: MaterialOption

    @Parameter(title: "Tool diameter (mm)", default: 6.35, inclusiveRange: (0.5, 25))
    var diameter: Double

    @Parameter(title: "Flutes", default: 2, inclusiveRange: (1, 6))
    var flutes: Int

    @Parameter(title: "Max spindle RPM", default: 24000)
    var maxRpm: Double

    static var parameterSummary: some ParameterSummary {
        Summary("Feeds for \(\.$material) with a \(\.$diameter) mm, \(\.$flutes) flute bit") {
            \.$maxRpm
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let m = CuttingMaterial.byID(material.rawValue) else {
            return .result(dialog: "Unknown material.")
        }
        let r = FeedsCalculator.calculate(FeedsInput(material: m, toolDiameterMm: diameter, flutes: flutes,
                                                     toolMaterial: .carbide, operation: .pocketing, maxSpindleRpm: maxRpm))
        let rpm = Int(r.spindleRpm.rounded())
        let feed = Int(r.feedRateMmPerMin.rounded())
        let doc = r.recommendedMaxDocMm.formatted(.number.precision(.fractionLength(1)))
        return .result(dialog: "Start at \(rpm) RPM and \(feed) millimeters per minute, up to \(doc) millimeters deep per pass. Make a test cut first.")
    }
}

struct ImportGCodeIntent: AppIntent {
    static let title: LocalizedStringResource = "Check a G-code File"
    static let description = IntentDescription("Opens Toolpath to import and check a G-code file.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentFlags.importRequested = true
        NotificationCenter.default.post(name: .toolpathImportRequested, object: nil)
        return .result()
    }
}

/// Survives a cold launch, when the notification fires before any view exists.
@MainActor
enum IntentFlags {
    static var importRequested = false
}

extension Notification.Name {
    static let toolpathImportRequested = Notification.Name("toolpathImportRequested")
}

struct ToolpathShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: DecodeAlarmIntent(),
            phrases: ["Decode a CNC alarm in \(.applicationName)", "What does my CNC alarm mean in \(.applicationName)"],
            shortTitle: "Decode Alarm",
            systemImageName: "exclamationmark.triangle"
        )
        AppShortcut(
            intent: FeedsSpeedsIntent(),
            phrases: ["Calculate feeds and speeds in \(.applicationName)", "\(.applicationName) feeds for \(\.$material)"],
            shortTitle: "Feeds & Speeds",
            systemImageName: "gauge.with.dots.needle.67percent"
        )
        AppShortcut(
            intent: ImportGCodeIntent(),
            phrases: ["Check a G-code file in \(.applicationName)"],
            shortTitle: "Check G-code",
            systemImageName: "doc.viewfinder"
        )
    }
}
