import CNCDesign
import CNCKit
import SwiftData
import SwiftUI

/// Wall-clock driven playback clock for simulation (speed multiplier, pause,
/// scrub). Value type: the view owns it, TimelineView reads it every frame.
struct SimulationClock: Equatable {
    var speed: Double = 5
    private(set) var isPlaying = false
    private var baseTime: Double = 0
    private var startedAt: Date?

    init(speed: Double = 5) { self.speed = speed }

    func time(at date: Date) -> Double {
        guard isPlaying, let startedAt else { return baseTime }
        return baseTime + date.timeIntervalSince(startedAt) * speed
    }

    mutating func play(at date: Date) {
        guard !isPlaying else { return }
        isPlaying = true
        startedAt = date
    }

    mutating func pause(at date: Date) {
        baseTime = time(at: date)
        isPlaying = false
        startedAt = nil
    }

    mutating func seek(to seconds: Double) {
        baseTime = seconds
        if isPlaying { startedAt = .now }
    }

    mutating func setSpeed(_ value: Double) {
        let now = Date.now
        baseTime = time(at: now)
        if isPlaying { startedAt = now }
        speed = value
    }

    mutating func reset() { self = SimulationClock(speed: speed) }
}

struct SimulationBar: View {
    @Binding var clock: SimulationClock
    let duration: Double
    let onClose: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let t = min(clock.time(at: context.date), duration)
            HStack(spacing: 12) {
                Button {
                    if clock.isPlaying { clock.pause(at: .now) } else {
                        if t >= duration { clock.seek(to: 0) }
                        clock.play(at: .now)
                    }
                } label: {
                    Image(systemName: clock.isPlaying ? "pause.fill" : "play.fill")
                        .font(.headline)
                        .frame(width: 40, height: 40)
                        .foregroundStyle(TP.Palette.onAccent)
                        .background(TP.Palette.accent, in: .circle)
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(clock.isPlaying ? Text("Pause") : Text("Play"))

                Slider(value: Binding(get: { t }, set: { clock.seek(to: $0) }), in: 0...max(duration, 0.001))
                    .accessibilityLabel(Text("Playback position"))

                Menu {
                    ForEach([1.0, 5, 20, 60], id: \.self) { speed in
                        Button("\(Int(speed))×") { clock.setSpeed(speed) }
                    }
                } label: {
                    Text("\(Int(clock.speed))×").font(.tpValue(14)).frame(minWidth: 36, minHeight: 40)
                }

                Button(action: onClose) {
                    Image(systemName: "xmark").font(.subheadline.weight(.semibold)).frame(width: 32, height: 40)
                }
                .accessibilityLabel(Text("Close simulation"))
            }
            .padding(.horizontal, 8)
            .frame(height: 56)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
    }
}

struct WarningsList: View {
    let groups: [FindingGroup]
    var kind: MachineKind = .mill
    @Binding var focusedMove: Int?

