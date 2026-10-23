import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - PermissionManaging Protocol

public protocol PermissionManaging: AnyObject, Sendable {
    var isScreenRecordingGranted: Bool { get }
    var isAccessibilityGranted: Bool { get }
    func checkScreenRecording() -> Bool
    func requestScreenRecording() -> Bool
    func openScreenRecordingSettings()
    func checkAccessibility() -> Bool
    func requestAccessibility() -> Bool
    @discardableResult
    func resetAccessibility() -> Bool
    func openAccessibilitySettings()
}

// MARK: - PermissionManager Implementation

public final class PermissionManager: PermissionManaging, @unchecked Sendable {
    public static let shared = PermissionManager()

    public init() {}

    public var isScreenRecordingGranted: Bool {
        return CGPreflightScreenCaptureAccess()
    }

    public var isAccessibilityGranted: Bool {
        return AXIsProcessTrusted()
    }

    public func checkScreenRecording() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }

    public func requestScreenRecording() -> Bool {
        return CGRequestScreenCaptureAccess()
    }

    public func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    public func checkAccessibility() -> Bool {
        return AXIsProcessTrusted()
    }

    public func requestAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    public func resetAccessibility() -> Bool {
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
    }

    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
