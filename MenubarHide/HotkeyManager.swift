import Carbon.HIToolbox

// Global hotkey ⌃⌥H via Carbon — the only dependency-free API for system-wide
// hotkeys. ⌘⌥H is taken by the system ("Hide Others").
@MainActor
final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private let onToggle: () -> Void

    init(onToggle: @escaping @MainActor () -> Void) {
        self.onToggle = onToggle

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        // passUnretained is safe: the AppDelegate retains this manager for the
        // app's whole lifetime, so no unregister/deinit path is needed.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            // Carbon delivers on the main run loop
            MainActor.assumeIsolated {
                Unmanaged<HotkeyManager>.fromOpaque(userData!).takeUnretainedValue().onToggle()
            }
            return noErr
        }, 1, &eventType, selfPtr, nil)

        let hotKeyID = EventHotKeyID(signature: OSType(0x4D42_4844), id: 1) // 'MBHD'
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_H), UInt32(controlKey | optionKey),
                                         hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr || hotKeyRef == nil {
            NSLog("menubar-hide: hotkey registration failed (status \(status)) — ⌃⌥H may be taken by another app")
        }
    }
}
