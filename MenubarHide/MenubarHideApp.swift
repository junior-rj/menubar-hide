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
        let statusBar = StatusBarController()
        self.statusBar = statusBar
        hotkey = HotkeyManager { statusBar.toggle() }
    }
}
