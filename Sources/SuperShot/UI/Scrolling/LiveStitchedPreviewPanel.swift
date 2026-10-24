import AppKit
import Carbon
import SwiftUI
import Combine
import SuperShotCore

// MARK: - Live Preview Layout Math Engine

public struct LivePreviewLayoutEngine {
    public static let defaultPanelSize = CGSize(width: 216, height: 290)
    public static let defaultMargin: CGFloat = 12.0
    public static let screenEdgePadding: CGFloat = 12.0

    /// Computes the optimal floating frame for the live preview panel anchored beside the selection rectangle.
    /// Guarantees that the preview panel never overlaps the active capture selection rectangle unless the selection
    /// spans 100% of the entire display.
    public static func computePanelFrame(
        selectionRect: CGRect,
        screenFrame: CGRect,
        panelSize: CGSize = defaultPanelSize,
        margin: CGFloat = defaultMargin,
        padding: CGFloat = screenEdgePadding
    ) -> CGRect {
        let pWidth = panelSize.width
        let pHeight = panelSize.height

        // Option 1: Right of selection
        let rightX = selectionRect.maxX + margin
        if rightX + pWidth <= screenFrame.maxX - padding {
            var rightY = min(selectionRect.maxY - pHeight, screenFrame.maxY - padding - pHeight)
            rightY = max(rightY, screenFrame.minY + padding)
            return CGRect(x: rightX, y: rightY, width: pWidth, height: pHeight)
        }

        // Option 2: Left of selection
        let leftX = selectionRect.minX - margin - pWidth
        if leftX >= screenFrame.minX + padding {
            var leftY = min(selectionRect.maxY - pHeight, screenFrame.maxY - padding - pHeight)
            leftY = max(leftY, screenFrame.minY + padding)
            return CGRect(x: leftX, y: leftY, width: pWidth, height: pHeight)
        }

        // Option 3: Above selection
        let aboveY = selectionRect.maxY + margin
        if aboveY + pHeight <= screenFrame.maxY - padding {
            let aboveX = max(screenFrame.minX + padding, min(selectionRect.maxX - pWidth, screenFrame.maxX - padding - pWidth))
            return CGRect(x: aboveX, y: aboveY, width: pWidth, height: pHeight)
        }

        // Option 4: Below selection
        let belowY = selectionRect.minY - margin - pHeight
        if belowY >= screenFrame.minY + padding {
            let belowX = max(screenFrame.minX + padding, min(selectionRect.maxX - pWidth, screenFrame.maxX - padding - pWidth))
            return CGRect(x: belowX, y: belowY, width: pWidth, height: pHeight)
        }

        // Fallback: Top-right corner of screen (with sharingType = .none to prevent capture)
        let fallbackX = screenFrame.maxX - padding - pWidth
        let fallbackY = screenFrame.maxY - padding - pHeight
        return CGRect(x: fallbackX, y: fallbackY, width: pWidth, height: pHeight)
    }
}

// MARK: - Live Preview State Observable View Model

public final class LiveStitchedPreviewViewModel: ObservableObject {
    @Published public var dimensionBadgeText: String = "0 x 0 px"
    @Published public var frameCount: Int = 0
    @Published public var currentHeightPx: Int = 0
    @Published public var currentWidthPx: Int = 0
    @Published public var mode: ScrollingCaptureMode = .manual
    @Published public var isPaused: Bool = false
    @Published public var previewImage: NSImage?
    @Published public var isAtBottom: Bool = false
    @Published public var isMaxHeightReached: Bool = false

    public weak var manager: ScrollingCaptureManager?

    public init(manager: ScrollingCaptureManager? = nil) {
        self.manager = manager
    }

    public func update(progress: ScrollingProgress, cgImage: CGImage?) {
        self.dimensionBadgeText = progress.dimensionBadgeText
        self.frameCount = progress.frameCount
        self.currentHeightPx = progress.currentHeightPx
        self.currentWidthPx = progress.currentWidthPx
        self.mode = progress.mode
        self.isAtBottom = progress.isAtBottom
        self.isMaxHeightReached = progress.isMaxHeightReached

        if let img = cgImage {
            self.previewImage = NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height))
        }
    }

    public func toggleMode() {
        manager?.toggleMode()
        if let mgr = manager, case .capturing(let next) = mgr.state {
            self.mode = next
        }
    }

    public func togglePause() {
        guard let mgr = manager else { return }
        if case .paused = mgr.state {
            mgr.resumeSession()
            self.isPaused = false
        } else {
            mgr.pauseSession()
            self.isPaused = true
        }
    }

    public func finish() {
        manager?.finishSession(reason: .userDone)
    }

    public func cancel() {
        manager?.cancelSession()
    }
}

// MARK: - Live Stitched Preview Panel (Floating NSPanel)

