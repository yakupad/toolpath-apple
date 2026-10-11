import Foundation
import UserNotifications

/// Local alerts for a running job: tool changes and the estimated finish.
/// Times come from the file's timeline, so they are re-scheduled whenever the
/// user pauses or resumes the timer.
enum RunNotifications {
    static let prefix = "toolpath.run."

    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    /// - Parameters:
    ///   - remaining: seconds until the job's estimated end.
    ///   - toolChanges: upcoming changes as (tool number, seconds from now).
    static func schedule(job: String, remaining: Double, toolChanges: [(tool: Int, inSeconds: Double)]) {
        cancelAll()
        let defaults = UserDefaults.standard
        let center = UNUserNotificationCenter.current()

        if defaults.object(forKey: "toolChangeAlerts") as? Bool ?? true {
            for change in toolChanges where change.inSeconds > 1 {
                let content = UNMutableNotificationContent()
                content.title = String(localized: "Change tool now")
                content.body = String(localized: "Swap to T\(change.tool), then re-zero Z")
                content.sound = .default
                content.interruptionLevel = .timeSensitive
                content.threadIdentifier = job
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: change.inSeconds, repeats: false)
                center.add(UNNotificationRequest(identifier: "\(prefix)tool.\(change.tool).\(Int(change.inSeconds))", content: content, trigger: trigger))
            }
        }
        if defaults.object(forKey: "jobFinishedAlerts") as? Bool ?? true, remaining > 1 {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Job finished")
            content.body = job
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            content.threadIdentifier = job
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: remaining, repeats: false)
            center.add(UNNotificationRequest(identifier: "\(prefix)finished", content: content, trigger: trigger))
        }
    }

    static func cancelAll() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }
}
