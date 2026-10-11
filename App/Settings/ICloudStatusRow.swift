import CloudKit
import CNCDesign
import SwiftUI

/// Shows whether iCloud sync is actually working for this user. Sync itself
/// is automatic (SwiftData + the private CloudKit database); without an
/// iCloud account the data simply stays on this device.
struct ICloudStatusRow: View {
    enum Status { case checking, on, signedOut, unavailable }
    @State private var status: Status = .checking

    var body: some View {
        LabeledContent("iCloud sync") {
            switch status {
            case .checking: ProgressView().controlSize(.small)
            case .on: Label("On", systemImage: "checkmark.icloud").foregroundStyle(TP.Palette.success)
            case .signedOut: Text("Sign in to iCloud in Settings")
            case .unavailable: Text("Unavailable")
            }
        }
        .task { await refresh() }
    }

    private func refresh() async {
        let container = CKContainer(identifier: "iCloud.com.yakupad.toolpath")
        do {
            switch try await container.accountStatus() {
            case .available: status = .on
            case .noAccount: status = .signedOut
            default: status = .unavailable
            }
        } catch {
            status = .unavailable
        }
    }
}
