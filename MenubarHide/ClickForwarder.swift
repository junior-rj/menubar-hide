import AppKit
import ApplicationServices

// Forwards a click from the panel to the real status item after it is
// temporarily brought back on-screen. Requires the Accessibility permission.
@MainActor
enum ClickForwarder {
    static func ensureAccessibility() -> Bool {
        // literal value of kAXTrustedCheckOptionPrompt (the global var is not
        // concurrency-safe under Swift 6 strict)
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// `point` in CG global coordinates (top-left origin), same space as
    /// the frames from MenuBarItemScanner.
    static func postClick(at point: CGPoint) {
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type,
                    mouseCursorPosition: point, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
    }
}