    var body: some View {
        ScrollView {
            if groups.isEmpty {
                ContentUnavailableView {
                    Label("No issues found", systemImage: "checkmark.seal")
                } description: {
                    Text("Every move passed the safety checks. Still run the pre-flight before you cut.")
                }
            }
            LazyVStack(spacing: 10) {
                ForEach(groups) { group in
                    WarningCard(group: group, kind: kind, isFocused: focusedMove == group.first.moveIndex) {
                        withAnimation(.snappy) {
                            focusedMove = focusedMove == group.first.moveIndex ? nil : group.first.moveIndex
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }
}

struct WarningCard: View {
    let group: FindingGroup
    var kind: MachineKind = .mill
    let isFocused: Bool
    let onShow: () -> Void
    @State private var expanded = false

    var body: some View {
        let explanation = Explainer.explain(group, kind: kind)
        let tint = group.severity == .danger ? TP.Palette.danger : TP.Palette.caution
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: group.severity == .danger ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(tint)
                    .symbolEffect(.wiggle, value: isFocused)
                VStack(alignment: .leading, spacing: 4) {
                    Text(explanation.title).font(.headline)
                    Text(explanation.whatHappened).font(.subheadline).foregroundStyle(TP.Palette.textSecondary)
                    Text("L\(group.first.sourceLine)").font(.tpCode).foregroundStyle(tint)
                }
                Spacer(minLength: 0)
                Button(isFocused ? "Hide" : "Show", action: onShow)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    Label { Text(explanation.whyItMatters) } icon: { Image(systemName: "questionmark.circle") }
                    Label { Text(explanation.howToFix) } icon: { Image(systemName: "wrench.and.screwdriver") }
                }
                .font(.subheadline)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Button(expanded ? "Less" : "Why & how to fix") {
                withAnimation(.snappy) { expanded.toggle() }
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(14)
        .background(tint.opacity(group.severity == .danger ? 0.10 : 0.07), in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(tint.opacity(isFocused ? 0.8 : 0.3), lineWidth: 1))
    }
}

struct StatsView: View {
    let analysis: JobAnalysis
    var job: JobFile?

    var body: some View {
        let s = analysis.statistics
        let b = analysis.document.bounds
        let one = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))
        ScrollView {
            if analysis.kind == .lathe, let job { LatheSetupCard(job: job) }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                GridRow {
                    ValueLabel("Est. time", value: Duration.seconds(s.estimatedMachiningTimeMinutes * 60).formatted(.time(pattern: .hourMinuteSecond)))
                    ValueLabel("Moves", value: analysis.document.moves.count.formatted())
                }
                if analysis.kind == .lathe {
                    // Lathe documents: x = axial Z, y = radius.
                    GridRow {
                        ValueLabel("Largest Ø", value: (b.maxY * 2).formatted(one), unit: "mm", size: 18)
                        ValueLabel("Z range", value: "\(b.minX.formatted(one)) … \(b.maxX.formatted(one))", unit: "mm", size: 18)
                    }
                } else {
                    GridRow {
                        ValueLabel("Size X × Y", value: "\(b.width.formatted(one)) × \(b.height.formatted(one))", unit: "mm", size: 18)
                        ValueLabel("Z range", value: "\(b.minZ.formatted(one)) … \(b.maxZ.formatted(one))", unit: "mm", size: 18)
                    }
                }
                GridRow {
                    ValueLabel("Cutting", value: (s.cutDistanceMm / 1000).formatted(.number.precision(.fractionLength(2))), unit: "m", size: 18)
                    ValueLabel("Travel", value: (s.travelDistanceMm / 1000).formatted(.number.precision(.fractionLength(2))), unit: "m", size: 18)
                }
                GridRow {
                    ValueLabel("Feed range", value: feedRange(s), unit: "mm/min", size: 18)
                    ValueLabel("Rapid · Cut · Arc", value: "\(s.rapidCount) · \(s.cutCount) · \(s.arcCount)", size: 18)
                }
            }
            .tpCard()
            Text("Time is an estimate: rapids are assumed at your machine's rapid rate, and acceleration isn't modelled.")
                .font(.footnote)
                .foregroundStyle(TP.Palette.textSecondary)
                .padding(.top, 8)
        }
    }

    private func feedRange(_ s: GCodeStatistics) -> String {
        guard let lo = s.minFeedRate, let hi = s.maxFeedRate else { return "—" }
        return lo == hi ? Int(lo).formatted() : "\(Int(lo).formatted())–\(Int(hi).formatted())"
    }
}

/// Lathe jobs: where the chuck jaws sit, so the chuck check is exact.
struct LatheSetupCard: View {
    @Bindable var job: JobFile
    @Environment(Router.self) private var router
    @Query(filter: #Predicate<Machine> { $0.isActive }) private var activeMachines: [Machine]
    @State private var stickout: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Lathe program", systemImage: "circle.circle").font(.headline)
            NumberField(title: "Stock out of the jaws", value: $stickout, unit: "mm")
            Text(job.chuckZ == nil
                 ? "Enter how far the stock sticks out so Toolpath can check every move against the chuck. 0 = not set."
                 : "Moves closer than 0.5 mm to the jaws are flagged as dangerous.")
                .font(.footnote).foregroundStyle(TP.Palette.textSecondary)
        }
        .tpCard()
        .padding(.bottom, 8)
        .onAppear { stickout = job.chuckZ.map { -$0 } ?? 0 }
        .onChange(of: stickout) { _, value in
            let newValue: Double? = value > 0 ? -value : nil
            guard newValue != job.chuckZ else { return }
            job.chuckZ = newValue
            router.analyses.invalidate(job.id)
            router.analyses.load(job, machine: activeMachines.first)
        }
    }
}

enum SafetyReport {
    static func text(job: JobFile, analysis: JobAnalysis) -> String {
        var lines = [
            "Toolpath safety report — \(job.name)",
            "Safety score: \(analysis.score)/100",
            "Estimated time: \(Int(analysis.statistics.estimatedMachiningTimeMinutes.rounded())) min",
            "",
        ]
        if analysis.groups.isEmpty { lines.append("No issues found.") }
        for group in analysis.groups {
            let e = Explainer.explain(group, kind: analysis.kind)
            lines.append("[\(group.severity == .danger ? "DANGER" : "CAUTION")] \(e.title)")
            lines.append("  \(e.whatHappened)")
            lines.append("  Fix: \(e.howToFix)")
        }
        lines.append("")
        lines.append("Checks are starting points, not guarantees. Always air-cut new files.")
        return lines.joined(separator: "\n")
    }
}
