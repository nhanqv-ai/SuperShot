import AppKit
import SwiftUI
import SuperShotCore

public final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    public static var shared: SettingsWindowController?

    public let appSettings: AppSettings
    public let storageManager: StorageManager
    public let hotKeyManager: any HotKeyManaging
    public let autoPasteService: any AutoPasteServicing
    public let launchAtLoginManager: any LaunchAtLoginManaging
    public let permissionManager: any PermissionManaging

    public var onPresentationDismissalRequested: (() -> Void)?

    private var hasBeenCentered: Bool = false

    public init(
        appSettings: AppSettings,
        storageManager: StorageManager,
        hotKeyManager: any HotKeyManaging = HotKeyManager.shared,
        autoPasteService: any AutoPasteServicing = AutoPasteService.shared,
        launchAtLoginManager: any LaunchAtLoginManaging = LaunchAtLoginManager.shared,
        permissionManager: any PermissionManaging = PermissionManager.shared,
        onPresentationDismissalRequested: (() -> Void)? = nil
    ) {
        self.appSettings = appSettings
        self.storageManager = storageManager
        self.hotKeyManager = hotKeyManager
        self.autoPasteService = autoPasteService
        self.launchAtLoginManager = launchAtLoginManager
        self.permissionManager = permissionManager
        self.onPresentationDismissalRequested = onPresentationDismissalRequested

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 530),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "SuperShot Preferences"
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.setContentSize(NSSize(width: 520, height: 530))
        window.setFrameAutosaveName("SuperShotSettingsWindow")

        super.init(window: window)
        window.delegate = self
        setupContentView()
    }

    public convenience init(
        appSettings: AppSettings,
        storageManager: StorageManager,
        hotKeyManager: any HotKeyManaging = HotKeyManager.shared,
        autoPasteService: any AutoPasteServicing = AutoPasteService.shared,
        onDismiss: (() -> Void)? = nil
    ) {
        self.init(
            appSettings: appSettings,
            storageManager: storageManager,
            hotKeyManager: hotKeyManager,
            autoPasteService: autoPasteService,
            launchAtLoginManager: LaunchAtLoginManager.shared,
            permissionManager: PermissionManager.shared,
            onPresentationDismissalRequested: onDismiss
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func setupContentView(initialTab: SettingsTab = .general) {
        guard let window = self.window else { return }

        let settingsView = SettingsView(
            appSettings: appSettings,
            storageManager: storageManager,
            hotKeyManager: hotKeyManager,
            launchAtLoginManager: launchAtLoginManager,
            autoPasteService: autoPasteService,
            permissionManager: permissionManager,
            initialTab: initialTab,
            onClose: { [weak self] in
                self?.close()
            }
        )
        let hostingController = NSHostingController(rootView: settingsView)
        hostingController.preferredContentSize = NSSize(width: 520, height: 530)
        window.contentViewController = hostingController
    }

    public func showSettings(tab: SettingsTab = .general) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.showSettings(tab: tab)
            }
            return
        }

        onPresentationDismissalRequested?()
        setupContentView(initialTab: tab)

        guard let window = self.window else { return }

        if !hasBeenCentered && !window.isVisible {
            window.center()
            hasBeenCentered = true
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    public func windowWillClose(_ notification: Notification) {
        setupContentView()
    }
}
