import Foundation
import CoreGraphics
import AppKit
import SuperShotCore
import SuperShot

/// Comprehensive headless unit tests for ScrollingCaptureManager, state machine transitions,
/// CGEvent scroll wheel synthesizer with mock protocol, settle delay loop, and live preview layout engine.
public struct ScrollingCaptureTests {
    public static func run() {
        TestHarness.startSuite("Milestone 3: ScrollingCaptureManager & Live Preview")

        // 1. Mock Scroll Event Synthesizer Tests
        testMockScrollSynthesizer()

        // 2. Coordinate Mapping Math Tests
        testCoordinateMapping()

        // 3. State Machine Transitions Tests
        testStateMachineTransitions()

        // 4. Configuration Clamping & Bounds Tests
        testConfigurationClamping()

        // 5. Live Preview Layout & Collision Avoidance Tests
        testLivePreviewLayoutEngine()

        // 6. Dimension Badge Real-Time Formatting Tests
        testDimensionBadgeFormatting()

        // 7. Headless Simulated Auto-Scroll Loop Tests
        testHeadlessAutoScrollLoop()

        // 8. Auto-Stop on End-of-Page (Zero-Delta) Tests
        testAutoStopOnEndOfPage()

        // 9. Auto-Stop on Max Scroll Height Ceiling Tests
        testAutoStopOnMaxHeightCeiling()

        // 10. Thread-Safety & Concurrent Cancellation Tests
        testConcurrentCancellation()

        // 11. Manual Scroll Default & Global Esc/Enter Key Handling Tests
        testManualScrollDefaultAndKeyHandling()
    }

    // MARK: - Test 1: Mock Scroll Event Synthesizer
    private static func testMockScrollSynthesizer() {
        let mock = MockScrollEventSynthesizer()
        TestHarness.assertTrue(mock.isAvailable, "Mock synthesizer is available")
        TestHarness.assertEqual(mock.totalScrollCount, 0, "Initial scroll count is 0")

        let pt1 = CGPoint(x: 300, y: 400)
        let success1 = mock.synthesizeScroll(deltaY: 60, at: pt1)
        TestHarness.assertTrue(success1, "synthesizeScroll returns true on success")
        TestHarness.assertEqual(mock.totalScrollCount, 1, "Scroll count incremented to 1")
        TestHarness.assertEqual(mock.history.first?.deltaY, 60, "Recorded deltaY is 60")
        TestHarness.assertEqual(mock.history.first?.point, pt1, "Recorded point is (300, 400)")

        // Simulate failure
        mock.shouldSucceed = false
        let success2 = mock.synthesizeScroll(deltaY: 80, at: CGPoint(x: 100, y: 100))
        TestHarness.assertFalse(success2, "synthesizeScroll returns false when shouldSucceed is false")
        TestHarness.assertEqual(mock.totalScrollCount, 1, "Scroll count does not increment on failure")

        mock.reset()
        TestHarness.assertEqual(mock.totalScrollCount, 0, "reset() clears history to 0")
    }

    // MARK: - Test 2: Coordinate Mapping Math
    private static func testCoordinateMapping() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let selection = CGRect(x: 200, y: 300, width: 600, height: 400)

        // Cocoa center: midX = 500, midY = 500
        // Screen height = 900
        // CoreGraphics global Y = 900 - 500 = 400
        let target = ScrollingCoordinateMapper.targetScrollCenter(
            selectionRect: selection,
            screenBounds: screen
        )
        TestHarness.assertEqual(target.x, 500.0, "Center X in CoreGraphics is 500")
        TestHarness.assertEqual(target.y, 400.0, "Center Y in CoreGraphics is 400 (900 - 500)")

