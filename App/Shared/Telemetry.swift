import FirebaseAnalytics
import FirebaseCore
import FirebaseCrashlytics
import Foundation

/// Anonymous usage and crash reporting (Firebase). No advertising identifier,
/// no ad personalization, no G-code or library content — only event names and
/// coarse parameters. The user can turn it off in Settings. Without a Firebase
/// config file (local builds, forks) nothing is started at all.
enum Telemetry {
    static let preferenceKey = "shareUsageData"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true
    }

    static func start() {
        guard FirebaseApp.app() == nil,
              Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        FirebaseApp.configure()
        apply(isEnabled)
    }

    static func apply(_ enabled: Bool) {
        guard FirebaseApp.app() != nil else { return }
        Analytics.setAnalyticsCollectionEnabled(enabled)
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(enabled)
    }

    enum Event: String {
        case jobImported = "job_imported"
        case simulationStarted = "simulation_started"
        case preflightCompleted = "preflight_completed"
        case jobLogged = "job_logged"
        case feedsCalculated = "feeds_calculated"
        case assistantQuestion = "assistant_question"
        case paywallShown = "paywall_shown"
        case purchaseCompleted = "purchase_completed"
    }

    static func log(_ event: Event, _ parameters: [String: Any] = [:]) {
        guard FirebaseApp.app() != nil, isEnabled else { return }
        Analytics.logEvent(event.rawValue, parameters: parameters.isEmpty ? nil : parameters)
    }
}
