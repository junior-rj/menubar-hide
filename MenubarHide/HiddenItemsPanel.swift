import SwiftUI

// Floating panel just below the menu bar showing screenshots of the hidden
// items (Ice Bar technique) — solves the notch swallowing icons on expand.
@MainActor
final class HiddenItemsPanel {
    private var panel: NSPanel?
    private var monitors: [Any] = []

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(items: [CapturedItem], below anchorFrame: NSRect,
              onClick: @escaping @MainActor (CapturedItem) -> Void) {
        close()

        let hosting = NSHostingView(rootView: PanelContentView(items: items) { [weak self] item in
            self?.close()
            onClick(item)
        })
        hosting.setFrameSize(hosting.fittingSize)

        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: hosting.frame.size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.contentView = hosting
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.isReleasedWhenClosed = false

        let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        let x = max(screen.minX + 4,
                    min(anchorFrame.maxX - panel.frame.width, screen.maxX - panel.frame.width - 4))
        panel.setFrameOrigin(NSPoint(x: x, y: anchorFrame.minY - panel.frame.height - 6))
        panel.orderFrontRegardless()
        self.panel = panel

        // dismiss on click outside or Esc
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown],
                                                           handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            if event.keyCode == 53 { self?.close(); return nil } // Esc
            return event
        }) {
            monitors.append(monitor)
        }
    }

    func close() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct PanelContentView: View {
    let items: [CapturedItem]
    let onClick: (CapturedItem) -> Void

    var body: some View {
        HStack(spacing: 2) {
            if items.isEmpty {
                Text("No hidden icons")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            }
            ForEach(items) { item in
                Button {
                    onClick(item)
                } label: {
                    Image(nsImage: item.image)
                }
                .buttonStyle(.plain)
                .help(item.window.ownerName)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
