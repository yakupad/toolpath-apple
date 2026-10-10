import CNCDesign
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance: Appearance = .system
    @AppStorage("workshopMode") private var workshopMode = false
    @AppStorage("toolChangeAlerts") private var toolChangeAlerts = true
    @AppStorage("jobFinishedAlerts") private var jobFinishedAlerts = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Workshop") {
                    Toggle(isOn: $workshopMode) {
                        VStack(alignment: .leading) {
                            Text("Workshop mode")
                            Text("Bigger buttons for gloves").font(.caption).foregroundStyle(TP.Palette.textSecondary)
                        }
                    }
                }
                Section("Notifications") {
                    Toggle("Tool change alerts", isOn: $toolChangeAlerts)
                    Toggle("Job finished", isOn: $jobFinishedAlerts)
                }
                Section("Language & appearance") {
                    #if os(iOS)
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    } label: {
                        LabeledContent("Language", value: Locale.current.localizedString(forLanguageCode: Locale.current.language.languageCode?.identifier ?? "en") ?? "")
                    }
                    #endif
                    Picker("Theme", selection: $appearance) {
                        Text("System").tag(Appearance.system)
                        Text("Light").tag(Appearance.light)
                        Text("Dark").tag(Appearance.dark)
                    }
                    .pickerStyle(.segmented)
                }
                Section("Data") {
                    LabeledContent("iCloud sync", value: String(localized: "Coming soon"))
                }
                Section {
                    Text("Cutting values and safety checks are starting points to test, not guarantees. Wear eye and ear protection, secure your work, and never leave a running machine unattended.")
                        .font(.footnote)
                } header: {
                    Text("Safety")
                }
                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                } footer: {
                    Text("No account needed — your data stays on your devices and in your iCloud.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
