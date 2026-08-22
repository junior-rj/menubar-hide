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
enum MenuBarArrangement {
    typealias Snapshot = [String: [String: Double]]

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
        let merged = merge(saved: saved() ?? [:], fresh: fresh, liveDomains: domains)
        let defaults = UserDefaults.standard
        defaults.set(merged, forKey: snapshotKey)
        defaults.set(Date(), forKey: snapshotDateKey)
        return merged.values.reduce(0) { $0 + $1.count }
    }

    /// Pure half of the merge above, split out so it can be exercised without
    /// touching cfprefsd or UserDefaults.
    static func merge(saved: Snapshot, fresh: Snapshot, liveDomains: Set<String>) -> Snapshot {
        var merged = saved.filter { liveDomains.contains($0.key) }
        for (domain, values) in fresh {
            merged[domain, default: [:]].merge(values) { _, new in new }
        }
        return merged
    }

    // MARK: - Restore

    /// Writes remembered positions back into each owning app's domain.
    /// Skips our own domain: the separator/chevron pair has its own pinning
    /// rules in StatusBarController and must not be written twice.
    /// Only apps that create their status item AFTER this takes effect, so
    /// already-running apps move on their next launch.
    @discardableResult
    static func restore(_ snapshot: Snapshot) -> Int {
        var rewritten = 0
        for (domain, positions) in snapshot where domain != ownDomain {
            var changed = false
            for (key, value) in positions where isValid(value) {
                let current = CFPreferencesCopyValue(key as CFString, domain as CFString,
                                                     kCFPreferencesCurrentUser,
                                                     kCFPreferencesAnyHost) as? Double
                guard current != value else { continue } // no churn for values already right
                CFPreferencesSetValue(key as CFString, NSNumber(value: value), domain as CFString,
                                      kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
                NSLog("menubar-hide: restored \(domain) [\(key)] \(String(describing: current)) -> \(value)")
                changed = true
                rewritten += 1
            }
            if changed { CFPreferencesAppSynchronize(domain as CFString) }
        }
        return rewritten
    }

    // MARK: - Storage

    static func saved() -> Snapshot? {
        UserDefaults.standard.dictionary(forKey: snapshotKey) as? Snapshot
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

    private static func preferenceDomains() -> [String] {
        let dir = ("~/Library/Preferences" as NSString).expandingTildeInPath
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return files.filter { $0.hasSuffix(".plist") }.map { String($0.dropLast(6)) }
    }
}
