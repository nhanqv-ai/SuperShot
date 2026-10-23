import Foundation
import CoreGraphics
import AppKit
import SuperShotCore
import SuperShot

/// Mock PasteSimulator recording simulated synthetic key events.
public final class MockPasteSimulator: PasteSimulating, @unchecked Sendable {
    public var postKeyEventCallCount: Int = 0
    public var activateAppCallCount: Int = 0
    public var shouldSucceed: Bool = true

    public init() {}

    public func activate(app: NSRunningApplication) -> Bool {
        activateAppCallCount += 1
        return shouldSucceed
    }

    public func postPasteKeyEvent() -> Bool {
        postKeyEventCallCount += 1
        return shouldSucceed
    }

    public func postPasteKeyEvent(tap: CGEventTapLocation) -> Bool {
        postKeyEventCallCount += 1
        return shouldSucceed
    }

    public func pasteToActiveApp(targetApp: NSRunningApplication?, delay: TimeInterval, completion: (() -> Void)?) {
        if let app = targetApp {
            _ = activate(app: app)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            _ = self?.postPasteKeyEvent()
            completion?()
        }
    }
}

public struct AutoPasteTests {
    public static func run() {
        TestHarness.startSuite("AutoPasteService & Synthetic Key Injection Tests")

        let mockSim = MockPasteSimulator()
        var mockAccessibilityTrusted = true
        var promptTriggered = false

        let service = AutoPasteService(
            pasteSimulator: mockSim,
            accessibilityChecker: { mockAccessibilityTrusted },
            accessibilityPrompter: {
                promptTriggered = true
                return true
            },
            accessibilityResetter: { true },
            settingsOpener: {}
        )

        // 1. Accessibility Status
        TestHarness.assertTrue(service.isAccessibilityTrusted, "Accessibility is trusted")
        TestHarness.assertTrue(service.checkAccessibilityPermission(), "checkAccessibilityPermission returns true")

        // 2. Successful Auto-Paste when Trusted
        let syncSuccess = service.pasteToActiveApp(targetApp: nil, delay: 0.0)
        TestHarness.assertTrue(syncSuccess, "pasteToActiveApp returns true when accessibility trusted")

        // Allow micro dispatch queue tick
        let exp = DispatchSemaphore(value: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            exp.signal()
        }
        _ = exp.wait(timeout: .now() + 1.0)
        TestHarness.assertTrue(mockSim.postKeyEventCallCount >= 1, "Synthetic Cmd+V event posted to system tap")

        // 3. Graceful Fallback when Untrusted
        mockAccessibilityTrusted = false
        mockSim.postKeyEventCallCount = 0

        let untrustedResult = service.pasteToActiveApp(targetApp: nil, delay: 0.0, promptIfUntrusted: false)
        TestHarness.assertFalse(untrustedResult, "pasteToActiveApp returns false when accessibility untrusted")
        TestHarness.assertEqual(mockSim.postKeyEventCallCount, 0, "No synthetic keys posted when untrusted")

        // 4. Prompt Triggering when promptIfUntrusted is True
        promptTriggered = false
        _ = service.pasteToActiveApp(targetApp: nil, delay: 0.0, promptIfUntrusted: true)
        TestHarness.assertTrue(promptTriggered, "System accessibility prompt triggered when untrusted and requested")

        // 5. PreviousAppTracker State Sanity
        let tracker = PreviousAppTracker.shared
        tracker.clear()
        TestHarness.assertNil(tracker.previousApp, "PreviousAppTracker cleared")
    }
}
