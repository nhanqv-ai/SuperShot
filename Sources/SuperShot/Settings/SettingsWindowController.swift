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

        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 565),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = LocalizationManager.shared.tr(.menuPreferences)
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.setContentSize(NSSize(width: 520, height: 565))
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
        hostingController.preferredContentSize = NSSize(width: 520, height: 565)
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
        if window?.contentViewController == nil {
            setupContentView(initialTab: tab)
        } else {
            NotificationCenter.default.post(name: .settingsSelectTab, object: tab)
        }

        guard let window = self.window else { return }
        window.title = LocalizationManager.shared.tr(.menuPreferences)

        if !hasBeenCentered && !window.isVisible {
            window.center()
            hasBeenCentered = true
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    public func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.post(name: .settingsSelectTab, object: SettingsTab.general)
    }
}

// MARK: - Settings Window with Keyboard Navigation & Escape Key Dismissal

private final class SettingsWindow: NSWindow {
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            close()
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command && (event.keyCode == 13 || event.charactersIgnoringModifiers?.lowercased() == "w") {
            close()
            return
        }
        if flags == .command,
           let chars = event.charactersIgnoringModifiers,
           let firstChar = chars.first,
           let digit = Int(String(firstChar)),
           digit >= 1 && digit <= SettingsTab.allCases.count {
            let tab = SettingsTab.allCases[digit - 1]
            NotificationCenter.default.post(name: .settingsSelectTab, object: tab, userInfo: ["tabIndex": digit - 1])
            return
        }

        // Cmd+[ or Cmd+Shift+[ (previous tab) and Cmd+] or Cmd+Shift+] (next tab)
        if flags == .command || flags == [.command, .shift] {
            let chars = event.charactersIgnoringModifiers ?? ""
            if event.keyCode == 33 || chars == "[" {
                NotificationCenter.default.post(name: .settingsCycleTab, object: nil, userInfo: ["direction": -1])
                return
            } else if event.keyCode == 30 || chars == "]" {
                NotificationCenter.default.post(name: .settingsCycleTab, object: nil, userInfo: ["direction": 1])
                return
            }
        }

        // Standard macOS Control+Tab (next tab) and Control+Shift+Tab (previous tab)
        if (flags == .control || flags == [.control, .shift]) && event.keyCode == 48 {
            let direction = flags.contains(.shift) ? -1 : 1
            NotificationCenter.default.post(name: .settingsCycleTab, object: nil, userInfo: ["direction": direction])
            return
        }

        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}
