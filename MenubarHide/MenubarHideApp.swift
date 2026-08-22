import SwiftUI

@main
struct MenubarHideApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings {} // app lives in the menu bar; no windows
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    private var hotkey: HotkeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The unit test bundle is hosted by this app, so a test run would
        // otherwise create real status items and start collapsing the user's
        // menu bar — and autosave a snapshot of whatever it did to it.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            NSLog("menubar-hide: running under XCTest, skipping setup")
            return
        }
        NSLog("menubar-hide: applicationDidFinishLaunching")
        let statusBar = StatusBarController()
        NSLog("menubar-hide: StatusBarController created")
        self.statusBar = statusBar
        hotkey = HotkeyManager { statusBar.toggle() }
    }
}
