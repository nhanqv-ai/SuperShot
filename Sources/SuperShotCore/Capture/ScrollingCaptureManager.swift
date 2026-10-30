import Foundation
import CoreGraphics
import AppKit

// MARK: - Scrolling Capture Mode & State

public enum ScrollingCaptureMode: String, Codable, CaseIterable, Sendable {
    case auto
    case manual
}

public enum ScrollingCaptureStopReason: Sendable, Equatable {
    case userDone
    case bottomReached
    case maxHeightReached
    case cancelled
    case failed(String)
}

public enum ScrollingCaptureState: Equatable, Sendable {
    case idle
    case capturing(mode: ScrollingCaptureMode)
    case paused(mode: ScrollingCaptureMode)
    case finished(CGImage)
    case cancelled
    case failed(String)

    public static func == (lhs: ScrollingCaptureState, rhs: ScrollingCaptureState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.cancelled, .cancelled):
            return true
        case (.capturing(let m1), .capturing(let m2)):
            return m1 == m2
        case (.paused(let m1), .paused(let m2)):
            return m1 == m2
        case (.finished(let img1), .finished(let img2)):
            return img1.width == img2.width && img1.height == img2.height
        case (.failed(let s1), .failed(let s2)):
            return s1 == s2
        default:
            return false
        }
    }
}

// MARK: - Scrolling Progress Model

public struct ScrollingProgress: Sendable, Equatable {
    public let frameCount: Int
    public let currentWidthPx: Int
    public let currentHeightPx: Int
    public let totalScrollDeltaPx: Int
    public let mode: ScrollingCaptureMode
    public let isAtBottom: Bool
    public let isMaxHeightReached: Bool

    public init(
        frameCount: Int = 0,
        currentWidthPx: Int = 0,
        currentHeightPx: Int = 0,
        totalScrollDeltaPx: Int = 0,
        mode: ScrollingCaptureMode = .manual,
        isAtBottom: Bool = false,
        isMaxHeightReached: Bool = false
    ) {
        self.frameCount = frameCount
        self.currentWidthPx = currentWidthPx
        self.currentHeightPx = currentHeightPx
        self.totalScrollDeltaPx = totalScrollDeltaPx
        self.mode = mode
        self.isAtBottom = isAtBottom
        self.isMaxHeightReached = isMaxHeightReached
    }

    public var dimensionBadgeText: String {
        "\(currentWidthPx) x \(currentHeightPx) px"
    }
}

// MARK: - Scroll Event Synthesizing Protocol & Implementations

public protocol ScrollEventSynthesizing: AnyObject, Sendable {
    var isAvailable: Bool { get }
    @discardableResult
    func synthesizeScroll(deltaY: Int32, at point: CGPoint) -> Bool
}

/// Production CGEvent-based downward scroll wheel event synthesizer.
public final class NativeScrollEventSynthesizer: ScrollEventSynthesizing, @unchecked Sendable {
    public init() {}

    public var isAvailable: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    public func synthesizeScroll(deltaY: Int32, at point: CGPoint) -> Bool {
        guard AXIsProcessTrusted() else { return false }

        // In macOS Quartz Event Services:
        // Negative wheel1 scrolls downward (moves content upward, revealing lower content).
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: -deltaY,
            wheel2: 0,
            wheel3: 0
        ) else {
            return false
        }

        event.location = point
        event.post(tap: .cghidEventTap)
        return true
    }
}

/// Headless mock scroll event synthesizer for 100% automated offline unit tests.
public final class MockScrollEventSynthesizer: ScrollEventSynthesizing, @unchecked Sendable {
    public struct ScrollRecord: Equatable, Sendable {
        public let deltaY: Int32
        public let point: CGPoint
        public let timestamp: Date
    }

    private let lock = NSLock()
    private var _history: [ScrollRecord] = []
    public var shouldSucceed: Bool = true
    public var isAvailable: Bool = true

    public init() {}

    public var history: [ScrollRecord] {
        lock.lock()
        defer { lock.unlock() }
        return _history
    }

    public var totalScrollCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _history.count
    }

    @discardableResult
    public func synthesizeScroll(deltaY: Int32, at point: CGPoint) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if shouldSucceed {
            _history.append(ScrollRecord(deltaY: deltaY, point: point, timestamp: Date()))
            return true
        }
        return false
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        _history.removeAll()
    }
}