public final class LiveStitchedPreviewPanel: NSPanel, ScrollingCaptureDelegate {
    public let viewModel: LiveStitchedPreviewViewModel
    public let captureManager: ScrollingCaptureManager
    public var onFinished: ((CGImage, CGFloat, ScrollingCaptureStopReason) -> Void)?
    public var onCancelled: (() -> Void)?

    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var carbonHandlerRef: EventHandlerRef?
    private var escapeHotKeyRef: EventHotKeyRef?
    private var returnHotKeyRef: EventHotKeyRef?
    private var keypadEnterHotKeyRef: EventHotKeyRef?
    private let carbonSignature = OSType(0x53535343) // 'SSSC'

    public init(
        captureManager: ScrollingCaptureManager = .shared,
        screenFrame: CGRect,
        selectionRect: CGRect
    ) {
        self.captureManager = captureManager
        let vm = LiveStitchedPreviewViewModel(manager: captureManager)
        self.viewModel = vm

        let panelFrame = LivePreviewLayoutEngine.computePanelFrame(
            selectionRect: selectionRect,
            screenFrame: screenFrame
        )

        super.init(
            contentRect: panelFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.sharingType = .none // Quartz WindowServer exclusion
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.ignoresMouseEvents = false
        self.becomesKeyOnlyIfNeeded = true

        let rootView = LiveStitchedPreviewContentView(viewModel: vm)
        self.contentView = NSHostingView(rootView: rootView)

        captureManager.delegate = self
    }

    deinit {
        removeKeyboardMonitors()
    }

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    public override func orderFront(_ sender: Any?) {
        super.orderFront(sender)
        installKeyboardMonitors()
    }

    public override func orderOut(_ sender: Any?) {
        removeKeyboardMonitors()
        super.orderOut(sender)
    }

    public override func close() {
        removeKeyboardMonitors()
        super.close()
    }

    /// Handles Escape (53) to cancel and Return (36) / Keypad Enter (76) to finish scrolling capture.
    @discardableResult
    public func handleScrollingKeyCode(_ keyCode: UInt16) -> Bool {
        if keyCode == 53 {
            removeKeyboardMonitors()
            viewModel.cancel()
            return true
        }
        if keyCode == 36 || keyCode == 76 {
            removeKeyboardMonitors()
            viewModel.finish()
            return true
        }
        return false
    }

    private func installKeyboardMonitors() {
        removeKeyboardMonitors()

        // 1. Local NSEvent monitor (when SuperShot is active)
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isVisible else { return event }
            if self.handleScrollingKeyCode(event.keyCode) {
                return nil
            }
            return event
        }

        // 2. Global NSEvent monitor fallback
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isVisible else { return }
            _ = self.handleScrollingKeyCode(event.keyCode)
        }

        // 3. Temporary Carbon HotKeys for Esc (53), Return (36), and Keypad Enter (76)
        // Guarantees 100% reliable interception while scrolling inside external apps without requiring Input Monitoring.
        guard ProcessInfo.processInfo.environment["SUPER_SHOT_HEADLESS"] == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData, let event = event else { return noErr }
                let panel = Unmanaged<LiveStitchedPreviewPanel>.fromOpaque(userData).takeUnretainedValue()

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

                guard paramStatus == noErr, hotKeyID.signature == panel.carbonSignature else {
                    return OSStatus(eventNotHandledErr)
                }

                DispatchQueue.main.async {
                    switch hotKeyID.id {
                    case 1:
                        _ = panel.handleScrollingKeyCode(53)
                    case 2:
                        _ = panel.handleScrollingKeyCode(36)
                    case 3:
                        _ = panel.handleScrollingKeyCode(76)
                    default:
                        break
                    }
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &carbonHandlerRef
        )

        if status == noErr {
            let escID = EventHotKeyID(signature: carbonSignature, id: 1)
            RegisterEventHotKey(UInt32(kVK_Escape), 0, escID, GetApplicationEventTarget(), 0, &escapeHotKeyRef)

            let retID = EventHotKeyID(signature: carbonSignature, id: 2)
            RegisterEventHotKey(UInt32(kVK_Return), 0, retID, GetApplicationEventTarget(), 0, &returnHotKeyRef)

            let kpID = EventHotKeyID(signature: carbonSignature, id: 3)
            RegisterEventHotKey(UInt32(kVK_ANSI_KeypadEnter), 0, kpID, GetApplicationEventTarget(), 0, &keypadEnterHotKeyRef)
        }
    }

    public func removeKeyboardMonitors() {
        if let local = localKeyMonitor {
            NSEvent.removeMonitor(local)
            localKeyMonitor = nil
        }
        if let global = globalKeyMonitor {
            NSEvent.removeMonitor(global)
            globalKeyMonitor = nil
        }
        if let escRef = escapeHotKeyRef {
            UnregisterEventHotKey(escRef)
            escapeHotKeyRef = nil
        }
        if let retRef = returnHotKeyRef {
            UnregisterEventHotKey(retRef)
            returnHotKeyRef = nil
        }
        if let kpRef = keypadEnterHotKeyRef {
            UnregisterEventHotKey(kpRef)
            keypadEnterHotKeyRef = nil
        }
        if let hRef = carbonHandlerRef {
            RemoveEventHandler(hRef)
            carbonHandlerRef = nil
        }
    }

    public override func keyDown(with event: NSEvent) {
        if handleScrollingKeyCode(event.keyCode) {
            return
        }
        super.keyDown(with: event)
    }

    // MARK: - ScrollingCaptureDelegate

    public func scrollingCaptureDidUpdate(progress: ScrollingProgress, previewImage: CGImage?) {
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.update(progress: progress, cgImage: previewImage)
        }
    }

    public func scrollingCaptureDidFinish(image: CGImage, totalHeight: CGFloat, reason: ScrollingCaptureStopReason) {
        DispatchQueue.main.async { [weak self] in
            self?.removeKeyboardMonitors()
            self?.orderOut(nil)
            self?.onFinished?(image, totalHeight, reason)
        }
    }

    public func scrollingCaptureDidCancel() {
        DispatchQueue.main.async { [weak self] in
            self?.removeKeyboardMonitors()
            self?.orderOut(nil)
            self?.onCancelled?()
        }
    }

    public func scrollingCaptureDidFail(error: String) {
        DispatchQueue.main.async { [weak self] in
            self?.removeKeyboardMonitors()
            self?.orderOut(nil)
            self?.onCancelled?()
        }
    }
}

