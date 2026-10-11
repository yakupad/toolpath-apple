import CNCDesign
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Store.self) private var store
    @State private var showPaywall = false
    @Environment(\.modelContext) private var context
    @State private var backupURL: URL?
    @State private var csvURL: URL?
    @State private var showImporter = false
    @State private var confirmDelete = false
    @State private var message: String?
    @AppStorage("appearance") private var appearance: Appearance = .system
    @AppStorage("workshopMode") private var workshopMode = false
    @AppStorage("toolChangeAlerts") private var toolChangeAlerts = true
    @AppStorage("jobFinishedAlerts") private var jobFinishedAlerts = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { showPaywall = true } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text(store.isPro ? "Toolpath Pro" : "Try Toolpath Pro").font(.headline)
                                Text(store.isPro ? "Thank you for your support" : "Quotes, recipes, maintenance")
                                    .font(.caption).foregroundStyle(TP.Palette.textSecondary)
                            }
                        } icon: {
                            Image(systemName: "seal.fill").foregroundStyle(TP.Palette.accent)
                        }
                    }
                    Button("Restore purchases") { Task { await store.restore() } }
                }
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
                Section {
                    ICloudStatusRow()
                    if let backupURL {
                        ShareLink(item: backupURL) { Label("Export backup (JSON)", systemImage: "square.and.arrow.up") }
                    }
                    if let csvURL {
                        ShareLink(item: csvURL) { Label("Export job history (CSV)", systemImage: "tablecells") }
                    }
                    Button { showImporter = true } label: {
                        Label("Import backup or CNC Maker Assistant data", systemImage: "square.and.arrow.down")
                    }
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Delete all data…", systemImage: "trash")
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Your data syncs through your own private iCloud — no account needed. It's yours: export it any time as JSON or CSV.")
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
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .task {
                backupURL = try? DataTransfer.backupFile(context: context)
                csvURL = try? DataTransfer.jobLogCSV(context: context)
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json], allowsMultipleSelection: true) { result in
                guard case let .success(urls) = result else { return }
                var total = 0
                for url in urls {
                    do { total += try DataTransfer.importFile(at: url, into: context).total }
                    catch { message = error.localizedDescription; return }
                }
                message = String(localized: "Imported \(total) items.")
            }
            .confirmationDialog("Delete all data?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) {
                    try? DataTransfer.deleteAll(context: context)
                    message = String(localized: "All data deleted.")
                }
            } message: {
                Text("Jobs, machines, tools, recipes, stock and history are removed from this device and your iCloud. This can't be undone.")
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
