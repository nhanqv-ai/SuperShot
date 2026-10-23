import AppKit
import SwiftUI
import AudioToolbox
import UniformTypeIdentifiers
import SuperShotCore

public final class AppDelegate: NSObject, NSApplicationDelegate, CaptureOverlayWindowDelegate, ScrollingCaptureDelegate {
    public static var shared: AppDelegate?

    // Core Managers & Services
    public var storageManager: StorageManager!
    public var appSettings: AppSettings!
    public var hotKeyManager: (any HotKeyManaging)!
    public var autoPasteService: (any AutoPasteServicing)!
    public var previousAppTracker: (any PreviousAppTracking)!
    public var statusItemManager: StatusItemManager!
    public var settingsWindowController: SettingsWindowController!

    // Active Capture Session Windows & Panels
    public var activeOverlayWindow: CaptureOverlayWindow?
    public var activeStitchedPreviewPanel: LiveStitchedPreviewPanel?
    public var activeScrollCanvasWindow: NSWindow?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        // 1. Enforce runtime menu bar accessory mode (LSUIElement safeguard)
        NSApplication.shared.setActivationPolicy(.accessory)

        // 2. Initialize Foundation Services
        storageManager = StorageManager()
        appSettings = AppSettings()
        hotKeyManager = HotKeyManager.shared
        previousAppTracker = PreviousAppTracker.shared
        autoPasteService = AutoPasteService.shared

        // 3. Initialize Settings Window Controller
        settingsWindowController = SettingsWindowController(
            appSettings: appSettings,
            storageManager: storageManager,
            hotKeyManager: hotKeyManager,
            autoPasteService: autoPasteService,
            onDismiss: { [weak self] in
                self?.statusItemManager?.dismissPopover()
            }
        )
        SettingsWindowController.shared = settingsWindowController

        // 4. Initialize History Popover & Status Item Manager
        let mainShotView = MainShotView(
            storageManager: storageManager,
            appSettings: appSettings,
            autoPasteService: autoPasteService,
            previousAppTracker: previousAppTracker,
            onDismiss: { [weak self] in
                self?.statusItemManager?.dismissPopover()
            },
            onOpenSettings: { [weak self] in
                self?.openSettings()
            },
            onTriggerRegionCapture: { [weak self] in
                self?.triggerRegionCapture()
            },
            onTriggerScrollingCapture: { [weak self] in
                self?.triggerScrollingCapture()
            }
        )

        let popoverVC = NSHostingController(rootView: mainShotView)
        popoverVC.preferredContentSize = NSSize(width: 380, height: 600)

        statusItemManager = StatusItemManager(
            contentViewController: popoverVC,
            storageManager: storageManager,
            appSettings: appSettings,
            hotKeyManager: hotKeyManager,
            previousAppTracker: previousAppTracker
        )

        statusItemManager.onRegionCaptureRequested = { [weak self] in
            self?.triggerRegionCapture()
        }
        statusItemManager.onScrollingCaptureRequested = { [weak self] in
            self?.triggerScrollingCapture()
        }
        statusItemManager.onOpenSettingsRequested = { [weak self] in
            self?.openSettings()
        }
        statusItemManager.onClearHistoryRequested = { [weak self] in
            self?.storageManager.clearUnpinnedHistory()
        }

