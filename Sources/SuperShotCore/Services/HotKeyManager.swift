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
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_X: return "X"
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
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

    public var onAction: ((HotKeyAction) -> Void)?

    private let lock = NSLock()
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
        defer { lock.unlock() }

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
            return true
        } else {
            print("Error registering Carbon hotkey for \(action): \(status)")
            return false
        }
    }

    public func unregister(action: HotKeyAction) {
        lock.lock()
        defer { lock.unlock() }

        if let ref = hotKeyRefs.removeValue(forKey: action) {
            UnregisterEventHotKey(ref)
        }
        registeredShortcuts.removeValue(forKey: action)
    }

    public func unregisterAll() {
        lock.lock()
        defer { lock.unlock() }

        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        registeredShortcuts.removeAll()
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
