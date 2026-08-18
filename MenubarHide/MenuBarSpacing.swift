import Foundation

/// Undocumented global defaults that control how much room each status item
/// takes. Shrinking them is the only way to fit more icons on a crowded bar:
/// the equivalent of `defaults write -g NSStatusItemSpacing -int 11`.
/// Every app reads them when it builds its status items, so the change only
/// shows up after a logout or restart.
enum MenuBarSpacing {
    static let presets = [4, 6, 8, 11, 12, 16]
    static let allowedRange = 0...32

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

    static func apply(_ value: Int) {
        write(NSNumber(value: value))
        NSLog("menubar-hide: menu bar spacing set to \(value)")
    }

    static func reset() {
        write(nil)
        NSLog("menubar-hide: menu bar spacing reset to the macOS default")
    }

    private static func write(_ value: NSNumber?) {
        for key in [spacingKey, paddingKey] {
            CFPreferencesSetValue(key as CFString, value, kCFPreferencesAnyApplication,
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
    }
}
