import CNCDesign
import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Workshop", systemImage: "square.grid.2x2", value: AppTab.workshop) {
                WorkshopView()
            }
            Tab("Jobs", systemImage: "doc.viewfinder", value: AppTab.jobs) {
                JobsView()
            }
            Tab("Calculate", systemImage: "gauge.with.dots.needle.67percent", value: AppTab.calculate) {
                CalculateView()
            }
            Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                LibraryView()
            }
            Tab(value: AppTab.ask, role: .search) {
                AskView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .fileImporter(isPresented: $router.isImporting, allowedContentTypes: JobImporter.contentTypes, allowsMultipleSelection: true) { result in
            if case let .success(urls) = result {
                router.pendingURLs.append(contentsOf: urls)
                router.consumePending(into: context)
            }
        }
        .onChange(of: router.pendingURLs) { router.consumePending(into: context) }
        .onAppear {
            router.consumePending(into: context)
            #if DEBUG
            DebugLaunch.apply(router: router, context: context)
            #endif
        }
        .alert("Couldn't import", isPresented: Binding(get: { router.importError != nil }, set: { if !$0 { router.importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(router.importError ?? "")
        }
        .sheet(isPresented: $router.showSettings) {
            SettingsView()
        }
        .dropDestination(for: URL.self) { urls, _ in
            router.pendingURLs.append(contentsOf: urls)
            return true
        }
    }
}

/// Settings + active machine button shown in every tab's toolbar.
struct ShopToolbar: ToolbarContent {
    @Environment(Router.self) private var router

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                router.showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }
}
