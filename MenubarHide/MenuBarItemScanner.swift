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

enum MenuBarItemScanner {
    /// Status items pushed off-screen by the expanded separator: every status
    /// window whose right edge sits left of the separator window's left edge.
    /// ponytail: assumes hidden items live left of the main display; exotic
    /// multi-display layouts are excluded by the threshold being ~-9970.
    static func hiddenItems(leftOf thresholdX: CGFloat, excluding pid: pid_t) -> [MenuBarItemWindow] {
        statusWindows(excluding: pid)
            .filter { $0.frame.maxX <= thresholdX }
            .sorted { $0.frame.minX < $1.frame.minX }
    }

    static func frame(of windowID: CGWindowID) -> CGRect? {
        statusWindows(excluding: nil).first { $0.id == windowID }?.frame
    }

    private static func statusWindows(excluding pid: pid_t?) -> [MenuBarItemWindow] {
        guard let list = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let statusLayer = Int(CGWindowLevelForKey(.statusWindow))
        return list.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == statusLayer,
                  let ownerPID = info[kCGWindowOwnerPID as String] as? Int,
                  ownerPID != pid.map(Int.init),
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
