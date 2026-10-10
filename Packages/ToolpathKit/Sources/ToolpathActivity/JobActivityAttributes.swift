#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

/// Shared between the app (starts/updates the activity) and the widget
/// extension (renders it). Times are absolute dates so the system can count
/// down without the app pushing updates every second.
public struct JobActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var startDate: Date
        public var endDate: Date
        public var isPaused: Bool
        /// Remaining seconds frozen at the moment of pausing.
        public var pausedRemaining: Double?
        public var nextToolChangeDate: Date?
        public var nextTool: Int?

        public init(startDate: Date, endDate: Date, isPaused: Bool = false, pausedRemaining: Double? = nil, nextToolChangeDate: Date? = nil, nextTool: Int? = nil) {
            self.startDate = startDate
            self.endDate = endDate
            self.isPaused = isPaused
            self.pausedRemaining = pausedRemaining
            self.nextToolChangeDate = nextToolChangeDate
            self.nextTool = nextTool
        }
    }

    public var jobName: String
    public var machineName: String

    public init(jobName: String, machineName: String) {
        self.jobName = jobName
        self.machineName = machineName
    }
}
#endif
