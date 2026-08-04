import AppKit
import ApplicationServices

// Forwards a click from the panel to the real status item after it is
// temporarily brought back on-screen. Requires the Accessibility permission.
@MainActor
enum ClickForwarder {
    /// Prompt-free check — the caller shows its own alert, and stacking the
    /// system prompt on top of it would give two competing dialogs.
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Triggers the system Accessibility prompt, which also registers the app
    /// in the Privacy & Security list (the settings deep link alone doesn't).
    static func promptForAccessibility() {
        // literal value of kAXTrustedCheckOptionPrompt (the global var is not
        // concurrency-safe under Swift 6 strict)
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// `point` in CG global coordinates (top-left origin), same space as
    /// the frames from MenuBarItemScanner.
    static func postClick(at point: CGPoint) {
        let restorePoint = CGEvent(source: nil)?.location

        // hover first: some status items only react after seeing the cursor arrive
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)

        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            let event = CGEvent(mouseEventSource: nil, mouseType: type,
                                mouseCursorPosition: point, mouseButton: .left)
            // default clickState 0 reads as NSEvent.clickCount == 0, which
            // most status item handlers ignore
            event?.setIntegerValueField(.mouseEventClickState, value: 1)
            event?.post(tap: .cghidEventTap)
        }

        if let restorePoint {
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                    mouseCursorPosition: restorePoint, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
        NSLog("menubar-hide: synthetic click posted at (\(point.x), \(point.y))")
    }
}
