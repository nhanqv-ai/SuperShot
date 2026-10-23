import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import UniformTypeIdentifiers
import SuperShotCore

// MARK: - PasteSimulating Protocol

public protocol PasteSimulating: AnyObject, Sendable {
    func activate(app: NSRunningApplication) -> Bool
    func postPasteKeyEvent() -> Bool
    func postPasteKeyEvent(tap: CGEventTapLocation) -> Bool
    func pasteToActiveApp(targetApp: NSRunningApplication?, delay: TimeInterval, completion: (() -> Void)?)
}

extension PasteSimulating {
    public func postPasteKeyEvent() -> Bool {
        return postPasteKeyEvent(tap: .cghidEventTap)
    }

    public func pasteToActiveApp(targetApp: NSRunningApplication?) {
        pasteToActiveApp(targetApp: targetApp, delay: 0.035, completion: nil)
    }
}

// MARK: - PasteSimulator Implementation

public final class PasteSimulator: PasteSimulating, @unchecked Sendable {
    public static let shared = PasteSimulator()
    public var defaultEventTap: CGEventTapLocation = .cghidEventTap

    public init() {}

    @discardableResult
    public func activate(app: NSRunningApplication) -> Bool {
        guard !app.isTerminated else { return false }
        return app.activate(options: [.activateIgnoringOtherApps])
    }

    @discardableResult
    public func postPasteKeyEvent(tap: CGEventTapLocation) -> Bool {
        let vKeyCode: CGKeyCode = 0x09 // kVK_ANSI_V
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true) else {
            return false
        }
        keyDown.flags = .maskCommand

        guard let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false) else {
            return false
        }
        keyUp.flags = .maskCommand

        keyDown.post(tap: tap)
        keyUp.post(tap: tap)
        return true
    }

    public func pasteToActiveApp(
        targetApp: NSRunningApplication?,
        delay: TimeInterval = 0.035,
        completion: (() -> Void)? = nil
    ) {
        if let app = targetApp {
            _ = activate(app: app)
        }
        let delaySeconds = max(0, delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds) { [weak self] in
            guard let self = self else {
                completion?()
                return
            }
            _ = self.postPasteKeyEvent(tap: self.defaultEventTap)
            completion?()
        }
    }
}

// MARK: - AutoPasteServicing Protocol

public protocol AutoPasteServicing: AnyObject, Sendable {
    var isAccessibilityTrusted: Bool { get }
    func checkAccessibilityPermission() -> Bool
    func requestAccessibilityPermission() -> Bool
    @discardableResult
    func resetAccessibilityPermission() -> Bool
    @discardableResult
    func resetAndRequestAccessibilityPermission() -> Bool
    func openAccessibilitySettings()
    @discardableResult
    func pasteToActiveApp(
        targetApp: NSRunningApplication?,
        delay: TimeInterval,
        promptIfUntrusted: Bool,
        completion: (() -> Void)?
    ) -> Bool
    @discardableResult
    func pasteImageDirectly(
        _ image: CGImage,
        targetApp: NSRunningApplication?,
        delay: TimeInterval,
        completion: (() -> Void)?
    ) async -> Bool
}

extension AutoPasteServicing {
    @discardableResult
    public func pasteToActiveApp(
        targetApp: NSRunningApplication?,
        delay: TimeInterval = 0.035
    ) -> Bool {
        return pasteToActiveApp(targetApp: targetApp, delay: delay, promptIfUntrusted: false, completion: nil)
    }

    @discardableResult
    public func pasteImageDirectly(
        _ image: CGImage,
        targetApp: NSRunningApplication? = nil
    ) async -> Bool {
        return await pasteImageDirectly(image, targetApp: targetApp, delay: 0.035, completion: nil)
    }
}

// MARK: - AutoPasteService Implementation

public final class AutoPasteService: AutoPasteServicing, @unchecked Sendable {
    public static let shared = AutoPasteService()

