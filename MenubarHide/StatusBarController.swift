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
    private var snapshotTask: Task<Void, Never>?
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

        // Everyone else's icons keep their position in THEIR app's domain, so
        // putting the bar back the way the user arranged it means writing those
        // positions before the owning apps register their items — which is why
        // this runs at launch, ahead of everything else.
        if let snapshot = MenuBarArrangement.saved() {
            let rewritten = MenuBarArrangement.restore(snapshot)
            NSLog("menubar-hide: restored arrangement, rewrote \(rewritten) of \(MenuBarArrangement.savedCount()) remembered positions")
        }

        let storedToggle = defaults.object(forKey: toggleKey) as? Double
        let storedSeparator = defaults.object(forKey: separatorKey) as? Double
        let togglePos: Double, separatorPos: Double
        // separator must stay left of (= greater than) the chevron; a swapped
        // pair is scramble damage and re-pinning it would swallow the chevron
        // on every launch, so reset BOTH — a half-reset recreates the swap
        if let t = storedToggle, let s = storedSeparator, Self.isSanePair(toggle: t, separator: s) {
            (togglePos, separatorPos) = (t, s)
            NSLog("menubar-hide: pinned positions toggle=\(t) separator=\(s)")
        } else if let t = MenuBarArrangement.savedOwnPosition(toggleKey),
                  let s = MenuBarArrangement.savedOwnPosition(separatorKey),
                  Self.isSanePair(toggle: t, separator: s) {
            // damaged pair, but the snapshot still holds the last sane one:
            // prefer it over the constants, which would shift the separator and
            // silently reclassify every icon between the two positions
            (togglePos, separatorPos) = (t, s)
            NSLog("menubar-hide: pinned positions from snapshot toggle=\(t) separator=\(s)")
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

    /// The separator must stay left of (= greater than) the chevron, and both
    /// must be on-screen: a parked item autosaves x ≈ -4220.
    private static func isSanePair(toggle: Double, separator: Double) -> Bool {
        MenuBarArrangement.isValid(toggle) && MenuBarArrangement.isValid(separator)
            && toggle > 0 && separator > toggle
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
        // Remember the arrangement BEFORE the length change: collapsing pushes
        // the icons off-screen and macOS autosaves those parked positions, so
        // capturing afterwards would remember the damage, not the arrangement.
        captureArrangement(reason: "before collapse")
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
        scheduleArrangementSnapshot()
    }

    /// Reads every app's stored icon position and merges it into our snapshot.
    /// 73ms on the first call, 2ms afterwards (cfprefsd caches), so it runs
    /// inline — it has to, since the collapse right after it would spoil what
    /// it reads.
    ///
    /// Never snapshot while collapsed: the hidden icons sit off-screen and
    /// their autosaved positions are garbage. The panel's flash-expand relies
    /// on this too — it changes the separator length without going through
    /// expand(), so isCollapsed stays true and can't poison the snapshot.
    private func captureArrangement(reason: String) {
        guard !isCollapsed else { return }
        let count = MenuBarArrangement.captureAndSave()
        NSLog("menubar-hide: arrangement snapshot (\(reason)) holds \(count) positions")
    }

    /// Snapshot once a ⌘-drag rearrangement settles, so it survives even if the
    /// user never collapses again. Read-only: this poller must never collapse.
    private func scheduleArrangementSnapshot() {
        snapshotTask?.cancel()
        snapshotTask = Task { @MainActor [weak self] in
            var fingerprint = Set<String>()
            var stablePolls = 0
            for _ in 0..<30 where stablePolls < 2 { // cap the wait at ~60s
                guard (try? await Task.sleep(for: .seconds(2))) != nil else { return }
                guard let self, !self.isCollapsed, !Task.isCancelled else { return }
                let current = MenuBarItemScanner.statusItemFingerprint()
                if current == fingerprint {
                    stablePolls += 1
                } else {
                    stablePolls = 0
                    fingerprint = current
                }
            }
            self?.captureArrangement(reason: "expanded and stable")
        }
    }

    /// Any collapse/expand supersedes pending automation: a stale
    /// auto-collapse monitor would fire on the NEXT forwarded click's own
    /// synthetic mouseUp, yanking the bar mid-interaction, and the initial
    /// stability poller must not override a manual toggle.
    private func stateWillChange() {
        initialCollapseTask?.cancel()
        initialCollapseTask = nil
        snapshotTask?.cancel()
        snapshotTask = nil
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
                message: String(localized: "Screen Recording permission needed"),
                informative: String(localized: "MenubarHide needs Screen Recording access to show the hidden icons in the panel. Grant it in System Settings, then relaunch MenubarHide (macOS requires a relaunch for this permission)."),
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
                message: String(localized: "Accessibility permission needed"),
                informative: String(localized: "MenubarHide needs Accessibility access to click hidden icons for you. Grant it in System Settings › Privacy & Security › Accessibility, then try again."),
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
        alert.addButton(withTitle: String(localized: "Open System Settings"))
        alert.addButton(withTitle: String(localized: "Cancel"))
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

        let aboutItem = NSMenuItem(title: String(localized: "About MenubarHide"),
                                   action: #selector(openAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(.separator())

        let panelItem = NSMenuItem(title: String(localized: "Show Hidden Icons in Panel"),
                                   action: #selector(togglePanelMode), keyEquivalent: "")
        panelItem.target = self
        panelItem.state = showInPanel ? .on : .off
        menu.addItem(panelItem)

        let loginItem = NSMenuItem(title: String(localized: "Launch at Login"),
                                   action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(arrangementMenuItem())
        menu.addItem(spacingMenuItem())

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Quit MenubarHide"),
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // Assign, click, unassign — keeps left-click free for toggle()
        toggleItem.menu = menu
        toggleItem.button?.performClick(nil)
        toggleItem.menu = nil
    }

    // MARK: - Icon arrangement menu

    private func arrangementMenuItem() -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false // otherwise AppKit re-enables anything whose target responds

        let save = NSMenuItem(title: String(localized: "Save Arrangement Now"),
                              action: #selector(saveArrangement), keyEquivalent: "")
        save.target = self
        // collapsed = the hidden icons are off-screen and their positions are
        // garbage; saving here would remember the damage
        save.isEnabled = !isCollapsed
        save.toolTip = isCollapsed ? String(localized: "Show the hidden icons first, then save.") : nil
        submenu.addItem(save)

        let restore = NSMenuItem(title: String(localized: "Restore Saved Arrangement"),
                                 action: #selector(restoreArrangement), keyEquivalent: "")
        restore.target = self
        restore.isEnabled = MenuBarArrangement.saved() != nil
        submenu.addItem(restore)

        submenu.addItem(.separator())
        let status: String
        if let date = MenuBarArrangement.savedDate() {
            // the date formats itself for the user's locale
            status = String(localized: "Saved \(date.formatted(date: .abbreviated, time: .shortened)) · \(MenuBarArrangement.savedCount()) icons")
        } else {
            status = String(localized: "Nothing saved yet")
        }
        let info = NSMenuItem(title: status, action: nil, keyEquivalent: "")
        info.isEnabled = false
        submenu.addItem(info)

        let item = NSMenuItem(title: String(localized: "Icon Arrangement"), action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    @objc private func saveArrangement() {
        captureArrangement(reason: "manual")
    }

    @objc private func restoreArrangement() {
        guard let snapshot = MenuBarArrangement.saved() else { return }
        let rewritten = MenuBarArrangement.restore(snapshot)
        let alert = NSAlert()
        alert.messageText = rewritten == 0
            ? String(localized: "Every icon is already where you left it")
            : String(localized: "Restored \(rewritten) icon positions")
        // AppKit reads the preferred position when an app creates its status
        // item, so nothing moves until the owning app launches again
        alert.informativeText = String(localized: "Icons of apps that are already running move back on their next launch, or after you log out and back in.")
        alert.addButton(withTitle: String(localized: "OK"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - Menu bar spacing menu

    private func spacingMenuItem() -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let current = MenuBarSpacing.current()

        for preset in MenuBarSpacing.presets {
            let entry = NSMenuItem(title: String(localized: "\(preset) pt"),
                                   action: #selector(spacingPresetChosen(_:)), keyEquivalent: "")
            entry.target = self
            entry.tag = preset
            entry.state = current == preset ? .on : .off
            submenu.addItem(entry)
        }

        let custom = NSMenuItem(title: String(localized: "Custom…"),
                                action: #selector(chooseCustomSpacing), keyEquivalent: "")
        custom.target = self
        custom.state = current.map { !MenuBarSpacing.presets.contains($0) } == true ? .on : .off
        submenu.addItem(custom)

        submenu.addItem(.separator())
        let reset = NSMenuItem(title: String(localized: "Reset to macOS Default"),
                               action: #selector(resetSpacing), keyEquivalent: "")
        reset.target = self
        reset.state = current == nil ? .on : .off
        submenu.addItem(reset)

        let item = NSMenuItem(title: String(localized: "Menu Bar Spacing"), action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    @objc private func spacingPresetChosen(_ sender: NSMenuItem) {
        MenuBarSpacing.apply(sender.tag)
        showSpacingNotice()
    }

    @objc private func chooseCustomSpacing() {
        let range = MenuBarSpacing.allowedRange
        let alert = NSAlert()
        alert.messageText = String(localized: "Custom menu bar spacing")
        alert.informativeText = String(localized: "Space around each menu bar icon, in points (\(range.lowerBound)–\(range.upperBound)). Smaller values fit more icons; the macOS default is around 12.")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 60, height: 24))
        field.stringValue = String(MenuBarSpacing.current() ?? 12)
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Apply"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let value = Int(field.stringValue.trimmingCharacters(in: .whitespaces)),
              range.contains(value) else {
            let error = NSAlert()
            error.messageText = String(localized: "Spacing not changed")
            error.informativeText = String(localized: "Enter a whole number between \(range.lowerBound) and \(range.upperBound).")
            error.addButton(withTitle: String(localized: "OK"))
            error.runModal()
            return
        }
        MenuBarSpacing.apply(value)
        showSpacingNotice()
    }

    @objc private func resetSpacing() {
        MenuBarSpacing.reset()
        showSpacingNotice()
    }

    /// Every app reads the spacing when it builds its status items, so only a
    /// full logout (or restart) rebuilds the whole bar.
    private func showSpacingNotice() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Log out to apply the new spacing")
        alert.informativeText = String(localized: "macOS only picks up the menu bar spacing when apps launch. Log out and back in, or restart your Mac, to see the change.")
        alert.addButton(withTitle: String(localized: "OK"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func openAbout() {
        // LSUIElement: without activating, the About panel opens behind other apps' windows
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSAttributedString(
            string: "github.com/junior-rj/menubar-hide",
            attributes: [
                .link: URL(string: "https://github.com/junior-rj/menubar-hide")!,
                .font: NSFont.systemFont(ofSize: 11),
            ])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
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