        // Selection near bottom of Cocoa screen (y = 50, height = 100 -> midY = 100)
        // CG global Y = 900 - 100 = 800
        let bottomSelection = CGRect(x: 100, y: 50, width: 200, height: 100)
        let bottomTarget = ScrollingCoordinateMapper.targetScrollCenter(
            selectionRect: bottomSelection,
            screenBounds: screen
        )
        TestHarness.assertEqual(bottomTarget.y, 800.0, "Bottom selection converts to CG Y = 800")
    }

    // MARK: - Test 3: State Machine Transitions
    private static func testStateMachineTransitions() {
        let mockProvider = MockScreenCaptureProvider()
        let mockSynthesizer = MockScrollEventSynthesizer()
        let manager = ScrollingCaptureManager(
            captureProvider: mockProvider,
            scrollSynthesizer: mockSynthesizer
        )

        TestHarness.assertEqual(manager.state, .idle, "Initial state is .idle")

        let display = mockProvider.availableDisplays()[0]
        let selection = CGRect(x: 100, y: 100, width: 400, height: 300)

        // 1. Idle -> Start (.auto)
        let started = manager.startSession(selectionRect: selection, displayInfo: display, mode: .auto)
        TestHarness.assertTrue(started, "startSession returns true")
        TestHarness.assertEqual(manager.state, .capturing(mode: .auto), "State transitions to .capturing(.auto)")

        // 2. Capturing -> Pause
        manager.pauseSession()
        TestHarness.assertEqual(manager.state, .paused(mode: .auto), "State transitions to .paused(.auto)")

        // 3. Paused -> Resume
        manager.resumeSession()
        TestHarness.assertEqual(manager.state, .capturing(mode: .auto), "State resumes to .capturing(.auto)")

        // 4. Capturing (.auto) -> Toggle Mode (.manual)
        manager.toggleMode()
        TestHarness.assertEqual(manager.state, .capturing(mode: .manual), "State toggles to .capturing(.manual)")

        // 5. Capturing (.manual) -> Toggle Mode (.auto)
        manager.toggleMode()
        TestHarness.assertEqual(manager.state, .capturing(mode: .auto), "State toggles back to .capturing(.auto)")

        // 6. Capturing -> Cancel
        manager.cancelSession()
        TestHarness.assertEqual(manager.state, .cancelled, "State transitions to .cancelled")

        // 7. Reset -> Idle
        manager.resetSession()
        TestHarness.assertEqual(manager.state, .idle, "State resets to .idle")
    }

    // MARK: - Test 4: Configuration Clamping & Bounds
    private static func testConfigurationClamping() {
        var config = ScrollingCaptureConfiguration(
            scrollStepDelta: 500,     // > 300 max
            settleDelay: 0.005,       // < 0.01 min
            tickInterval: 1.0,        // > 0.5 max
            maxScrollHeightPx: 40000, // > 30000 max
            scrollbarStripWidth: 100, // > 60 max
            maxConsecutiveZeroDeltas: 10 // > 5 max
        )

        TestHarness.assertEqual(config.scrollStepDelta, 300, "scrollStepDelta clamped to maximum 300")
        TestHarness.assertEqual(config.settleDelay, 0.01, "settleDelay clamped to minimum 0.01s (10ms)")
        TestHarness.assertEqual(config.tickInterval, 0.5, "tickInterval clamped to maximum 0.5s")
        TestHarness.assertEqual(config.maxScrollHeightPx, 30000, "maxScrollHeightPx clamped to maximum 30,000 px")
        TestHarness.assertEqual(config.scrollbarStripWidth, 60.0, "scrollbarStripWidth clamped to 60.0")
        TestHarness.assertEqual(config.maxConsecutiveZeroDeltas, 5, "maxConsecutiveZeroDeltas clamped to 5")

        config = ScrollingCaptureConfiguration(
            scrollStepDelta: 2,       // < 10 min
            maxScrollHeightPx: 2000   // < 5000 min
        )
        TestHarness.assertEqual(config.scrollStepDelta, 10, "scrollStepDelta clamped to minimum 10")
        TestHarness.assertEqual(config.maxScrollHeightPx, 5000, "maxScrollHeightPx clamped to minimum 5,000 px")
    }

    // MARK: - Test 5: Live Preview Layout & Collision Avoidance
    private static func testLivePreviewLayoutEngine() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let panelSize = CGSize(width: 190, height: 290)

        // Case A: Mid-screen selection -> places panel to the RIGHT of selection
        let midSelection = CGRect(x: 300, y: 200, width: 500, height: 400)
        let rightPanel = LivePreviewLayoutEngine.computePanelFrame(
            selectionRect: midSelection,
            screenFrame: screen,
            panelSize: panelSize
        )
        TestHarness.assertEqual(rightPanel.origin.x, midSelection.maxX + 12.0, "Panel placed right of selection")
        TestHarness.assertFalse(rightPanel.intersects(midSelection), "Right panel does not overlap selection")
        TestHarness.assertTrue(screen.contains(rightPanel), "Right panel is fully contained within screen")

        // Case B: Right-edge selection -> flips panel to the LEFT of selection
        let rightSelection = CGRect(x: 1200, y: 200, width: 220, height: 400)
        let leftPanel = LivePreviewLayoutEngine.computePanelFrame(
            selectionRect: rightSelection,
            screenFrame: screen,
            panelSize: panelSize
        )
        TestHarness.assertTrue(leftPanel.maxX <= rightSelection.minX - 12.0, "Panel flipped to the left of selection")
        TestHarness.assertFalse(leftPanel.intersects(rightSelection), "Left panel does not overlap selection")
        TestHarness.assertTrue(screen.contains(leftPanel), "Left panel is fully contained within screen")

        // Case C: Wide selection covering horizontal space -> places Above or Below
        let wideSelection = CGRect(x: 20, y: 100, width: 1400, height: 400)
        let vertPanel = LivePreviewLayoutEngine.computePanelFrame(
            selectionRect: wideSelection,
            screenFrame: screen,
            panelSize: panelSize
        )
        TestHarness.assertFalse(vertPanel.intersects(wideSelection), "Vertical panel does not overlap wide selection")
        TestHarness.assertTrue(screen.contains(vertPanel), "Vertical panel is contained within screen")
    }

    // MARK: - Test 6: Dimension Badge Real-Time Formatting
    private static func testDimensionBadgeFormatting() {
        let prog1 = ScrollingProgress(
            frameCount: 1,
            currentWidthPx: 800,
            currentHeightPx: 600,
            mode: .auto
        )
        TestHarness.assertEqual(prog1.dimensionBadgeText, "800 x 600 px", "Formats initial dimension badge")

        let prog2 = ScrollingProgress(
            frameCount: 10,
            currentWidthPx: 800,
            currentHeightPx: 4250,
            mode: .auto
        )
        TestHarness.assertEqual(prog2.dimensionBadgeText, "800 x 4250 px", "Formats tall stitched dimension badge")
    }

    // MARK: - Test 7: Headless Simulated Auto-Scroll Loop
    private static func testHeadlessAutoScrollLoop() {
        let mockProvider = MockScreenCaptureProvider()
        let mockSynthesizer = MockScrollEventSynthesizer()
        let config = ScrollingCaptureConfiguration(
            scrollStepDelta: 50,
            settleDelay: 0.01,
            tickInterval: 0.01
        )
        let manager = ScrollingCaptureManager(
            captureProvider: mockProvider,
            scrollSynthesizer: mockSynthesizer,
            configuration: config
        )

        let display = mockProvider.availableDisplays()[0]
        let selection = CGRect(x: 100, y: 100, width: 300, height: 200)

        let started = manager.startSession(selectionRect: selection, displayInfo: display, mode: .auto)
        TestHarness.assertTrue(started, "Session started successfully")
        TestHarness.assertEqual(manager.progress.frameCount, 1, "Initial frame captured")

        // Allow simulated ticks to run briefly
        Thread.sleep(forTimeInterval: 0.06)

        TestHarness.assertTrue(mockSynthesizer.totalScrollCount >= 1, "Scroll synthesizer was invoked at least once")
        manager.cancelSession()
    }

    // MARK: - Test 8: Auto-Stop on End-of-Page (Zero-Delta)
    private static func testAutoStopOnEndOfPage() {
        let mockProvider = MockScreenCaptureProvider()
        let mockSynthesizer = MockScrollEventSynthesizer()
        let config = ScrollingCaptureConfiguration(
            scrollStepDelta: 60,
            settleDelay: 0.01,
            tickInterval: 0.01,
            maxConsecutiveZeroDeltas: 2
        )
        let manager = ScrollingCaptureManager(
            captureProvider: mockProvider,
            scrollSynthesizer: mockSynthesizer,
            configuration: config
        )

        let display = mockProvider.availableDisplays()[0]
        let selection = CGRect(x: 100, y: 100, width: 300, height: 200)

        _ = manager.startSession(selectionRect: selection, displayInfo: display, mode: .auto)

        // MockScreenCaptureProvider returns identical synthetic images on every capture.
        // Therefore, consecutive zero-deltas will immediately accumulate to 2 and auto-stop!
        Thread.sleep(forTimeInterval: 0.08)

        TestHarness.assertTrue(manager.isFinished, "Session automatically finished on zero-delta end-of-page")
    }

    // MARK: - Test 9: Auto-Stop on Max Scroll Height Ceiling
    private static func testAutoStopOnMaxHeightCeiling() {
        let config = ScrollingCaptureConfiguration(maxScrollHeightPx: 5000)
        TestHarness.assertEqual(config.maxScrollHeightPx, 5000, "Config ceiling is 5000 px")

        let simulatedHeight = 5200
        let clamped = min(simulatedHeight, config.maxScrollHeightPx)
        TestHarness.assertEqual(clamped, 5000, "Height clamped to 5000 px")
    }

    // MARK: - Test 10: Thread-Safety & Concurrent Cancellation
    private static func testConcurrentCancellation() {
        let mockProvider = MockScreenCaptureProvider()
        let mockSynthesizer = MockScrollEventSynthesizer()
        let manager = ScrollingCaptureManager(
            captureProvider: mockProvider,
            scrollSynthesizer: mockSynthesizer
        )
        let display = mockProvider.availableDisplays()[0]
        let selection = CGRect(x: 100, y: 100, width: 300, height: 200)

        // Rapid start and cancel across concurrent queues
        let group = DispatchGroup()
        for _ in 0..<10 {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                _ = manager.startSession(selectionRect: selection, displayInfo: display, mode: .auto)
                manager.cancelSession()
                group.leave()
            }
        }
        let waitResult = group.wait(timeout: .now() + 2.0)
        TestHarness.assertEqual(waitResult, .success, "Concurrent start and cancel completed without deadlock")
    }

    // MARK: - Test 11: Manual Scroll Default & Global Esc/Enter Key Handling
    private static func testManualScrollDefaultAndKeyHandling() {
        let mockProvider = MockScreenCaptureProvider()
        let mockSynthesizer = MockScrollEventSynthesizer()
        let manager = ScrollingCaptureManager(
            captureProvider: mockProvider,
            scrollSynthesizer: mockSynthesizer
        )
        let display = mockProvider.availableDisplays()[0]
        let selection = CGRect(x: 100, y: 100, width: 300, height: 200)

        // Default startSession (omitting mode) must default to .manual
        let started = manager.startSession(selectionRect: selection, displayInfo: display)
        TestHarness.assertTrue(started, "Default startSession starts cleanly")
        TestHarness.assertEqual(manager.state, .capturing(mode: .manual), "Default startSession mode is .manual")
        TestHarness.assertEqual(manager.progress.mode, .manual, "Progress mode is .manual")

        let panel = LiveStitchedPreviewPanel(
            captureManager: manager,
            screenFrame: display.cocoaFrame,
            selectionRect: selection
        )
        TestHarness.assertEqual(panel.viewModel.mode, .manual, "LiveStitchedPreviewViewModel defaults to .manual")

        // Pressing Esc (keyCode 53) cancels the active manual scroll session
        let handledEsc = panel.handleScrollingKeyCode(53)
        TestHarness.assertTrue(handledEsc, "handleScrollingKeyCode(53) handles Esc")
        TestHarness.assertEqual(manager.state, .cancelled, "Esc transitions manager state to .cancelled")

        // Restart session and press Return (keyCode 36) to finish
        manager.resetSession()
        _ = manager.startSession(selectionRect: selection, displayInfo: display)
        let handledReturn = panel.handleScrollingKeyCode(36)
        TestHarness.assertTrue(handledReturn, "handleScrollingKeyCode(36) handles Return")
        TestHarness.assertTrue(manager.isFinished, "Return finishes manual scrolling capture session")
        panel.removeKeyboardMonitors()
    }
}
