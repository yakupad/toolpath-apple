import CNCDesign
import CNCKit
import SwiftUI

struct PreflightView: View {
    let job: JobFile
    let analysis: JobAnalysis
    let machine: Machine?
    let onStart: () -> Void

    @State private var checked: Set<String> = []

    private var items: [PreflightItem] {
        PreflightGenerator.items(document: analysis.document, findings: analysis.findings, machine: machine?.context ?? MachineContext())
    }

    var body: some View {
        let items = items
        let critical = items.filter(\.isCritical)
        let remaining = critical.filter { !checked.contains($0.id) }.count
        VStack(spacing: 12) {
            HStack {
                Text("\(checked.intersection(items.map(\.id)).count) / \(items.count)").font(.tpValue(15))
                ProgressView(value: Double(checked.count), total: Double(max(items.count, 1)))
                    .tint(TP.Palette.accent)
            }
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(PreflightSection.allCases, id: \.self) { section in
                        let sectionItems = items.filter { $0.section == section }
                        if !sectionItems.isEmpty {
                            VStack(spacing: 0) {
                                SectionCaption(section.title).padding(.bottom, 6)
                                ForEach(sectionItems) { item in
                                    PreflightRow(item: item, isChecked: checked.contains(item.id)) {
                                        if checked.contains(item.id) { checked.remove(item.id) } else { checked.insert(item.id) }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)

            HoldToStartButton(remaining: remaining, action: onStart)
                .padding(.bottom, 8)
        }
        .sensoryFeedback(.selection, trigger: checked)
    }
}

struct PreflightRow: View {
    let item: PreflightItem
    let isChecked: Bool
    let toggle: () -> Void

    var body: some View {
        let text = PreflightText(item)
        Button(action: toggle) {
            HStack(spacing: 14) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isChecked ? TP.Palette.success : TP.Palette.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(text.title).font(.body.weight(.semibold))
                        if item.isCritical, !isChecked {
                            Text("Required").font(.caption2.weight(.bold)).foregroundStyle(TP.Palette.accentText)
                        }
                    }
                    if let detail = text.detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(item.isWarning ? TP.Palette.caution : TP.Palette.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(minHeight: TP.Metric.target)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(TP.Palette.card, in: .rect(cornerRadius: 14))
        .padding(.bottom, 6)
        .accessibilityAddTraits(isChecked ? .isSelected : [])
    }
}

/// Requires a 0.8 s press so a gloved brush can't start a job.
struct HoldToStartButton: View {
    let remaining: Int
    let action: () -> Void
    @State private var progress = 0.0

    var body: some View {
        let locked = remaining > 0
        ZStack(alignment: .leading) {
            Capsule().fill(locked ? TP.Palette.cardRaised : TP.Palette.accent.opacity(0.25))
            Capsule().fill(TP.Palette.accent).frame(maxWidth: .infinity).scaleEffect(x: progress, anchor: .leading)
            HStack {
                Image(systemName: locked ? "lock.fill" : "play.fill")
                    .symbolEffect(.wiggle, value: remaining)
                Text(locked ? "\(remaining) required checks left" : "Hold to start")
            }
            .font(.headline)
            .foregroundStyle(locked ? TP.Palette.textSecondary : TP.Palette.onAccent)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 60)
        .clipShape(.capsule)
        .onLongPressGesture(minimumDuration: 0.8, perform: {
            guard !locked else { return }
            action()
            progress = 0
        }, onPressingChanged: { pressing in
            guard !locked else { return }
            withAnimation(pressing ? .linear(duration: 0.8) : .snappy) { progress = pressing ? 1 : 0 }
        })
        .sensoryFeedback(.success, trigger: progress) { old, new in old < 1 && new == 1 }
        .accessibilityElement()
        .accessibilityLabel(locked ? Text("\(remaining) required checks left") : Text("Start job"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if !locked { action() } }
    }
}

extension PreflightSection {
    var title: LocalizedStringKey {
        switch self {
        case .setup: "Setup · from your file"
        case .tooling: "Tooling"
        case .machine: "Machine"
        case .safety: "Safety"
        }
    }
}

/// Localized wording for each deterministic checklist item.
struct PreflightText {
    let title: String
    let detail: String?

    init(_ item: PreflightItem) {
        func mm(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...1))) }
        switch item.kind {
        case let .resolveDangers(count):
            title = String(localized: "Fix or accept \(count) danger findings")
            detail = String(localized: "See Warnings. Only continue if you know the file is right for your setup.")
        case let .zeroXY(corner, w, h):
            let place: String = switch corner {
            case .lowerLeft: String(localized: "the lower-left corner")
            case .lowerRight: String(localized: "the lower-right corner")
            case .upperLeft: String(localized: "the upper-left corner")
            case .upperRight: String(localized: "the upper-right corner")
            case .center: String(localized: "the center of the part")
            case let .custom(x, y): String(localized: "a point \(mm(-x)) mm left and \(mm(-y)) mm below the job")
            }
            title = String(localized: "Zero X/Y at \(place)")
            detail = String(localized: "The toolpath covers \(mm(w)) × \(mm(h)) mm from that point.")
        case let .zeroZ(reference):
            title = reference == .stockTop ? String(localized: "Zero Z on top of the stock") : String(localized: "Zero Z on the spoilboard")
            detail = reference == .stockTop
                ? String(localized: "Cuts go below Z0, so Z0 must be the stock surface.")
                : String(localized: "All cuts stay above Z0, so Z0 must be the bed under the stock.")
        case let .stockThickness(minimum):
            title = String(localized: "Stock at least \(mm(minimum)) mm thick")
            detail = String(localized: "The deepest cut reaches this depth.")
        case let .clampClearance(margin):
            title = String(localized: "Keep clamps \(mm(margin)) mm outside the path")
            detail = String(localized: "Check against the outline in the viewer.")
        case let .toolLoaded(number, _):
            title = number.map { String(localized: "Tool T\($0) loaded") } ?? String(localized: "Correct bit loaded")
            detail = String(localized: "Seat it fully in the collet and tighten.")
        case let .toolChange(number, line, at):
            title = String(localized: "Change to T\(number) at line \(line)")
            let when = at.map { Duration.seconds($0).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)) }
            detail = when.map { String(localized: "About \($0) in. Re-zero Z after the change.") } ?? String(localized: "Re-zero Z after the change.")
        case let .spindleSpeed(rpm, outOfRange):
            title = String(localized: "Spindle at \(Int(rpm).formatted()) RPM")
            detail = outOfRange
                ? String(localized: "Outside your machine's spindle range — set it by hand or check the file.")
                : String(localized: "Set the dial if your router is manual.")
        case let .fitsMachine(fits, w, h, d):
            title = fits ? String(localized: "Fits your machine's travel") : String(localized: "Larger than your machine's travel")
            detail = String(localized: "Job: \(mm(w)) × \(mm(h)) × \(mm(d)) mm")
        case let .travelHeight(z):
            title = String(localized: "Rapids travel at Z\(mm(z))")
            detail = z < GCodeAnalyzer.safeClearanceZ
                ? String(localized: "Very low — clamps or screws can be hit.")
                : String(localized: "Clamps must be lower than this.")
        case .airCut:
            title = String(localized: "Air-cut first (optional)")
            detail = String(localized: "Run 5–10 mm above the stock with the spindle off and watch the moves.")
        case .personalProtection:
            title = String(localized: "Eye and hearing protection on")
            detail = nil
        case .dustCollection:
            title = String(localized: "Dust collection ready")
            detail = nil
        }
    }
}
