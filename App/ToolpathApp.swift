import SwiftData
import SwiftUI

@main
struct ToolpathApp: App {
    let container: ModelContainer
    @State private var router = Router()
    @AppStorage("appearance") private var appearance: Appearance = .system

    init() {
        let schema = Schema(AppSchema.models)
        // iCloud sync switches on once the CloudKit entitlement is added
        // (see vault: Identity & Sync). Until then the store is local.
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        do {
            container = try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Could not open the data store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .preferredColorScheme(appearance.colorScheme)
                .tint(Color.accentColor)
                .onOpenURL { url in router.importFile(at: url) }
        }
        .modelContainer(container)
        #if os(macOS)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Import G-code…") { router.isImporting = true }
                    .keyboardShortcut("o")
            }
        }
        #endif
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
