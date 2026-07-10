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
        guard let content = try? await SCShareableContent
            .excludingDesktopWindows(false, onScreenWindowsOnly: false) else { return [] }
        let scale = NSScreen.main?.backingScaleFactor ?? 2

        var items: [CapturedItem] = []
        for window in windows {
            guard let scWindow = content.windows.first(where: { $0.windowID == window.id }) else { continue }
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width * scale)
            config.height = Int(window.frame.height * scale)
            config.showsCursor = false
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            guard let cgImage = try? await SCScreenshotManager
                .captureImage(contentFilter: filter, configuration: config) else { continue }
            items.append(CapturedItem(window: window,
                                      image: NSImage(cgImage: cgImage, size: window.frame.size)))
        }
        return items
    }
}
