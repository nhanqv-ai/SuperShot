import AppKit
import SwiftUI
import AudioToolbox
import UniformTypeIdentifiers
import SuperShotCore

public final class AppDelegate: NSObject, NSApplicationDelegate, CaptureOverlayWindowDelegate, ScrollingCaptureDelegate {
    public static var shared: AppDelegate?
    // Canonical Application Version: 1.0.32 (Build 32)
    public static let canonicalVersion = "1.0.32"
    public static let canonicalBuild = "32"

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
    public var activeScrollRegionBorderWindow: ScrollingRegionBorderWindow?
    public var activeScrollCanvasWindow: NSWindow?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        // 1. Enforce runtime menu bar accessory mode (LSUIElement safeguard)
        NSApplication.shared.setActivationPolicy(.accessory)

        // 2. Initialize Foundation Services
        appSettings = AppSettings()
        LocalizationManager.shared.setLanguage(code: appSettings.language)
        storageManager = StorageManager(initialCapacity: appSettings.capacity)
        hotKeyManager = HotKeyManager.shared
        previousAppTracker = PreviousAppTracker.shared
        autoPasteService = AutoPasteService.shared

        // 2b. Initialize Update Subsystem
        UpdateManager.shared.appSettings = appSettings
        UpdateManager.shared.checkOnStartupIfNeeded(appSettings: appSettings)
        UpdateManager.shared.startPeriodicCheck(interval: 86400, appSettings: appSettings)

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
            updateManager: UpdateManager.shared,
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
            },
            onAnnotateItem: { [weak self] item in
                self?.openInAnnotationWindow(item: item)
            }
        )

        let popoverVC = NSHostingController(rootView: mainShotView)
        popoverVC.preferredContentSize = NSSize(width: 380, height: 560)

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
        statusItemManager.onCheckForUpdatesRequested = { [weak self] in
            self?.openSettings(tab: .about)
            UpdateManager.shared.checkForUpdates(userInitiated: true)
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
        let regionRegistered = hotKeyManager.register(
            action: .inPlaceCapture,
            keyCode: appSettings.regionHotKeyKeyCode,
            modifiers: appSettings.regionHotKeyModifiers
        )
        let scrollRegistered = hotKeyManager.register(
            action: .scrollingCapture,
            keyCode: appSettings.scrollHotKeyKeyCode,
            modifiers: appSettings.scrollHotKeyModifiers
        )
        if !regionRegistered || !scrollRegistered {
            hotKeyManager.registerDefaults()
        }
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

        let overlay = CaptureOverlayWindow(capturedScreen: capturedScreen, appSettings: appSettings)
        overlay.captureDelegate = self
        self.activeOverlayWindow = overlay

        overlay.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func triggerScrollingCapture() {
        previousAppTracker.captureFrontmostApplication()
        statusItemManager?.dismissPopover()

        let mouseLocation = NSEvent.mouseLocation
        guard let capturedScreen = ScreenCaptureManager.shared.captureScreen(at: mouseLocation)
                ?? ScreenCaptureManager.shared.captureMainScreen() else {
            NSLog("SuperShot: Failed to capture screen bitmap for scrolling capture. Check Screen Recording permissions.")
            return
        }

        // Close any existing overlay so the user can drag-select the exact scrolling region first
        activeOverlayWindow?.close()

        let overlay = CaptureOverlayWindow(
            capturedScreen: capturedScreen,
            appSettings: appSettings,
            prefersScrollingOnConfirm: true
        )
        overlay.captureDelegate = self
        self.activeOverlayWindow = overlay

        overlay.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func startScrollingCapture(selectionRect: CGRect, display: CaptureDisplayInfo) {
        activeOverlayWindow?.close()
        activeOverlayWindow = nil
        activeScrollRegionBorderWindow?.close()
        activeScrollRegionBorderWindow = nil

        let globalSelectionRect = selectionRect.offsetBy(
            dx: display.cocoaFrame.minX,
            dy: display.cocoaFrame.minY
        )
        let borderWin = ScrollingRegionBorderWindow(selectionRect: globalSelectionRect)
        borderWin.orderFront(nil)
        self.activeScrollRegionBorderWindow = borderWin

        let panel = LiveStitchedPreviewPanel(
            captureManager: ScrollingCaptureManager.shared,
            screenFrame: display.cocoaFrame,
            selectionRect: globalSelectionRect
        )
        panel.onFinished = { [weak self] image, _, _ in
            guard let self = self else { return }
            self.activeScrollRegionBorderWindow?.close()
            self.activeScrollRegionBorderWindow = nil
            self.activeStitchedPreviewPanel?.close()
            self.activeStitchedPreviewPanel = nil
            self.handleCaptureCompletion(
                image: image,
                captureType: .scrolling,
                sourceApp: self.previousAppTracker.previousApp?.localizedName
            )
            self.presentScrollableAnnotationWindow(image: image, scale: display.scaleFactor)
        }
        panel.onCancelled = { [weak self] in
            self?.activeScrollRegionBorderWindow?.close()
            self?.activeScrollRegionBorderWindow = nil
            self?.activeStitchedPreviewPanel?.close()
            self?.activeStitchedPreviewPanel = nil
        }
        panel.orderFront(nil)
        self.activeStitchedPreviewPanel = panel

        // Re-activate the target application beneath the capture border so manual scroll wheel / trackpad events flow naturally
        previousAppTracker.previousApp?.activate(options: [])

        ScrollingCaptureManager.shared.configuration.maxScrollHeightPx = appSettings.maxScrollHeightPx
        ScrollingCaptureManager.shared.delegate = panel
        _ = ScrollingCaptureManager.shared.startSession(
            selectionRect: selectionRect,
            displayInfo: display,
            mode: .manual
        )
    }

    public func presentScrollableAnnotationWindow(image: CGImage, scale: CGFloat) {
        guard ProcessInfo.processInfo.environment["SUPER_SHOT_HEADLESS"] == nil else { return }
        activeScrollCanvasWindow?.close()

        let win = ScrollableAnnotationWindow(baseImage: image, scale: scale, appSettings: appSettings)
        win.onWindowClosed = { [weak self, weak win] in
            if self?.activeScrollCanvasWindow === win {
                self?.activeScrollCanvasWindow = nil
            }
        }
        win.canvasView.onCloseRequested = { [weak self, weak win] in
            win?.close()
            if self?.activeScrollCanvasWindow === win {
                self?.activeScrollCanvasWindow = nil
            }
        }
        win.canvasView.onCopyRequested = { [weak self, weak win] in
            guard let self = self, let win = win else { return }
            if let rendered = ImageRenderer.render(
                baseImage: win.canvasView.documentView.baseImage,
                annotations: win.canvasView.engine.objects,
                scale: win.canvasView.documentView.scale
            ) {
                self.handleCaptureCompletion(
                    image: rendered,
                    captureType: .scrolling,
                    sourceApp: self.previousAppTracker.previousApp?.localizedName
                )
            }
            win.close()
            if self.activeScrollCanvasWindow === win {
                self.activeScrollCanvasWindow = nil
            }
        }
        self.activeScrollCanvasWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func openInAnnotationWindow(item: ShotItem) {
        statusItemManager?.dismissPopover()
        guard let cgImage = storageManager.loadCGImage(for: item) else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        presentScrollableAnnotationWindow(image: cgImage, scale: scale)
    }

    // MARK: - CaptureOverlayWindowDelegate

    public func overlayDidCancel() {
        activeOverlayWindow?.close()
        activeOverlayWindow = nil
        previousAppTracker.previousApp?.activate(options: [])
    }

    public func overlayDidConfirmSelection(rect: CGRect, display: CaptureDisplayInfo) {
        guard let overlay = activeOverlayWindow else { return }
        let fullImage = overlay.capturedScreen.fullImage
        let windowSize = overlay.frame.size
        let scale = display.scaleFactor

        let finalImage = overlay.contentViewRef?.renderFinalSelectionImage()
            ?? ScreenCaptureManager.cropImage(
                fullImage,
                selectionInWindow: rect,
                windowSize: windowSize,
                scaleFactor: scale
            )
            ?? fullImage

        handleCaptureCompletion(
            image: finalImage,
            captureType: .region,
            sourceApp: previousAppTracker.previousApp?.localizedName
        )
        if ProcessInfo.processInfo.environment["SUPER_SHOT_HEADLESS"] != nil {
            overlay.close()
            self.activeOverlayWindow = nil
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self, weak overlay] in
                overlay?.close()
                if self?.activeOverlayWindow === overlay {
                    self?.activeOverlayWindow = nil
                }
            }
        }
    }

    public func overlayDidTriggerSave(rect: CGRect, display: CaptureDisplayInfo) {
        guard let overlay = activeOverlayWindow else { return }
        let fullImage = overlay.capturedScreen.fullImage
        let windowSize = overlay.frame.size
        let scale = display.scaleFactor

        let finalImage = overlay.contentViewRef?.renderFinalSelectionImage()
            ?? ScreenCaptureManager.cropImage(
                fullImage,
                selectionInWindow: rect,
                windowSize: windowSize,
                scaleFactor: scale
            )
            ?? fullImage

        saveImageToFile(finalImage)
        handleCaptureCompletion(
            image: finalImage,
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
            format: appSettings.saveFormat,
            jpegQuality: appSettings.jpegQuality
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

    public func copyImageToPasteboard(_ image: CGImage, scale: CGFloat? = nil) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let rep = NSBitmapImageRep(cgImage: image)
        let effectiveScale = max(1.0, scale ?? NSScreen.main?.backingScaleFactor ?? 2.0)
        rep.size = NSSize(width: CGFloat(image.width) / effectiveScale, height: CGFloat(image.height) / effectiveScale)
        if let pngData = rep.representation(using: .png, properties: [:]) {
            pb.declareTypes([.png, .tiff], owner: nil)
            pb.setData(pngData, forType: .png)
            if let tiff = rep.tiffRepresentation {
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
                var options: [CFString: Any] = [:]
                if self.appSettings.saveFormat == .jpeg {
                    options[kCGImageDestinationLossyCompressionQuality] = self.appSettings.jpegQuality
                }
                CGImageDestinationAddImage(dest, image, options as CFDictionary)
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
        var options: [CFString: Any] = [:]
        if appSettings.saveFormat == .jpeg {
            options[kCGImageDestinationLossyCompressionQuality] = appSettings.jpegQuality
        }
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        CGImageDestinationFinalize(dest)
    }

    private func playCaptureSound() {
        AudioServicesPlaySystemSound(1108)
    }

    public func openSettings(tab: SettingsTab = .general) {
        statusItemManager?.dismissPopover()
        settingsWindowController?.showSettings(tab: tab)
    }

    // MARK: - Lifecycle Termination

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    public func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager?.unregisterAll()
        activeOverlayWindow?.close()
        activeScrollRegionBorderWindow?.close()
        activeStitchedPreviewPanel?.close()
        statusItemManager?.dismissPopover()
        storageManager?.flushDiskQueue()
        appSettings?.flushDiskQueue()
        UpdateManager.shared.stopPeriodicCheck()
    }
}
