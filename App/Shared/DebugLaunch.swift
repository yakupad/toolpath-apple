import Foundation

enum DebugFlags {
    /// `-localStore`: no CloudKit, so unsigned debug builds can run.
    static var localStore: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-localStore")
        #else
        false
        #endif
    }

    /// Value after a `-name value` launch argument (debug builds only).
    static func value(_ name: String) -> String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: name), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
        #else
        return nil
        #endif
    }

    static var panelExpanded: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-panelExpanded")
        #else
        false
        #endif
    }

    /// Screenshot runs open job previews in 2D with `-view2D`.
    static var start2D: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-view2D")
        #else
        false
        #endif
    }

    /// Screenshot runs skip onboarding with `-skipOnboarding`.
    static var skipOnboarding: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-skipOnboarding")
        #else
        false
        #endif
    }
}

#if DEBUG
#if os(macOS)
import AppKit
#endif
import SwiftData
import SwiftUI

/// Launch arguments for screenshots and UI checks (debug builds only):
/// `-openSample` opens the sample job, `-tab <workshop|jobs|calculate|library|ask>`.
@MainActor
enum DebugLaunch {
    static func apply(router: Router, context: ModelContext) {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-tab"), args.indices.contains(i + 1) {
            router.tab = switch args[i + 1] {
            case "jobs": .jobs
            case "calculate": .calculate
            case "library": .library
            case "ask": .ask
            default: .workshop
            }
        }
        if args.contains("-renderReport") {
            let job = JobImporter.sampleJob()
            let analysis = JobAnalysis.make(content: job.content, name: job.name, rapidRate: 3000, envelope: nil)
            if let url = SafetyReportPDF.make(job: job, analysis: analysis, machine: nil),
               let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let target = docs.appending(path: "report.pdf")
                try? FileManager.default.removeItem(at: target)
                try? FileManager.default.copyItem(at: url, to: target)
            }
        }
        if args.contains("-showPaywall") { router.showPaywall = true }
        if args.contains("-renderCreatives") { CreativeRenderer.renderAll() }
        #if os(macOS)
        if args.contains("-screenshotWindow") {
            // 1440×900 pt = 2880×1800 px on Retina: the App Store Mac size.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                for window in NSApplication.shared.windows where window.isVisible {
                    window.setFrame(NSRect(x: 80, y: 80, width: 1440, height: 900), display: true)
                }
            }
        }
        #endif
        if args.contains("-openLatheDanger") {
            // G96 without a G50 limit facing to the centre, and a rapid into uncut stock.
            let job = JobFile(name: "lathe_mistakes.nc", content: "G21 G96 S150 M3\nG95\nT0101\nG0 X32 Z2\nG1 X30 F0.2\nG1 Z-20\nG0 X20 Z-10\nG0 X32 Z0\nG1 X0 F0.1\nG0 Z5\nM5")
            context.insert(job)
            router.analyses.load(job, machine: nil)
            router.open(job: job.id)
        }
        if args.contains("-openLatheSample") {
            let job = JobImporter.latheSampleJob()
            context.insert(job)
            router.analyses.load(job, machine: nil)
            router.open(job: job.id)
        }
        if args.contains("-openSample") {
            let job = JobImporter.sampleJob()
            context.insert(job)
            router.open(job: job.id)
        }
        if args.contains("-openDanger") {
            let job = JobFile(name: "knob_pocket.nc", content: """
            G21 G90
            M3 S12000
            G0 Z5
            G0 X0 Y0
            G1 Z-1 F300
            G2 X0 Y0 I20 J0 F800
            G0 Z0.5
            G0 X40 Y0 Z-1
            G1 X60 F600
            G0 Z10
            M5
            """)
            context.insert(job)
            router.open(job: job.id)
        }
    }
}
#endif
