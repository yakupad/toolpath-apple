#if DEBUG
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
