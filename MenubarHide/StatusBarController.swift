import AppKit
import ServiceManagement

@MainActor
final class StatusBarController {
    // Hidden Bar technique: expanding the separator's length pushes every
    // status item to its left off-screen. Never use isVisible — removing an
    // item loses its autosaved position.
    private static let collapsedLength: CGFloat = 10_000

    private let toggleItem: NSStatusItem
    private let separatorItem: NSStatusItem
    private(set) var isCollapsed = false

    init() {
        // Creation order matters on first launch: new items enter on the left,
        // so create the chevron first (rightmost), then the separator.
        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        toggleItem.autosaveName = "menubarhide_toggle"
        separatorItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        separatorItem.autosaveName = "menubarhide_separator"

        if let button = toggleItem.button {
            button.target = self
            button.action = #selector(toggleClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        separatorItem.button?.image = symbol("line.diagonal")

        collapse()
    }

    func toggle() {
        isCollapsed ? expand() : collapse()
    }

    private func collapse() {
        separatorItem.length = Self.collapsedLength
        isCollapsed = true
        toggleItem.button?.image = symbol("chevron.left")
    }

    private func expand() {
        separatorItem.length = NSStatusItem.variableLength
        isCollapsed = false
        toggleItem.button?.image = symbol("chevron.right")
    }

    private func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    @objc private func toggleClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            toggle()
        }
    }

    // MARK: - Right-click menu

    private func showMenu() {
        let menu = NSMenu()
        let loginItem = NSMenuItem(title: "Launch at Login",
                                   action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit MenubarHide",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // Assign, click, unassign — keeps left-click free for toggle()
        toggleItem.menu = menu
        toggleItem.button?.performClick(nil)
        toggleItem.menu = nil
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch {
            NSLog("Launch at Login change failed: \(error)")
        }
    }
}
