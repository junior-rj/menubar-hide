import AppKit
import ScreenCaptureKit

// Screenshots of individual (off-screen) status item windows via
// ScreenCaptureKit. Requires the Screen Recording permission.
@MainActor
enum ItemCapturer {
    static func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestPermission() {
        CGRequestScreenCaptureAccess()
    }

    static func capture(_ windows: [MenuBarItemWindow]) async -> [CapturedItem] {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent
                .excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            NSLog("menubar-hide: SCShareableContent failed: \(error)")
            return []
        }
        NSLog("menubar-hide: capturing \(windows.count) windows, shareable has \(content.windows.count)")
        let scale = NSScreen.main?.backingScaleFactor ?? 2

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
            guard let scWindow = content.windows.first(where: { $0.windowID == window.id }) else {
                NSLog("menubar-hide: window \(window.id) not in shareable content")
                continue
            }
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