        // 5. Register Global Carbon Hotkeys
        setupHotKeys()
    }

    // MARK: - HotKey Setup & Dispatch

    private func setupHotKeys() {
        hotKeyManager.onAction = { [weak self] action in
            guard let self = self else { return }
            switch action {
            case .inPlaceCapture:
                self.triggerRegionCapture()
            case .scrollingCapture:
                self.triggerScrollingCapture()
            }
        }
        hotKeyManager.registerDefaults()
    }

    // MARK: - Capture Triggers

    public func triggerRegionCapture() {
        previousAppTracker.captureFrontmostApplication()
        statusItemManager?.dismissPopover()

        let mouseLocation = NSEvent.mouseLocation
        guard let capturedScreen = ScreenCaptureManager.shared.captureScreen(at: mouseLocation)
                ?? ScreenCaptureManager.shared.captureMainScreen() else {
            NSLog("SuperShot: Failed to capture screen bitmap. Check Screen Recording permissions.")
            return
        }

        // Close any existing overlay
        activeOverlayWindow?.close()

        let overlay = CaptureOverlayWindow(capturedScreen: capturedScreen)
        overlay.captureDelegate = self
        self.activeOverlayWindow = overlay

        overlay.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func triggerScrollingCapture() {
        previousAppTracker.captureFrontmostApplication()
        statusItemManager?.dismissPopover()

        let mouseLocation = NSEvent.mouseLocation
        let display = ScreenCaptureManager.shared.provider.display(containing: mouseLocation)
            ?? ScreenCaptureManager.shared.provider.availableDisplays().first
        guard let targetDisplay = display else { return }

        // Start scrolling capture on active screen or center region
        let defaultRect = CGRect(
            x: targetDisplay.cocoaFrame.midX - 400,
            y: targetDisplay.cocoaFrame.midY - 300,
            width: 800,
            height: 600
        )
        startScrollingCapture(selectionRect: defaultRect, display: targetDisplay)
    }

    public func startScrollingCapture(selectionRect: CGRect, display: CaptureDisplayInfo) {
        activeOverlayWindow?.close()
        activeOverlayWindow = nil

        let panel = LiveStitchedPreviewPanel(
            captureManager: ScrollingCaptureManager.shared,
            screenFrame: display.cocoaFrame,
            selectionRect: selectionRect
        )
        panel.onFinished = { [weak self] image, _, _ in
            self?.activeStitchedPreviewPanel?.close()
            self?.activeStitchedPreviewPanel = nil
            self?.handleCaptureCompletion(
                image: image,
                captureType: .scrolling,
                sourceApp: self?.previousAppTracker.previousApp?.localizedName
            )
        }
        panel.onCancelled = { [weak self] in
            self?.activeStitchedPreviewPanel?.close()
            self?.activeStitchedPreviewPanel = nil
        }
        panel.orderFront(nil)
        self.activeStitchedPreviewPanel = panel

        ScrollingCaptureManager.shared.delegate = panel
        _ = ScrollingCaptureManager.shared.startSession(
            selectionRect: selectionRect,
            displayInfo: display,
            mode: .auto
        )
    }

    // MARK: - CaptureOverlayWindowDelegate

    public func overlayDidCancel() {
        activeOverlayWindow?.close()
        activeOverlayWindow = nil
    }

    public func overlayDidConfirmSelection(rect: CGRect, display: CaptureDisplayInfo) {
        guard let overlay = activeOverlayWindow else { return }
        let fullImage = overlay.capturedScreen.fullImage
        let windowSize = overlay.frame.size
        let scale = display.scaleFactor

        let croppedImage = ScreenCaptureManager.cropImage(
            fullImage,
            selectionInWindow: rect,
            windowSize: windowSize,
            scaleFactor: scale
        ) ?? fullImage

        handleCaptureCompletion(
            image: croppedImage,
            captureType: .region,
            sourceApp: previousAppTracker.previousApp?.localizedName
        )
        overlay.close()
        activeOverlayWindow = nil
    }

    public func overlayDidTriggerSave(rect: CGRect, display: CaptureDisplayInfo) {
        guard let overlay = activeOverlayWindow else { return }
        let fullImage = overlay.capturedScreen.fullImage
        let windowSize = overlay.frame.size
        let scale = display.scaleFactor

        let croppedImage = ScreenCaptureManager.cropImage(
            fullImage,
            selectionInWindow: rect,
            windowSize: windowSize,
            scaleFactor: scale
        ) ?? fullImage

        saveImageToFile(croppedImage)
        handleCaptureCompletion(
            image: croppedImage,
            captureType: .region,
            sourceApp: previousAppTracker.previousApp?.localizedName,
            skipClipboard: true
        )
        overlay.close()
        activeOverlayWindow = nil
    }

    public func overlayDidTriggerScroll(rect: CGRect, display: CaptureDisplayInfo) {
        startScrollingCapture(selectionRect: rect, display: display)
    }

    // MARK: - ScrollingCaptureDelegate

    public func scrollingCaptureDidUpdate(progress: ScrollingProgress, previewImage: CGImage?) {
        DispatchQueue.main.async { [weak self] in
            self?.activeStitchedPreviewPanel?.scrollingCaptureDidUpdate(progress: progress, previewImage: previewImage)
        }
    }

    public func scrollingCaptureDidFinish(image: CGImage, totalHeight: CGFloat, reason: ScrollingCaptureStopReason) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.activeStitchedPreviewPanel?.close()
            self.activeStitchedPreviewPanel = nil

            self.handleCaptureCompletion(
                image: image,
                captureType: .scrolling,
                sourceApp: self.previousAppTracker.previousApp?.localizedName
            )
        }
    }

    public func scrollingCaptureDidCancel() {
        DispatchQueue.main.async { [weak self] in
            self?.activeStitchedPreviewPanel?.close()
            self?.activeStitchedPreviewPanel = nil
        }
    }

    public func scrollingCaptureDidFail(error: String) {
        DispatchQueue.main.async { [weak self] in
            self?.activeStitchedPreviewPanel?.close()
            self?.activeStitchedPreviewPanel = nil
            NSLog("SuperShot: Scrolling capture failed: \(error)")
        }
    }

    // MARK: - Completion Pipeline: Storage, Clipboard, Auto-Paste & Audio

    public func handleCaptureCompletion(
        image: CGImage,
        captureType: ShotCaptureType,
        sourceApp: String?,
        skipClipboard: Bool = false
    ) {
        // 1. Persist to StorageManager and update history
        let savedItem = try? storageManager.save(
            image: image,
            sourceApp: sourceApp,
            captureType: captureType,
            tags: [],
            format: appSettings.saveFormat
        )

        // 2. Auto-save to directory if configured
        if appSettings.autoSaveEnabled {
            saveImageDirectlyToAutoSaveDirectory(image: image, item: savedItem)
        }

        // 3. Write to Pasteboard unless explicitly skipped
        if !skipClipboard {
            copyImageToPasteboard(image)

            // 4. Direct Auto-Paste if enabled & permissions granted
            if appSettings.autoPasteOnSelection && autoPasteService.isAccessibilityTrusted {
                let target = previousAppTracker.previousApp
                _ = autoPasteService.pasteToActiveApp(targetApp: target, delay: 0.035, promptIfUntrusted: false, completion: nil)
            }
        }

        // 5. Auditory Feedback
        playCaptureSound()
    }

    public func copyImageToPasteboard(_ image: CGImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let rep = NSBitmapImageRep(cgImage: image)
        if let pngData = rep.representation(using: .png, properties: [:]) {
            pb.declareTypes([.png, .tiff], owner: nil)
            pb.setData(pngData, forType: .png)
            if let nsImg = NSImage(data: pngData), let tiff = nsImg.tiffRepresentation {
                pb.setData(tiff, forType: .tiff)
            }
        }
    }

    public func saveImageToFile(_ image: CGImage) {
        if appSettings.autoSaveEnabled {
            saveImageDirectlyToAutoSaveDirectory(image: image, item: nil)
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [appSettings.saveFormat == .png ? .png : .jpeg]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH.mm.ss"
        panel.nameFieldStringValue = "SuperShot_\(formatter.string(from: Date())).\(appSettings.saveFormat == .png ? "png" : "jpg")"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                let uti = self.appSettings.saveFormat == .png ? UTType.png.identifier : UTType.jpeg.identifier
                guard let dest = CGImageDestinationCreateWithURL(url as CFURL, uti as CFString, 1, nil) else { return }
                CGImageDestinationAddImage(dest, image, nil)
                CGImageDestinationFinalize(dest)
            }
        }
    }

    private func saveImageDirectlyToAutoSaveDirectory(image: CGImage, item: ShotItem?) {
        let dir = appSettings.autoSaveDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH.mm.ss"
        let ext = appSettings.saveFormat == .png ? "png" : "jpg"
        let filename = "SuperShot_\(formatter.string(from: item?.timestamp ?? Date())).\(ext)"
        let targetURL = dir.appendingPathComponent(filename)

        let uti = appSettings.saveFormat == .png ? UTType.png.identifier : UTType.jpeg.identifier
        guard let dest = CGImageDestinationCreateWithURL(targetURL as CFURL, uti as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    private func playCaptureSound() {
        AudioServicesPlaySystemSound(1108)
    }

    public func openSettings() {
        statusItemManager?.dismissPopover()
        settingsWindowController?.showSettings()
    }

    // MARK: - Lifecycle Termination

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    public func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager?.unregisterAll()
        activeOverlayWindow?.close()
        activeStitchedPreviewPanel?.close()
        statusItemManager?.dismissPopover()
        storageManager?.flushDiskQueue()
        appSettings?.flushDiskQueue()
    }
}
