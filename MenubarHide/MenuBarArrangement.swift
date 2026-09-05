import Foundation

/// Menu bar icon positions do NOT live in one place: every app stores its own
/// under "NSStatusItem Preferred Position <autosaveName>" in ITS preferences
/// domain, and AppKit only reads that value when the app creates the status
/// item. So the arrangement survives a restart only if someone writes the
/// remembered positions back before the owning apps register their items.
///
/// Keying by (domain, key) sidesteps the macOS 26 identification problem: the
/// status windows all report Control Center as their owner, and apps that never
/// set an autosaveName all share the key "Item-0" — useless for matching a
/// window to an app, irrelevant here since we never need that mapping.
///
/// A domain is either a bundle id (plist under ~/Library/Preferences) or the
/// absolute path of a sandboxed app's container plist: cfprefsd redirects
/// sandboxed apps to ~/Library/Containers/<id>/Data/Library/Preferences, so
/// their bundle id resolves to the wrong file from this unsandboxed process.
/// CFPreferences accepts a path as the application id (like `defaults write
/// /path/file.plist`), which keeps every read and write going through cfprefsd.
enum MenuBarArrangement {
    typealias Snapshot = [String: [String: Double]]

    struct RestoreResult {
        var rewritten = 0
        /// Domains whose CFPreferencesAppSynchronize reported failure.
        var failedDomains = 0
    }

    static let ownDomain = Bundle.main.bundleIdentifier ?? "com.sparrow.menubarhide"

    private static let keyPrefix = "NSStatusItem Preferred Position"
    private static let snapshotKey = "savedArrangement"
    private static let snapshotDateKey = "savedArrangementDate"
    /// A parked-off-screen item autosaves a wildly negative position (x ≈ -4220);
    /// 0 is legitimate (rightmost), larger values sit further left.
    private static let validRange: ClosedRange<Double> = 0...10_000

    static func isValid(_ position: Double) -> Bool { validRange.contains(position) }

    // MARK: - Capture

    /// Reads every domain's status item positions. Measured at 73ms cold and
    /// 2ms warm (cfprefsd caches), cheap enough to run inline before a collapse
    /// — which it must, since collapsing rewrites the positions it would read.
    static func capture() -> (positions: Snapshot, domains: Set<String>) {
        var positions: Snapshot = [:]
        var domains: Set<String> = []
        for domain in preferenceDomains() {
            domains.insert(domain)
            guard let keys = CFPreferencesCopyKeyList(domain as CFString,
                                                     kCFPreferencesCurrentUser,
                                                     kCFPreferencesAnyHost) as? [String] else { continue }
            var found: [String: Double] = [:]
            for key in keys where key.hasPrefix(keyPrefix) {
                guard let value = CFPreferencesCopyValue(key as CFString, domain as CFString,
                                                         kCFPreferencesCurrentUser,
                                                         kCFPreferencesAnyHost) as? Double,
                      isValid(value) else { continue } // damaged value: keep the remembered one
                found[key] = value
            }
            if !found.isEmpty { positions[domain] = found }
        }
        return (positions, domains)
    }

    /// Captures and merges into the stored snapshot, returning the total count.
    ///
    /// Merging rather than replacing is the whole point of the repair: a
    /// position that got corrupted is dropped by `capture`, so replacing would
    /// forget the last good value exactly when we need it. Domains whose plist
    /// is gone (app uninstalled) are dropped, so we never resurrect junk.
    @discardableResult
    static func captureAndSave() -> Int {
        let (fresh, domains) = capture()
        guard !domains.isEmpty else {
            // the preferences directory was unreadable: merging would drop every
            // remembered domain and wipe the only backup right before a collapse
            NSLog("menubar-hide: no preference domains readable, keeping the saved arrangement")
            return savedCount()
        }
        let merged = merge(saved: saved() ?? [:], fresh: fresh, liveDomains: domains)
        let defaults = UserDefaults.standard
        defaults.set(merged, forKey: snapshotKey)
        defaults.set(Date(), forKey: snapshotDateKey)
        return merged.values.reduce(0) { $0 + $1.count }
    }

    /// Pure half of the merge above, split out so it can be exercised without
    /// touching cfprefsd or UserDefaults. No live domains means nothing could
    /// be read, not that every app vanished: the saved snapshot stays as is.
    static func merge(saved: Snapshot, fresh: Snapshot, liveDomains: Set<String>) -> Snapshot {
        guard !liveDomains.isEmpty else { return saved }
        var merged = saved.filter { liveDomains.contains($0.key) }
        for (domain, values) in fresh {
            merged[domain, default: [:]].merge(values) { _, new in new }
        }
        return merged
    }

