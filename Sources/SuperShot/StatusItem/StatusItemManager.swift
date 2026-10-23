import AppKit
import Carbon
import Combine
import SuperShotCore

/// StatusItemManager manages the macOS menu bar status item, attached NSPopover,
/// secondary context menu, and coordinates with capture engines and settings.
public final class StatusItemManager: NSObject, NSPopoverDelegate, NSMenuDelegate {
    // MARK: - Properties

    public private(set) var statusItem: NSStatusItem
    public private(set) var popover: NSPopover

    public var hotKeyManager: any HotKeyManaging
    public var previousAppTracker: any PreviousAppTracking
    public weak var storageManager: StorageManager?
    public weak var appSettings: AppSettings?

    // Action callbacks
    public var onRegionCaptureRequested: (() -> Void)?
    public var onScrollingCaptureRequested: (() -> Void)?
    public var onOpenSettingsRequested: (() -> Void)?
    public var onClearHistoryRequested: (() -> Void)?
    public var onCheckForUpdatesRequested: (() -> Void)?
    public var onPopoverVisibilityChanged: ((Bool) -> Void)?

    private var escapeMonitor: Any?
    private var outsideClickMonitor: Any?
    private var lastPopoverCloseTimestamp: TimeInterval = 0

    // MARK: - Context Menu

    public private(set) lazy var contextMenu: NSMenu = {
        let menu = NSMenu(title: "SuperShot")
        menu.delegate = self

        // 1. Take Screenshot (Option+S)
        let captureItem = NSMenuItem(
            title: LocalizationManager.shared.tr(.menuCapture),
            action: #selector(captureRegionMenuItemClicked(_:)),
            keyEquivalent: "s"
        )
        captureItem.keyEquivalentModifierMask = [.option]
        captureItem.target = self
        captureItem.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)
        menu.addItem(captureItem)

        // 2. Scrolling Screenshot (Option+Shift+S)
        let scrollItem = NSMenuItem(
            title: LocalizationManager.shared.tr(.menuScrollingCapture),
            action: #selector(scrollingCaptureMenuItemClicked(_:)),
            keyEquivalent: "s"
        )
        scrollItem.keyEquivalentModifierMask = [.option, .shift]
        scrollItem.target = self
        scrollItem.image = NSImage(systemSymbolName: "arrow.up.and.down.text.horizontal", accessibilityDescription: nil)
        menu.addItem(scrollItem)

        // 3. Show History
        let showHistoryItem = NSMenuItem(
            title: LocalizationManager.shared.tr(.menuShowHistory),
            action: #selector(showHistoryMenuItemClicked(_:)),
            keyEquivalent: ""
        )
        showHistoryItem.target = self
        showHistoryItem.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        menu.addItem(showHistoryItem)

        // 4. Preferences... (Cmd+,)
        let settingsItem = NSMenuItem(
            title: LocalizationManager.shared.tr(.menuPreferences),
            action: #selector(settingsMenuItemClicked(_:)),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // 5. Clear Unpinned History
        let clearItem = NSMenuItem(
            title: LocalizationManager.shared.tr(.menuClearHistory),
            action: #selector(clearHistoryMenuItemClicked(_:)),
            keyEquivalent: ""
        )
        clearItem.target = self
        clearItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        menu.addItem(clearItem)

        // 6. Welcome & Quick Guide
        let welcomeItem = NSMenuItem(
            title: LocalizationManager.shared.tr(.welcomeGuideButton),
            action: #selector(welcomeGuideMenuItemClicked(_:)),
            keyEquivalent: ""
        )
        welcomeItem.target = self
        welcomeItem.image = NSImage(systemSymbolName: "book.pages", accessibilityDescription: nil)
        menu.addItem(welcomeItem)

        // 7. Check for Updates...
        let updateItem = NSMenuItem(
            title: LocalizationManager.shared.tr(.menuCheckUpdates),
            action: #selector(checkUpdatesMenuItemClicked(_:)),
            keyEquivalent: ""
        )
        updateItem.target = self
        updateItem.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        // 7. Quit SuperShot (Cmd+Q)
        let quitItem = NSMenuItem(
            title: LocalizationManager.shared.tr(.menuQuit),
            action: #selector(quitMenuItemClicked(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)

        return menu
    }()

    // MARK: - Initialization

    public init(
        contentViewController: NSViewController? = nil,
        storageManager: StorageManager? = nil,
        appSettings: AppSettings? = nil,
        hotKeyManager: any HotKeyManaging = HotKeyManager.shared,
        previousAppTracker: any PreviousAppTracking = PreviousAppTracker.shared
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        self.storageManager = storageManager
        self.appSettings = appSettings
        self.hotKeyManager = hotKeyManager
        self.previousAppTracker = previousAppTracker

        super.init()

        setupStatusItem()
        setupPopover(contentViewController: contentViewController)
    }

    // MARK: - Status Item Setup

    private func setupStatusItem() {
        guard let button = statusItem.button else { return }

        let icon = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "SuperShot")
        icon?.isTemplate = true

        button.image = icon
        button.imagePosition = .imageOnly
        button.toolTip = "SuperShot - Screenshot & Annotate (Option+S)"
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    // MARK: - Popover Setup

    public func setupPopover(contentViewController: NSViewController?) {
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self

        if let vc = contentViewController {
            setContentViewController(vc)
        }
    }

    public func setContentViewController(_ vc: NSViewController) {
        popover.contentViewController = vc
        let prefSize = vc.preferredContentSize
        popover.contentSize = prefSize.width > 0 && prefSize.height > 0
            ? prefSize
            : NSSize(width: 380, height: 560)
    }

    // MARK: - Status Item Action Handling

    @objc public func statusItemClicked(_ sender: Any?) {
        previousAppTracker.captureFrontmostApplication()

        let event = NSApp.currentEvent
        let isRightClick = (event?.type == .rightMouseUp) ||
            ((event?.type == .leftMouseUp) && (event?.modifierFlags.contains(.control) == true))

        if isRightClick {
            showContextMenu()
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        if popover.isShown {
            dismissPopover()
        } else {
            // Debounce transient popover re-opening
            if now - lastPopoverCloseTimestamp < 0.25 {
                return
            }
            showPopover()
        }
    }

    // MARK: - Context Menu Presentation

    public func showContextMenu() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.showContextMenu() }
            return
        }

