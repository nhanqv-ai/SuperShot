import AppKit
import SwiftUI
import SuperShotCore

/// Host view rendering the floating hover zoom preview card.
public struct ThumbnailHoverPreviewCardView: View {
    public let item: ShotItem?
    @State private var previewImage: NSImage?

    public init(item: ShotItem?) {
        self.item = item
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

                    if let img = previewImage {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 300, maxHeight: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
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
                if let item = item {
                    HStack(spacing: 6) {
                        Image(systemName: item.captureType == .scrolling ? "arrow.up.and.down.text.horizontal" : "camera.viewfinder")
                            .font(.system(size: 10))
                            .foregroundColor(.accentColor)

                        Text(item.dimensionsString)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.primary)

                        Text("•")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)

                        Text(item.formattedByteSize)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(.secondary)

                        Spacer()

                        Text(RelativeTimeFormatter.format(item.timestamp))
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 4)
                }
            }
            .padding(10)
        }
        .frame(width: 320, height: 230)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        )
        .onAppear { loadFullImage() }
    }

    private func loadFullImage() {
        guard let item = item else { return }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let imageURL = appSupport.appendingPathComponent("SuperShot/images").appendingPathComponent(item.filePath)

        if let cached = ThumbnailImageCache.shared.image(for: imageURL) {
            self.previewImage = cached
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            if let img = NSImage(contentsOf: imageURL) {
                ThumbnailImageCache.shared.setImage(img, for: imageURL)
                DispatchQueue.main.async {
                    self.previewImage = img
                }
            }
        }
    }
}

/// Floating NSPanel displaying thumbnail zoom preview on hover.
public final class ThumbnailHoverPreviewPanel: NSPanel {
    public static let shared = ThumbnailHoverPreviewPanel()

    public private(set) var currentItemId: UUID?
    private var hostingView: NSHostingView<ThumbnailHoverPreviewCardView>
    private var showTimer: Timer?
    private var hideTimer: Timer?

    public init() {
        self.hostingView = NSHostingView(rootView: ThumbnailHoverPreviewCardView(item: nil))

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
        self.contentView = hostingView
    }

    public func show(for item: ShotItem) {
        hideTimer?.invalidate()
        hideTimer = nil

        if currentItemId == item.id && isVisible { return }

        showTimer?.invalidate()
        showTimer = nil

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
        self.currentItemId = item.id
        hostingView.rootView = ThumbnailHoverPreviewCardView(item: item)
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

    public func hide(immediate: Bool = false) {
        showTimer?.invalidate()
        showTimer = nil

        if immediate {
            hideTimer?.invalidate()
            hideTimer = nil
            currentItemId = nil
            if isVisible { self.orderOut(nil) }
            return
        }

        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.currentItemId = nil
            if self.isVisible { self.orderOut(nil) }
        }
    }
}
