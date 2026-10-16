import Foundation
import Security
import SystemConfiguration

/// The journal contains only the SOCKS subset; unrelated HTTP/PAC/exclusion settings never change.
struct ProxySnapshot: Codable {
    let serviceID: String
    let original: Data
    let applied: Data
}

struct ProxyJournal: Codable {
    var snapshots: [ProxySnapshot]
}

enum ProxyRestoration {
    static func socks(_ dictionary: [String: Any]) -> [String: Any] {
        dictionary.filter { $0.key.hasPrefix("SOCKS") }
    }
    static func equals(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool {
        NSDictionary(dictionary: lhs).isEqual(to: rhs)
    }
    /// Restore only while the full owned subset still matches, preserving a user's later SOCKS edits.
    static func restore(current: [String: Any], original: [String: Any], applied: [String: Any]) -> (settings: [String: Any], owned: Bool) {
        guard equals(socks(current), socks(applied)) else { return (current, false) }
        var restored = current.filter { !$0.key.hasPrefix("SOCKS") }
        restored.merge(socks(original)) { _, old in old }
        return (restored, true)
    }
}

@MainActor
final class ProxySettings {
    let journalURL: URL
    var hasPendingRecovery: Bool { FileManager.default.fileExists(atPath: journalURL.path) }
    init(journalURL: URL) { self.journalURL = journalURL }

    private func session() throws -> (SCPreferences, AuthorizationRef) {
        var authorization: AuthorizationRef?
        let status = AuthorizationCreate(nil, nil, [.interactionAllowed, .extendRights, .preAuthorize], &authorization)
        guard status == errAuthorizationSuccess, let authorization else { throw RuntimeError.message("Network settings authorization was cancelled or denied (\(status)).") }
        guard let preferences = SCPreferencesCreateWithAuthorization(nil, "Darkware Zapret" as CFString, nil, authorization) else {
            AuthorizationFree(authorization, [])
            throw RuntimeError.message("Cannot open macOS network preferences.")
        }
        guard SCPreferencesLock(preferences, true) else {
            AuthorizationFree(authorization, [])
            throw RuntimeError.message("Cannot lock macOS network preferences: \(String(cString: SCErrorString(SCError())))")
        }
        return (preferences, authorization)
    }

    func apply(port: Int) throws {
        guard !hasPendingRecovery else { throw RuntimeError.message("Restore the previous network settings before connecting.") }
        let (preferences, authorization) = try session()
        defer { SCPreferencesUnlock(preferences); AuthorizationFree(authorization, []) }
        guard let services = SCNetworkServiceCopyAll(preferences) as? [SCNetworkService] else { throw RuntimeError.message("Cannot read network services.") }
        var snapshots: [ProxySnapshot] = []
        for service in services where SCNetworkServiceGetEnabled(service) {
            guard let proto = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeProxies), SCNetworkProtocolGetEnabled(proto), let identifier = SCNetworkServiceGetServiceID(service) as String? else { continue }
            let original = SCNetworkProtocolGetConfiguration(proto) as? [String: Any] ?? [:]
            var applied = original.filter { !$0.key.hasPrefix("SOCKS") }
            applied["SOCKSEnable"] = 1
            applied["SOCKSProxy"] = "127.0.0.1"
            applied["SOCKSPort"] = port
            snapshots.append(ProxySnapshot(serviceID: identifier, original: try encode(ProxyRestoration.socks(original)), applied: try encode(ProxyRestoration.socks(applied))))
            guard SCNetworkProtocolSetConfiguration(proto, applied as CFDictionary) else { throw RuntimeError.message("Cannot prepare SOCKS settings for a network service.") }
        }
        guard !snapshots.isEmpty else { throw RuntimeError.message("No enabled network service supports proxy settings.") }
        // Save first: a crash at any later point can restore settings on the next launch.
        try JSONEncoder().encode(ProxyJournal(snapshots: snapshots)).write(to: journalURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: journalURL.path)
        guard SCPreferencesCommitChanges(preferences), SCPreferencesApplyChanges(preferences) else {
            throw RuntimeError.message("macOS could not apply SOCKS settings. Recovery is available on the next launch.")
        }
    }

    @discardableResult
    func restore() throws -> Int {
        guard hasPendingRecovery else { return 0 }
        let journal = try JSONDecoder().decode(ProxyJournal.self, from: Data(contentsOf: journalURL))
        let (preferences, authorization) = try session()
        defer { SCPreferencesUnlock(preferences); AuthorizationFree(authorization, []) }
        var changed = false, conflicts = 0
        for snapshot in journal.snapshots {
            guard let service = SCNetworkServiceCopy(preferences, snapshot.serviceID as CFString), let proto = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeProxies) else { continue }
            let current = SCNetworkProtocolGetConfiguration(proto) as? [String: Any] ?? [:]
            let result = ProxyRestoration.restore(current: current, original: try decode(snapshot.original), applied: try decode(snapshot.applied))
            if result.owned {
                guard SCNetworkProtocolSetConfiguration(proto, result.settings as CFDictionary) else { throw RuntimeError.message("Cannot restore saved SOCKS settings.") }
                changed = true
            } else { conflicts += 1 }
        }
        if changed {
            guard SCPreferencesCommitChanges(preferences), SCPreferencesApplyChanges(preferences) else { throw RuntimeError.message("macOS could not restore saved SOCKS settings. The recovery journal has been kept.") }
        }
        try FileManager.default.removeItem(at: journalURL)
        return conflicts
    }

    private func encode(_ settings: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: settings, format: .binary, options: 0)
    }
    private func decode(_ data: Data) throws -> [String: Any] {
        guard let settings = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { throw RuntimeError.message("The recovery journal is invalid.") }
        return settings
    }
}
