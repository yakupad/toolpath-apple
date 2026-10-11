import SwiftData
import SwiftUI

@main
struct ToolpathApp: App {
    let container: ModelContainer
    @State private var router = Router()
    @State private var store = Store()
    @AppStorage("appearance") private var appearance: Appearance = .system
    @AppStorage("workshopMode") private var workshopMode = false

    init() {
        let schema = Schema(AppSchema.models)
        // Free iCloud sync through the user's private CloudKit database — no
        // account or login of our own. Without an iCloud account the store
        // simply stays local.
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .private("iCloud.com.yakupad.toolpath"))
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
                .environment(store)
                .preferredColorScheme(appearance.colorScheme)
                // Workshop mode: at least xxLarge text and controls for gloved hands.
                .dynamicTypeSize(workshopMode ? DynamicTypeSize.xxLarge...DynamicTypeSize.accessibility3 : DynamicTypeSize.xSmall...DynamicTypeSize.accessibility5)
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