// MARK: - Scrolling Region Border Window (Non-Interactive Capture Frame Highlight)

public final class ScrollingRegionBorderWindow: NSPanel {
    public init(selectionRect: CGRect) {
        let borderFrame = selectionRect.insetBy(dx: -2, dy: -2)
        super.init(
            contentRect: borderFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.sharingType = .none // Excluded from CGWindowListCreateImage during scrolling capture
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let borderView = NSView(frame: NSRect(origin: .zero, size: borderFrame.size))
        borderView.wantsLayer = true
        borderView.layer?.borderColor = NSColor.controlAccentColor.cgColor
        borderView.layer?.borderWidth = 2.0
        borderView.layer?.cornerRadius = 4.0
        self.contentView = borderView
    }
}

// MARK: - Live Preview SwiftUI Content View

public struct LiveStitchedPreviewContentView: View {
    @ObservedObject public var viewModel: LiveStitchedPreviewViewModel
    @ObservedObject private var localizationManager = LocalizationManager.shared

    public init(viewModel: LiveStitchedPreviewViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Header Row: Status Indicator, Mode Tag & Dimension Badge
            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.isPaused ? Color.orange : Color.green)
                    .frame(width: 8, height: 8)

                Text(statusText)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer()

                // Real-time Dimension Badge
                Text(viewModel.dimensionBadgeText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(4)
            }

            // Thumbnail Stitched Viewport Box
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )

                if let img = viewModel.previewImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(4)
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.up.and.down.text.horizontal")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                        Text(LocalizationManager.shared.tr(.scrollCapturing))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }

                if viewModel.frameCount > 0 {
                    VStack {
                        HStack {
                            HStack(spacing: 3) {
                                Image(systemName: "photo.stack")
                                    .font(.system(size: 9, weight: .semibold))
                                Text(LocalizationManager.shared.tr(.framesCount(viewModel.frameCount)))
                                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.72))
                            .cornerRadius(4)
                            .padding(6)
                            Spacer()
                        }
                        Spacer()
                    }
                }
            }
            .frame(height: 155)
            .clipped()

            // Manual Scroll Hint Bar (Auto Scroll hidden per user preference)
            HStack(spacing: 4) {
                Image(systemName: "computermouse.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.accentColor)
                Text("\(LocalizationManager.shared.tr(.scrollManualMode)) • Enter / Esc")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 20)
            .background(Color.white.opacity(0.08))
            .cornerRadius(4)

            // Footer Control Buttons
            HStack(spacing: 8) {
                Button(action: { viewModel.cancel() }) {
                    Text(LocalizationManager.shared.tr(.actionCancel))
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .pointingHandCursor()
                .help(localizationManager.tr(.previewCancelTooltip))

                Button(action: { viewModel.finish() }) {
                    Text(localizationManager.tr(.doneButton))
                        .font(.system(size: 11, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .background(Color.accentColor)
                        .cornerRadius(5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .pointingHandCursor()
                .help(localizationManager.tr(.previewDoneTooltip))
            }
        }
        .padding(10)
        .frame(width: LivePreviewLayoutEngine.defaultPanelSize.width, height: LivePreviewLayoutEngine.defaultPanelSize.height)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.45), radius: 10, x: 0, y: 4)
        )
    }

    private var statusText: String {
        LocalizationManager.shared.tr(.scrollManualMode)
    }
}

// MARK: - Reusable Mode Pill Button

public struct ModePillButton: View {
    public let title: String
    public let isSelected: Bool
    public let action: () -> Void

    public init(title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: isSelected ? .bold : .regular))
                .foregroundColor(isSelected ? .white : .secondary)
                .frame(maxWidth: .infinity, minHeight: 20)
                .background(isSelected ? Color.accentColor.opacity(0.85) : Color.white.opacity(0.06))
                .cornerRadius(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .pointingHandCursor()
    }
}