// MARK: - Scrolling Capture Configuration

public struct ScrollingCaptureConfiguration: Sendable, Equatable {
    public var scrollStepDelta: Int32
    public var settleDelay: TimeInterval
    public var tickInterval: TimeInterval
    public var maxScrollHeightPx: Int
    public var scrollbarStripWidth: CGFloat
    public var maxConsecutiveZeroDeltas: Int
    public var manualPollInterval: TimeInterval

    public init(
        scrollStepDelta: Int32 = 60,
        settleDelay: TimeInterval = 0.08,
        tickInterval: TimeInterval = 0.05,
        maxScrollHeightPx: Int = 15000,
        scrollbarStripWidth: CGFloat = 24.0,
        maxConsecutiveZeroDeltas: Int = 2,
        manualPollInterval: TimeInterval = 0.15
    ) {
        self.scrollStepDelta = max(10, min(scrollStepDelta, 300))
        self.settleDelay = max(0.01, min(settleDelay, 0.5))
        self.tickInterval = max(0.01, min(tickInterval, 0.5))
        self.maxScrollHeightPx = max(5000, min(maxScrollHeightPx, 30000))
        self.scrollbarStripWidth = max(0, min(scrollbarStripWidth, 60.0))
        self.maxConsecutiveZeroDeltas = max(1, min(maxConsecutiveZeroDeltas, 5))
        self.manualPollInterval = max(0.05, min(manualPollInterval, 1.0))
    }

    public static let `default` = ScrollingCaptureConfiguration()
}

// MARK: - Scrolling Capture Delegate

public protocol ScrollingCaptureDelegate: AnyObject {
    func scrollingCaptureDidUpdate(progress: ScrollingProgress, previewImage: CGImage?)
    func scrollingCaptureDidFinish(image: CGImage, totalHeight: CGFloat, reason: ScrollingCaptureStopReason)
    func scrollingCaptureDidCancel()
    func scrollingCaptureDidFail(error: String)
}

// MARK: - Coordinate Conversion Helper

public struct ScrollingCoordinateMapper {
    /// Maps a Cocoa window/screen selection rectangle (bottom-left origin) into CoreGraphics global coordinates (top-left origin).
    public static func targetScrollCenter(
        selectionRect: CGRect,
        display: CaptureDisplayInfo
    ) -> CGPoint {
        let localCenterX = selectionRect.midX
        let localCenterY = selectionRect.midY
        let globalX = display.cgBounds.minX + localCenterX
        let globalY = display.cgBounds.minY + (display.cgBounds.height - localCenterY)
        return CGPoint(x: globalX, y: globalY)
    }

    /// Backwards-compatible mapping using screenBounds.
    public static func targetScrollCenter(
        selectionRect: CGRect,
        screenBounds: CGRect
    ) -> CGPoint {
        let centerX = selectionRect.midX
        let cocoaCenterY = selectionRect.midY
        let globalX = screenBounds.minX + centerX
        let globalY = screenBounds.minY + (screenBounds.height - cocoaCenterY)
        return CGPoint(x: globalX, y: globalY)
    }
}

// MARK: - ScrollingCaptureManager

public final class ScrollingCaptureManager: @unchecked Sendable {
    public static let shared = ScrollingCaptureManager()

    public weak var delegate: ScrollingCaptureDelegate?

    public var captureProvider: ScreenCaptureProviding
    public var scrollSynthesizer: ScrollEventSynthesizing
    public var configuration: ScrollingCaptureConfiguration

    private let stateLock = NSRecursiveLock()
    private var _state: ScrollingCaptureState = .idle
    private var _progress: ScrollingProgress = ScrollingProgress()

    // Active session parameters
    private var selectionRect: CGRect = .zero
    private var displayInfo: CaptureDisplayInfo?
    private var capturedFrames: [CGImage] = []
    private var lastCapturedFrame: CGImage?
    private var accumulatedHeightPx: CGFloat = 0.0
    private var consecutiveZeroDeltas: Int = 0

    // Concurrency Task
    private var captureTask: Task<Void, Never>?

