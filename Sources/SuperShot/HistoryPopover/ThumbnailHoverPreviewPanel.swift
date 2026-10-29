import AppKit
import SwiftUI
import SuperShotCore

/// Observable state model driving the floating hover zoom preview card.
/// Using an explicit ObservableObject guarantees that NSHostingView updates
/// synchronously even when the panel transitions between orderOut and orderFront.
public final class ThumbnailHoverPreviewViewModel: ObservableObject {
    @Published public var item: ShotItem?
    @Published public var previewImage: NSImage?

    public init(item: ShotItem? = nil, previewImage: NSImage? = nil) {
        self.item = item
        self.previewImage = previewImage
    }

    public func update(item: ShotItem?, storageManager: StorageManager?) {
        self.item = item
        self.previewImage = ThumbnailHoverPreviewCardView.resolveImage(for: item, storageManager: storageManager)
    }
}

/// Host view rendering the floating hover zoom preview card.
public struct ThumbnailHoverPreviewCardView: View {
    @ObservedObject public var viewModel: ThumbnailHoverPreviewViewModel
    public let item: ShotItem?
    public let storageManager: StorageManager?

    public init(
        viewModel: ThumbnailHoverPreviewViewModel? = nil,
        item: ShotItem?,
        storageManager: StorageManager? = nil
    ) {
        self.item = item
        self.storageManager = storageManager
        if let vm = viewModel {
            self.viewModel = vm
        } else {
            let resolved = Self.resolveImage(for: item, storageManager: storageManager)
            self.viewModel = ThumbnailHoverPreviewViewModel(item: item, previewImage: resolved)
        }
    }

    private var activeItem: ShotItem? {
        viewModel.item ?? item
    }

    private var activeImage: NSImage? {
        if let img = viewModel.previewImage {
            return img
        }
        return Self.resolveImage(for: activeItem, storageManager: storageManager)
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 5)

            VStack(spacing: 8) {
                // High-resolution preview viewport
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))

                    if let img = activeImage {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 300, maxHeight: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .id(activeItem?.id)
                    } else {
                        VStack(spacing: 4) {
                            Image(systemName: "photo")
                                .font(.system(size: 28, weight: .light))
                                .foregroundColor(.secondary)
                        }
                        .frame(width: 300, height: 180)
                    }
                }
                .frame(width: 300, height: 180)

                // Metadata footer
                if let currentItem = activeItem {
                    HStack(spacing: 6) {
                        Image(systemName: currentItem.captureType == .scrolling ? "arrow.up.and.down.text.horizontal" : "camera.viewfinder")
                            .font(.system(size: 10))
                            .foregroundColor(.accentColor)

                        Text(currentItem.dimensionsString)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.primary)

                        Text("•")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)

                        Text(currentItem.formattedByteSize)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(.secondary)

                        Spacer()

                        Text(RelativeTimeFormatter.format(currentItem.timestamp))
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 4)
                    .id(currentItem.id)
                }
            }
            .padding(10)
        }
        .frame(width: 320, height: 230)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        )
    }

    /// Synchronously resolves the full-resolution preview NSImage for the given ShotItem,
    /// guaranteeing that the preview card always matches the hovered ShotItem without stale @State.
    public static func resolveImage(for item: ShotItem?, storageManager: StorageManager?) -> NSImage? {
        guard let item = item else { return nil }

        let imageURL: URL
        if let sm = storageManager {
            imageURL = sm.getImageURL(for: item)
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            imageURL = appSupport.appendingPathComponent("SuperShot/images").appendingPathComponent(item.filePath)
        }

        if let cached = ThumbnailImageCache.shared.image(for: imageURL) {
            return cached
        }

        if let sm = storageManager, let cgImg = sm.loadCGImage(for: item) {
            let img = NSImage(cgImage: cgImg, size: NSSize(width: cgImg.width, height: cgImg.height))
            ThumbnailImageCache.shared.setImage(img, for: imageURL)
            return img
        }

        if let img = NSImage(contentsOf: imageURL) {
            ThumbnailImageCache.shared.setImage(img, for: imageURL)
            return img
        }

        if let sm = storageManager, let thumbCG = sm.loadThumbnailCGImage(for: item) {
            return NSImage(cgImage: thumbCG, size: NSSize(width: thumbCG.width, height: thumbCG.height))
        }

        return nil
    }
}

