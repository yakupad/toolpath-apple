import CNCDesign
import StoreKit
import SwiftUI

/// Top of the assistant when Apple Intelligence isn't available: says where
/// answers come from and how many cloud questions are left.
struct CloudAssistantBanner: View {
    let quota: ToolpathAPI.Quota?
    let reason: LocalizedStringKey

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                if let quota, quota.remaining > 0 {
                    Text("Cloud assistant · \(quota.remaining) questions left").font(.subheadline.weight(.semibold))
                    Text(quota.isPro ? "Included with Pro, renews monthly." : "Free questions renew every month.")
                        .font(.footnote).foregroundStyle(TP.Palette.textSecondary)
                } else if quota != nil {
                    Text("Answers from the built-in workshop library").font(.subheadline.weight(.semibold))
                    Text("You've used this month's cloud questions.").font(.footnote).foregroundStyle(TP.Palette.textSecondary)
                } else {
                    Text("Cloud assistant").font(.subheadline.weight(.semibold))
                    Text(reason).font(.footnote).foregroundStyle(TP.Palette.textSecondary)
                }
            }
        } icon: {
            Image(systemName: quota?.remaining == 0 ? "book.closed" : "cloud").foregroundStyle(TP.Palette.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TP.Metric.gutter)
        .background(TP.Palette.card)
    }
}

/// Shown under the conversation once the cloud allowance is used up.
struct UpgradeCard: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @State private var buying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Want fuller answers?", systemImage: "sparkles").font(.headline)
            Text("Pro includes 150 cloud assistant questions a month, plus unlimited machines and recipes, PDF reports and maintenance reminders.")
                .font(.subheadline).foregroundStyle(TP.Palette.textSecondary)
            Button("See Pro") { router.showPaywall = true }
                .buttonStyle(.tpPrimary)
            if let pack = store.creditPack {
                Button {
                    buying = true
                    Task { await store.purchase(pack); buying = false }
                } label: {
                    if buying { ProgressView() } else { Text("Add 100 questions · \(pack.displayPrice)") }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .disabled(buying)
            }
        }
        .padding(16)
        .background(TP.Palette.accent.opacity(0.08), in: .rect(cornerRadius: 18))
    }
}
