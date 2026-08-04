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
    private var autoCollapseTask: Task<Void, Never>?
    private var initialCollapseTask: Task<Void, Never>?
    private var isOpeningPanel = false
    private(set) var isCollapsed = false

    private var showInPanel: Bool {
        get { UserDefaults.standard.bool(forKey: Self.showInPanelKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.showInPanelKey) }
    }

    init() {
        // Two macOS 26 quirks force us to pin positions BEFORE item creation:
        // 1. On a full menu bar new items are parked off-screen (x ≈ -4220).
        // 2. Collapsing scrambles the saved positions, swapping the order, so
        //    the next launch would put the separator right of the chevron and
        //    push the chevron itself off-screen.
        // The pin only needs the key to EXIST with a sane value when
        // autosaveName is assigned, so re-assert whatever AppKit autosaved
        // last session — overwriting it with constants would shift the
        // separator and silently reclassify every icon between the old and
        // new positions as hidden/visible. Fall back to the defaults (larger
        // value = further left, separator 265 left of chevron 250) on first
        // launch or when the stored value shows off-screen parking damage.
        let defaults = UserDefaults.standard
        let toggleKey = "NSStatusItem Preferred Position menubarhide_toggle"
        let separatorKey = "NSStatusItem Preferred Position menubarhide_separator"
        let storedToggle = defaults.object(forKey: toggleKey) as? Double
        let storedSeparator = defaults.object(forKey: separatorKey) as? Double
        let togglePos: Double, separatorPos: Double
        // separator must stay left of (= greater than) the chevron; a swapped
        // pair is scramble damage and re-pinning it would swallow the chevron
        // on every launch, so reset BOTH — a half-reset recreates the swap
        if let t = storedToggle, let s = storedSeparator,
           t > 0, s > 0, t <= 10_000, s <= 10_000, s > t {
            (togglePos, separatorPos) = (t, s)
            NSLog("menubar-hide: pinned positions toggle=\(t) separator=\(s)")
        } else {
            (togglePos, separatorPos) = (250, 265)
            NSLog("menubar-hide: resetting positions to defaults (stored toggle=\(String(describing: storedToggle)) separator=\(String(describing: storedSeparator)))")
        }
        defaults.set(togglePos, forKey: toggleKey)
        defaults.set(separatorPos, forKey: separatorKey)

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

        updateToggleIcon()
        scheduleInitialCollapse()
    }

    // Start expanded and collapse only once the menu bar population settles.
    // An immediate collapse scrambles the saved positions above, and
    // collapsing during the login launch storm swallows apps that register
    // later AND corrupts their own autosaved positions (parked off-screen).
    // Wall-clock guards don't work here: uptime measures boot, not login,
    // so FileVault waits and logout/login break any fixed threshold.
    private func scheduleInitialCollapse() {
        initialCollapseTask = Task { @MainActor [weak self] in
            guard (try? await Task.sleep(for: .milliseconds(500))) != nil else { return } // let the first layout settle
            var fingerprint = Set<String>()
            var stablePolls = 0
            for poll in 0..<60 { // 2s each: cap the wait at ~120s
                guard let self, !self.isCollapsed, !Task.isCancelled else { return }
                let current = MenuBarItemScanner.statusItemFingerprint()
                if current == fingerprint {
                    stablePolls += 1
                    if stablePolls >= 3 {
                        NSLog("menubar-hide: menu bar stable after \(poll + 1) polls, collapsing")
                        self.collapse()
                        return
                    }
                } else {
                    stablePolls = 0
                    fingerprint = current
                }
                guard (try? await Task.sleep(for: .seconds(2))) != nil else { return }
            }
            guard let self, !self.isCollapsed, !Task.isCancelled else { return }
            NSLog("menubar-hide: menu bar never stabilized, collapsing anyway")
            self.collapse()
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
        stateWillChange()
        panel.close()
        separatorItem.length = Self.collapsedLength
        isCollapsed = true
        updateToggleIcon()
    }

    private func expand() {
        stateWillChange()
        panel.close()
        separatorItem.length = NSStatusItem.variableLength
        isCollapsed = false
        updateToggleIcon()
    }

    /// Any collapse/expand supersedes pending automation: a stale
    /// auto-collapse monitor would fire on the NEXT forwarded click's own
    /// synthetic mouseUp, yanking the bar mid-interaction, and the initial
    /// stability poller must not override a manual toggle.
    private func stateWillChange() {
        initialCollapseTask?.cancel()
        initialCollapseTask = nil
        disarmAutoCollapse()
    }

    private func disarmAutoCollapse() {
        autoCollapseTask?.cancel()
        autoCollapseTask = nil
        if let monitor = autoCollapseMonitor {
            NSEvent.removeMonitor(monitor)
            autoCollapseMonitor = nil
            NSLog("menubar-hide: auto-collapse disarmed")
        }
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
        guard !isOpeningPanel else { return } // overlapping flash-expands fight over the separator length
        guard ItemCapturer.hasPermission() else {
            NSLog("menubar-hide: screen recording permission missing")
            showPermissionAlert(
                message: "Screen Recording permission needed",
                informative: "MenubarHide needs Screen Recording access to show the hidden icons in the panel. Grant it in System Settings, then relaunch MenubarHide (macOS requires a relaunch for this permission).",
                settingsAnchor: "Privacy_ScreenCapture",
                beforeOpeningSettings: { ItemCapturer.requestPermission() })
            return
        }
        isOpeningPanel = true
        let anchorFrame = toggleItem.button?.window?.frame ?? .zero
        Task { @MainActor in
            defer { isOpeningPanel = false }
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
        NSLog("menubar-hide: forwarding click to item \(item.id) (\(item.window.ownerName))")
        guard ClickForwarder.isTrusted() else {
            NSLog("menubar-hide: accessibility not granted, cannot forward click")
            showPermissionAlert(
                message: "Accessibility permission needed",
                informative: "MenubarHide needs Accessibility access to click hidden icons for you. Grant it in System Settings › Privacy & Security › Accessibility, then try again.",
                settingsAnchor: "Privacy_Accessibility",
                beforeOpeningSettings: { ClickForwarder.promptForAccessibility() })
            return
        }
        expand()
        Task { @MainActor in
            // the bar relayouts asynchronously; retry until the item lands on-screen
            var frame: CGRect?
            for _ in 0..<3 {
                try? await Task.sleep(for: .milliseconds(150))
                if let found = MenuBarItemScanner.frame(of: item.id), Self.isInMenuBarStrip(found) {
                    frame = found
                    break
                }
            }
            guard let frame else {
                // still off-screen (e.g. behind the notch): stay expanded so
                // the user can click the real item, but keep a way back down
                NSLog("menubar-hide: item \(item.id) still off-screen after expand")
                armAutoCollapse()
                return
            }
            NSLog("menubar-hide: posting click at (\(frame.midX), \(frame.midY))")
            ClickForwarder.postClick(at: CGPoint(x: frame.midX, y: frame.midY))
            armAutoCollapse()
        }
    }

    /// The click target must sit in some display's menu bar strip. A frame
    /// anywhere else means a foreign window spoofed the status layer to
    /// redirect our synthetic click (we hold the Accessibility grant).
    /// CGDisplayBounds shares the CG global space of the scanner frames;
    /// displays left of the main one legitimately have negative X.
    private static func isInMenuBarStrip(_ frame: CGRect) -> Bool {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)
        let mid = CGPoint(x: frame.midX, y: frame.midY)
        return displays.contains { display in
            let bounds = CGDisplayBounds(display)
            return bounds.contains(mid)
                && abs(frame.minY - bounds.minY) <= 2
                && frame.height <= 40
        }
    }

    private func showPermissionAlert(message: String, informative: String,
                                     settingsAnchor: String, beforeOpeningSettings: () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informative
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true) // LSUIElement apps need this for runModal
        if alert.runModal() == .alertFirstButtonReturn {
            // system prompt fires here, right as Settings opens — it also
            // registers the app in the permission list, unlike the deep link
            beforeOpeningSettings()
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(settingsAnchor)") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Re-collapse after the forwarded click's interaction ends (the next
    /// real click anywhere, usually dismissing the item's menu).
    /// ponytail: submenus need a second click-cycle; 15s fallback covers it.
    private func armAutoCollapse() {
        autoCollapseTask?.cancel()
        autoCollapseTask = Task { @MainActor [weak self] in
            guard (try? await Task.sleep(for: .milliseconds(400))) != nil else { return } // skip our synthetic click
            guard let self, !self.isCollapsed else { return }
            if self.autoCollapseMonitor == nil {
                self.autoCollapseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
                    MainActor.assumeIsolated { self.finishAutoCollapse() }
                }
                NSLog("menubar-hide: auto-collapse armed")
            }
            guard (try? await Task.sleep(for: .seconds(15))) != nil else { return }
            self.finishAutoCollapse()
        }
    }

    private func finishAutoCollapse() {
        autoCollapseTask?.cancel()
        autoCollapseTask = nil
        guard let monitor = autoCollapseMonitor else { return }
        NSEvent.removeMonitor(monitor)
        autoCollapseMonitor = nil
        NSLog("menubar-hide: auto-collapse fired")
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