    public var pasteSimulator: any PasteSimulating
    public var accessibilityChecker: @Sendable () -> Bool
    public var accessibilityPrompter: @Sendable () -> Bool
    public var accessibilityResetter: @Sendable () -> Bool
    public var settingsOpener: @Sendable () -> Void
    public var dispatchQueue: DispatchQueue

    public init(
        pasteSimulator: any PasteSimulating = PasteSimulator.shared,
        accessibilityChecker: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() },
        accessibilityPrompter: @escaping @Sendable () -> Bool = {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        },
        accessibilityResetter: @escaping @Sendable () -> Bool = {
            let bundleId = Bundle.main.bundleIdentifier ?? "com.supershot.SuperShot"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", "Accessibility", bundleId]
            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus == 0
            } catch {
                return false
            }
        },
        settingsOpener: @escaping @Sendable () -> Void = {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),
               NSWorkspace.shared.open(url) {
                return
            }
            if let fallbackURL = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                NSWorkspace.shared.open(fallbackURL)
            }
        },
        dispatchQueue: DispatchQueue = .main
    ) {
        self.pasteSimulator = pasteSimulator
        self.accessibilityChecker = accessibilityChecker
        self.accessibilityPrompter = accessibilityPrompter
        self.accessibilityResetter = accessibilityResetter
        self.settingsOpener = settingsOpener
        self.dispatchQueue = dispatchQueue
    }

    public var isAccessibilityTrusted: Bool {
        return accessibilityChecker()
    }

    public func checkAccessibilityPermission() -> Bool {
        return accessibilityChecker()
    }

    public func requestAccessibilityPermission() -> Bool {
        return accessibilityPrompter()
    }

    @discardableResult
    public func resetAccessibilityPermission() -> Bool {
        return accessibilityResetter()
    }

    @discardableResult
    public func resetAndRequestAccessibilityPermission() -> Bool {
        _ = resetAccessibilityPermission()
        openAccessibilitySettings()
        return requestAccessibilityPermission()
    }

    public func openAccessibilitySettings() {
        settingsOpener()
    }

    @discardableResult
    public func pasteToActiveApp(
        targetApp: NSRunningApplication?,
        delay: TimeInterval = 0.035,
        promptIfUntrusted: Bool = false,
        completion: (() -> Void)? = nil
    ) -> Bool {
        if let app = targetApp, !app.isTerminated {
            _ = pasteSimulator.activate(app: app)
        }

        guard isAccessibilityTrusted else {
            if promptIfUntrusted {
                _ = requestAccessibilityPermission()
            }
            completion?()
            return false
        }

        if delay <= 0 {
            _ = self.pasteSimulator.postPasteKeyEvent()
            completion?()
        } else {
            let delaySeconds = max(0, delay)
            dispatchQueue.asyncAfter(deadline: .now() + delaySeconds) { [weak self] in
                guard let self = self else {
                    completion?()
                    return
                }
                _ = self.pasteSimulator.postPasteKeyEvent()
                completion?()
            }
        }

        return true
    }

    @discardableResult
    public func pasteImageDirectly(
        _ image: CGImage,
        targetApp: NSRunningApplication? = nil,
        delay: TimeInterval = 0.035,
        completion: (() -> Void)? = nil
    ) async -> Bool {
        // Copy image to system pasteboard first
        let pb = NSPasteboard.general
        pb.clearContents()
        let rep = NSBitmapImageRep(cgImage: image)
        if let pngData = rep.representation(using: .png, properties: [:]) {
            pb.declareTypes([.png, .tiff], owner: nil)
            pb.setData(pngData, forType: .png)
            if let nsImg = NSImage(data: pngData), let tiff = nsImg.tiffRepresentation {
                pb.setData(tiff, forType: .tiff)
            }
        }

        return pasteToActiveApp(
            targetApp: targetApp,
            delay: delay,
            promptIfUntrusted: false,
            completion: completion
        )
    }
}