    public var state: ScrollingCaptureState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _state
    }

    public var progress: ScrollingProgress {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _progress
    }

    public init(
        captureProvider: ScreenCaptureProviding? = nil,
        scrollSynthesizer: ScrollEventSynthesizing? = nil,
        configuration: ScrollingCaptureConfiguration = .default
    ) {
        if let provider = captureProvider {
            self.captureProvider = provider
        } else if ProcessInfo.processInfo.environment["SUPER_SHOT_HEADLESS"] != nil {
            self.captureProvider = MockScreenCaptureProvider()
        } else {
            self.captureProvider = NativeScreenCaptureProvider()
        }

        if let synthesizer = scrollSynthesizer {
            self.scrollSynthesizer = synthesizer
        } else if ProcessInfo.processInfo.environment["SUPER_SHOT_HEADLESS"] != nil {
            self.scrollSynthesizer = MockScrollEventSynthesizer()
        } else {
            self.scrollSynthesizer = NativeScrollEventSynthesizer()
        }

        self.configuration = configuration
        setupWorkspaceObservers()
    }

    private var workspaceObservers: [Any] = []

    private func setupWorkspaceObservers() {
        guard ProcessInfo.processInfo.environment["SUPER_SHOT_HEADLESS"] == nil else { return }
        let wsCenter = NSWorkspace.shared.notificationCenter
        let o1 = wsCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.cancelSession()
        }
        let o2 = wsCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.cancelSession()
        }
        let o3 = DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.cancelSession()
        }
        workspaceObservers = [o1, o2, o3]
    }

    deinit {
        for obs in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            DistributedNotificationCenter.default().removeObserver(obs)
        }
        workspaceObservers.removeAll()
    }

    // MARK: - Session Control

    public func startSession(
        selectionRect: CGRect,
        displayInfo: CaptureDisplayInfo,
        mode: ScrollingCaptureMode = .manual,
        initialFrame: CGImage? = nil
    ) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard _state == .idle || _state == .cancelled || isFinished else {
            return false
        }

        self.selectionRect = selectionRect
        self.displayInfo = displayInfo
        self.capturedFrames = []
        self.lastCapturedFrame = nil
        self.accumulatedHeightPx = 0.0
        self.consecutiveZeroDeltas = 0

        let scale = displayInfo.scaleFactor
        let widthPx = Int(round(selectionRect.width * scale))
        let initialHeightPx = Int(round(selectionRect.height * scale))

        self.accumulatedHeightPx = CGFloat(initialHeightPx)
        self._state = .capturing(mode: mode)
        self._progress = ScrollingProgress(
            frameCount: 0,
            currentWidthPx: widthPx,
            currentHeightPx: initialHeightPx,
            totalScrollDeltaPx: 0,
            mode: mode,
            isAtBottom: false,
            isMaxHeightReached: false
        )

        // Use clean pre-cropped initialFrame when provided, otherwise capture display image
        let resolvedInitial: CGImage?
        if let provided = initialFrame {
            resolvedInitial = provided
        } else if let initialFullImage = captureProvider.captureDisplayImage(displayID: displayInfo.displayID) {
            resolvedInitial = ScreenCaptureManager.cropImage(
                initialFullImage,
                selectionInWindow: selectionRect,
                windowSize: displayInfo.cocoaFrame.size,
                scaleFactor: scale
            )
        } else {
            resolvedInitial = nil
        }

        guard let initialCropped = resolvedInitial else {
            _state = .failed("Failed to capture initial screen frame")
            delegate?.scrollingCaptureDidFail(error: "Failed to capture initial screen frame")
            return false
        }

        capturedFrames.append(initialCropped)
        lastCapturedFrame = initialCropped
        _progress = ScrollingProgress(
            frameCount: 1,
            currentWidthPx: initialCropped.width,
            currentHeightPx: initialCropped.height,
            totalScrollDeltaPx: 0,
            mode: mode,
            isAtBottom: false,
            isMaxHeightReached: false
        )

        delegate?.scrollingCaptureDidUpdate(progress: _progress, previewImage: initialCropped)

        // Launch background acquisition loop
        launchLoop(mode: mode)
        return true
    }

    public func pauseSession() {
        stateLock.lock()
        defer { stateLock.unlock() }

        if case .capturing(let mode) = _state {
            _state = .paused(mode: mode)
            captureTask?.cancel()
            captureTask = nil
        }
    }

    public func resumeSession() {
        stateLock.lock()
        defer { stateLock.unlock() }

        if case .paused(let mode) = _state {
            _state = .capturing(mode: mode)
            launchLoop(mode: mode)
        }
    }

    public func toggleMode() {
        stateLock.lock()
        defer { stateLock.unlock() }

        switch _state {
        case .capturing(let current):
            let next: ScrollingCaptureMode = (current == .auto) ? .manual : .auto
            _state = .capturing(mode: next)
            captureTask?.cancel()
            captureTask = nil
            launchLoop(mode: next)
        case .paused(let current):
            let next: ScrollingCaptureMode = (current == .auto) ? .manual : .auto
            _state = .paused(mode: next)
        default:
            break
        }
    }

    public func finishSession(reason: ScrollingCaptureStopReason = .userDone) {
        stateLock.lock()
        captureTask?.cancel()
        captureTask = nil

        guard !capturedFrames.isEmpty else {
            _state = .cancelled
            stateLock.unlock()
            delegate?.scrollingCaptureDidCancel()
            return
        }

        let frames = self.capturedFrames
        let totalH = self.accumulatedHeightPx
        let scale = self.displayInfo?.scaleFactor ?? 2.0
        let scrollbarW = self.configuration.scrollbarStripWidth
        let maxScrollH = CGFloat(self.configuration.maxScrollHeightPx)
        stateLock.unlock()

        // Assemble final stitched image using pure ImageStitcher engine
        let stitchOptions = StitchOptions(
            scrollbarStripWidth: scrollbarW,
            maxScrollHeightPx: maxScrollH,
            scaleFactor: scale
        )

        let finalImage: CGImage
        let finalHeight: CGFloat
        if let stitched = try? ImageStitcher.stitch(frames: frames, options: stitchOptions) {
            finalImage = stitched.image
            finalHeight = stitched.totalHeight
        } else {
            finalImage = frames.first!
            finalHeight = totalH
        }

        stateLock.lock()
        guard _state != .cancelled else {
            stateLock.unlock()
            return
        }
        _state = .finished(finalImage)
        stateLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.scrollingCaptureDidFinish(image: finalImage, totalHeight: finalHeight, reason: reason)
        }
    }

    public func cancelSession() {
        stateLock.lock()
        captureTask?.cancel()
        captureTask = nil
        _state = .cancelled
        capturedFrames.removeAll()
        lastCapturedFrame = nil
        stateLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.scrollingCaptureDidCancel()
        }
    }

    public func resetSession() {
        stateLock.lock()
        defer { stateLock.unlock() }
        captureTask?.cancel()
        captureTask = nil
        _state = .idle
        capturedFrames.removeAll()
        lastCapturedFrame = nil
        accumulatedHeightPx = 0.0
        consecutiveZeroDeltas = 0
        _progress = ScrollingProgress()
    }

    public var isFinished: Bool {
        if case .finished = _state { return true }
        return false
    }

    // MARK: - Internal Acquisition Loop

    private func launchLoop(mode: ScrollingCaptureMode) {
        captureTask?.cancel()

        captureTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            if mode == .auto {
                await self.executeAutoScrollLoop()
            } else {
                await self.executeManualScrollLoop()
            }
        }
    }

    private func executeAutoScrollLoop() async {
        while !Task.isCancelled {
            // Check state
            let (targetPoint, display, rect, delta) = stateLock.withLock { () -> (CGPoint, CaptureDisplayInfo?, CGRect, Int32) in
                guard case .capturing(mode: .auto) = self._state, let disp = self.displayInfo else {
                    return (.zero, nil, .zero, 0)
                }
                let pt = ScrollingCoordinateMapper.targetScrollCenter(
                    selectionRect: self.selectionRect,
                    display: disp
                )
                return (pt, disp, self.selectionRect, self.configuration.scrollStepDelta)
            }

            guard let disp = display, !rect.isEmpty else { break }

            // Step 1: Synthesize downward scroll wheel event
            let scrolled = scrollSynthesizer.synthesizeScroll(deltaY: delta, at: targetPoint)
            if !scrolled && !scrollSynthesizer.isAvailable {
                // Accessibility permission unavailable -> fallback to manual mode
                stateLock.withLock {
                    self._state = .capturing(mode: .manual)
                    self._progress = ScrollingProgress(
                        frameCount: self.capturedFrames.count,
                        currentWidthPx: self.progress.currentWidthPx,
                        currentHeightPx: self.progress.currentHeightPx,
                        totalScrollDeltaPx: self.progress.totalScrollDeltaPx,
                        mode: .manual,
                        isAtBottom: self.progress.isAtBottom,
                        isMaxHeightReached: self.progress.isMaxHeightReached
                    )
                }
                let updatedProg = self.progress
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.scrollingCaptureDidUpdate(progress: updatedProg, previewImage: nil)
                }
                await executeManualScrollLoop()
                break
            }

            // Step 2: Settle Delay (DOM layout & paint settling)
            let settleNanos = UInt64(configuration.settleDelay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: settleNanos)
            if Task.isCancelled { break }

            // Step 3: Capture display image & crop selection
            let croppedImage: CGImage? = autoreleasepool {
                guard let fullImage = captureProvider.captureDisplayImage(displayID: disp.displayID) else { return nil }
                return ScreenCaptureManager.cropImage(
                    fullImage,
                    selectionInWindow: rect,
                    windowSize: disp.cocoaFrame.size,
                    scaleFactor: disp.scaleFactor
                )
            }
            guard let cropped = croppedImage else {
                continue
            }

            // Step 4: Estimate vertical offset between consecutive frames
            let (offset, shouldStop, stopReason, framesSnapshot) = stateLock.withLock { () -> (CGFloat, Bool, ScrollingCaptureStopReason?, [CGImage]) in
                guard let last = self.lastCapturedFrame else {
                    return (0, false, nil, [])
                }

                let effectiveW = max(1, last.width - Int(round(self.configuration.scrollbarStripWidth * disp.scaleFactor)))
                let maxHeaderPx = min(last.height / 3, Int(round(80.0 * disp.scaleFactor)))
                let maxFooterPx = min(last.height / 3, Int(round(80.0 * disp.scaleFactor)))
                let candH = ImageStitcher.detectStationaryHeader(f1: last, f2: cropped, effectiveWidth: effectiveW, maxHeaderH: maxHeaderPx)
                let candF = ImageStitcher.detectStationaryFooter(f1: last, f2: cropped, effectiveWidth: effectiveW, maxFooterH: maxFooterPx)
                let est = ImageStitcher.estimateVerticalOffset(
                    f1: last,
                    f2: cropped,
                    effectiveWidth: effectiveW,
                    headerH: candH,
                    footerH: candF,
                    minOffset: 6
                )

                if est.isZeroDelta || est.offset <= 0 || est.confidence < 0.85 {
                    self.consecutiveZeroDeltas += 1
                    if self.consecutiveZeroDeltas >= self.configuration.maxConsecutiveZeroDeltas {
                        return (0, true, .bottomReached, [])
                    }
                    return (0, false, nil, [])
                }

                self.consecutiveZeroDeltas = 0
                self.accumulatedHeightPx += CGFloat(est.offset)
                self.capturedFrames.append(cropped)
                self.lastCapturedFrame = cropped

                let isMax = self.accumulatedHeightPx >= CGFloat(self.configuration.maxScrollHeightPx)
                if isMax {
                    self.accumulatedHeightPx = CGFloat(self.configuration.maxScrollHeightPx)
                    return (CGFloat(est.offset), true, .maxHeightReached, self.capturedFrames)
                }

                let currentProg = ScrollingProgress(
                    frameCount: self.capturedFrames.count,
                    currentWidthPx: cropped.width,
                    currentHeightPx: Int(self.accumulatedHeightPx),
                    totalScrollDeltaPx: Int(self.accumulatedHeightPx) - cropped.height,
                    mode: .auto,
                    isAtBottom: false,
                    isMaxHeightReached: false
                )
                self._progress = currentProg
                return (CGFloat(est.offset), false, nil, self.capturedFrames)
            }

            // Update live stitched preview on UI thread
            if offset > 0 {
                let stitchOptions = StitchOptions(
                    scrollbarStripWidth: configuration.scrollbarStripWidth,
                    maxScrollHeightPx: CGFloat(configuration.maxScrollHeightPx),
                    scaleFactor: disp.scaleFactor
                )
                let liveImage = (try? ImageStitcher.stitch(frames: framesSnapshot, options: stitchOptions).image) ?? cropped
                let prog = self.progress
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.scrollingCaptureDidUpdate(progress: prog, previewImage: liveImage)
                }
            }

            if shouldStop, let reason = stopReason {
                finishSession(reason: reason)
                break
            }

            // Step 5: Inter-tick sleep
            let tickNanos = UInt64(configuration.tickInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: tickNanos)
        }
    }

    private func executeManualScrollLoop() async {
        while !Task.isCancelled {
            let (display, rect) = stateLock.withLock { () -> (CaptureDisplayInfo?, CGRect) in
                guard case .capturing(mode: .manual) = self._state, let disp = self.displayInfo else {
                    return (nil, .zero)
                }
                return (disp, self.selectionRect)
            }

            guard let disp = display, !rect.isEmpty else { break }

            let pollNanos = UInt64(configuration.manualPollInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: pollNanos)
            if Task.isCancelled { break }

            let croppedImage: CGImage? = autoreleasepool {
                guard let fullImage = captureProvider.captureDisplayImage(displayID: disp.displayID) else { return nil }
                return ScreenCaptureManager.cropImage(
                    fullImage,
                    selectionInWindow: rect,
                    windowSize: disp.cocoaFrame.size,
                    scaleFactor: disp.scaleFactor
                )
            }
            guard let cropped = croppedImage else {
                continue
            }

            let (offset, shouldStop, framesSnapshot) = stateLock.withLock { () -> (CGFloat, Bool, [CGImage]) in
                guard let last = self.lastCapturedFrame else { return (0, false, []) }
                let effectiveW = max(1, last.width - Int(round(self.configuration.scrollbarStripWidth * disp.scaleFactor)))
                let maxHeaderPx = min(last.height / 3, Int(round(80.0 * disp.scaleFactor)))
                let maxFooterPx = min(last.height / 3, Int(round(80.0 * disp.scaleFactor)))
                let candH = ImageStitcher.detectStationaryHeader(f1: last, f2: cropped, effectiveWidth: effectiveW, maxHeaderH: maxHeaderPx)
                let candF = ImageStitcher.detectStationaryFooter(f1: last, f2: cropped, effectiveWidth: effectiveW, maxFooterH: maxFooterPx)
                let est = ImageStitcher.estimateVerticalOffset(
                    f1: last,
                    f2: cropped,
                    effectiveWidth: effectiveW,
                    headerH: candH,
                    footerH: candF,
                    minOffset: 8
                )

                // Only accumulate if user scrolled by at least 8px with high confidence
                if !est.isZeroDelta && est.offset >= 8 && est.confidence >= 0.88 {
                    self.accumulatedHeightPx += CGFloat(est.offset)
                    self.capturedFrames.append(cropped)
                    self.lastCapturedFrame = cropped

                    let isMax = self.accumulatedHeightPx >= CGFloat(self.configuration.maxScrollHeightPx)
                    if isMax {
                        self.accumulatedHeightPx = CGFloat(self.configuration.maxScrollHeightPx)
                        return (CGFloat(est.offset), true, self.capturedFrames)
                    }

                    let currentProg = ScrollingProgress(
                        frameCount: self.capturedFrames.count,
                        currentWidthPx: cropped.width,
                        currentHeightPx: Int(self.accumulatedHeightPx),
                        totalScrollDeltaPx: Int(self.accumulatedHeightPx) - cropped.height,
                        mode: .manual,
                        isAtBottom: false,
                        isMaxHeightReached: false
                    )
                    self._progress = currentProg
                    return (CGFloat(est.offset), false, self.capturedFrames)
                }
                return (0, false, [])
            }

            if offset > 0 {
                let stitchOptions = StitchOptions(
                    scrollbarStripWidth: configuration.scrollbarStripWidth,
                    maxScrollHeightPx: CGFloat(configuration.maxScrollHeightPx),
                    scaleFactor: disp.scaleFactor
                )
                let liveImage = (try? ImageStitcher.stitch(frames: framesSnapshot, options: stitchOptions).image) ?? cropped
                let prog = self.progress
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.scrollingCaptureDidUpdate(progress: prog, previewImage: liveImage)
                }
            }

            if shouldStop {
                finishSession(reason: .maxHeightReached)
                break
            }
        }
    }
}
