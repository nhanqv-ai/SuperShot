import SwiftUI
import AppKit
import SuperShotCore

/// MainShotView is the root SwiftUI container for the Screenshot History Popover.
public struct MainShotView: View {
    @ObservedObject public var storageManager: StorageManager
    public var appSettings: AppSettings?
    @ObservedObject public var updateManager: UpdateManager
    public var autoPasteService: any AutoPasteServicing
    public var previousAppTracker: any PreviousAppTracking
    public var onCaptureRegion: (() -> Void)?
    public var onScrollingCapture: (() -> Void)?
    public var onOpenSettings: (() -> Void)?
    public var onDismiss: (() -> Void)?
    public var onItemSelected: ((ShotItem) -> Void)?
    public var onAnnotateItem: ((ShotItem) -> Void)?

    @ObservedObject private var localizationManager = LocalizationManager.shared
    @State private var searchText: String = ""
    @State private var selectedIndex: Int? = 0
    @State private var shouldScrollToSelection: Bool = false
    @State private var localKeyMonitor: Any? = nil
    @State private var hostWindow: NSWindow? = nil
    @State private var copiedItemId: UUID? = nil
    @State private var showCopiedToast: Bool = false
    @State private var copyFeedbackTask: Task<Void, Never>? = nil
    @State private var showDeletedToast: Bool = false
    @State private var deleteFeedbackTask: Task<Void, Never>? = nil
    @State private var showClearedToast: Bool = false
    @State private var clearFeedbackTask: Task<Void, Never>? = nil

    public init(
        storageManager: StorageManager,
        appSettings: AppSettings? = nil,
        updateManager: UpdateManager = UpdateManager.shared,
        autoPasteService: any AutoPasteServicing = AutoPasteService.shared,
        previousAppTracker: any PreviousAppTracking = PreviousAppTracker.shared,
        onDismiss: (() -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil,
        onTriggerRegionCapture: (() -> Void)? = nil,
        onTriggerScrollingCapture: (() -> Void)? = nil,
        onItemSelected: ((ShotItem) -> Void)? = nil,
        onAnnotateItem: ((ShotItem) -> Void)? = nil
    ) {
        self.storageManager = storageManager
        self.appSettings = appSettings
        self.updateManager = updateManager
        self.autoPasteService = autoPasteService
        self.previousAppTracker = previousAppTracker
        self.onDismiss = onDismiss
        self.onOpenSettings = onOpenSettings
        self.onCaptureRegion = onTriggerRegionCapture
        self.onScrollingCapture = onTriggerScrollingCapture
        self.onItemSelected = onItemSelected
        self.onAnnotateItem = onAnnotateItem
    }

    // MARK: - Partitioned & Filtered Items

    public var filteredItems: [ShotItem] {
        storageManager.search(query: searchText)
    }

    public var pinnedItems: [ShotItem] {
        filteredItems.filter { $0.isPinned }
    }

    public var recentItems: [ShotItem] {
        filteredItems.filter { !$0.isPinned }
    }

    public var visibleItems: [ShotItem] {
        pinnedItems + recentItems
    }

    public var selectedItemId: UUID? {
        guard let idx = selectedIndex, idx >= 0 && idx < visibleItems.count else { return nil }
        return visibleItems[idx].id
    }

    // MARK: - Body View

    public var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    headerBar
                    searchBarSection
                    if updateManager.shouldShowBanner {
                        updateBannerView
                    }
                    Divider().opacity(0.6)
                    contentSection(scrollProxy: proxy)
                    if !visibleItems.isEmpty {
                        Divider().opacity(0.4)
                        footerHintBar
                    }
                }

