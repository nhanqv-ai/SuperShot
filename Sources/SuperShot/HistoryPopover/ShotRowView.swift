import SwiftUI
import AppKit
import SuperShotCore

/// ShotRowView presents an individual screenshot history entry with thumbnail,
/// dimensions badge, timestamp, right-aligned shortcut indicator, and hover action buttons.
public struct ShotRowView: View {
    public let item: ShotItem
    public let storageManager: StorageManager?
    public let shortcutIndex: Int?
    public let isSelected: Bool
    public var onSelect: ((ShotItem) -> Void)?
    public var onCopy: ((ShotItem) -> Void)?
    public var onSave: ((ShotItem) -> Void)?
    public var onTogglePin: ((ShotItem) -> Void)?
    public var onDelete: ((ShotItem) -> Void)?

    @State private var isHovered: Bool = false
    @ObservedObject private var localizationManager = LocalizationManager.shared

    public init(
        item: ShotItem,
        storageManager: StorageManager? = nil,
        shortcutIndex: Int? = nil,
        isSelected: Bool = false,
        onSelect: ((ShotItem) -> Void)? = nil,
        onCopy: ((ShotItem) -> Void)? = nil,
        onSave: ((ShotItem) -> Void)? = nil,
        onTogglePin: ((ShotItem) -> Void)? = nil,
        onDelete: ((ShotItem) -> Void)? = nil
    ) {
        self.item = item
        self.storageManager = storageManager
        self.shortcutIndex = shortcutIndex
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onCopy = onCopy
        self.onSave = onSave
        self.onTogglePin = onTogglePin
        self.onDelete = onDelete
    }

    public var body: some View {
        HStack(spacing: 8) {
            // Thumbnail icon
            ShotThumbnailView(item: item, storageManager: storageManager)

            // Title & Dimension Metadata
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(item.dimensionsString)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.secondary)

                    Text("•")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.5))

                    Text(RelativeTimeFormatter.format(item.timestamp))
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.secondary)

                    if item.captureType == .scrolling {
                        Text("SCROLL")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 3)
                            .background(RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.12)))
                    }
                }
            }

            Spacer()

            // Trailing actions and shortcut badge
            trailingControls
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(height: 42)
        .background(backgroundFillColor)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(borderStrokeColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .pointingHandCursor()
        .onTapGesture {
            ThumbnailHoverPreviewPanel.shared.hide(immediate: true)
            onSelect?(item)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
            if hovering {
                ThumbnailHoverPreviewPanel.shared.show(for: item)
            } else {
                ThumbnailHoverPreviewPanel.shared.hide()
            }
        }
        .contextMenu {
            Button(localizationManager.tr(.actionCopy)) {
                ThumbnailHoverPreviewPanel.shared.hide(immediate: true)
                onCopy?(item)
            }
            Button(localizationManager.tr(.actionSave) + "...") {
                ThumbnailHoverPreviewPanel.shared.hide(immediate: true)
                onSave?(item)
            }
            Button(item.isPinned ? "Unpin" : "Pin") {
                ThumbnailHoverPreviewPanel.shared.hide(immediate: true)
                onTogglePin?(item)
            }
            Divider()
            Button(localizationManager.tr(.openInFinder)) {
                ThumbnailHoverPreviewPanel.shared.hide(immediate: true)
                let url: URL
                if let sm = storageManager {
                    url = sm.getImageURL(for: item)
                } else {
                    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                    url = appSupport.appendingPathComponent("SuperShot/images").appendingPathComponent(item.filePath)
                }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            Divider()
            Button(localizationManager.tr(.deleteButton)) {
                ThumbnailHoverPreviewPanel.shared.hide(immediate: true)
                onDelete?(item)
            }
        }
    }

    // MARK: - Trailing Controls

    @ViewBuilder
    private var trailingControls: some View {
        HStack(spacing: 5) {
            if isHovered {
                // Copy Button
                Button(action: {
                    ThumbnailHoverPreviewPanel.shared.hide(immediate: true)
                    onCopy?(item)
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help(localizationManager.tr(.actionCopy))

                // Save to File Button
                Button(action: {
                    ThumbnailHoverPreviewPanel.shared.hide(immediate: true)
                    onSave?(item)
                }) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help(localizationManager.tr(.actionSave))

                // Pin / Unpin Button
                Button(action: {
                    ThumbnailHoverPreviewPanel.shared.hide(immediate: true)
                    onTogglePin?(item)
                }) {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 11))
                        .foregroundColor(item.isPinned ? .accentColor : .secondary)
                        .frame(width: 20, height: 20)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help(item.isPinned ? "Unpin" : "Pin")

                // Delete Button
                Button(action: {
                    ThumbnailHoverPreviewPanel.shared.hide(immediate: true)
                    onDelete?(item)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                        .frame(width: 20, height: 20)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.red.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help(localizationManager.tr(.deleteButton))
            } else {
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.accentColor)
                }

                if let shortcut = shortcutIndex {
                    Text("\(shortcut)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.12)))
                }
            }
        }
    }

    // MARK: - Visual Styling

    private var backgroundFillColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.18)
        } else if isHovered {
            return Color.accentColor.opacity(0.08)
        } else {
            return Color.clear
        }
    }

    private var borderStrokeColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.4)
        } else if isHovered {
            return Color(nsColor: .separatorColor).opacity(0.25)
        } else {
            return Color.clear
        }
    }
}

/// Thumbnail view supporting in-memory cached loading.
public struct ShotThumbnailView: View {
    public let item: ShotItem
    public let storageManager: StorageManager?
    @State private var loadedImage: NSImage?

    public init(item: ShotItem, storageManager: StorageManager? = nil) {
        self.item = item
        self.storageManager = storageManager
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.secondary.opacity(0.1))

            if let img = loadedImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 32, height: 32)
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .onAppear { loadThumbnail() }
        .onChange(of: item.id) { _ in
            loadedImage = nil
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        if let sm = storageManager, let cgImage = sm.loadThumbnailCGImage(for: item) {
            self.loadedImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            return
        }

        let thumbURL: URL
        if let sm = storageManager {
            thumbURL = sm.getThumbnailURL(for: item)
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            thumbURL = appSupport.appendingPathComponent("SuperShot/thumbnails").appendingPathComponent(item.thumbnailPath)
        }

        if let cached = ThumbnailImageCache.shared.image(for: thumbURL) {
            self.loadedImage = cached
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            if let image = NSImage(contentsOf: thumbURL) {
                ThumbnailImageCache.shared.setImage(image, for: thumbURL)
                DispatchQueue.main.async {
                    self.loadedImage = image
                }
            }
        }
    }
}
