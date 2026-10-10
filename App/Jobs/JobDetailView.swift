import CNCDesign
import CNCKit
import CNCRender
import SwiftData
import SwiftUI

struct JobDetailView: View {
    @Bindable var job: JobFile
    @Environment(Router.self) private var router
    @Query(filter: #Predicate<Machine> { $0.isActive }) private var activeMachines: [Machine]

    @State private var camera = OrbitCamera.isometric
    @State private var is3D = true
    @State private var showInspector = true
    @State private var inspectorTab: InspectorTab = .warnings
    @State private var focusedMove: Int?
    @State private var drawProgress = 0.0
    @State private var filter = MoveFilter()
    @State private var simulation = SimulationClock()
    @State private var isSimulating = false
    @State private var showRun = false
    @State private var panelExpanded = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    enum InspectorTab: String, CaseIterable, Identifiable {
        case warnings, preflight, stats
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .warnings: "Warnings"
            case .preflight: "Pre-flight"
            case .stats: "Stats"
            }
        }
    }

    private var machine: Machine? { activeMachines.first }
    private var analysis: JobAnalysis? {
        router.analyses.analysis(for: job, machine: machine)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if let analysis {
                viewer(analysis)
                if sizeClass == .compact {
                    BottomPanel(expanded: $panelExpanded) { inspector(analysis) }
                }
            } else {
                TP.Viewer.background.ignoresSafeArea()
                ProgressView("Analyzing…")
            }
        }
        .navigationTitle(job.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        #endif
        .toolbar { toolbar }
        #if os(iOS)
        .toolbarVisibility(sizeClass == .compact ? .hidden : .automatic, for: .tabBar)
        #endif
        .inspector(isPresented: Binding(get: { showInspector && sizeClass != .compact }, set: { showInspector = $0 })) {
            if let analysis {
                inspector(analysis)
                    .inspectorColumnWidth(min: 300, ideal: 340, max: 420)
            }
        }
        .onAppear { job.lastOpenedAt = .now }
        .fullScreenCoverCompat(isPresented: $showRun) {
            if let analysis {
                JobRunView(job: job, analysis: analysis, machine: machine)
            }
        }
    }

    // MARK: Viewer

    @ViewBuilder
    private func viewer(_ analysis: JobAnalysis) -> some View {
        ZStack(alignment: .bottom) {
            TimelineView(.animation(paused: !simulation.isPlaying)) { context in
                let cursor = isSimulating ? analysis.timeline.position(at: simulation.time(at: context.date)) : nil
                ToolpathViewer(
                    geometry: analysis.geometry,
                    camera: $camera,
                    is3D: is3D,
                    filter: filter,
                    cursor: cursor,
                    focusedMove: focusedMove,
                    drawProgress: drawProgress,
                    insets: EdgeInsetsValue(top: 110, bottom: sizeClass == .compact ? BottomPanelMetrics.collapsedHeight : 24)
                )
                .ignoresSafeArea()
                .onChange(of: context.date) {
                    if simulation.time(at: context.date) >= analysis.timeline.totalDurationSeconds { simulation.pause(at: context.date) }
                }
            }

            if isSimulating {
                SimulationBar(clock: $simulation, duration: analysis.timeline.totalDurationSeconds) {
                    withAnimation { isSimulating = false }
                    simulation.reset()
                }
                .padding(.horizontal, TP.Metric.gutter)
                .padding(.bottom, sizeClass == .compact ? BottomPanelMetrics.collapsedHeight + 12 : 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            guard drawProgress < 1 else { return }
            withAnimation(.easeOut(duration: 0.9)) { drawProgress = 1 }
        }
        .sensoryFeedback(.warning, trigger: focusedMove) { _, new in new != nil }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("View", selection: $is3D.animation()) {
                Text("3D").tag(true)
                Text("2D").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(width: 110)
            .onChange(of: is3D) { _, new in
                withAnimation(.spring(duration: 0.5)) { camera = new ? .isometric : .top }
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                withAnimation { isSimulating.toggle() }
                if isSimulating { simulation.play(at: .now) } else { simulation.reset() }
            } label: {
                Label("Simulate", systemImage: isSimulating ? "play.circle.fill" : "play.circle")
            }
            Menu {
                Section("Camera") {
                    ForEach(OrbitCamera.Preset.allCases, id: \.self) { preset in
                        Button(preset.title) {
                            is3D = preset != .top
                            withAnimation(.spring(duration: 0.5)) { camera = preset.camera }
                        }
                    }
                }
                Section("Show") {
                    Toggle("Rapid moves (G0)", isOn: $filter.showRapid)
                    Toggle("Cutting moves (G1)", isOn: $filter.showLinear)
                    Toggle("Arcs (G2)", isOn: $filter.showArcCW)
                    Toggle("Arcs (G3)", isOn: $filter.showArcCCW)
                    Toggle("Plunge & retract", isOn: $filter.showZOnly)
                }
                if let analysis {
                    Section {
                        ShareLink(item: SafetyReport.text(job: job, analysis: analysis), subject: Text(job.name)) {
                            Label("Share report", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            if sizeClass != .compact {
                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
            }
        }
    }

    // MARK: Inspector

    @ViewBuilder
    private func inspector(_ analysis: JobAnalysis) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                ScoreBadge(score: analysis.score, hasDanger: analysis.dangerCount > 0, size: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(headline(analysis)).font(.headline)
                    Text(subheadline(analysis)).font(.subheadline).foregroundStyle(TP.Palette.textSecondary)
                }
                Spacer(minLength: 0)
            }
            Picker("Section", selection: $inspectorTab) {
                ForEach(InspectorTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            switch inspectorTab {
            case .warnings:
                WarningsList(groups: analysis.groups, focusedMove: $focusedMove)
            case .preflight:
                PreflightView(job: job, analysis: analysis, machine: machine) { showRun = true }
            case .stats:
                StatsView(analysis: analysis)
            }
        }
        .padding(.horizontal, TP.Metric.gutter)
        .padding(.top, sizeClass == .compact ? 4 : 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(sizeClass == .compact ? Color.clear : TP.Palette.canvas)
    }

    private func headline(_ a: JobAnalysis) -> String {
        if a.dangerCount > 0 { return String(localized: "Fix \(a.groups.filter { $0.severity == .danger }.count) danger before running") }
        if a.cautionCount > 0 { return String(localized: "Ready, with \(a.groups.count) things to check") }
        return String(localized: "Looks good to run")
    }

    private func subheadline(_ a: JobAnalysis) -> String {
        let time = Duration.seconds(a.statistics.estimatedMachiningTimeMinutes * 60).shortEstimate
        let tools = max(a.document.toolChanges.count, 1)
        return String(AttributedString(localized: "Est. \(time) · ^[\(tools) tool](inflect: true)").characters)
    }
}

extension OrbitCamera.Preset {
    var title: LocalizedStringKey {
        switch self {
        case .isometric: "Isometric"
        case .top: "Top"
        case .front: "Front"
        case .right: "Right"
        case .left: "Left"
        case .back: "Back"
        case .bottom: "Bottom"
        }
    }
}

extension View {
    /// Full-screen cover on iOS, sheet on macOS.
    @ViewBuilder
    func fullScreenCoverCompat<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented, content: content)
        #else
        sheet(isPresented: isPresented) { content().frame(minWidth: 480, minHeight: 640) }
        #endif
    }
}

extension Duration {
    /// "42 min", "1 hr 5 min", or "45 sec" for very short programs.
    var shortEstimate: String {
        components.seconds < 60
            ? formatted(.units(allowed: [.seconds], width: .abbreviated))
            : formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

/// Non-modal bottom panel for compact widths: the toolpath stays visible
/// and interactive above it. Drag or tap the handle to expand.
struct BottomPanel<Content: View>: View {
    @Binding var expanded: Bool
    @ViewBuilder let content: Content
    @GestureState private var drag: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let full = proxy.size.height * 0.86
            let height = max(BottomPanelMetrics.collapsedHeight, min(full, (expanded ? full : BottomPanelMetrics.collapsedHeight) - drag))
            VStack(spacing: 0) {
                Capsule()
                    .fill(TP.Palette.textTertiary.opacity(0.5))
                    .frame(width: 40, height: 5)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                    .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }
                    .gesture(
                        DragGesture()
                            .updating($drag) { value, state, _ in state = value.translation.height }
                            .onEnded { value in
                                withAnimation(.snappy) { expanded = value.translation.height < 0 ? true : value.translation.height > 60 ? false : expanded }
                            }
                    )
                    .accessibilityLabel(expanded ? Text("Collapse panel") : Text("Expand panel"))
                    .accessibilityAddTraits(.isButton)
                content
            }
            .frame(height: height)
            .background(TP.Palette.canvas, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
            .shadow(color: .black.opacity(0.15), radius: 12, y: -2)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

enum BottomPanelMetrics {
    static let collapsedHeight: CGFloat = 340
}
