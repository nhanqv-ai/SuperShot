import SwiftUI
import AppKit
import SuperShotCore

/// MainShotView is the root SwiftUI container for the Screenshot History Popover.
public struct MainShotView: View {
    @ObservedObject public var storageManager: StorageManager
    public var appSettings: AppSettings?
    public var autoPasteService: any AutoPasteServicing
    public var previousAppTracker: any PreviousAppTracking
    public var onCaptureRegion: (() -> Void)?
    public var onScrollingCapture: (() -> Void)?
    public var onOpenSettings: (() -> Void)?
    public var onDismiss: (() -> Void)?
    public var onItemSelected: ((ShotItem) -> Void)?

    @ObservedObject private var localizationManager = LocalizationManager.shared
    @State private var searchText: String = ""
    @State private var selectedIndex: Int? = 0
    @State private var localKeyMonitor: Any? = nil
    @State private var hostWindow: NSWindow? = nil

    public init(
        storageManager: StorageManager,
        appSettings: AppSettings? = nil,
        autoPasteService: any AutoPasteServicing = AutoPasteService.shared,
        previousAppTracker: any PreviousAppTracking = PreviousAppTracker.shared,
        onDismiss: (() -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil,
        onTriggerRegionCapture: (() -> Void)? = nil,
        onTriggerScrollingCapture: (() -> Void)? = nil,
        onItemSelected: ((ShotItem) -> Void)? = nil
    ) {
        self.storageManager = storageManager
        self.appSettings = appSettings
        self.autoPasteService = autoPasteService
        self.previousAppTracker = previousAppTracker
        self.onDismiss = onDismiss
        self.onOpenSettings = onOpenSettings
        self.onCaptureRegion = onTriggerRegionCapture
        self.onScrollingCapture = onTriggerScrollingCapture
        self.onItemSelected = onItemSelected
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
            VStack(spacing: 0) {
                headerBar
                searchBarSection
                Divider().opacity(0.6)
                contentSection(scrollProxy: proxy)
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
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help(localizationManager.tr(.menuCapture) + " (Option+S)")

            // Quick Scrolling Capture Button
            Button(action: {
                onDismiss?()
                onScrollingCapture?()
            }) {
                Image(systemName: "arrow.up.and.down.text.horizontal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help(localizationManager.tr(.menuScrollingCapture) + " (Option+Shift+S)")

            // Settings Button
            Button(action: {
                onDismiss?()
                onOpenSettings?()
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(4)
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
                                isSelected: item.id == selectedItemId,
                                onSelect: { selectItem($0) },
                                onCopy: { copyItem($0) },
                                onSave: { saveItem($0) },
                                onTogglePin: { storageManager.togglePin(id: $0.id) },
                                onDelete: { storageManager.deleteItem(id: $0.id) }
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
                                isSelected: item.id == selectedItemId,
                                onSelect: { selectItem($0) },
                                onCopy: { copyItem($0) },
                                onSave: { saveItem($0) },
                                onTogglePin: { storageManager.togglePin(id: $0.id) },
                                onDelete: { storageManager.deleteItem(id: $0.id) }
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
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func resetSelection(scrollProxy: ScrollViewProxy? = nil) {
        let count = visibleItems.count
        selectedIndex = count > 0 ? 0 : nil
        if count > 0, let firstID = visibleItems.first?.id {
            withAnimation(.easeInOut(duration: 0.12)) {
                scrollProxy?.scrollTo(firstID, anchor: .center)
            }
        }
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

            // Escape
            if event.keyCode == 53 {
                onDismiss?()
                return nil
            }

            // Down Arrow (125) - Circular cycling
            if event.keyCode == 125 {
                selectedIndex = ShortcutNavigator.stepDown(currentIndex: selectedIndex, visibleCount: visibleItems.count)
                return nil
            }

            // Up Arrow (126) - Circular cycling
            if event.keyCode == 126 {
                selectedIndex = ShortcutNavigator.stepUp(currentIndex: selectedIndex, visibleCount: visibleItems.count)
                return nil
            }

            // Return (36) or Keypad Enter (76)
            if event.keyCode == 36 || event.keyCode == 76 {
                handleReturnKey()
                return nil
            }

            // 1..9 shortcuts
            let isSearchFocused = (hostWindow?.firstResponder is NSTextView)
            if let digit = ShortcutNavigator.parseShortcut(from: event, searchFieldHasFocus: isSearchFocused) {
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
