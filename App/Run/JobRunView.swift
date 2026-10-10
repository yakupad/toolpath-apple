import CNCDesign
import CNCKit
import SwiftData
import SwiftUI

/// Timer for a running job. Without a machine connection we can only follow
/// the file's estimated timeline; the user pauses it if the machine pauses.
struct JobRunView: View {
    let job: JobFile
    let analysis: JobAnalysis
    let machine: Machine?

    @Environment(\.dismiss) private var dismiss
    @State private var clock = SimulationClock(speed: 1)
    @State private var showOutcome = false
    @State private var acknowledgedChanges: Set<Int> = []

    private var duration: Double { analysis.timeline.totalDurationSeconds }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = min(clock.time(at: context.date), duration)
                let remaining = max(duration - elapsed, 0)
                let next = nextChange(after: elapsed)
                VStack(spacing: 24) {
                    ZStack {
                        RingGauge(progress: duration > 0 ? elapsed / duration : 1, tint: TP.Palette.accent, lineWidth: 18)
                        VStack(spacing: 4) {
                            Text(Duration.seconds(remaining).formatted(.time(pattern: .minuteSecond)))
                                .font(.tpValue(56))
                                .contentTransition(.numericText(countsDown: true))
                            Text("remaining · \(Int((elapsed / max(duration, 1)) * 100))%")
                                .font(.subheadline)
                                .foregroundStyle(TP.Palette.textSecondary)
                        }
                    }
                    .frame(width: 290, height: 290)

                    if let next {
                        let inSeconds = next.atSeconds - elapsed
                        HStack(spacing: 12) {
                            Image(systemName: "wrench.adjustable")
                                .font(.title2)
                                .foregroundStyle(TP.Palette.caution)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(inSeconds > 0
                                     ? "Tool change in \(Duration.seconds(inSeconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 1)))"
                                     : "Change tool now")
                                    .font(.headline)
                                Text("Swap to T\(next.tool), then re-zero Z").font(.subheadline)
                            }
                            Spacer()
                            if inSeconds <= 0 {
                                Button("Done") { acknowledgedChanges.insert(next.line) }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(16)
                        .background(TP.Palette.caution.opacity(0.12), in: .rect(cornerRadius: 20))
                    }

                    Spacer()

                    HStack(spacing: 12) {
                        Button {
                            if clock.isPlaying { clock.pause(at: .now) } else { clock.play(at: .now) }
                        } label: {
                            Text(clock.isPlaying ? "Pause timer" : "Resume")
                                .frame(maxWidth: .infinity, minHeight: TP.Metric.targetWorkshop)
                        }
                        .buttonStyle(.bordered)
                        .clipShape(.capsule)

                        Button {
                            clock.pause(at: .now)
                            showOutcome = true
                        } label: {
                            Text("Finish & log").frame(maxWidth: .infinity, minHeight: TP.Metric.targetWorkshop)
                        }
                        .buttonStyle(.borderedProminent)
                        .clipShape(.capsule)
                    }
                    .font(.headline)
                }
                .padding(TP.Metric.gutter)
                .onChange(of: remaining <= 0) { _, done in if done { showOutcome = true } }
            }
            .navigationTitle(job.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .background(TP.Palette.canvas)
        }
        .onAppear {
            clock.play(at: .now)
            RunActivity.start(job: job.name, duration: duration)
        }
        .onDisappear { RunActivity.end() }
        .sheet(isPresented: $showOutcome) {
            OutcomeView(job: job, minutes: clock.time(at: .now) / 60, machine: machine) { dismiss() }
        }
        .persistentSystemOverlays(.hidden)
        #if os(iOS)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        #endif
    }

    private func nextChange(after elapsed: Double) -> (tool: Int, line: Int, atSeconds: Double)? {
        analysis.document.toolChanges.dropFirst().compactMap { change -> (Int, Int, Double)? in
            guard !acknowledgedChanges.contains(change.sourceLine),
                  let index = change.firstMoveIndex,
                  let at = analysis.timeline.startTime(ofMove: index) else { return nil }
            return (change.toolNumber, change.sourceLine, at)
        }.first
    }
}

/// Live Activity hooks. Implemented in the widget extension step; no-op now.
enum RunActivity {
    static func start(job: String, duration: Double) {}
    static func end() {}
}
