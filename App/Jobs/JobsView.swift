import CNCDesign
import CNCKit
import SwiftData
import SwiftUI

struct JobsView: View {
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \JobFile.lastOpenedAt, order: .reverse) private var jobs: [JobFile]
    @State private var filter: JobFilter = .all

    enum JobFilter: String, CaseIterable, Identifiable {
        case all, needsFixes
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .all: "All"
            case .needsFixes: "Needs fixes"
            }
        }
    }

    private var visibleJobs: [JobFile] {
        switch filter {
        case .all: jobs
        case .needsFixes: jobs.filter { $0.dangerCount > 0 }
        }
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.jobsPath) {
            Group {
                if jobs.isEmpty {
                    EmptyStateView(
                        systemImage: "doc.badge.arrow.up",
                        title: "Check your first file",
                        message: "Open a .nc or .gcode file from Files, AirDrop it from your CAM computer, or try the sample sign."
                    ) {
                        VStack(spacing: 8) {
                            Button("Import G-code") { router.isImporting = true }
                                .buttonStyle(.tpPrimary)
                            Button("Open sample file") { openSample() }
                        }
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        Picker("Filter", selection: $filter) {
                            ForEach(JobFilter.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())

                        ForEach(visibleJobs) { job in
                            NavigationLink(value: job.id) {
                                JobRow(job: job)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { context.delete(visibleJobs[index]) }
                        }
                    }
                }
            }
            .navigationTitle("Jobs")
            .navigationDestination(for: UUID.self) { id in
                if let job = jobs.first(where: { $0.id == id }) {
                    JobDetailView(job: job)
                } else {
                    ContentUnavailableView("Job not found", systemImage: "questionmark.folder")
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { router.isImporting = true } label: {
                        Label("Import G-code", systemImage: "plus")
                    }
                }
            }
        }
    }

    private func openSample() {
        let job = JobImporter.sampleJob()
        context.insert(job)
        router.open(job: job.id)
    }
}

struct JobRow: View {
    let job: JobFile
    @Environment(Router.self) private var router

    var body: some View {
        HStack(spacing: 12) {
            JobScoreBadge(job: job)
            VStack(alignment: .leading, spacing: 3) {
                Text(job.name).font(.headline).lineLimit(1)
                Text(summary).font(.subheadline).foregroundStyle(TP.Palette.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var summary: String {
        guard job.isAnalyzed else { return String(localized: "Analyzing…") }
        let minutes = Duration.seconds(job.estimatedMinutes * 60).shortEstimate
        let size = "\(Int(job.widthMm.rounded()))×\(Int(job.heightMm.rounded())) mm"
        return job.dangerCount > 0
            ? String(localized: "\(minutes) · \(job.dangerCount) danger")
            : "\(minutes) · \(size)"
    }
}

struct ScoreBadge: View {
    let score: Int
    let hasDanger: Bool
    var size: CGFloat = 44

    var tint: Color {
        switch SafetyScore.band(for: score, hasDanger: hasDanger) {
        case .good: TP.Palette.success
        case .check: TP.Palette.caution
        case .danger: TP.Palette.danger
        }
    }

    var body: some View {
        ZStack {
            RingGauge(progress: Double(score) / 100, tint: tint, lineWidth: size / 9)
            Text("\(score)").font(.tpValue(size * 0.32, weight: .bold))
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(Text("Safety score \(score)"))
    }
}

/// Score badge for a saved job; analyzes it on first display if needed.
struct JobScoreBadge: View {
    let job: JobFile
    var size: CGFloat = 44
    @Environment(Router.self) private var router

    var body: some View {
        Group {
            if job.isAnalyzed {
                ScoreBadge(score: job.safetyScore, hasDanger: job.dangerCount > 0, size: size)
            } else {
                ProgressView().frame(width: size, height: size)
                    .onAppear { router.analyses.load(job, machine: nil) }
            }
        }
    }
}