    // MARK: - Restore

    /// Writes remembered positions back into each owning app's domain.
    /// Only apps that create their status item AFTER this takes effect, so
    /// already-running apps move on their next launch.
    @discardableResult
    static func restore(_ snapshot: Snapshot) -> RestoreResult {
        var result = RestoreResult()
        for (domain, positions) in snapshot {
            var changed = false
            for (key, value) in positions where isValid(value) && isRestorable(domain: domain, key: key) {
                let current = CFPreferencesCopyValue(key as CFString, domain as CFString,
                                                     kCFPreferencesCurrentUser,
                                                     kCFPreferencesAnyHost) as? Double
                guard current != value else { continue } // no churn for values already right
                CFPreferencesSetValue(key as CFString, NSNumber(value: value), domain as CFString,
                                      kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
                changed = true
                result.rewritten += 1
            }
            if changed, !CFPreferencesAppSynchronize(domain as CFString) {
                result.failedDomains += 1
                NSLog("menubar-hide: could not synchronize a preference domain while restoring")
            }
        }
        // counts only: the domains are the user's installed-app inventory and
        // the unified log is not the place for it
        NSLog("menubar-hide: restore rewrote \(result.rewritten) positions, \(result.failedDomains) domains failed to sync")
        return result
    }

    /// The snapshot lives in this app's own plist, which any process running as
    /// the user can edit, so restore re-checks what capture guaranteed: only
    /// status item keys, never the global domain, never a path outside the
    /// user's app containers. Our own pair is pinned by StatusBarController and
    /// must not be written twice.
    static func isRestorable(domain: String, key: String, home: String = NSHomeDirectory()) -> Bool {
        guard key.hasPrefix(keyPrefix), domain != ownDomain, !domain.hasPrefix(".") else { return false }
        if domain.hasPrefix("/") {
            return domain.hasPrefix(home + "/Library/Containers/") && !domain.contains("/../")
        }
        return !domain.contains("/")
    }

    // MARK: - Storage

    static func saved() -> Snapshot? {
        guard let raw = UserDefaults.standard.dictionary(forKey: snapshotKey) else { return nil }
        let decoded = decode(raw)
        return decoded.isEmpty ? nil : decoded
    }

    /// Element-wise, so one malformed leaf costs one position, not the whole
    /// backup (an all-or-nothing `as? Snapshot` would report "nothing saved"
    /// and the next merge would start from scratch).
    static func decode(_ raw: [String: Any]) -> Snapshot {
        var snapshot: Snapshot = [:]
        for (domain, entry) in raw {
            guard let values = entry as? [String: Any] else { continue }
            var positions: [String: Double] = [:]
            for (key, value) in values {
                guard let number = value as? NSNumber else { continue }
                positions[key] = number.doubleValue
            }
            if !positions.isEmpty { snapshot[domain] = positions }
        }
        return snapshot
    }

    static func savedDate() -> Date? {
        UserDefaults.standard.object(forKey: snapshotDateKey) as? Date
    }

    static func savedCount() -> Int {
        (saved() ?? [:]).values.reduce(0) { $0 + $1.count }
    }

    static func savedOwnPosition(_ key: String) -> Double? {
        saved()?[ownDomain]?[key]
    }

    static func containerPlistPath(home: String, containerID: String) -> String {
        "\(home)/Library/Containers/\(containerID)/Data/Library/Preferences/\(containerID).plist"
    }

    /// Bundle ids for the plain domains plus the container plist path of every
    /// sandboxed app. Listing the directory is the only enumeration available:
    /// `CFPreferencesCopyApplicationList` is unavailable in the SDK.
    private static func preferenceDomains() -> [String] {
        let home = NSHomeDirectory()
        let fm = FileManager.default
        let plain = ((try? fm.contentsOfDirectory(atPath: home + "/Library/Preferences")) ?? [])
            .filter { $0.hasSuffix(".plist") }
            .map { String($0.dropLast(6)) }
        let containers = ((try? fm.contentsOfDirectory(atPath: home + "/Library/Containers")) ?? [])
            .map { containerPlistPath(home: home, containerID: $0) }
            .filter { fm.fileExists(atPath: $0) }
        return plain + containers
    }
}
