import CNCDesign
import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID = "pro_yearly"
    @State private var purchasing = false

    private let benefits: [(String, LocalizedStringKey)] = [
        ("doc.text", "Quotes and cost breakdowns for every job"),
        ("square.stack.3d.up", "Unlimited machines and cut recipes"),
        ("wrench.and.screwdriver", "Maintenance schedule from spindle hours"),
        ("heart", "Support an independent workshop app"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HeroToolpath()
                        .frame(height: 180)
                        .clipShape(.rect(cornerRadius: 24))
                    Text("Run your shop like a pro").font(.largeTitle.bold())
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(benefits, id: \.0) { icon, text in
                            Label { Text(text) } icon: {
                                Image(systemName: icon).foregroundStyle(TP.Palette.accent)
                            }
                        }
                    }
                    .font(.body)

                    if store.products.isEmpty {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                    ForEach(store.products, id: \.id) { product in
                        PlanRow(product: product, isSelected: selectedID == product.id) {
                            selectedID = product.id
                        }
                    }

                    Text("G-code checks, pre-flight, feeds and speeds, alarms and iCloud sync stay free — forever.")
                        .font(.footnote)
                        .foregroundStyle(TP.Palette.textSecondary)

                    if store.isPro {
                        Label("You're Pro — thank you!", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(TP.Palette.success)
                    }
                    if let error = store.lastError {
                        Text(error).font(.footnote).foregroundStyle(TP.Palette.danger)
                    }
                }
                .padding(TP.Metric.gutter)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button {
                        guard let product = store.products.first(where: { $0.id == selectedID }) else { return }
                        purchasing = true
                        Task {
                            await store.purchase(product)
                            purchasing = false
                            if store.isPro { dismiss() }
                        }
                    } label: {
                        if purchasing { ProgressView() } else { Text(ctaTitle) }
                    }
                    .buttonStyle(.tpPrimary)
                    .disabled(store.isPro || store.products.isEmpty || purchasing)
                    HStack(spacing: 20) {
                        Button("Restore") { Task { await store.restore() } }
                        Link("Terms", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                        Link("Privacy", destination: URL(string: "https://github.com/yakupad/toolpath-apple/blob/main/PRIVACY.md")!)
                    }
                    .font(.footnote)
                }
                .padding(TP.Metric.gutter)
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }

    private var ctaTitle: LocalizedStringKey {
        guard let product = store.products.first(where: { $0.id == selectedID }) else { return "Continue" }
        if product.subscription?.introductoryOffer?.paymentMode == .freeTrial { return "Start free trial" }
        return "Continue"
    }
}

struct PlanRow: View {
    let product: Product
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if let detail { Text(detail).font(.caption).foregroundStyle(TP.Palette.textSecondary) }
                }
                Spacer()
                Text(product.displayPrice).font(.tpValue(18))
            }
            .padding(16)
            .frame(minHeight: 64)
            .background(isSelected ? TP.Palette.accent.opacity(0.12) : TP.Palette.card, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(isSelected ? TP.Palette.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var title: LocalizedStringKey {
        switch product.id {
        case "pro_yearly": "Yearly"
        case "pro_monthly": "Monthly"
        default: "Lifetime"
        }
    }

    private var detail: LocalizedStringKey? {
        switch product.id {
        case "pro_yearly":
            if product.subscription?.introductoryOffer?.paymentMode == .freeTrial { return "7 days free, then billed yearly" }
            return "Billed yearly"
        case "pro_lifetime": return "One payment · no subscription"
        default: return nil
        }
    }
}
