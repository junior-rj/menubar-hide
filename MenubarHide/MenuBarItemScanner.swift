import AppKit

struct MenuBarItemWindow: Identifiable {
    let id: CGWindowID
    let frame: CGRect // CG global coordinates (top-left origin)
    let ownerName: String
}

struct CapturedItem: Identifiable {
    let window: MenuBarItemWindow
    let image: NSImage
    var id: CGWindowID { window.id }
}

// On macOS 26 status item windows are hosted by Control Center (owner name
// and pid are useless for identifying whose icon it is), and the window
// server clamps our 10000pt separator to ~5000pt. So discovery is by shape:
// find the huge separator window, then take the contiguous run of icons
// sitting immediately left of it.
enum MenuBarItemScanner {
    /// ponytail: 2500 clears real icons and full-bar overlays like NotchNook
    /// (<= screen width) while matching the clamped separator (~5016).
    private static let separatorMinWidth: CGFloat = 2_500

    /// Largest gap between two neighbouring hidden icons; beyond it the run
    /// has jumped to another display's copy of the bar.
    private static let contiguityGap: CGFloat = 50

    static func hiddenItems() -> [MenuBarItemWindow] {
        hiddenItems(among: statusWindows())
    }

    /// Pure half of the discovery, split out so the shape heuristics can be
    /// tested without a live window server.
    static func hiddenItems(among windows: [MenuBarItemWindow]) -> [MenuBarItemWindow] {
        // our collapsed separator on the main menu bar = the rightmost huge
        // status window (a second display's bar has its own copy further left)
        guard let separator = windows
            .filter({ $0.frame.width >= separatorMinWidth })
            .max(by: { $0.frame.minX < $1.frame.minX })
        else { return [] }

        // walk leftwards from the separator's left edge; the hidden icons are
        // contiguous, so a big gap means we reached the second display's copies
        var result: [MenuBarItemWindow] = []
        var edge = separator.frame.minX
        let candidates = windows
            .filter { $0.frame.maxX <= separator.frame.minX + 1 && $0.frame.width < separatorMinWidth }
            .sorted { $0.frame.maxX > $1.frame.maxX }
        for window in candidates {
            guard edge - window.frame.maxX <= contiguityGap else { break }
            result.append(window)
            edge = window.frame.minX
        }
        return result.sorted { $0.frame.minX < $1.frame.minX }
    }

    static func frame(of windowID: CGWindowID) -> CGRect? {
        statusWindows().first { $0.id == windowID }?.frame
    }

    /// Fingerprint of the status-layer population (window IDs AND positions,
    /// so a cmd-drag rearrangement in progress reads as "not settled") — used
    /// to detect when the launch storm ended before the initial collapse.
    static func statusItemFingerprint() -> Set<String> {
        Set(statusWindows().map { "\($0.id)@\(Int($0.frame.minX.rounded()))" })
    }

    private static func statusWindows() -> [MenuBarItemWindow] {
        guard let list = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let statusLayer = Int(CGWindowLevelForKey(.statusWindow))
        return list.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == statusLayer,
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsDict),
                  frame.width > 0, frame.height > 0
            else { return nil }
            return MenuBarItemWindow(id: windowID,
                                     frame: frame,
                                     ownerName: info[kCGWindowOwnerName as String] as? String ?? "")
        }
    }
}
