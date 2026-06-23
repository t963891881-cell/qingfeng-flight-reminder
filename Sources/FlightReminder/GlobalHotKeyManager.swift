import AppKit
import Carbon.HIToolbox
import Foundation

private let testFlightHotKeySignature: OSType = 0x5146_524D // QFRM

private func testFlightHotKeyHandler(
    _: EventHandlerCallRef?,
    _: EventRef?,
    _: UnsafeMutableRawPointer?
) -> OSStatus {
    Task { @MainActor in
        ReminderMonitor.shared.testFlight()
    }
    return noErr
}

@MainActor
final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?

    private init() {}

    func prepare() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            testFlightHotKeyHandler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
    }

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32) -> OSStatus {
        prepare()
        unregister()

        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: testFlightHotKeySignature, id: 1)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if status == noErr {
            hotKeyRef = reference
        }
        return status
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    func stop() {
        unregister()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}

@MainActor
final class ShortcutSettings: ObservableObject {
    static let shared = ShortcutSettings()

    @Published private(set) var displayText = "设置"
    @Published private(set) var isRecording = false
    @Published private(set) var errorMessage: String?

    private enum Key {
        static let enabled = "testFlightShortcutEnabled"
        static let keyCode = "testFlightShortcutKeyCode"
        static let modifiers = "testFlightShortcutModifiers"
        static let display = "testFlightShortcutDisplay"
    }

    private var localMonitor: Any?
    private var isQAPreview = false

    private init() {
        reloadDisplay()
    }

    func activate() {
        guard !isQAPreview else { return }
        GlobalHotKeyManager.shared.prepare()
        guard UserDefaults.standard.bool(forKey: Key.enabled) else { return }
        let keyCode = UInt32(UserDefaults.standard.integer(forKey: Key.keyCode))
        let modifiers = UInt32(UserDefaults.standard.integer(forKey: Key.modifiers))
        let status = GlobalHotKeyManager.shared.register(keyCode: keyCode, modifiers: modifiers)
        if status != noErr {
            errorMessage = "快捷键注册失败，请重新设置。"
        }
    }

    func startRecording() {
        if isRecording {
            cancelRecording()
            return
        }

        errorMessage = nil
        isRecording = true
        displayText = "按下快捷键…"
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.capture(event)
            }
            return nil
        }
    }

    func cancelRecording() {
        removeLocalMonitor()
        isRecording = false
        reloadDisplay()
    }

    func prepareQAPreview() {
        isQAPreview = true
        displayText = "⌥⌘F"
        errorMessage = nil
    }

    private func capture(_ event: NSEvent) {
        if event.keyCode == 53 { // Escape
            cancelRecording()
            return
        }
        if event.keyCode == 51 || event.keyCode == 117 { // Delete
            clearShortcut()
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let carbonModifiers = Self.carbonModifiers(from: flags)
        let requiredFlags: NSEvent.ModifierFlags = [.command, .option, .control]
        guard !flags.intersection(requiredFlags).isEmpty else {
            errorMessage = "请至少搭配 ⌘、⌥ 或 ⌃。"
            return
        }

        let keyName = Self.keyName(for: event)
        guard !keyName.isEmpty else {
            errorMessage = "这个按键暂不支持。"
            return
        }

        let display = Self.displayString(flags: flags, keyName: keyName)
        let oldEnabled = UserDefaults.standard.bool(forKey: Key.enabled)
        let oldKeyCode = UInt32(UserDefaults.standard.integer(forKey: Key.keyCode))
        let oldModifiers = UInt32(UserDefaults.standard.integer(forKey: Key.modifiers))

        let status = GlobalHotKeyManager.shared.register(
            keyCode: UInt32(event.keyCode),
            modifiers: carbonModifiers
        )
        guard status == noErr else {
            if oldEnabled {
                GlobalHotKeyManager.shared.register(keyCode: oldKeyCode, modifiers: oldModifiers)
            }
            errorMessage = "快捷键已被其他应用占用。"
            cancelRecording()
            return
        }

        let defaults = UserDefaults.standard
        defaults.set(true, forKey: Key.enabled)
        defaults.set(Int(event.keyCode), forKey: Key.keyCode)
        defaults.set(Int(carbonModifiers), forKey: Key.modifiers)
        defaults.set(display, forKey: Key.display)

        removeLocalMonitor()
        isRecording = false
        displayText = display
        errorMessage = nil
    }

    private func clearShortcut() {
        GlobalHotKeyManager.shared.unregister()
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: Key.enabled)
        defaults.removeObject(forKey: Key.keyCode)
        defaults.removeObject(forKey: Key.modifiers)
        defaults.removeObject(forKey: Key.display)
        removeLocalMonitor()
        isRecording = false
        displayText = "设置"
        errorMessage = nil
    }

    private func reloadDisplay() {
        displayText = UserDefaults.standard.bool(forKey: Key.enabled)
            ? UserDefaults.standard.string(forKey: Key.display) ?? "设置"
            : "设置"
    }

    private func removeLocalMonitor() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }

    private static func displayString(flags: NSEvent.ModifierFlags, keyName: String) -> String {
        var result = ""
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        return result + keyName
    }

    private static func keyName(for event: NSEvent) -> String {
        let specialKeys: [UInt16: String] = [
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "Esc",
            115: "Home", 116: "⇞", 117: "⌦", 119: "End", 121: "⇟",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
        ]
        if let special = specialKeys[event.keyCode] { return special }
        return event.charactersIgnoringModifiers?.uppercased() ?? ""
    }
}
