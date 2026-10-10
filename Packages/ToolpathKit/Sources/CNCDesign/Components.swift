import SwiftUI

/// Flat card surface used across the app.
public struct CardBackground: ViewModifier {
    var padding: CGFloat
    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TP.Palette.card, in: .rect(cornerRadius: TP.Metric.cardRadius))
    }
}

extension View {
    public func tpCard(padding: CGFloat = 16) -> some View { modifier(CardBackground(padding: padding)) }
}

/// Uppercase section caption ("SETUP · FROM YOUR FILE").
public struct SectionCaption: View {
    let text: LocalizedStringKey
    public init(_ text: LocalizedStringKey) { self.text = text }
    public var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(TP.Palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A machine value: big monospaced number with a small unit.
public struct ValueLabel: View {
    let caption: LocalizedStringKey
    let value: String
    let unit: String?
    let size: CGFloat

    public init(_ caption: LocalizedStringKey, value: String, unit: String? = nil, size: CGFloat = 24) {
        self.caption = caption
        self.value = value
        self.unit = unit
        self.size = size
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption).font(.caption).foregroundStyle(TP.Palette.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.tpValue(size)).contentTransition(.numericText())
                if let unit {
                    Text(unit).font(.footnote).foregroundStyle(TP.Palette.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Animated ring gauge (safety score, job progress).
public struct RingGauge: View {
    let progress: Double
    let tint: Color
    let lineWidth: CGFloat

    public init(progress: Double, tint: Color, lineWidth: CGFloat = 8) {
        self.progress = progress
        self.tint = tint
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            Circle().stroke(TP.Palette.separator, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.8), value: progress)
        }
    }
}

/// Primary capsule button with a 52pt minimum height.
public struct PrimaryButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(TP.Palette.onAccent)
            .frame(maxWidth: .infinity, minHeight: TP.Metric.target)
            .background(TP.Palette.accent, in: .capsule)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    public static var tpPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

/// Empty state: icon badge, title, message, optional action.
public struct EmptyStateView<Action: View>: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let action: Action

    public init(systemImage: String, title: LocalizedStringKey, message: LocalizedStringKey, @ViewBuilder action: () -> Action) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.action = action()
    }

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(TP.Palette.accent)
                .frame(width: 84, height: 84)
                .background(TP.Palette.accent.opacity(0.14), in: .circle)
                .symbolEffect(.bounce, options: .nonRepeating)
            Text(title).font(.title3.weight(.bold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(TP.Palette.textSecondary)
                .multilineTextAlignment(.center)
            action.padding(.top, 6)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}
