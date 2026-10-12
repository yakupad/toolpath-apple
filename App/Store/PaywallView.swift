import CNCDesign
import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID = "toolpath_pro_yearly"
    @State private var purchasing = false

    private let benefits: [(String, LocalizedStringKey)] = [
        ("sparkles", "150 cloud assistant questions a month — even without Apple Intelligence"),
        ("square.stack.3d.up", "Unlimited machines and cut recipes"),
        ("doc.richtext", "PDF safety reports to print or share"),
        ("wrench.and.screwdriver", "Maintenance reminders from spindle hours"),
        ("heart", "Support an independent workshop app"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HeroToolpath()
                        .frame(height: 110)
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

                    if let pack = store.creditPack {
                        Button {
                            Task { await store.purchase(pack) }
                        } label: {
                            HStack {
                                Label("Just need answers? Add 100 cloud questions", systemImage: "sparkles")
                                    .font(.subheadline)
                                Spacer()
                                Text(pack.displayPrice).font(.tpValue(15))
                            }
                            .padding(14)
                            .background(TP.Palette.card, in: .rect(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Payment is charged to your Apple Account when you confirm. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period; renewal is charged within 24 hours before that. Manage or cancel any time in your Apple Account settings. If a free trial is offered, any unused part of it ends when you subscribe.")
                        .font(.caption2)
                        .foregroundStyle(TP.Palette.textTertiary)
                    Text("G-code checks, pre-flight, feeds and speeds, calculators, alarms, iCloud sync and 5 cloud questions a month stay free.")
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
                        Link("Privacy", destination: URL(string: "https://yakupad.github.io/toolpath-apple/privacy/")!)
                    }
                    .font(.footnote)
                }
                .padding(TP.Metric.gutter)
                .background(.bar)
            }
            .onAppear { Telemetry.log(.paywallShown) }
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
        product.id == "toolpath_pro_yearly" ? "Yearly" : "Monthly"
    }

    private var detail: LocalizedStringKey? {
        guard product.id == "toolpath_pro_yearly" else { return "Billed monthly" }
        if product.subscription?.introductoryOffer?.paymentMode == .freeTrial { return "7 days free, then billed yearly" }
        return "Billed yearly"
    }
}
