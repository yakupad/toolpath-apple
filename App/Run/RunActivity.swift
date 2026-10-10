import Foundation
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import ToolpathActivity

/// Starts, updates and ends the job's Live Activity (lock screen, Dynamic
/// Island, StandBy, Apple Watch Smart Stack).
@MainActor
enum RunActivity {
    static func start(job: String, machine: String, duration: Double, toolChange: (tool: Int, at: Double)?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let now = Date.now
        let state = JobActivityAttributes.ContentState(
            startDate: now,
            endDate: now.addingTimeInterval(duration),
            nextToolChangeDate: toolChange.map { now.addingTimeInterval($0.at) },
            nextTool: toolChange?.tool
        )
        Task {
            // End any activity left from a previous run before starting a new one.
            for activity in Activity<JobActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            _ = try? Activity.request(
                attributes: JobActivityAttributes(jobName: job, machineName: machine),
                content: .init(state: state, staleDate: state.endDate.addingTimeInterval(600))
            )
        }
    }

    static func update(elapsed: Double, duration: Double, paused: Bool, toolChange: (tool: Int, at: Double)?) {
        let now = Date.now
        let state = JobActivityAttributes.ContentState(
            startDate: now.addingTimeInterval(-elapsed),
            endDate: now.addingTimeInterval(duration - elapsed),
            isPaused: paused,
            pausedRemaining: paused ? max(duration - elapsed, 0) : nil,
            nextToolChangeDate: toolChange.map { now.addingTimeInterval($0.at - elapsed) },
            nextTool: toolChange?.tool
        )
        Task {
            for activity in Activity<JobActivityAttributes>.activities {
                await activity.update(.init(state: state, staleDate: nil))
            }
        }
    }

    static func end() {
        Task {
            for activity in Activity<JobActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
#else
@MainActor
enum RunActivity {
    static func start(job: String, machine: String, duration: Double, toolChange: (tool: Int, at: Double)?) {}
    static func update(elapsed: Double, duration: Double, paused: Bool, toolChange: (tool: Int, at: Double)?) {}
    static func end() {}
}
#endif
