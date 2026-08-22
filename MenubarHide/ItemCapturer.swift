import AppKit
import ScreenCaptureKit

// Screenshots of individual (off-screen) status item windows. Tries the legacy
// CGWindowList API first and falls back to ScreenCaptureKit; both need the
// Screen Recording permission.
@MainActor
enum ItemCapturer {
    static func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestPermission() {
        CGRequestScreenCaptureAccess()
    }

    /// Backing scale of the display the window sits on. NSScreen.frame is
    /// AppKit space (y flipped relative to the CGWindowList frames we get
    /// here), but X is identical in both, and a menu bar item is unambiguous
    /// by X alone — so match on that instead of converting.
    private static func scale(for frame: CGRect) -> CGFloat {
        let midX = frame.midX
        let screen = NSScreen.screens.first { $0.frame.minX <= midX && midX < $0.frame.maxX }
        return (screen ?? NSScreen.main)?.backingScaleFactor ?? 2
    }

    static func capture(_ windows: [MenuBarItemWindow]) async -> [CapturedItem] {
        NSLog("menubar-hide: capturing \(windows.count) windows")

        // Fetched lazily: the legacy path below must not be gated on the SCK
        // one. Nil after a fetch attempt means SCK is unavailable — don't retry
        // it once per window.
        var content: SCShareableContent?
        var triedFetchingContent = false

        var items: [CapturedItem] = []
        for window in windows {
            // legacy API first: cheaper for tiny windows. Off-screen windows
            // fail in BOTH APIs (SCK -3811, legacy nil) — that's what the
            // flash-expand retry in openPanel exists for
            if let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow,
                                                     window.id, [.boundsIgnoreFraming, .bestResolution]) {
                NSLog("menubar-hide: legacy capture of \(window.id) ok")
                items.append(CapturedItem(window: window,
                                          image: NSImage(cgImage: cgImage, size: window.frame.size)))
                continue
            }
            if !triedFetchingContent {
                triedFetchingContent = true
                do {
                    content = try await SCShareableContent
                        .excludingDesktopWindows(false, onScreenWindowsOnly: false)
                    NSLog("menubar-hide: shareable content has \(content?.windows.count ?? 0) windows")
                } catch {
                    NSLog("menubar-hide: SCShareableContent failed: \(error)")
                }
            }
            guard let scWindow = content?.windows.first(where: { $0.windowID == window.id }) else {
                NSLog("menubar-hide: window \(window.id) not in shareable content")
                continue
            }
            let scale = scale(for: window.frame)
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width * scale)
            config.height = Int(window.frame.height * scale)
            config.showsCursor = false
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            do {
                let cgImage = try await SCScreenshotManager
                    .captureImage(contentFilter: filter, configuration: config)
                items.append(CapturedItem(window: window,
                                          image: NSImage(cgImage: cgImage, size: window.frame.size)))
            } catch {
                NSLog("menubar-hide: capture of \(window.id) failed: \(error)")
            }
        }
        return items
    }
}
