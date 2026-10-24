import Carbon
import AppKit
import Foundation

/// Global shortcut actions triggered across macOS.
public enum HotKeyAction: UInt32, CaseIterable, Codable, Sendable {
    case inPlaceCapture = 1
    case scrollingCapture = 2

    public var identifier: String {
        switch self {
        case .inPlaceCapture: return "inPlaceCapture"
        case .scrollingCapture: return "scrollingCapture"
        }
    }
}

/// Abstract representation of a registered global shortcut.
public struct HotKeyShortcut: Equatable, Codable, Sendable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32

    public init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    /// Formats the shortcut for UI display (e.g., "⌥S" or "⌥⇧S").
    public var displayString: String {
        var str = ""
        if (carbonModifiers & UInt32(controlKey)) != 0 { str += "⌃" }
        if (carbonModifiers & UInt32(optionKey)) != 0 { str += "⌥" }
        if (carbonModifiers & UInt32(shiftKey)) != 0 { str += "⇧" }
        if (carbonModifiers & UInt32(cmdKey)) != 0 { str += "⌘" }
        str += keyGlyph(for: keyCode)
        return str
    }

    private func keyGlyph(for code: UInt32) -> String {
        switch Int(code) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        default: return "Key_\(code)"
        }
    }
}

public enum HotKeyModifierConverter {
    /// Converts Carbon modifier bitmask to Cocoa NSEvent.ModifierFlags.
    public static func toCocoaModifiers(_ carbonMods: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if (carbonMods & UInt32(cmdKey)) != 0 { flags.insert(.command) }
        if (carbonMods & UInt32(shiftKey)) != 0 { flags.insert(.shift) }
        if (carbonMods & UInt32(optionKey)) != 0 { flags.insert(.option) }
        if (carbonMods & UInt32(controlKey)) != 0 { flags.insert(.control) }
        return flags
    }

    /// Converts Cocoa NSEvent.ModifierFlags to Carbon modifier bitmask.
    public static func toCarbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbonMods: UInt32 = 0
        if flags.contains(.command) { carbonMods |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbonMods |= UInt32(shiftKey) }
        if flags.contains(.option) { carbonMods |= UInt32(optionKey) }
        if flags.contains(.control) { carbonMods |= UInt32(controlKey) }
        return carbonMods
    }
}

public protocol HotKeyManaging: AnyObject {
    var onAction: ((HotKeyAction) -> Void)? { get set }
    func register(action: HotKeyAction, keyCode: UInt32, modifiers: UInt32) -> Bool
    func unregister(action: HotKeyAction)
    func unregisterAll()
    func registerDefaults()
    func isRegistered(action: HotKeyAction) -> Bool
    func shortcut(for action: HotKeyAction) -> HotKeyShortcut?
}

public final class HotKeyManager: HotKeyManaging, @unchecked Sendable {
    public static let shared = HotKeyManager()
    public static let hotKeyDidChangeNotification = Notification.Name("SuperShotHotKeyDidChangeNotification")

    public var onAction: ((HotKeyAction) -> Void)?

    private let lock = NSRecursiveLock()
    private var hotKeyRefs: [HotKeyAction: EventHotKeyRef] = [:]
    private var registeredShortcuts: [HotKeyAction: HotKeyShortcut] = [:]
    private var handlerRef: EventHandlerRef?

    // Signature 'SSHT' = 0x53534854
    private let signature = OSType(0x53534854)

    public init() {
        installCarbonHandler()
    }

    private func installCarbonHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData, let event = event else { return noErr }
                let mgr = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()

                var hotKeyID = EventHotKeyID()
                let paramStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                if paramStatus == noErr, let action = HotKeyAction(rawValue: hotKeyID.id) {
                    DispatchQueue.main.async {
                        mgr.onAction?(action)
                    }
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &handlerRef
        )

        if status != noErr {
            print("Failed to install Carbon hotkey handler: \(status)")
        }
    }

    @discardableResult
    public func register(action: HotKeyAction, keyCode: UInt32, modifiers: UInt32) -> Bool {
        lock.lock()

        // Unregister existing ref if present
        if let existingRef = hotKeyRefs[action] {
            UnregisterEventHotKey(existingRef)
            hotKeyRefs.removeValue(forKey: action)
            registeredShortcuts.removeValue(forKey: action)
        }

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: action.rawValue)

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr, let ref = hotKeyRef {
            hotKeyRefs[action] = ref
            registeredShortcuts[action] = HotKeyShortcut(keyCode: keyCode, carbonModifiers: modifiers)
            lock.unlock()
            NotificationCenter.default.post(name: HotKeyManager.hotKeyDidChangeNotification, object: self)
            return true
        } else {
            lock.unlock()
            print("Error registering Carbon hotkey for \(action): \(status)")
            return false
        }
    }

    public func unregister(action: HotKeyAction) {
        lock.lock()
        if let ref = hotKeyRefs.removeValue(forKey: action) {
            UnregisterEventHotKey(ref)
        }
        registeredShortcuts.removeValue(forKey: action)
        lock.unlock()
        NotificationCenter.default.post(name: HotKeyManager.hotKeyDidChangeNotification, object: self)
    }

    public func unregisterAll() {
        lock.lock()
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        registeredShortcuts.removeAll()
        lock.unlock()
        NotificationCenter.default.post(name: HotKeyManager.hotKeyDidChangeNotification, object: self)
    }

    public func registerDefaults() {
        // 1. In-place screen capture: Option + S
        register(
            action: .inPlaceCapture,
            keyCode: UInt32(kVK_ANSI_S),
            modifiers: UInt32(optionKey)
        )

        // 2. Scrolling screenshot: Option + Shift + S
        register(
            action: .scrollingCapture,
            keyCode: UInt32(kVK_ANSI_S),
            modifiers: UInt32(optionKey | shiftKey)
        )
    }

    public func isRegistered(action: HotKeyAction) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return hotKeyRefs[action] != nil
    }

    public func shortcut(for action: HotKeyAction) -> HotKeyShortcut? {
        lock.lock()
        defer { lock.unlock() }
        return registeredShortcuts[action]
    }

    deinit {
        unregisterAll()
        if let hRef = handlerRef {
            RemoveEventHandler(hRef)
        }
    }
}
