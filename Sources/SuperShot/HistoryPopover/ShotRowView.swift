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
    public let isRecentlyCopied: Bool
    public var onSelect: ((ShotItem) -> Void)?
    public var onCopy: ((ShotItem) -> Void)?
    public var onSave: ((ShotItem) -> Void)?
    public var onTogglePin: ((ShotItem) -> Void)?
    public var onDelete: ((ShotItem) -> Void)?
    public var onHoverChange: ((ShotItem, Bool) -> Void)?

    @State private var isHovered: Bool = false
    @State private var localCopiedFeedback: Bool = false
    @ObservedObject private var localizationManager = LocalizationManager.shared

    private var isCopied: Bool {
        isRecentlyCopied || localCopiedFeedback
    }

    public init(
        item: ShotItem,
        storageManager: StorageManager? = nil,
        shortcutIndex: Int? = nil,
        isSelected: Bool = false,
        isRecentlyCopied: Bool = false,
        onSelect: ((ShotItem) -> Void)? = nil,
        onCopy: ((ShotItem) -> Void)? = nil,
        onSave: ((ShotItem) -> Void)? = nil,
        onTogglePin: ((ShotItem) -> Void)? = nil,
        onDelete: ((ShotItem) -> Void)? = nil,
        onHoverChange: ((ShotItem, Bool) -> Void)? = nil
    ) {
        self.item = item
        self.storageManager = storageManager
        self.shortcutIndex = shortcutIndex
        self.isSelected = isSelected
        self.isRecentlyCopied = isRecentlyCopied
        self.onSelect = onSelect
        self.onCopy = onCopy
        self.onSave = onSave
        self.onTogglePin = onTogglePin
        self.onDelete = onDelete
        self.onHoverChange = onHoverChange
    }

    private func triggerLocalCopyFeedback() {
        withAnimation(.easeInOut(duration: 0.15)) {
            localCopiedFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.localCopiedFeedback = false
            }
        }
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
            onHoverChange?(item, hovering)
            if hovering {
                ThumbnailHoverPreviewPanel.shared.show(for: item)
            } else {
                ThumbnailHoverPreviewPanel.shared.hide(forItemId: item.id)
            }
        }
        .contextMenu {
            Button(localizationManager.tr(.actionCopy)) {
                ThumbnailHoverPreviewPanel.shared.hide(immediate: true)
                triggerLocalCopyFeedback()
                onCopy?(item)
            }
            Button(localizationManager.tr(.actionSave) + "...") {
                ThumbnailHoverPreviewPanel.shared.hide(immediate: true)
                onSave?(item)
            }
            Button(localizationManager.tr(item.isPinned ? .unpinButton : .pinButton)) {
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
                // Copy Button with 1.2s checkmark transition
                RowActionButton(
                    icon: isCopied ? "checkmark" : "doc.on.doc",
                    tooltip: isCopied ? localizationManager.tr(.copiedToClipboard) : localizationManager.tr(.actionCopy),
                    defaultTint: isCopied ? .green : .secondary,
                    hoverTint: isCopied ? .green : .primary,
                    customBackground: isCopied ? Color.green.opacity(0.18) : nil
                ) {
                    ThumbnailHoverPreviewPanel.shared.hide(immediate: true)
                    triggerLocalCopyFeedback()
                    onCopy?(item)
                }

                // Save to File Button
                RowActionButton(
                    icon: "square.and.arrow.down",
                    tooltip: localizationManager.tr(.actionSave),
                    defaultTint: .secondary,
                    hoverTint: .primary
                ) {
                    ThumbnailHoverPreviewPanel.shared.hide(immediate: true)
                    onSave?(item)
                }

                // Pin / Unpin Button
                RowActionButton(
                    icon: item.isPinned ? "pin.fill" : "pin",
                    tooltip: localizationManager.tr(item.isPinned ? .unpinButton : .pinButton),
                    defaultTint: item.isPinned ? .accentColor : .secondary,
                    hoverTint: item.isPinned ? .accentColor : .primary,
                    customBackground: item.isPinned ? Color.accentColor.opacity(0.18) : nil
                ) {
                    ThumbnailHoverPreviewPanel.shared.hide(immediate: true)
                    onTogglePin?(item)
                }

                // Delete Button
                RowActionButton(
                    icon: "trash",
                    tooltip: localizationManager.tr(.deleteButton),
                    defaultTint: .red,
                    hoverTint: .red,
                    customBackground: Color.red.opacity(0.12)
                ) {
                    ThumbnailHoverPreviewPanel.shared.hide(immediate: true)
                    onDelete?(item)
                }
            } else {
                if isCopied {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.green.opacity(0.14)))
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

/// Interactive action button for history item rows with smooth hover luminance (0.10 -> 0.18 on hover),
/// spring animation, and pointingHand cursor.
public struct RowActionButton: View {
    public let icon: String
    public let tooltip: String
    public var defaultTint: Color = .secondary
    public var hoverTint: Color = .primary
    public var customBackground: Color? = nil
    public let action: () -> Void

    @State private var isHovered: Bool = false

    public init(
        icon: String,
        tooltip: String,
        defaultTint: Color = .secondary,
        hoverTint: Color = .primary,
        customBackground: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.tooltip = tooltip
        self.defaultTint = defaultTint
        self.hoverTint = hoverTint
        self.customBackground = customBackground
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(isHovered ? hoverTint : defaultTint)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(customBackground ?? (isHovered ? Color.primary.opacity(0.18) : Color.secondary.opacity(0.10)))
                )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help(tooltip)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                isHovered = hovering
            }
        }
    }
}

/// Thumbnail view supporting synchronous in-memory cached loading.
public struct ShotThumbnailView: View {
    public let item: ShotItem
    public let storageManager: StorageManager?

    public init(item: ShotItem, storageManager: StorageManager? = nil) {
        self.item = item
        self.storageManager = storageManager
    }

    private var thumbnailImage: NSImage? {
        Self.resolveThumbnail(for: item, storageManager: storageManager)
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.secondary.opacity(0.1))

            if let img = thumbnailImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .id(item.id)
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
    }

    public static func resolveThumbnail(for item: ShotItem, storageManager: StorageManager?) -> NSImage? {
        let thumbURL: URL
        if let sm = storageManager {
            thumbURL = sm.getThumbnailURL(for: item)
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            thumbURL = appSupport.appendingPathComponent("SuperShot/thumbnails").appendingPathComponent(item.thumbnailPath)
        }

        if let cached = ThumbnailImageCache.shared.image(for: thumbURL) {
            return cached
        }

        if let sm = storageManager, let cgImage = sm.loadThumbnailCGImage(for: item) {
            let img = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            ThumbnailImageCache.shared.setImage(img, for: thumbURL)
            return img
        }

        if let image = NSImage(contentsOf: thumbURL) {
            ThumbnailImageCache.shared.setImage(image, for: thumbURL)
            return image
        }

        if let sm = storageManager, let fullCG = sm.loadCGImage(for: item) {
            let img = NSImage(cgImage: fullCG, size: NSSize(width: fullCG.width, height: fullCG.height))
            ThumbnailImageCache.shared.setImage(img, for: thumbURL)
            return img
        }

        return nil
    }
}
