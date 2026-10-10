import ActivityKit
import CNCDesign
import SwiftUI
import ToolpathActivity
import WidgetKit

@main
struct ToolpathWidgets: WidgetBundle {
    var body: some Widget {
        JobActivityWidget()
    }
}

struct JobActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: JobActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(TP.Palette.accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    SpindleIcon(spinning: !context.state.isPaused)
                        .font(.title2)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Remaining(state: context.state)
                        .font(.tpValue(24))
                        .foregroundStyle(TP.Palette.accent)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.jobName).font(.subheadline.weight(.semibold)).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        Progress(state: context.state)
                        if let tool = context.state.nextTool, let date = context.state.nextToolChangeDate, date > .now {
                            HStack {
                                Image(systemName: "wrench.adjustable")
                                Text("T\(tool) change in ") + Text(timerInterval: Date.now...date, countsDown: true)
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TP.Palette.caution)
                        }
                    }
                }
            } compactLeading: {
                SpindleIcon(spinning: !context.state.isPaused)
            } compactTrailing: {
                Remaining(state: context.state)
                    .font(.tpValue(14))
                    .foregroundStyle(TP.Palette.accent)
                    .frame(maxWidth: 56)
            } minimal: {
                SpindleIcon(spinning: !context.state.isPaused)
            }
            .keylineTint(TP.Palette.accent)
        }
    }
}

struct LockScreenView: View {
    let attributes: JobActivityAttributes
    let state: JobActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SpindleIcon(spinning: !state.isPaused)
                Text(attributes.jobName).font(.headline).lineLimit(1)
                Spacer()
                Text(attributes.machineName).font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .lastTextBaseline) {
                Remaining(state: state).font(.tpValue(40))
                Spacer()
                if state.isPaused {
                    Text("Paused").font(.subheadline.weight(.semibold)).foregroundStyle(TP.Palette.caution)
                } else {
                    Text("ends \(state.endDate, style: .time)").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Progress(state: state)
            if let tool = state.nextTool, let date = state.nextToolChangeDate, date > .now {
                Label {
                    Text("Change to T\(tool) in ") + Text(timerInterval: Date.now...date, countsDown: true)
                } icon: {
                    Image(systemName: "wrench.adjustable")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TP.Palette.caution)
            }
        }
        .padding(16)
    }
}

struct Remaining: View {
    let state: JobActivityAttributes.ContentState
    var body: some View {
        if state.isPaused, let remaining = state.pausedRemaining {
            Text(Duration.seconds(remaining).formatted(.time(pattern: .minuteSecond)))
        } else {
            Text(timerInterval: Date.now...max(state.endDate, .now), countsDown: true)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
    }
}

struct Progress: View {
    let state: JobActivityAttributes.ContentState
    var body: some View {
        if state.isPaused {
            ProgressView(value: 0.5).tint(TP.Palette.caution)
        } else {
            ProgressView(timerInterval: state.startDate...max(state.endDate, state.startDate.addingTimeInterval(1)), countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(TP.Palette.accent)
        }
    }
}

struct SpindleIcon: View {
    let spinning: Bool
    var body: some View {
        Image(systemName: "gear")
            .foregroundStyle(TP.Palette.accent)
            .symbolEffect(.rotate, isActive: spinning)
            .accessibilityLabel(spinning ? Text("Running") : Text("Paused"))
    }
}