/// Floating NSPanel displaying thumbnail zoom preview on hover.
public final class ThumbnailHoverPreviewPanel: NSPanel {
    public static let shared = ThumbnailHoverPreviewPanel()

    public weak var storageManager: StorageManager?
    public let viewModel = ThumbnailHoverPreviewViewModel()
    public private(set) var currentItemId: UUID?
    private var pendingItemId: UUID?
    private var hostingView: NSHostingView<ThumbnailHoverPreviewCardView>
    private var showTimer: Timer?
    private var hideTimer: Timer?

    public init() {
        let vm = ThumbnailHoverPreviewViewModel()
        self.hostingView = NSHostingView(rootView: ThumbnailHoverPreviewCardView(viewModel: vm, item: nil))

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 230),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .popUpMenu
        self.hasShadow = true
        self.ignoresMouseEvents = true
        self.isReleasedWhenClosed = false
        self.hostingView.rootView = ThumbnailHoverPreviewCardView(viewModel: self.viewModel, item: nil)
        self.contentView = hostingView
    }

    deinit {
        showTimer?.invalidate()
        showTimer = nil
        hideTimer?.invalidate()
        hideTimer = nil
    }

    public func show(for item: ShotItem) {
        hideTimer?.invalidate()
        hideTimer = nil

        showTimer?.invalidate()
        showTimer = nil
        pendingItemId = item.id

        if isVisible {
            // Instant transition if already visible
            display(item: item)
        } else {
            // 100ms entry debounce
            showTimer = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: false) { [weak self] _ in
                self?.display(item: item)
            }
        }
    }

    private func display(item: ShotItem) {
        self.pendingItemId = nil
        self.currentItemId = item.id
        self.viewModel.update(item: item, storageManager: storageManager)
        self.hostingView.rootView = ThumbnailHoverPreviewCardView(
            viewModel: self.viewModel,
            item: item,
            storageManager: storageManager
        )
        self.hostingView.needsLayout = true
        self.hostingView.layoutSubtreeIfNeeded()
        self.hostingView.needsDisplay = true
        positionPanel(width: 320, height: 230)
    }

    private func positionPanel(width: CGFloat, height: CGFloat) {
        let mouseScreen = NSEvent.mouseLocation
        let targetWindow = NSApp.windows.first { win in
            win.isVisible && win != self && (win.className.contains("Popover") || win.isKeyWindow)
        } ?? NSApp.keyWindow

        let screen = NSScreen.screens.first { NSMouseInRect(mouseScreen, $0.frame, false) }
            ?? targetWindow?.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first

        let screenVisible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)

        var targetX: CGFloat
        var targetY = mouseScreen.y - (height / 2)

        if let win = targetWindow {
            let winFrame = win.frame
            let leftSpace = winFrame.minX - screenVisible.minX
            if leftSpace >= (width + 12) {
                targetX = winFrame.minX - width - 8
            } else {
                targetX = winFrame.maxX + 8
            }
        } else {
            targetX = mouseScreen.x - width - 12
        }

        // Screen boundary safety clamping
        if targetX < screenVisible.minX + 8 { targetX = screenVisible.minX + 8 }
        if targetX + width > screenVisible.maxX - 8 { targetX = screenVisible.maxX - width - 8 }
        if targetY < screenVisible.minY + 8 { targetY = screenVisible.minY + 8 }
        if targetY + height > screenVisible.maxY - 8 { targetY = screenVisible.maxY - height - 8 }

        self.setFrame(NSRect(x: targetX, y: targetY, width: width, height: height), display: true)
        if !isVisible {
            self.orderFront(nil)
        }
    }

    public func hide(forItemId exitingItemId: UUID? = nil, immediate: Bool = false) {
        if !immediate, let exitingId = exitingItemId {
            // If another item is already pending or displayed, ignore stale hover-exit from the previous row
            if let pending = pendingItemId, pending != exitingId {
                return
            }
            if pendingItemId == nil, let current = currentItemId, current != exitingId {
                return
            }
        }

        showTimer?.invalidate()
        showTimer = nil
        pendingItemId = nil

        if immediate {
            hideTimer?.invalidate()
            hideTimer = nil
            currentItemId = nil
            viewModel.update(item: nil, storageManager: nil)
            if isVisible { self.orderOut(nil) }
            return
        }

        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.currentItemId = nil
            self.viewModel.update(item: nil, storageManager: nil)
            if self.isVisible { self.orderOut(nil) }
        }
    }
}
