import CNCDesign
import CNCKit
import SwiftData
import SwiftUI

struct WorkshopView: View {
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \JobFile.lastOpenedAt, order: .reverse) private var jobs: [JobFile]
    @Query(filter: #Predicate<Machine> { $0.isActive }) private var activeMachines: [Machine]
    @Query(sort: \JobLog.date, order: .reverse) private var logs: [JobLog]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TP.Metric.sectionSpacing) {
                    if jobs.isEmpty {
                        firstRun
                    }
                    quickActions
                    if !jobs.isEmpty { recentFiles }
                    if !logs.isEmpty { weekSummary }
                }
                .padding(TP.Metric.gutter)
            }
            .background(TP.Palette.canvas)
            .navigationTitle("Workshop")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { router.showSettings = true } label: {
                        Label(activeMachines.first?.name ?? String(localized: "Settings"), systemImage: "gearshape")
                    }
                }
            }
        }
    }

    private var firstRun: some View {
        EmptyStateView(
            systemImage: "doc.badge.arrow.up",
            title: "Check your first file",
            message: "Open a .nc or .gcode file from Files, AirDrop it from your CAM computer, or try the sample sign."
        ) {
            VStack(spacing: 8) {
                Button("Import G-code") { router.isImporting = true }.buttonStyle(.tpPrimary)
                Button("Open sample file") {
                    let job = JobImporter.sampleJob()
                    context.insert(job)
                    router.open(job: job.id)
                }
            }
        }
        .background(TP.Palette.card, in: .rect(cornerRadius: 26))
    }

    private var quickActions: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            QuickAction(title: "Import G-code", systemImage: "doc.badge.arrow.up", tint: TP.Palette.accentText) {
                router.isImporting = true
            }
            QuickAction(title: "Feeds & Speeds", systemImage: "gauge.with.dots.needle.67percent", tint: TP.Palette.success) {
                router.tab = .calculate
            }
            QuickAction(title: "Fix an alarm", systemImage: "exclamationmark.triangle", tint: TP.Palette.caution) {
                router.tab = .ask
            }
            QuickAction(title: "Price a job", systemImage: "doc.text", tint: TP.Viewer.arcCCW) {
                router.tab = .calculate
            }
        }
    }

    private var recentFiles: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent files").font(.title3.bold())
                Spacer()
                Button("See all") { router.tab = .jobs }
            }
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(jobs.prefix(8)) { job in
                        Button { router.open(job: job.id) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ScoreBadge(score: job.safetyScore, hasDanger: job.dangerCount > 0, size: 40)
                                Text(job.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(Duration.seconds(job.estimatedMinutes * 60).shortEstimate)
                                    .font(.caption)
                                    .foregroundStyle(TP.Palette.textSecondary)
                            }
                            .frame(width: 140, alignment: .leading)
                            .tpCard(padding: 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var weekSummary: some View {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        let recent = logs.filter { $0.date >= weekAgo }
        let hours = recent.reduce(0) { $0 + $1.durationMinutes } / 60
        let clean = recent.isEmpty ? 0 : Double(recent.filter { $0.outcome == .clean }.count) / Double(recent.count)
        return VStack(alignment: .leading, spacing: 12) {
            Text("This week").font(.title3.bold())
            HStack {
                ValueLabel("Jobs", value: recent.count.formatted())
                Spacer()
                ValueLabel("Spindle", value: hours.formatted(.number.precision(.fractionLength(1))), unit: "h")
                Spacer()
                ValueLabel("Clean", value: clean.formatted(.percent.precision(.fractionLength(0))))
            }
            .tpCard()
        }
    }
}

struct QuickAction: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading) {
                Image(systemName: systemImage).font(.title2).foregroundStyle(tint)
                Spacer()
                Text(title).font(.headline).foregroundStyle(TP.Palette.textPrimary)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .tpCard(padding: 14)
        }
        .buttonStyle(.plain)
    }
}
