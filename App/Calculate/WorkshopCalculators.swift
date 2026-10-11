import CNCDesign
import CNCKit
import SwiftUI

/// Number field used by every calculator.
struct NumberField: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    var unit: String = "mm"

    var body: some View {
        LabeledContent {
            HStack(spacing: 4) {
                TextField(title, value: $value, format: .number.precision(.fractionLength(0...3)))
                    .multilineTextAlignment(.trailing)
                    .font(.tpValue(17, weight: .regular))
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                Text(unit).foregroundStyle(TP.Palette.textSecondary)
            }
        } label: {
            Text(title)
        }
    }
}

struct ResultRow: View {
    let title: LocalizedStringKey
    let value: String
    var unit: String? = nil

    var body: some View {
        LabeledContent(title) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.tpValue(22)).contentTransition(.numericText())
                if let unit { Text(unit).font(.footnote).foregroundStyle(TP.Palette.textSecondary) }
            }
        }
    }
}

private func f(_ v: Double, _ digits: Int = 2) -> String { v.formatted(.number.precision(.fractionLength(0...digits))) }

struct VBitView: View {
    @State private var angle = 60.0
    @State private var width = 6.0
    var body: some View {
        Form {
            Section {
                Picker("Bit angle", selection: $angle) {
                    ForEach([30.0, 60, 90, 120], id: \.self) { Text("\(Int($0))°").tag($0) }
                }
                .pickerStyle(.segmented)
                NumberField(title: "Line width", value: $width)
            }
            Section("Result") {
                ResultRow(title: "Depth", value: f(VBit.depth(forWidth: width, includedAngleDegrees: angle)), unit: "mm")
            }
        }
        .navigationTitle("V-bit depth")
    }
}

struct ChipThinningView: View {
    @State private var diameter = 6.35
    @State private var engagement = 0.6
    var body: some View {
        let factor = ChipThinning.feedFactor(toolDiameter: diameter, radialEngagement: engagement)
        Form {
            Section {
                NumberField(title: "Tool diameter", value: $diameter)
                NumberField(title: "Stepover (radial)", value: $engagement)
            }
            Section {
                ResultRow(title: "Multiply feed by", value: "×" + f(factor))
            } footer: {
                Text("Below half the diameter, the real chip is thinner than programmed. Raise the feed by this factor to keep the intended chip load — then test.")
            }
        }
        .navigationTitle("Chip thinning")
    }
}

struct ScallopView: View {
    @State private var diameter = 3.175
    @State private var stepover = 0.5
    var body: some View {
        let height = ScallopHeight.height(toolRadius: diameter / 2, stepover: stepover)
        Form {
            Section {
                NumberField(title: "Ball-nose diameter", value: $diameter)
                NumberField(title: "Stepover", value: $stepover)
            }
            Section("Result") {
                ResultRow(title: "Scallop height", value: f(height, 4), unit: "mm")
            }
        }
        .navigationTitle("Scallop height")
    }
}

struct BoltCircleView: View {
    @State private var diameter = 50.0
    @State private var count = 6
    @State private var start = 0.0
    var body: some View {
        let holes = BoltCircle.holes(centerX: 0, centerY: 0, radius: diameter / 2, count: count, startAngleDegrees: start)
        Form {
            Section {
                NumberField(title: "Circle diameter", value: $diameter)
                Stepper("Holes: \(count)", value: $count, in: 2...36)
                NumberField(title: "Start angle", value: $start, unit: "°")
            }
            Section {
                Canvas { context, size in
                    let r = min(size.width, size.height) / 2 - 16
                    let c = CGPoint(x: size.width / 2, y: size.height / 2)
                    context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                                   with: .color(TP.Palette.textTertiary), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    for hole in holes {
                        let p = CGPoint(x: c.x + hole.xMm / (diameter / 2) * r, y: c.y - hole.yMm / (diameter / 2) * r)
                        context.fill(Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)), with: .color(TP.Palette.accent))
                    }
                }
                .frame(height: 200)
            }
            Section("Hole positions from center") {
                ForEach(holes, id: \.index) { hole in
                    LabeledContent("\(hole.index + 1)") {
                        Text("X \(f(hole.xMm, 3))   Y \(f(hole.yMm, 3))").font(.tpValue(15, weight: .regular))
                    }
                }
            }
        }
        .navigationTitle("Bolt circle")
    }
}

struct TapDrillView: View {
    var body: some View {
        List {
            ForEach([ThreadStandard.metric, .unc], id: \.self) { standard in
                Section(standard == .metric ? "Metric" : "UNC / UNF") {
                    ForEach(ThreadSpec.catalog.filter { $0.standard == standard }) { spec in
                        LabeledContent(spec.designation) {
                            Text("\(f(spec.recommendedTapDrillMm)) mm").font(.tpValue(15, weight: .regular))
                        }
                    }
                }
            }
            Section {
                Text("About 75% thread engagement (major diameter − pitch). Round to the nearest drill you own and check a full chart for critical parts.")
                    .font(.footnote)
            }
        }
        .navigationTitle("Tap drill")
    }
}