        dismissPopover()
        guard let button = statusItem.button else { return }

        statusItem.menu = contextMenu
        button.performClick(nil)
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu == contextMenu, menu.items.count >= 9 else { return }
        menu.items[0].title = LocalizationManager.shared.tr(.menuCapture)
        menu.items[1].title = LocalizationManager.shared.tr(.menuScrollingCapture)
        menu.items[2].title = LocalizationManager.shared.tr(.menuShowHistory)
        menu.items[3].title = LocalizationManager.shared.tr(.menuPreferences)
        menu.items[5].title = LocalizationManager.shared.tr(.menuClearHistory)
        menu.items[6].title = LocalizationManager.shared.tr(.menuCheckUpdates)
        menu.items[8].title = LocalizationManager.shared.tr(.menuQuit)
    }

    public func menuDidClose(_ menu: NSMenu) {
        if menu == contextMenu {
            statusItem.menu = nil
        }
    }

    // MARK: - Context Menu Actions

    @objc public func captureRegionMenuItemClicked(_ sender: Any?) {
        dismissPopover()
        onRegionCaptureRequested?()
    }

    @objc public func scrollingCaptureMenuItemClicked(_ sender: Any?) {
        dismissPopover()
        onScrollingCaptureRequested?()
    }

    @objc public func showHistoryMenuItemClicked(_ sender: Any?) {
        showPopover()
    }

    @objc public func settingsMenuItemClicked(_ sender: Any?) {
        dismissPopover()
        onOpenSettingsRequested?()
    }

    @objc public func clearHistoryMenuItemClicked(_ sender: Any?) {
        storageManager?.clearUnpinnedHistory()
        onClearHistoryRequested?()
    }

    @objc public func welcomeGuideMenuItemClicked(_ sender: Any?) {
        dismissPopover()
        WelcomeWindowController.shared.showWelcomeWindow()
    }

    @objc public func checkUpdatesMenuItemClicked(_ sender: Any?) {
        dismissPopover()
        onCheckForUpdatesRequested?()
    }

    @objc public func quitMenuItemClicked(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    // MARK: - Popover Visibility Controls

    public func showPopover() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.showPopover() }
            return
        }

        guard let button = statusItem.button, popover.contentViewController != nil else { return }

        previousAppTracker.captureFrontmostApplication()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        installEventMonitors()

        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
        onPopoverVisibilityChanged?(true)
    }

    public func dismissPopover() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.dismissPopover() }
            return
        }

        removeEventMonitors()
        ThumbnailHoverPreviewPanel.shared.hide(immediate: true)
        guard popover.isShown else { return }

        lastPopoverCloseTimestamp = ProcessInfo.processInfo.systemUptime
        let wasAnimated = popover.animates
        popover.animates = false
        popover.close()
        popover.animates = wasAnimated

        onPopoverVisibilityChanged?(false)
    }

    public func togglePopover() {
        if popover.isShown {
            dismissPopover()
        } else {
            showPopover()
        }
    }

    // MARK: - Event Monitors (Escape & Outside Clicks)

    private func installEventMonitors() {
        removeEventMonitors()

        // 1. Local Escape monitor
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                guard let self = self, self.popover.isShown else { return event }
                self.dismissPopover()
                return nil
            }
            return event
        }

        // 2. Global Outside Click monitor
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, self.popover.isShown else { return }
            self.dismissPopover()
        }
    }

    private func removeEventMonitors() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    // MARK: - NSPopoverDelegate

    public func popoverDidShow(_ notification: Notification) {
        installEventMonitors()
        onPopoverVisibilityChanged?(true)
    }

    public func popoverDidClose(_ notification: Notification) {
        lastPopoverCloseTimestamp = ProcessInfo.processInfo.systemUptime
        removeEventMonitors()
        onPopoverVisibilityChanged?(false)
    }

    deinit {
        removeEventMonitors()
        NSStatusBar.system.removeStatusItem(statusItem)
    }
}
