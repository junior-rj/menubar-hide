import AppKit
import ServiceManagement

@MainActor
final class StatusBarController {
    // Hidden Bar technique: expanding the separator's length pushes every
    // status item to its left off-screen. Never use isVisible — removing an
    // item loses its autosaved position.
    private static let collapsedLength: CGFloat = 10_000
    private static let showInPanelKey = "showInPanel"

    private let toggleItem: NSStatusItem
    private let separatorItem: NSStatusItem
    private let panel = HiddenItemsPanel()
    private var autoCollapseMonitor: Any?
    private(set) var isCollapsed = false

    private var showInPanel: Bool {
        get { UserDefaults.standard.bool(forKey: Self.showInPanelKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.showInPanelKey) }
    }

    init() {
        // Two macOS 26 quirks force us to pin positions on EVERY launch:
        // 1. On a full menu bar new items are parked off-screen (x ≈ -4220).
        // 2. Collapsing scrambles the saved positions, swapping the order, so
        //    the next launch would put the separator right of the chevron and
        //    push the chevron itself off-screen.
        // Larger value = further left, so separator (265) sits left of the
        // chevron (250). ponytail: user drags of our two items don't persist
        // across launches; revisit if that ever matters.
        let defaults = UserDefaults.standard
        defaults.set(250, forKey: "NSStatusItem Preferred Position menubarhide_toggle")
        defaults.set(265, forKey: "NSStatusItem Preferred Position menubarhide_separator")

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
        separatorItem.button?.image = symbol("number")

        // Start expanded and collapse after the first layout settles — an
        // immediate collapse is what scrambles the saved positions above.
        // Right after boot, stay expanded: menu bar apps still launching would
        // materialize left of the huge separator and get hidden unintentionally.
        updateToggleIcon()
        if ProcessInfo.processInfo.systemUptime > 300 {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !self.isCollapsed else { return }
                self.collapse()
            }
        }
    }

    func toggle() {
        if showInPanel, isCollapsed {
            panel.isVisible ? panel.close() : openPanel()
        } else {
            isCollapsed ? expand() : collapse()
        }
    }

    private func collapse() {
        panel.close()
        separatorItem.length = Self.collapsedLength
        isCollapsed = true
        updateToggleIcon()
    }

    private func expand() {
        panel.close()
        separatorItem.length = NSStatusItem.variableLength
        isCollapsed = false
        updateToggleIcon()
    }

    private func updateToggleIcon() {
        toggleItem.button?.image = symbol(isCollapsed ? "plus" : "minus")
    }

    private func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    @objc private func toggleClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showMenu()
        } else if event?.modifierFlags.contains(.option) == true {
            // option-click always toggles laterally — needed to rearrange
            // icons with cmd-drag even in panel mode
            isCollapsed ? expand() : collapse()
        } else {
            toggle()
        }
    }

    // MARK: - Panel (Ice Bar technique)

    private func openPanel() {
        guard ItemCapturer.hasPermission() else {
            ItemCapturer.requestPermission()
            return
        }
        let anchorFrame = toggleItem.button?.window?.frame ?? .zero
        Task { @MainActor in
            let windows = MenuBarItemScanner.hiddenItems()
            NSLog("menubar-hide: scanner found \(windows.count) hidden items")
            var items = await ItemCapturer.capture(windows)
            if items.count < windows.count, isCollapsed {
                // flash-expand: neither capture API renders off-screen windows,
                // so briefly bring the icons back, capture, hide again
                NSLog("menubar-hide: flash-expand to capture \(windows.count - items.count) missing")
                let captured = Set(items.map(\.id))
                let missing = windows.filter { !captured.contains($0.id) }
                separatorItem.length = NSStatusItem.variableLength
                try? await Task.sleep(for: .milliseconds(300))
                items += await ItemCapturer.capture(missing)
                separatorItem.length = Self.collapsedLength
                items.sort { $0.window.frame.minX < $1.window.frame.minX }
            }
            NSLog("menubar-hide: showing panel with \(items.count) items")
            panel.show(items: items, below: anchorFrame) { [weak self] item in
                self?.forwardClick(to: item)
            }
        }
    }

    private func forwardClick(to item: CapturedItem) {
        guard ClickForwarder.ensureAccessibility() else { return }
        expand()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300)) // let the bar relayout
            guard let frame = MenuBarItemScanner.frame(of: item.id), frame.minX >= 0 else {
                // still off-screen (e.g. behind the notch): stay expanded
                return
            }
            ClickForwarder.postClick(at: CGPoint(x: frame.midX, y: frame.midY))
            armAutoCollapse()
        }
    }

    /// Re-collapse after the forwarded click's interaction ends (the next
    /// real click anywhere, usually dismissing the item's menu).
    /// ponytail: submenus need a second click-cycle; 15s fallback covers it.
    private func armAutoCollapse() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400)) // skip our synthetic click
            guard let self, !self.isCollapsed, self.autoCollapseMonitor == nil else { return }
            self.autoCollapseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
                MainActor.assumeIsolated { self.finishAutoCollapse() }
            }
            try? await Task.sleep(for: .seconds(15))
            self.finishAutoCollapse()
        }
    }

    private func finishAutoCollapse() {
        guard let monitor = autoCollapseMonitor else { return }
        NSEvent.removeMonitor(monitor)
        autoCollapseMonitor = nil
        if !isCollapsed { collapse() }
    }

    // MARK: - Right-click menu

    private func showMenu() {
        let menu = NSMenu()

        let panelItem = NSMenuItem(title: "Show Hidden Icons in Panel",
                                   action: #selector(togglePanelMode), keyEquivalent: "")
        panelItem.target = self
        panelItem.state = showInPanel ? .on : .off
        menu.addItem(panelItem)

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

    @objc private func togglePanelMode() {
        showInPanel.toggle()
        updateToggleIcon()
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