struct UnitsView: View {
    @State private var mm = 25.4
    @State private var feedMm = 1000.0
    var body: some View {
        Form {
            Section("Length") {
                NumberField(title: "Millimeters", value: $mm)
                ResultRow(title: "Inches", value: f(UnitConverter.mmToInch(mm), 4), unit: "in")
                ResultRow(title: "Thou", value: f(UnitConverter.mmToThou(mm), 1), unit: "thou")
            }
            Section("Feed rate") {
                NumberField(title: "mm/min", value: $feedMm, unit: "mm/min")
                ResultRow(title: "in/min", value: f(UnitConverter.mmPerMinToInchPerMin(feedMm), 1), unit: "in/min")
            }
        }
        .navigationTitle("Units")
    }
}

/// Currencies offered in the quote calculator: the common ones for makers
/// selling online, plus the device's own and whatever was picked before.
enum QuoteCurrency {
    static let common = ["USD", "EUR", "GBP", "TRY", "CAD", "AUD", "CHF", "JPY", "CNY",
                         "RUB", "SAR", "AED", "SEK", "NOK", "DKK", "PLN", "INR", "BRL", "MXN"]

    static func options(including selected: String) -> [String] {
        var codes = common
        for extra in [selected, Locale.current.currency?.identifier].compactMap({ $0 }) where !codes.contains(extra) {
            codes.insert(extra, at: 0)
        }
        return codes
    }

    static func label(for code: String) -> String {
        let name = Locale.current.localizedString(forCurrencyCode: code) ?? code
        return "\(code) · \(name)"
    }
}

struct QuoteView: View {
    @AppStorage("quote.machineRate") private var machineRate = 12.0
    @AppStorage("quote.laborRate") private var laborRate = 20.0
    @AppStorage("quote.feePercent") private var feePercent = 0.065
    @AppStorage("quote.feeFixed") private var feeFixed = 0.2
    @AppStorage("quote.margin") private var margin = 0.6
    @AppStorage("quote.currency") private var currency = Locale.current.currency?.identifier ?? "USD"
    @State private var input: QuoteInput

    /// `machineMinutes` pre-fills from a job's estimated time.
    init(machineMinutes: Double = 30, title: String? = nil) {
        _input = State(initialValue: QuoteInput(materialCost: 0, machineMinutes: machineMinutes.rounded(.up),
                                                machineHourlyRate: 12, laborMinutes: 20, laborHourlyRate: 20,
                                                feePercent: 0.065, feeFixed: 0.2, targetMargin: 0.6))
        self.title = title
    }

    private let title: String?

    var body: some View {
        let q = QuoteCalculator.quote(input)
        Form {
            Section {
                Picker("Currency", selection: $currency) {
                    ForEach(QuoteCurrency.options(including: currency), id: \.self) { code in
                        Text(QuoteCurrency.label(for: code)).tag(code)
                    }
                }
            }
            Section("Costs") {
                NumberField(title: "Material", value: $input.materialCost, unit: currency)
                NumberField(title: "Machine time", value: $input.machineMinutes, unit: "min")
                NumberField(title: "Machine rate", value: $input.machineHourlyRate, unit: "\(currency)/h")
                NumberField(title: "Finishing time", value: $input.laborMinutes, unit: "min")
                NumberField(title: "Your rate", value: $input.laborHourlyRate, unit: "\(currency)/h")
            }
            Section("Selling") {
                NumberField(title: "Marketplace fee", value: Binding(get: { input.feePercent * 100 }, set: { input.feePercent = $0 / 100 }), unit: "%")
                NumberField(title: "Fixed fee", value: $input.feeFixed, unit: currency)
                VStack(alignment: .leading) {
                    Text("Target margin: \(Int(input.targetMargin * 100))%")
                    Slider(value: $input.targetMargin, in: 0...2, step: 0.05)
                }
            }
            Section {
                ResultRow(title: "Suggested price", value: q.suggestedUnitPrice.formatted(.currency(code: currency)))
                LabeledContent("Total cost", value: (q.totalCost).formatted(.currency(code: currency)))
                LabeledContent("Profit", value: q.profitPerUnit.formatted(.currency(code: currency)))
            }
        }
        .navigationTitle(title ?? String(localized: "Quote"))
        .onAppear {
            input.machineHourlyRate = machineRate
            input.laborHourlyRate = laborRate
            input.feePercent = feePercent
            input.feeFixed = feeFixed
            input.targetMargin = margin
        }
        .onChange(of: input) {
            // Remember the shop's rates; the job-specific values stay per quote.
            machineRate = input.machineHourlyRate
            laborRate = input.laborHourlyRate
            feePercent = input.feePercent
            feeFixed = input.feeFixed
            margin = input.targetMargin
        }
    }
}
