import CNCDesign
import CNCKit
import SwiftData
import SwiftUI

/// Side-by-side numbers for two files (e.g. two versions of the same job).
struct CompareView: View {
    let a: JobFile
    let b: JobFile
    @Environment(Router.self) private var router

    var body: some View {
        let ra = router.analyses.analysis(for: a, machine: nil)
        let rb = router.analyses.analysis(for: b, machine: nil)
        List {
            if let ra, let rb {
                Section {
                    row("Safety score", "\(ra.score)", "\(rb.score)", better: rb.score > ra.score ? .b : rb.score < ra.score ? .a : nil)
                    row("Est. time", Duration.seconds(ra.statistics.estimatedMachiningTimeMinutes * 60).shortEstimate,
                        Duration.seconds(rb.statistics.estimatedMachiningTimeMinutes * 60).shortEstimate,
                        better: compare(ra.statistics.estimatedMachiningTimeMinutes, rb.statistics.estimatedMachiningTimeMinutes, lowerIsBetter: true))
                    row("Tools", "\(max(ra.document.toolChanges.count, 1))", "\(max(rb.document.toolChanges.count, 1))", better: nil)
                    row("Z range", zRange(ra), zRange(rb), better: nil)
                    row("Cutting", meters(ra.statistics.cutDistanceMm), meters(rb.statistics.cutDistanceMm), better: nil)
                    row("Travel", meters(ra.statistics.travelDistanceMm), meters(rb.statistics.travelDistanceMm),
                        better: compare(ra.statistics.travelDistanceMm, rb.statistics.travelDistanceMm, lowerIsBetter: true))
                    row("Feed range", feed(ra.statistics), feed(rb.statistics), better: nil)
                    row("Moves", ra.document.moves.count.formatted(), rb.document.moves.count.formatted(), better: nil)
                } header: {
                    HStack {
                        Text("")
                        Spacer()
                        Text(a.name).lineLimit(1).frame(width: 110, alignment: .trailing)
                        Text(b.name).lineLimit(1).frame(width: 110, alignment: .trailing)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Compare")
    }

    enum Side { case a, b }

    private func compare(_ x: Double, _ y: Double, lowerIsBetter: Bool) -> Side? {
        guard abs(x - y) > 0.01 * max(x, y) else { return nil }
        return (y < x) == lowerIsBetter ? .b : .a
    }

    private func row(_ title: LocalizedStringKey, _ x: String, _ y: String, better: Side?) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(x).font(.tpValue(15, weight: better == .a ? .bold : .regular))
                .foregroundStyle(better == .a ? TP.Palette.success : TP.Palette.textPrimary)
                .frame(width: 110, alignment: .trailing)
            Text(y).font(.tpValue(15, weight: better == .b ? .bold : .regular))
                .foregroundStyle(better == .b ? TP.Palette.success : TP.Palette.textPrimary)
                .frame(width: 110, alignment: .trailing)
        }
    }

    private func meters(_ mm: Double) -> String { "\((mm / 1000).formatted(.number.precision(.fractionLength(1)))) m" }
    private func zRange(_ r: JobAnalysis) -> String {
        let b = r.document.bounds
        return "\(b.minZ.formatted(.number.precision(.fractionLength(1)))) … \(b.maxZ.formatted(.number.precision(.fractionLength(1))))"
    }
    private func feed(_ s: GCodeStatistics) -> String {
        guard let lo = s.minFeedRate, let hi = s.maxFeedRate else { return "—" }
        return lo == hi ? Int(lo).formatted() : "\(Int(lo))–\(Int(hi))"
    }
}

/// Pick the second file to compare against.
struct ComparePicker: View {
    let current: JobFile
    @Query(sort: \JobFile.lastOpenedAt, order: .reverse) private var jobs: [JobFile]

    var body: some View {
        List(jobs.filter { $0.id != current.id }) { job in
            NavigationLink { CompareView(a: current, b: job) } label: { JobRow(job: job) }
        }
        .navigationTitle("Compare with…")
        .overlay {
            if jobs.count < 2 {
                ContentUnavailableView("Import another file to compare", systemImage: "square.split.2x1")
            }
        }
    }
}
