import Foundation
import AppKit
import SuperShotCore

public protocol CaptureOverlayWindowDelegate: AnyObject {
    func overlayDidCancel()
    func overlayDidConfirmSelection(rect: CGRect, display: CaptureDisplayInfo)
    func overlayDidTriggerSave(rect: CGRect, display: CaptureDisplayInfo)
    func overlayDidTriggerScroll(rect: CGRect, display: CaptureDisplayInfo)
}

public class CaptureOverlayWindow: NSPanel {
    public weak var captureDelegate: CaptureOverlayWindowDelegate?
    public let capturedScreen: CapturedScreen
    public private(set) var contentViewRef: CaptureOverlayContentView?

    public init(capturedScreen: CapturedScreen) {
        self.capturedScreen = capturedScreen
        let frame = capturedScreen.displayInfo.cocoaFrame

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = CaptureOverlayContentView(
            frame: NSRect(origin: .zero, size: frame.size),
            capturedScreen: capturedScreen,
            windowDelegate: self
        )
        self.contentView = view
        self.contentViewRef = view
    }

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }

    public override func keyDown(with event: NSEvent) {
        // Esc: Cancel capture
        if event.keyCode == 53 {
            captureDelegate?.overlayDidCancel()
            close()
            return
        }

        // Return / Enter: Confirm selection and copy
        if event.keyCode == 36 || event.keyCode == 76 {
            if let view = contentViewRef, !view.selectionRect.isEmpty {
                captureDelegate?.overlayDidConfirmSelection(rect: view.selectionRect, display: capturedScreen.displayInfo)
                close()
                return
            }
        }

        // Cmd+C: Copy to clipboard
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "c" {
            if let view = contentViewRef, !view.selectionRect.isEmpty {
                captureDelegate?.overlayDidConfirmSelection(rect: view.selectionRect, display: capturedScreen.displayInfo)
                close()
                return
            }
        }

        // Cmd+S: Save to file
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "s" {
            if let view = contentViewRef, !view.selectionRect.isEmpty {
                captureDelegate?.overlayDidTriggerSave(rect: view.selectionRect, display: capturedScreen.displayInfo)
                close()
                return
            }
        }

        super.keyDown(with: event)
    }
}