                if showCopiedToast {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 11, weight: .semibold))
                        Text(localizationManager.tr(.copiedToClipboard))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color(nsColor: .windowBackgroundColor))
                            .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.green.opacity(0.4), lineWidth: 1)
                    )
                    .padding(.bottom, 12)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.85).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .zIndex(100)
                }

                if showDeletedToast {
                    HStack(spacing: 6) {
                        Image(systemName: "trash.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 11, weight: .semibold))
                        Text(localizationManager.tr(.screenshotDeleted))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color(nsColor: .windowBackgroundColor))
                            .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.red.opacity(0.4), lineWidth: 1)
                    )
                    .padding(.bottom, 12)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.85).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .zIndex(100)
                }

                if showClearedToast {
                    HStack(spacing: 6) {
                        Image(systemName: "trash.slash.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 11, weight: .semibold))
                        Text(localizationManager.tr(.unpinnedHistoryCleared))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color(nsColor: .windowBackgroundColor))
                            .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                    )
                    .padding(.bottom, 12)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.85).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .zIndex(100)
                }
            }
            .frame(width: 380, height: 560)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .background(WindowAccessor { win in self.hostWindow = win })
            .onAppear {
                ThumbnailHoverPreviewPanel.shared.storageManager = storageManager
                installKeyboardMonitor()
                resetSelection(scrollProxy: proxy)
            }
            .onDisappear {
                ThumbnailHoverPreviewPanel.shared.hide(immediate: true)
                removeKeyboardMonitor()
            }
            .onChange(of: searchText) { _ in
                resetSelection(scrollProxy: proxy)
            }
            .onChange(of: storageManager.items) { _ in
                resetSelection(scrollProxy: proxy)
            }
            .onChange(of: selectedIndex) { newIndex in
                guard shouldScrollToSelection else { return }
                if let idx = newIndex, idx >= 0 && idx < visibleItems.count {
                    let targetID = visibleItems[idx].id
                    withAnimation(.easeInOut(duration: 0.12)) {
                        proxy.scrollTo(targetID, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.accentColor)

            Text(localizationManager.tr(.appTitle))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()

            // Quick Region Capture Button
            Button(action: {
                onDismiss?()
                onCaptureRegion?()
            }) {
                Image(systemName: "crop")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help("\(localizationManager.tr(.menuCapture)) (\(HotKeyManager.shared.shortcut(for: .captureRegion)?.displayString ?? "⌥S"))")

            // Quick Scrolling Capture Button
            Button(action: {
                onDismiss?()
                onScrollingCapture?()
            }) {
                Image(systemName: "arrow.up.and.down.text.horizontal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help("\(localizationManager.tr(.menuScrollingCapture)) (\(HotKeyManager.shared.shortcut(for: .scrollingCapture)?.displayString ?? "⌥⇧S"))")

            // Settings Button
            Button(action: {
                onDismiss?()
                onOpenSettings?()
            }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(4)

                    if updateManager.hasPendingUpdate {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                            .offset(x: 2, y: -2)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help(localizationManager.tr(.menuPreferences))

            // Dismiss Button
            Button(action: { onDismiss?() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help(localizationManager.tr(.dismissTooltip))
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: - Search Bar Section

    private var searchBarSection: some View {
        SearchBarView(
            text: $searchText,
            placeholder: localizationManager.tr(.searchPlaceholder),
            onCommit: { handleReturnKey() }
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    // MARK: - Update Banner View

    public var updateBannerView: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .foregroundColor(.accentColor)
                .font(.system(size: 13))

            VStack(alignment: .leading, spacing: 1) {
                switch updateManager.status {
                case .readyToRestart:
                    Text(localizationManager.tr(.updateReadyRestart))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)

                case .downloading(let progress):
                    Text(localizationManager.tr(.downloadingUpdate) + (progress > 0 ? String(format: " (%.0f%%)", progress * 100) : ""))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)

                case .updateAvailable(let release):
                    let tag = release.tagName.lowercased().hasPrefix("v") ? release.tagName : "v\(release.tagName)"
                    Text(localizationManager.tr(.updateAvailable(tag)))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)

                case .error(let msg):
                    Text(msg)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.red)
                        .lineLimit(1)

                default:
                    EmptyView()
                }
            }

            Spacer()

            switch updateManager.status {
            case .readyToRestart:
                Button(action: {
                    updateManager.dismissBannerForSession()
                }) {
                    Text(localizationManager.tr(.later))
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .pointingHandCursor()

                Button(action: {
                    updateManager.restartApp()
                }) {
                    Text(localizationManager.tr(.restart))
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .pointingHandCursor()

            case .downloading:
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)

            case .updateAvailable(let release):
                Button(action: {
                    NSWorkspace.shared.open(release.htmlURL)
                }) {
                    Text(localizationManager.tr(.releaseNotes))
                        .font(.system(size: 10))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .pointingHandCursor()

                Button(action: {
                    updateManager.dismissBannerForSession()
                }) {
                    Text(localizationManager.tr(.later))
                        .font(.system(size: 10))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .pointingHandCursor()

                Button(action: {
                    updateManager.startDownloadAndInstall(release: release)
                }) {
                    Text(localizationManager.tr(.updateNow))
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .pointingHandCursor()

            case .error:
                if let release = updateManager.latestRelease {
                    Button(action: {
                        NSWorkspace.shared.open(release.htmlURL)
                    }) {
                        Text(localizationManager.tr(.releaseNotes))
                            .font(.system(size: 10))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .pointingHandCursor()
                }

                Button(action: {
                    updateManager.dismissBannerForSession()
                }) {
                    Text(localizationManager.tr(.later))
                        .font(.system(size: 10))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .pointingHandCursor()

                if let release = updateManager.latestRelease {
                    Button(action: {
                        updateManager.startDownloadAndInstall(release: release)
                    }) {
                        Text(localizationManager.tr(.updateNow))
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .pointingHandCursor()
                }

            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.12))
        .cornerRadius(6)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    // MARK: - Content Section

    @ViewBuilder
    private func contentSection(scrollProxy: ScrollViewProxy) -> some View {
        if visibleItems.isEmpty {
            if !searchText.isEmpty {
                emptySearchView
            } else {
                emptyStorageView
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if !pinnedItems.isEmpty {
                        sectionHeader(
                            title: localizationManager.tr(.pinnedSection),
                            icon: "pin.fill",
                            count: pinnedItems.count
                        )

                        ForEach(pinnedItems) { item in
                            ShotRowView(
                                item: item,
                                storageManager: storageManager,
                                shortcutIndex: ShortcutNavigator.shortcutIndex(for: item, in: visibleItems),
                                shortcutBadge: ShortcutNavigator.badgeString(for: item, pinnedItems: pinnedItems, recentItems: recentItems),
                                isSelected: item.id == selectedItemId,
                                isRecentlyCopied: item.id == copiedItemId,
                                onSelect: { selectItem($0) },
                                onCopy: { copyItem($0) },
                                onSave: { saveItem($0) },
                                onShare: { shareItem($0) },
                                onAnnotate: { annotateItem($0) },
                                onTogglePin: { storageManager.togglePin(id: $0.id) },
                                onDelete: {
                                    storageManager.deleteItem(id: $0.id)
                                    triggerDeleteFeedback()
                                },
                                onHoverChange: { hoveredItem, hovering in
                                    if hovering, let idx = visibleItems.firstIndex(where: { $0.id == hoveredItem.id }) {
                                        shouldScrollToSelection = false
                                        selectedIndex = idx
                                    }
                                }
                            )
                            .id(item.id)
                        }
                    }

                    if !recentItems.isEmpty {
                        recentSectionHeader

                        ForEach(recentItems) { item in
                            ShotRowView(
                                item: item,
                                storageManager: storageManager,
                                shortcutIndex: ShortcutNavigator.shortcutIndex(for: item, in: visibleItems),
                                shortcutBadge: ShortcutNavigator.badgeString(for: item, pinnedItems: pinnedItems, recentItems: recentItems),
                                isSelected: item.id == selectedItemId,
                                isRecentlyCopied: item.id == copiedItemId,
                                onSelect: { selectItem($0) },
                                onCopy: { copyItem($0) },
                                onSave: { saveItem($0) },
                                onShare: { shareItem($0) },
                                onAnnotate: { annotateItem($0) },
                                onTogglePin: { storageManager.togglePin(id: $0.id) },
                                onDelete: {
                                    storageManager.deleteItem(id: $0.id)
                                    triggerDeleteFeedback()
                                },
                                onHoverChange: { hoveredItem, hovering in
                                    if hovering, let idx = visibleItems.firstIndex(where: { $0.id == hoveredItem.id }) {
                                        shouldScrollToSelection = false
                                        selectedIndex = idx
                                    }
                                }
                            )
                            .id(item.id)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
    }

    private func sectionHeader(title: String, icon: String, count: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.accentColor)

            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)

            Text("\(count)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary.opacity(0.8))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color(nsColor: .quaternaryLabelColor)))

            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    private var recentSectionHeader: some View {
        HStack(spacing: 5) {
            Image(systemName: "clock")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)

            Text(localizationManager.tr(.recentSection))
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)

            Text("\(recentItems.count)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary.opacity(0.8))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color(nsColor: .quaternaryLabelColor)))

            Spacer()

            Button(action: {
                ThumbnailHoverPreviewPanel.shared.hide(immediate: true)
                storageManager.clearUnpinnedHistory()
                triggerClearAllFeedback()
                if pinnedItems.isEmpty {
                    selectedIndex = nil
                } else if let idx = selectedIndex, idx >= pinnedItems.count {
                    selectedIndex = pinnedItems.count - 1
                }
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "trash").font(.system(size: 9))
                    Text(localizationManager.tr(.clearHistory))
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.6))
                )
                .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help("\(localizationManager.tr(.clearHistory)) (⌘⇧⌫)")
        }
        .padding(.horizontal, 4)
        .padding(.top, pinnedItems.isEmpty ? 4 : 8)
        .padding(.bottom, 2)
    }

    // MARK: - Empty State Views

    private var emptySearchView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(.secondary)

            Text(localizationManager.tr(.noMatchingResults))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            Text(localizationManager.tr(.refineSearch))
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.8))

            Button(action: {
                searchText = ""
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "xmark.circle")
                    Text(localizationManager.tr(.clearSearchButton))
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.15))
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStorageView: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 30, weight: .light))
                .foregroundColor(.secondary)

            Text(localizationManager.tr(.emptyHistoryTitle))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            Text(localizationManager.tr(.emptyHistorySubtitle))
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.8))

            HStack(spacing: 8) {
                Button(action: {
                    onDismiss?()
                    onCaptureRegion?()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "camera.viewfinder")
                        Text(localizationManager.tr(.quickCaptureRegion))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accentColor.opacity(0.15))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .pointingHandCursor()

                Button(action: {
                    onDismiss?()
                    onScrollingCapture?()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.and.down.text.horizontal")
                        Text(localizationManager.tr(.quickCaptureScroll))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.12))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footerHintBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "command")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary.opacity(0.8))
            Text(localizationManager.tr(.quickSelectHint))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
    }

    // MARK: - Selection & Actions

    public func selectItem(_ item: ShotItem) {
        ThumbnailHoverPreviewPanel.shared.hide(immediate: true)
        copyItem(item)
        onDismiss?()
        onItemSelected?(item)

        let targetApp = previousAppTracker.previousApp
        let autoPasteEnabled = appSettings?.autoPasteOnSelection ?? true
        if autoPasteEnabled {
            Task {
                if let image = storageManager.loadCGImage(for: item) {
                    _ = await autoPasteService.pasteImageDirectly(image, targetApp: targetApp)
                }
            }
        }
    }

    public func copyItem(_ item: ShotItem) {
        ThumbnailHoverPreviewPanel.shared.hide(immediate: true)
        guard let data = storageManager.getImageData(for: item) else { return }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.png, .tiff], owner: nil)
        pb.setData(data, forType: .png)
        if let img = NSImage(data: data), let tiff = img.tiffRepresentation {
            pb.setData(tiff, forType: .tiff)
        }

        triggerCopyFeedback(for: item.id)
    }

    public func triggerCopyFeedback(for itemId: UUID) {
        copyFeedbackTask?.cancel()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            copiedItemId = itemId
            showCopiedToast = true
        }
        copyFeedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if self.copiedItemId == itemId {
                        self.copiedItemId = nil
                    }
                    self.showCopiedToast = false
                }
            }
        }
    }

    public func triggerDeleteFeedback() {
        deleteFeedbackTask?.cancel()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            showDeletedToast = true
        }
        deleteFeedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.showDeletedToast = false
                }
            }
        }
    }

    public func triggerClearAllFeedback() {
        clearFeedbackTask?.cancel()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            showClearedToast = true
        }
        clearFeedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.showClearedToast = false
                }
            }
        }
    }

    public func saveItem(_ item: ShotItem) {
        ThumbnailHoverPreviewPanel.shared.hide(immediate: true)
        guard let data = storageManager.getImageData(for: item) else { return }

        onDismiss?()

        let panel = NSSavePanel()
        panel.title = localizationManager.tr(.actionSave)
        panel.nameFieldStringValue = "Screenshot_\(item.id.uuidString.prefix(8)).png"
        panel.allowedContentTypes = [.png, .jpeg]
        panel.canCreateDirectories = true

        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            if response == .OK, let destinationURL = panel.url {
                try? data.write(to: destinationURL, options: .atomic)
            }
        }
    }

    public func shareItem(_ item: ShotItem, from view: NSView? = nil) {
        ThumbnailHoverPreviewPanel.shared.hide(immediate: true)
        let url = storageManager.getImageURL(for: item)
        let picker = NSSharingServicePicker(items: [url])
        let targetView = view ?? hostWindow?.contentView ?? NSApp.keyWindow?.contentView
        if let target = targetView {
            picker.show(relativeTo: target.bounds, of: target, preferredEdge: .minY)
        }
    }

    public func annotateItem(_ item: ShotItem) {
        ThumbnailHoverPreviewPanel.shared.hide(immediate: true)
        onDismiss?()
        if let onAnnotate = onAnnotateItem {
            onAnnotate(item)
        } else if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.openInAnnotationWindow(item: item)
        } else if let cgImage = storageManager.loadCGImage(for: item) {
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            (NSApp.delegate as? AppDelegate)?.presentScrollableAnnotationWindow(image: cgImage, scale: scale)
        }
    }

    private func resetSelection(scrollProxy: ScrollViewProxy? = nil) {
        let count = visibleItems.count
        selectedIndex = count > 0 ? 0 : nil
        if count > 0, let firstID = visibleItems.first?.id {
            withAnimation(.easeInOut(duration: 0.12)) {
                scrollProxy?.scrollTo(firstID, anchor: .center)
            }
        }
    }

    public func focusSearchField() {
        NotificationCenter.default.post(name: Notification.Name("SuperShotFocusSearchField"), object: nil)
    }

    private func handleReturnKey() {
        if let idx = selectedIndex, idx >= 0 && idx < visibleItems.count {
            selectItem(visibleItems[idx])
        }
    }

    private func installKeyboardMonitor() {
        removeKeyboardMonitor()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if let host = hostWindow {
                guard let eventWin = event.window, eventWin === host, host.isKeyWindow else { return event }
            }

            let targetWin = hostWindow ?? NSApp.keyWindow
            let hasMarkedText = (targetWin?.firstResponder as? NSTextView)?.hasMarkedText() ?? false
            let isSearchFocused = (hostWindow?.firstResponder is NSTextView)
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // 1. Escape: Clear search query first if populated, otherwise dismiss popover
            if event.keyCode == 53 {
                if !searchText.isEmpty {
                    searchText = ""
                    return nil
                }
                ThumbnailHoverPreviewPanel.shared.hide(immediate: true)
                onDismiss?()
                return nil
            }

            // 1b. Cmd+F or Slash (44 / "/"): Focus search field
            if (!isSearchFocused && flags.isEmpty && (event.keyCode == 44 || event.characters == "/" || event.charactersIgnoringModifiers == "/")) ||
               (flags == .command && (event.keyCode == 3 || event.charactersIgnoringModifiers?.lowercased() == "f")) {
                NotificationCenter.default.post(name: Notification.Name("SuperShotFocusSearchField"), object: nil)
                return nil
            }

            // 2. Spacebar (49): Toggle Quick Look hover preview when search field is not focused
            if event.keyCode == 49 && !isSearchFocused && flags.isEmpty {
                if let idx = selectedIndex, idx >= 0 && idx < visibleItems.count {
                    let item = visibleItems[idx]
                    if ThumbnailHoverPreviewPanel.shared.isVisible {
                        ThumbnailHoverPreviewPanel.shared.hide(immediate: true)
                    } else {
                        ThumbnailHoverPreviewPanel.shared.show(for: item)
                    }
                    return nil
                }
            }

            // 2b. Home (115) or Cmd+Up: Jump to top item (yield to IME if active)
            if (event.keyCode == 115 || (flags.contains(.command) && event.keyCode == 126)) && !hasMarkedText {
                if !visibleItems.isEmpty {
                    selectedIndex = 0
                    shouldScrollToSelection = true
                    let item = visibleItems[0]
                    if ThumbnailHoverPreviewPanel.shared.isVisible {
                        ThumbnailHoverPreviewPanel.shared.show(for: item)
                    }
                    return nil
                }
            }

            // 2c. End (119) or Cmd+Down: Jump to bottom item (yield to IME if active)
            if (event.keyCode == 119 || (flags.contains(.command) && event.keyCode == 125)) && !hasMarkedText {
                if !visibleItems.isEmpty {
                    let lastIdx = visibleItems.count - 1
                    selectedIndex = lastIdx
                    shouldScrollToSelection = true
                    let item = visibleItems[lastIdx]
                    if ThumbnailHoverPreviewPanel.shared.isVisible {
                        ThumbnailHoverPreviewPanel.shared.show(for: item)
                    }
                    return nil
                }
            }

            // 2d. Page Up (116): Step backward by 5 items (yield to IME if active)
            if event.keyCode == 116 && !hasMarkedText {
                if !visibleItems.isEmpty {
                    let current = selectedIndex ?? 0
                    let newIdx = max(0, current - 5)
                    selectedIndex = newIdx
                    shouldScrollToSelection = true
                    let item = visibleItems[newIdx]
                    if ThumbnailHoverPreviewPanel.shared.isVisible {
                        ThumbnailHoverPreviewPanel.shared.show(for: item)
                    }
                    return nil
                }
            }

            // 2e. Page Down (121): Step forward by 5 items (yield to IME if active)
            if event.keyCode == 121 && !hasMarkedText {
                if !visibleItems.isEmpty {
                    let current = selectedIndex ?? 0
                    let newIdx = min(visibleItems.count - 1, current + 5)
                    selectedIndex = newIdx
                    shouldScrollToSelection = true
                    let item = visibleItems[newIdx]
                    if ThumbnailHoverPreviewPanel.shared.isVisible {
                        ThumbnailHoverPreviewPanel.shared.show(for: item)
                    }
                    return nil
                }
            }

            // 3. Down Arrow (125) - Circular cycling with live preview update (yield to IME if active)
            if event.keyCode == 125 && !flags.contains(.command) && !hasMarkedText {
                let newIdx = ShortcutNavigator.stepDown(currentIndex: selectedIndex, visibleCount: visibleItems.count)
                shouldScrollToSelection = true
                selectedIndex = newIdx
                if let idx = newIdx, idx >= 0 && idx < visibleItems.count {
                    let item = visibleItems[idx]
                    if ThumbnailHoverPreviewPanel.shared.isVisible {
                        ThumbnailHoverPreviewPanel.shared.show(for: item)
                    }
                }
                return nil
            }

            // 4. Up Arrow (126) - Circular cycling with live preview update (yield to IME if active)
            if event.keyCode == 126 && !flags.contains(.command) && !hasMarkedText {
                let newIdx = ShortcutNavigator.stepUp(currentIndex: selectedIndex, visibleCount: visibleItems.count)
                shouldScrollToSelection = true
                selectedIndex = newIdx
                if let idx = newIdx, idx >= 0 && idx < visibleItems.count {
                    let item = visibleItems[idx]
                    if ThumbnailHoverPreviewPanel.shared.isVisible {
                        ThumbnailHoverPreviewPanel.shared.show(for: item)
                    }
                }
                return nil
            }

            // 5a. Cmd+O or Cmd+Return / Keypad Enter: Reveal selected item in macOS Finder
            if flags == .command && (event.keyCode == 31 || event.charactersIgnoringModifiers?.lowercased() == "o" || event.keyCode == 36 || event.keyCode == 76) {
                if let idx = selectedIndex, idx >= 0 && idx < visibleItems.count {
                    let item = visibleItems[idx]
                    ThumbnailHoverPreviewPanel.shared.hide(immediate: true)
                    let url = storageManager.getImageURL(for: item)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    return nil
                }
            }

            // 5b. Return (36) or Keypad Enter (76): Select / copy item (yield to IME if active)
            if (event.keyCode == 36 || event.keyCode == 76) && flags.isEmpty && !hasMarkedText {
                handleReturnKey()
                return nil
            }

            // 6a. Cmd+Shift+Delete (51 or 117): Clear unpinned history
            if (event.keyCode == 51 || event.keyCode == 117) && flags.contains([.command, .shift]) && !hasMarkedText {
                if !recentItems.isEmpty {
                    ThumbnailHoverPreviewPanel.shared.hide(immediate: true)
                    storageManager.clearUnpinnedHistory()
                    triggerClearAllFeedback()
                    if pinnedItems.isEmpty {
                        selectedIndex = nil
                    } else if let idx = selectedIndex, idx >= pinnedItems.count {
                        selectedIndex = pinnedItems.count - 1
                    }
                    return nil
                }
            }

            // 6b. Delete (51) / Forward Delete (117): Remove selected history item
            if (event.keyCode == 51 || event.keyCode == 117) && !flags.contains(.shift) && (!isSearchFocused || flags.contains(.command)) && !hasMarkedText {
                if let idx = selectedIndex, idx >= 0 && idx < visibleItems.count {
                    let item = visibleItems[idx]
                    ThumbnailHoverPreviewPanel.shared.hide(immediate: true)
                    storageManager.deleteItem(id: item.id)
                    triggerDeleteFeedback()
                    if visibleItems.count > 1 {
                        selectedIndex = min(idx, visibleItems.count - 2)
                    } else {
                        selectedIndex = nil
                    }
                    return nil
                }
            }

            // 7. Cmd+P: Toggle Pin on selected item
            if flags == .command && (event.keyCode == 35 || event.charactersIgnoringModifiers?.lowercased() == "p") {
                if let idx = selectedIndex, idx >= 0 && idx < visibleItems.count {
                    storageManager.togglePin(id: visibleItems[idx].id)
                    return nil
                }
            }

            // 8. Cmd+S: Save selected item to file
            if flags == .command && (event.keyCode == 1 || event.charactersIgnoringModifiers?.lowercased() == "s") {
                if let idx = selectedIndex, idx >= 0 && idx < visibleItems.count {
                    saveItem(visibleItems[idx])
                    return nil
                }
            }

            // 8b. Cmd+E: Share selected item
            if flags == .command && (event.keyCode == 14 || event.charactersIgnoringModifiers?.lowercased() == "e") {
                if let idx = selectedIndex, idx >= 0 && idx < visibleItems.count {
                    shareItem(visibleItems[idx])
                    return nil
                }
            }

            // 9. Cmd+C: Copy selected item to clipboard without auto-paste
            if flags == .command && (event.keyCode == 8 || event.charactersIgnoringModifiers?.lowercased() == "c") {
                if let idx = selectedIndex, idx >= 0 && idx < visibleItems.count {
                    copyItem(visibleItems[idx])
                    return nil
                }
            }

            // 10. Differentiated Section Shortcuts (⌥1..⌥9 Pinned, 1..9 / ⌘1..⌘9 Recent)
            if let resolved = ShortcutNavigator.parseSectionShortcut(from: event, searchFieldHasFocus: isSearchFocused) {
                if let target = ShortcutNavigator.targetItem(forSectionShortcut: resolved, pinnedItems: pinnedItems, recentItems: recentItems) {
                    selectItem(target)
                    return nil
                }
            } else if let digit = ShortcutNavigator.parseShortcut(from: event, searchFieldHasFocus: isSearchFocused) {
                if let target = ShortcutNavigator.targetItem(forShortcut: digit, in: visibleItems) {
                    selectItem(target)
                    return nil
                }
            }

            return event
        }
    }

    private func removeKeyboardMonitor() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }
}
