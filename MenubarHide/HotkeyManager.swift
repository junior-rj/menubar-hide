import Carbon.HIToolbox

// Global hotkey ⌃⌥H via Carbon — the only dependency-free API for system-wide
// hotkeys. ⌘⌥H is taken by the system ("Hide Others").
@MainActor
final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onToggle: () -> Void
    /// False when either Carbon call failed; the menu tells the user ⌃⌥H is taken.
    private(set) var isRegistered = false

    init(onToggle: @escaping @MainActor () -> Void) {
        self.onToggle = onToggle

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        // passUnretained is safe: the handler is torn down in deinit, so the
        // callback can never outlive the instance it dereferences.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            // Carbon delivers on the main run loop
            MainActor.assumeIsolated {
                Unmanaged<HotkeyManager>.fromOpaque(userData!).takeUnretainedValue().onToggle()
            }
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)
        guard handlerStatus == noErr, handlerRef != nil else {
            // registering the key with nobody listening would look like a
            // working hotkey that never fires
            NSLog("menubar-hide: hotkey handler installation failed (status \(handlerStatus))")
            return
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4D42_4844), id: 1) // 'MBHD'
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_H), UInt32(controlKey | optionKey),
                                         hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr || hotKeyRef == nil {
            NSLog("menubar-hide: hotkey registration failed (status \(status)) — ⌃⌥H may be taken by another app")
            return
        }
        isRegistered = true
    }

    // The AppDelegate keeps this alive for the whole process, so this is a
    // safety net rather than a fix — but an unbalanced Carbon registration is
    // exactly the kind of thing that bites once the ownership ever changes.
    // `isolated deinit` links its runtime hook weakly below macOS 15.4, where
    // it degrades to a plain deinit on whatever thread releases the object;
    // harmless as long as the object lives for the whole process.
    isolated deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
