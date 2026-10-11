import Foundation

/// Toolpath has no login. This random id identifies the user's quota and
/// purchases on the Toolpath API and is passed to StoreKit as the
/// appAccountToken. It lives in the iCloud key-value store, so it is the same
/// on all of the user's devices, with a local copy for when iCloud is off.
enum ToolpathAccount {
    private static let key = "toolpath.accountID"

    static var id: UUID {
        let cloud = NSUbiquitousKeyValueStore.default
        if let raw = cloud.string(forKey: key), let id = UUID(uuidString: raw) {
            UserDefaults.standard.set(raw, forKey: key)
            return id
        }
        if let raw = UserDefaults.standard.string(forKey: key), let id = UUID(uuidString: raw) {
            cloud.set(raw, forKey: key)
            return id
        }
        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: key)
        cloud.set(id.uuidString, forKey: key)
        cloud.synchronize()
        return id
    }
}
