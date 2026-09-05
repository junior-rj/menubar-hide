import Foundation

/// Undocumented global defaults that control how much room each status item
/// takes. Shrinking them is the only way to fit more icons on a crowded bar:
/// the equivalent of `defaults write -g NSStatusItemSpacing -int 11`.
/// Every app reads them when it builds its status items, so the change only
/// shows up after a logout or restart.
enum MenuBarSpacing {
    static let presets = [4, 6, 8, 11, 12, 16]
    static let allowedRange = 0...32
    /// What macOS uses when the keys are absent; only shown as the seed of the custom prompt.
    static let systemDefault = 12

    private static let spacingKey = "NSStatusItemSpacing"
    private static let paddingKey = "NSStatusItemSelectionPadding"

    /// nil = key absent, i.e. the macOS default is in effect.
    /// Read through kCFPreferencesAnyApplication (the `-g` domain) instead of
    /// UserDefaults.standard, which would also see a value set for this app.
    static func current() -> Int? {
        guard let value = CFPreferencesCopyValue(spacingKey as CFString, kCFPreferencesAnyApplication,
                                                 kCFPreferencesCurrentUser,
                                                 kCFPreferencesAnyHost) as? NSNumber else { return nil }
        return value.intValue
    }

    /// The range is enforced here, not only in the UI: this writes the global
    /// domain every app reads, and an absurd value makes every menu bar on the
    /// machine unusable until `defaults delete -g` is run by hand.
    @discardableResult
    static func apply(_ value: Int) -> Bool {
        guard allowedRange.contains(value) else {
            NSLog("menubar-hide: refused menu bar spacing \(value), outside \(allowedRange)")
            return false
        }
        let ok = write(NSNumber(value: value))
        NSLog("menubar-hide: menu bar spacing set to \(value) (synchronized: \(ok))")
        return ok
    }

    @discardableResult
    static func reset() -> Bool {
        let ok = write(nil)
        NSLog("menubar-hide: menu bar spacing reset to the macOS default (synchronized: \(ok))")
        return ok
    }

    private static func write(_ value: NSNumber?) -> Bool {
        for key in [spacingKey, paddingKey] {
            CFPreferencesSetValue(key as CFString, value, kCFPreferencesAnyApplication,
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }
        return CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
    }
}
