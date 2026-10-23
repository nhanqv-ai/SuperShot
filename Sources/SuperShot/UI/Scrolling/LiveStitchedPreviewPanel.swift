import AppKit
import SwiftUI
import Combine
import SuperShotCore

// MARK: - Live Preview Layout Math Engine

public struct LivePreviewLayoutEngine {
    public static let defaultPanelSize = CGSize(width: 190, height: 290)
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
    @Published public var mode: ScrollingCaptureMode = .auto
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

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    public override func keyDown(with event: NSEvent) {
        // Esc: Cancel capture
        if event.keyCode == 53 {
            viewModel.cancel()
            return
        }

        // Return / Enter: Confirm / Stop capture
        if event.keyCode == 36 || event.keyCode == 76 {
            viewModel.finish()
            return
        }

        // Space: Toggle pause/resume in auto mode
        if event.keyCode == 49 {
            viewModel.togglePause()
            return
        }

        // 'A' key: Switch to Auto
        if event.charactersIgnoringModifiers?.lowercased() == "a" {
            if viewModel.mode != .auto {
                viewModel.toggleMode()
            }
            return
        }

        // 'M' key: Switch to Manual
        if event.charactersIgnoringModifiers?.lowercased() == "m" {
            if viewModel.mode != .manual {
                viewModel.toggleMode()
            }
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
            self?.orderOut(nil)
            self?.onFinished?(image, totalHeight, reason)
        }
    }

    public func scrollingCaptureDidCancel() {
        DispatchQueue.main.async { [weak self] in
            self?.orderOut(nil)
            self?.onCancelled?()
        }
    }

    public func scrollingCaptureDidFail(error: String) {
        DispatchQueue.main.async { [weak self] in
            self?.orderOut(nil)
            self?.onCancelled?()
        }
    }
}

// MARK: - Live Preview SwiftUI Content View

public struct LiveStitchedPreviewContentView: View {
    @ObservedObject public var viewModel: LiveStitchedPreviewViewModel

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

                // Scanning Line Indicator
                if !viewModel.isPaused && viewModel.mode == .auto {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.8))
                        .frame(height: 2)
                        .shadow(color: Color.accentColor, radius: 2)
                }
            }
            .frame(height: 155)
            .clipped()

            // Mode Selector Pill
            HStack(spacing: 4) {
                ModePillButton(
                    title: LocalizationManager.shared.tr(.scrollAutoMode),
                    isSelected: viewModel.mode == .auto
                ) {
                    if viewModel.mode != .auto { viewModel.toggleMode() }
                }

                ModePillButton(
                    title: LocalizationManager.shared.tr(.scrollManualMode),
                    isSelected: viewModel.mode == .manual
                ) {
                    if viewModel.mode != .manual { viewModel.toggleMode() }
                }
            }

            // Footer Control Buttons
            HStack(spacing: 8) {
                if viewModel.mode == .auto {
                    Button(action: { viewModel.togglePause() }) {
                        Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 28, height: 26)
                            .background(Color.white.opacity(0.12))
                            .cornerRadius(5)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(viewModel.isPaused ? "Resume" : "Pause")
                }

                Button(action: { viewModel.cancel() }) {
                    Text(LocalizationManager.shared.tr(.actionCancel))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(5)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Cancel (Esc)")

                Button(action: { viewModel.finish() }) {
                    Text("Done")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .background(Color.accentColor)
                        .cornerRadius(5)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Done (Return / Space)")
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
        if viewModel.isPaused {
            return "Paused"
        }
        if viewModel.mode == .auto {
            return "Auto"
        }
        return "Manual"
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
        }
        .buttonStyle(PlainButtonStyle())
    }
}
