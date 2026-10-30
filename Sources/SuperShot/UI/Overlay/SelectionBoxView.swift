import Foundation
import AppKit
import SwiftUI
import Combine
import CoreText
import SuperShotCore

public enum DragMode: Equatable {
    case none
    case creating(startPoint: CGPoint)
    case moving(startPoint: CGPoint, originalRect: CGRect)
    case resizing(handle: SelectionHandle, anchorPoint: CGPoint)
    case annotating
}

// MARK: - WYSIWYG Auto-Expanding Inline Canvas Text Editor

public final class InlineCanvasTextFieldCell: NSTextFieldCell {
    public static let horizontalPadding: CGFloat = 8.0
    public static let verticalPadding: CGFloat = 5.0

    public override func drawingRect(forBounds rect: NSRect) -> NSRect {
        return rect.insetBy(dx: Self.horizontalPadding, dy: Self.verticalPadding)
    }

    public override func titleRect(forBounds rect: NSRect) -> NSRect {
        return rect.insetBy(dx: Self.horizontalPadding, dy: Self.verticalPadding)
    }

    public override func edit(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        event: NSEvent?
    ) {
        let insetRect = rect.insetBy(dx: Self.horizontalPadding, dy: Self.verticalPadding)
        super.edit(withFrame: insetRect, in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    public override func select(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        start selStart: Int,
        length selLength: Int
    ) {
        let insetRect = rect.insetBy(dx: Self.horizontalPadding, dy: Self.verticalPadding)
        super.select(withFrame: insetRect, in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

public final class InlineCanvasTextField: NSTextField {
    public var onFrameMoved: ((CGPoint) -> Void)?
    public var allowedDragBounds: CGRect?
    public private(set) var isDraggingBorder: Bool = false
    private var lastDragSuperviewPoint: CGPoint?

    public override class var cellClass: AnyClass? {
        get { InlineCanvasTextFieldCell.self }
        set { }
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let customCell = InlineCanvasTextFieldCell(textCell: "")
        customCell.isEditable = true
        customCell.isSelectable = true
        customCell.wraps = true
        customCell.isScrollable = false
        customCell.usesSingleLineMode = false
        customCell.lineBreakMode = .byClipping
        customCell.drawsBackground = false
        customCell.focusRingType = .none
        self.cell = customCell

        self.isEditable = true
        self.isSelectable = true
        self.isBordered = false
        self.drawsBackground = false
        self.backgroundColor = .clear
        self.focusRingType = .none
        self.wantsLayer = true
        self.layer?.masksToBounds = false
        updateTypographyColor(.white)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func updateTypographyColor(_ color: NSColor) {
        self.textColor = color
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(cgColor: ImageRenderer.textShadowColor(for: color)) ?? NSColor.black.withAlphaComponent(0.55)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 2.0
        self.shadow = shadow
        if let editor = currentEditor() as? NSTextView {
            editor.textColor = color
            editor.insertionPointColor = color
        }
        needsDisplay = true
    }

    public func configureFieldEditor() {
        guard let editor = currentEditor() as? NSTextView else { return }
        editor.drawsBackground = false
        editor.backgroundColor = .clear
        editor.insertionPointColor = textColor ?? .white
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.lineFragmentPadding = 0
        let insetBounds = bounds.insetBy(
            dx: InlineCanvasTextFieldCell.horizontalPadding,
            dy: InlineCanvasTextFieldCell.verticalPadding
        )
        if insetBounds.width > 0 && insetBounds.height > 0 {
            editor.frame = insetBounds
            editor.textContainer?.containerSize = NSSize(width: insetBounds.width, height: .greatestFiniteMagnitude)
        }
    }

    /// Returns true when a point in local coordinates lies on the outer draggable border ring.
    public func isPointInBorderDragZone(_ localPoint: CGPoint) -> Bool {
        guard bounds.contains(localPoint) else { return false }
        let inner = bounds.insetBy(
            dx: InlineCanvasTextFieldCell.horizontalPadding,
            dy: InlineCanvasTextFieldCell.verticalPadding
        )
        return !inner.contains(localPoint)
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = superview != nil ? convert(point, from: superview) : point
        guard bounds.contains(localPoint) else { return nil }
        if isPointInBorderDragZone(localPoint) {
            return self
        }
        return super.hitTest(point)
    }

    public override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        if isPointInBorderDragZone(localPoint), let sv = superview {
            isDraggingBorder = true
            lastDragSuperviewPoint = sv.convert(event.locationInWindow, from: nil)
            NSCursor.closedHand.set()
            return
        }
        super.mouseDown(with: event)
    }

    public override func mouseDragged(with event: NSEvent) {
        if isDraggingBorder, let sv = superview, let lastPt = lastDragSuperviewPoint {
            let currentPt = sv.convert(event.locationInWindow, from: nil)
            var dx = currentPt.x - lastPt.x
            var dy = currentPt.y - lastPt.y
            var newFrame = frame.offsetBy(dx: dx, dy: dy)
            if let limit = allowedDragBounds, !limit.isEmpty {
                if newFrame.minX < limit.minX { newFrame.origin.x = limit.minX }
                if newFrame.maxX > limit.maxX { newFrame.origin.x = max(limit.minX, limit.maxX - newFrame.width) }
                if newFrame.minY < limit.minY { newFrame.origin.y = limit.minY }
                if newFrame.maxY > limit.maxY { newFrame.origin.y = max(limit.minY, limit.maxY - newFrame.height) }
                dx = newFrame.origin.x - frame.origin.x
                dy = newFrame.origin.y - frame.origin.y
            }
            if dx != 0 || dy != 0 {
                frame = newFrame
                lastDragSuperviewPoint = currentPt
                onFrameMoved?(CGPoint(x: dx, y: dy))
            }
            NSCursor.closedHand.set()
            return
        }
        super.mouseDragged(with: event)
    }

    public override func mouseUp(with event: NSEvent) {
        if isDraggingBorder {
            isDraggingBorder = false
            lastDragSuperviewPoint = nil
            NSCursor.openHand.set()
            return
        }
        super.mouseUp(with: event)
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            super.draw(dirtyRect)
            return
        }
        ctx.saveGState()
        let borderRect = bounds.insetBy(dx: 1.0, dy: 1.0)
        let roundedPath = NSBezierPath(roundedRect: borderRect, xRadius: 5.0, yRadius: 5.0)

        NSColor.black.withAlphaComponent(0.16).setFill()
        roundedPath.fill()

        NSColor.systemBlue.withAlphaComponent(0.90).setStroke()
        roundedPath.lineWidth = 1.5
        let dashPattern: [CGFloat] = [4.0, 3.0]
        roundedPath.setLineDash(dashPattern, count: dashPattern.count, phase: 0)
        roundedPath.stroke()
        ctx.restoreGState()

        super.draw(dirtyRect)
    }
}

public typealias SelectionBoxView = CaptureOverlayContentView

public class CaptureOverlayContentView: NSView, NSTextFieldDelegate {
    public let capturedScreen: CapturedScreen
    public let appSettings: AppSettings
    public let annotationEngine = AnnotationEngine()
    public let toolbarsViewModel: FloatingToolbarsViewModel
    public weak var windowDelegate: CaptureOverlayWindow?

    public var selectionRect: CGRect = .zero {
        didSet {
            toolbarsViewModel.selectionRect = selectionRect
            updateToolbarPositions()
            needsDisplay = true
        }
    }

    private var dragMode: DragMode = .none {
        didSet {
            updateToolbarVisibility()
        }
    }

    private var initialResizingRect: CGRect = .zero

    private var verticalToolbarHost: NSHostingView<VerticalAnnotationToolbarView>?
    private var horizontalToolbarHost: NSHostingView<HorizontalActionToolbarView>?
    public private(set) var activeTextField: NSTextField?
    private var editingObjectID: UUID?
    private var preEditTextSnapshot: String?
    private var preEditBoundsSnapshot: CGRect?
    private var isNewTextAnnotation: Bool = false
    public var currentMousePoint: CGPoint?
    private var trackingAreaRef: NSTrackingArea?
    public private(set) var spaceKeyDragging: Bool = false
    public private(set) var isHoveringDimensionBadge: Bool = false
    public private(set) var isHoveringQuickCopyPill: Bool = false
    private var isSpaceKeyPressed: Bool = false
    private var previousDragPoint: CGPoint?

    public private(set) var toolHUDText: String? = nil
    private var toolHUDTimer: Timer? = nil
    private var cancellables = Set<AnyCancellable>()

    public init(
        frame: NSRect,
        capturedScreen: CapturedScreen,
        appSettings: AppSettings = AppSettings(),
        windowDelegate: CaptureOverlayWindow? = nil
    ) {
        self.capturedScreen = capturedScreen
        self.appSettings = appSettings
        self.toolbarsViewModel = FloatingToolbarsViewModel(appSettings: appSettings)
        self.windowDelegate = windowDelegate
        super.init(frame: frame)
        self.wantsLayer = true

        setupFloatingToolbars()
        setupBindings()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func cleanup() {
        toolHUDTimer?.invalidate()
        toolHUDTimer = nil
    }

    deinit {
        cleanup()
    }

    public override var acceptsFirstResponder: Bool { true }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingAreaRef {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    // MARK: - Floating Toolbars Setup

    private func setupFloatingToolbars() {
        let vView = VerticalAnnotationToolbarView(viewModel: toolbarsViewModel, appSettings: appSettings)
        let hView = HorizontalActionToolbarView(viewModel: toolbarsViewModel)

        let vHost = NSHostingView(rootView: vView)
        let hHost = NSHostingView(rootView: hView)

        vHost.frame = CGRect(origin: .zero, size: ToolbarLayoutCalculator.verticalToolbarSize)
        hHost.frame = CGRect(origin: .zero, size: ToolbarLayoutCalculator.horizontalToolbarSize)
        vHost.isHidden = true
        hHost.isHidden = true

        addSubview(vHost)
        addSubview(hHost)

        self.verticalToolbarHost = vHost
        self.horizontalToolbarHost = hHost
        toolbarsViewModel.defaultAnchorView = hHost
    }

    private func setupBindings() {
        toolbarsViewModel.onClearAllRequested = { [weak self] in
            guard let self = self else { return }
            let count = self.annotationEngine.clearAll()
            if count > 0 {
                self.showHUDNotification(text: LocalizationManager.shared.tr(.annotationsCleared))
                self.needsDisplay = true
            }
        }

        annotationEngine.$canUndo
            .sink { [weak self] canUndo in
                self?.toolbarsViewModel.canUndo = canUndo
            }
            .store(in: &cancellables)

        annotationEngine.$canRedo
            .sink { [weak self] canRedo in
                self?.toolbarsViewModel.canRedo = canRedo
            }
            .store(in: &cancellables)

        annotationEngine.objectWillChange
            .sink { [weak self] _ in
                self?.needsDisplay = true
            }
            .store(in: &cancellables)

        toolbarsViewModel.onToolChanged = { [weak self] toolType in
            guard let self = self else { return }
            self.commitActiveTextEditing()
            self.annotationEngine.cancelDrag()
            self.dragMode = .none
            let mapped = Self.mapTool(toolType)
            if mapped != .select {
                self.annotationEngine.deselectAll()
            }
            self.annotationEngine.activeTool = mapped
            self.updateTextTargetState()
            let pt = self.currentMousePoint ?? (self.window.map { self.convert($0.mouseLocationOutsideOfEventStream, from: nil) }) ?? CGPoint(x: self.bounds.midX, y: self.bounds.midY)
            self.updateCanvasCursor(at: pt)
            self.showToolSelectionHUD(tool: toolType)
            self.needsDisplay = true
        }

        toolbarsViewModel.onColorSelected = { [weak self] hex in
            guard let self = self else { return }
            if self.annotationEngine.selectedObjectID != nil {
                self.annotationEngine.recolorSelected(newHex: hex)
            }
            if let field = self.activeTextField as? InlineCanvasTextField {
                let newColor = ColorPreset(name: "", hex: hex).toNSColor()
                field.updateTypographyColor(newColor)
                self.window?.makeFirstResponder(field)
                field.configureFieldEditor()
            }
            self.needsDisplay = true
        }

        toolbarsViewModel.onStrokeWidthSelected = { [weak self] width in
            guard let self = self else { return }
            if self.annotationEngine.selectedObjectID != nil {
                self.annotationEngine.updateSelectedStrokeWidth(width)
            }
            self.showStrokeWidthHUD(width: Int(width))
            self.needsDisplay = true
        }

        toolbarsViewModel.onFontSizeSelected = { [weak self] size in
            guard let self = self else { return }
            if let sel = self.annotationEngine.selectedObject, sel.tool == .text {
                self.annotationEngine.updateSelectedFontSize(size, anchorMaxY: true)
            }
            if let field = self.activeTextField {
                field.font = NSFont.systemFont(ofSize: size, weight: .semibold)
                self.adjustActiveTextFieldFrame()
                self.window?.makeFirstResponder(field)
                (field as? InlineCanvasTextField)?.configureFieldEditor()
            }
            self.showFontSizeHUD(size: Int(round(size)))
            self.needsDisplay = true
        }

        toolbarsViewModel.onUndoRequested = { [weak self] in
            self?.commitActiveTextEditing()
            self?.annotationEngine.undo()
            self?.showHUDNotification(text: LocalizationManager.shared.tr(.hudUndo))
            self?.needsDisplay = true
        }

        toolbarsViewModel.onRedoRequested = { [weak self] in
            self?.commitActiveTextEditing()
            self?.annotationEngine.redo()
            self?.showHUDNotification(text: LocalizationManager.shared.tr(.hudRedo))
            self?.needsDisplay = true
        }

        toolbarsViewModel.onDuplicateRequested = { [weak self] in
            guard let self = self else { return }
            self.commitActiveTextEditing()
            if self.annotationEngine.selectedObjectID != nil {
                self.annotationEngine.duplicateSelected(within: self.selectionRect)
                self.showHUDNotification(text: LocalizationManager.shared.tr(.hudDuplicate))
                self.needsDisplay = true
            }
        }

        toolbarsViewModel.onCopyRequested = { [weak self] in
            guard let self = self, !self.selectionRect.isEmpty else { return }
            self.commitActiveTextEditing()
            self.showHUDNotification(text: LocalizationManager.shared.tr(.copiedToClipboard))
            self.windowDelegate?.captureDelegate?.overlayDidConfirmSelection(
                rect: self.selectionRect,
                display: self.capturedScreen.displayInfo
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                self?.windowDelegate?.close()
            }
        }

        toolbarsViewModel.onSaveRequested = { [weak self] in
            guard let self = self, !self.selectionRect.isEmpty else { return }
            self.commitActiveTextEditing()
            self.windowDelegate?.captureDelegate?.overlayDidTriggerSave(
                rect: self.selectionRect,
                display: self.capturedScreen.displayInfo
            )
            self.windowDelegate?.close()
        }

        toolbarsViewModel.onShareRequested = { [weak self] anchorView in
            guard let self = self, !self.selectionRect.isEmpty else { return }
            self.commitActiveTextEditing()
            guard let rendered = self.renderFinalSelectionImage() else { return }
            let nsImage = NSImage(cgImage: rendered, size: NSSize(width: rendered.width, height: rendered.height))
            let picker = NSSharingServicePicker(items: [nsImage])
            picker.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
        }

        toolbarsViewModel.onScrollCaptureRequested = { [weak self] in
            guard let self = self, !self.selectionRect.isEmpty else { return }
            self.commitActiveTextEditing()
            self.windowDelegate?.captureDelegate?.overlayDidTriggerScroll(
                rect: self.selectionRect,
                display: self.capturedScreen.displayInfo
            )
            self.windowDelegate?.close()
        }

        toolbarsViewModel.onCancelRequested = { [weak self] in
            guard let self = self else { return }
            self.commitActiveTextEditing()
            self.windowDelegate?.captureDelegate?.overlayDidCancel()
            self.windowDelegate?.close()
        }
    }

    private static func mapTool(_ toolType: AnnotationToolType) -> AnnotationTool {
        switch toolType {
        case .select: return .select
        case .rectangle: return .rectangle
        case .ellipse: return .ellipse
        case .arrow: return .arrow
        case .line: return .line
        case .pen: return .pen
        case .highlighter: return .highlighter
        case .text: return .text
        case .blur: return .blur
        }
    }

    private func updateToolbarVisibility() {
        let shouldShow = !selectionRect.isEmpty && dragMode == .none
        verticalToolbarHost?.isHidden = !shouldShow
        horizontalToolbarHost?.isHidden = !shouldShow
    }

    private func updateToolbarPositions() {
        guard !selectionRect.isEmpty else {
            verticalToolbarHost?.isHidden = true
            horizontalToolbarHost?.isHidden = true
            return
        }

        let vFitting = verticalToolbarHost?.fittingSize ?? ToolbarLayoutCalculator.verticalToolbarSize
        let hFitting = horizontalToolbarHost?.fittingSize ?? ToolbarLayoutCalculator.horizontalToolbarSize
        let vSize = CGSize(
            width: max(ToolbarLayoutCalculator.verticalToolbarSize.width, vFitting.width),
            height: max(ToolbarLayoutCalculator.verticalToolbarSize.height, vFitting.height)
        )
        let hSize = CGSize(
            width: max(ToolbarLayoutCalculator.horizontalToolbarSize.width, hFitting.width),
            height: max(ToolbarLayoutCalculator.horizontalToolbarSize.height, hFitting.height)
        )

        let resolved = ToolbarPositionCalculator.resolveToolbarFrames(
            selectionRect: selectionRect,
            screenBounds: bounds,
            vertSize: vSize,
            horizSize: hSize
        )

        verticalToolbarHost?.frame = resolved.vertical
        horizontalToolbarHost?.frame = resolved.horizontal
        toolbarsViewModel.verticalToolbarFrame = resolved.vertical
        toolbarsViewModel.canvasBounds = bounds
        updateToolbarVisibility()
    }

    // MARK: - Final Composited Bitmap Rendering

    public func renderFinalSelectionImage() -> CGImage? {
        commitActiveTextEditing()
        guard !selectionRect.isEmpty else { return nil }

        let windowH = bounds.height
        let scale = capturedScreen.displayInfo.scaleFactor

        if annotationEngine.objects.isEmpty {
            return ScreenCaptureManager.cropImage(
                capturedScreen.fullImage,
                selectionInWindow: selectionRect,
                windowSize: bounds.size,
                scaleFactor: scale
            )
        }

        // Convert selectionRect and AnnotationObjects from Cocoa (bottom-left) to top-left coordinate space
        let safeSelection = selectionRect.intersection(bounds)
        guard !safeSelection.isNull && safeSelection.width >= 1 && safeSelection.height >= 1 else { return nil }

        let pixelX = round(safeSelection.minX * scale)
        let pixelY = round((windowH - safeSelection.maxY) * scale)
        let pixelW = max(1, round(safeSelection.maxX * scale) - pixelX)
        let pixelH = max(1, round((windowH - safeSelection.minY) * scale) - pixelY)

        let topLeftCropRect = CGRect(
            x: pixelX / scale,
            y: pixelY / scale,
            width: pixelW / scale,
            height: pixelH / scale
        )

        let topLeftAnnotations: [AnnotationObject] = annotationEngine.objects.map { obj in
            var copy = obj
            copy.bounds = CGRect(
                x: obj.bounds.minX,
                y: windowH - obj.bounds.maxY,
                width: obj.bounds.width,
                height: obj.bounds.height
            )
            copy.points = obj.points.map { CGPoint(x: $0.x, y: windowH - $0.y) }
            return copy
        }

        return ImageRenderer.render(
            baseImage: capturedScreen.fullImage,
            annotations: topLeftAnnotations,
            cropRect: topLeftCropRect,
            scale: scale
        )
    }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Step 1: Draw frozen display image
        context.draw(capturedScreen.fullImage, in: bounds)

        // Step 2: Draw outside dimming (black with 0.45 opacity) using Even-Odd cutout
        context.saveGState()
        let dimColor = NSColor.black.withAlphaComponent(0.45)
        dimColor.setFill()

        if selectionRect.isEmpty {
            bounds.fill()
            drawInstructionBanner(in: context)
            if let mousePt = currentMousePoint {
                drawCrosshairGuides(at: mousePt, in: context)
            }
        } else {
            let dimPath = NSBezierPath(rect: bounds)
            dimPath.append(NSBezierPath(rect: selectionRect))
            dimPath.windingRule = .evenOdd
            dimPath.fill()

            // Step 2b: Draw vector annotations clipped inside selectionRect
            context.saveGState()
            context.clip(to: selectionRect)
            drawAnnotations(in: context)
            context.restoreGState()

            // Step 3: Draw selection border (crisp 1.5pt white outline)
            NSColor.white.setStroke()
            let borderPath = NSBezierPath(rect: selectionRect)
            borderPath.lineWidth = 1.5
            borderPath.stroke()

            // Step 4: Draw 8 grab handles
            let handles = SelectionBoxGeometry.handlePositions(for: selectionRect)
            let radius = SelectionBoxGeometry.handleRadius

            for (_, pos) in handles {
                let handleRect = CGRect(x: pos.x - radius, y: pos.y - radius, width: radius * 2, height: radius * 2)
                let handlePath = NSBezierPath(ovalIn: handleRect)
                NSColor.white.setFill()
                handlePath.fill()
                NSColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0).setStroke()
                handlePath.lineWidth = 1.5
                handlePath.stroke()
            }

            // Step 5: Draw live dimension badge & quick copy action pill
            drawDimensionBadge(in: context)
            drawQuickCopyPill(in: context)
        }
        context.restoreGState()

        // Step 6: Tool selection feedback HUD indicator
        if let hudText = toolHUDText {
            drawToolFeedbackHUD(text: hudText, in: context)
        }
    }

    private func drawAnnotations(in context: CGContext) {
        // 1. Region Blur objects
        for obj in annotationEngine.objects where obj.tool == .blur {
            drawBlurAnnotation(obj: obj, in: context)
        }

        // 2. Vector objects
        for obj in annotationEngine.objects where obj.tool != .blur {
            drawVectorAnnotation(obj: obj, in: context)
        }

        // 3. Active drag draft
        if let draft = annotationEngine.activeDragObject {
            if draft.tool == .blur {
                drawBlurAnnotation(obj: draft, in: context)
            } else {
                drawVectorAnnotation(obj: draft, in: context)
            }
        }

        // 4. Selection handles on selected vector annotation (hidden while inline editor is open on that object)
        if let selected = annotationEngine.selectedObject, editingObjectID != selected.id {
            context.saveGState()
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(1.5)
            context.stroke(selected.selectionBounds)

            for (_, pos) in selected.handlePositions() {
                let hr = CGRect(x: pos.x - 4, y: pos.y - 4, width: 8, height: 8)
                context.setFillColor(NSColor.white.cgColor)
                context.fillEllipse(in: hr)
                context.setStrokeColor(NSColor.systemBlue.cgColor)
                context.setLineWidth(1.5)
                context.strokeEllipse(in: hr)
            }
            context.restoreGState()
        }
    }

    private func drawBlurAnnotation(obj: AnnotationObject, in context: CGContext) {
        context.saveGState()
        let rect = obj.bounds.intersection(bounds)
        guard rect.width > 1, rect.height > 1 else {
            context.restoreGState()
            return
        }

        let scale = capturedScreen.displayInfo.scaleFactor
        let windowH = bounds.height
        let fullImgPixelRect = CGRect(x: 0, y: 0, width: capturedScreen.fullImage.width, height: capturedScreen.fullImage.height)
        let rawCrop = CGRect(
            x: rect.minX * scale,
            y: (windowH - rect.maxY) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        let cropInPixels = rawCrop.intersection(fullImgPixelRect)
        guard cropInPixels.width >= 1, cropInPixels.height >= 1 else {
            context.restoreGState()
            return
        }

        let blockSize: CGFloat = 12.0
        let smallW = max(1, Int(ceil(rect.width / blockSize)))
        let smallH = max(1, Int(ceil(rect.height / blockSize)))
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        if let cropped = capturedScreen.fullImage.cropping(to: cropInPixels),
           let smallCtx = CGContext(
               data: nil,
               width: smallW,
               height: smallH,
               bitsPerComponent: 8,
               bytesPerRow: smallW * 4,
               space: colorSpace,
               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
           ) {
            smallCtx.interpolationQuality = .medium
            smallCtx.draw(cropped, in: CGRect(x: 0, y: 0, width: smallW, height: smallH))
            if let pixelated = smallCtx.makeImage() {
                context.interpolationQuality = .none
                context.draw(pixelated, in: rect)
                context.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
                context.setLineWidth(1.0)
                context.setLineDash(phase: 0, lengths: [3, 3])
                context.stroke(rect)
                context.restoreGState()
                return
            }
        }

        // Fallback mosaic grid if cropping fails
        let cols = max(1, Int(ceil(rect.width / blockSize)))
        let rows = max(1, Int(ceil(rect.height / blockSize)))
        for r in 0..<rows {
            for c in 0..<cols {
                let cellX = rect.minX + CGFloat(c) * blockSize
                let cellY = rect.minY + CGFloat(r) * blockSize
                let cell = CGRect(
                    x: cellX,
                    y: cellY,
                    width: min(blockSize, rect.maxX - cellX),
                    height: min(blockSize, rect.maxY - cellY)
                )
                let shade = ((r + c) % 2 == 0) ? 0.45 : 0.55
                context.setFillColor(gray: shade, alpha: 0.90)
                context.fill(cell)
            }
        }
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
        context.setLineWidth(1.0)
        context.setLineDash(phase: 0, lengths: [3, 3])
        context.stroke(rect)
        context.restoreGState()
    }

    private func drawVectorAnnotation(obj: AnnotationObject, in context: CGContext) {
        let nsColor = ColorPreset(name: "", hex: obj.colorHex).toNSColor()
        context.saveGState()
        context.setStrokeColor(nsColor.cgColor)
        context.setFillColor(nsColor.cgColor)
        context.setLineWidth(obj.strokeWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch obj.tool {
        case .rectangle:
            context.stroke(obj.bounds)
        case .ellipse:
            context.strokeEllipse(in: obj.bounds)
        case .line:
            guard obj.points.count >= 2 else { break }
            context.strokeLineSegments(between: [obj.points[0], obj.points[1]])
        case .arrow:
            guard obj.points.count >= 2 else { break }
            drawArrow(p1: obj.points[0], p2: obj.points[1], strokeWidth: obj.strokeWidth, color: nsColor, context: context)
        case .pen:
            guard !obj.points.isEmpty else { break }
            let path = buildSmoothPath(points: obj.points)
            context.addPath(path)
            context.strokePath()
        case .highlighter:
            guard !obj.points.isEmpty else { break }
            context.setBlendMode(.multiply)
            let marker = nsColor.withAlphaComponent(0.35)
            context.setStrokeColor(marker.cgColor)
            context.setLineWidth(max(16.0, obj.strokeWidth))
            let path = buildSmoothPath(points: obj.points)
            context.addPath(path)
            context.strokePath()
        case .text:
            guard !obj.text.isEmpty, editingObjectID != obj.id else { break }
            let font = NSFont.systemFont(ofSize: obj.fontSize, weight: .semibold)
            let shadowCGColor = ImageRenderer.textShadowColor(for: nsColor)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: nsColor]
            let lines = obj.text.components(separatedBy: .newlines)
            let lineHeight = obj.fontSize * 1.25

            for (index, rawLine) in lines.enumerated() {
                guard !rawLine.isEmpty else { continue }
                let attrStr = NSAttributedString(string: rawLine, attributes: attrs)
                let line = CTLineCreateWithAttributedString(attrStr)

                context.saveGState()
                context.setShadow(offset: CGSize(width: 0, height: -1.0), blur: 2.0, color: shadowCGColor)
                context.translateBy(
                    x: obj.bounds.minX,
                    y: obj.bounds.maxY - obj.fontSize - CGFloat(index) * lineHeight
                )
                context.textPosition = .zero
                CTLineDraw(line, context)
                context.restoreGState()
            }
        case .blur, .select:
            break
        }
        context.restoreGState()
    }

    private func drawArrow(p1: CGPoint, p2: CGPoint, strokeWidth: CGFloat, color: NSColor, context: CGContext) {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        let len = hypot(dx, dy)
        guard len > 1.0 else {
            context.setFillColor(color.cgColor)
            let anchorRadius = max(2.0, strokeWidth / 2.0)
            context.fillEllipse(in: CGRect(x: p1.x - anchorRadius, y: p1.y - anchorRadius, width: anchorRadius * 2, height: anchorRadius * 2))
            return
        }
        let theta = atan2(dy, dx)
        let desiredHeadLen = max(8.0, strokeWidth * 3.5)
        let headLen = min(desiredHeadLen, max(3.0, len * 0.6))
        let wingAngle: CGFloat = 0.488

        let shaftSetback = min(headLen * 0.7, len)
        let shaftEnd = CGPoint(x: p2.x - shaftSetback * cos(theta), y: p2.y - shaftSetback * sin(theta))

        if len > shaftSetback + 0.5 {
            context.strokeLineSegments(between: [p1, shaftEnd])
        }

        let w1 = CGPoint(x: p2.x - headLen * cos(theta - wingAngle), y: p2.y - headLen * sin(theta - wingAngle))
        let w2 = CGPoint(x: p2.x - headLen * cos(theta + wingAngle), y: p2.y - headLen * sin(theta + wingAngle))

        let arrowPath = CGMutablePath()
        arrowPath.move(to: p2)
        arrowPath.addLine(to: w1)
        arrowPath.addLine(to: w2)
        arrowPath.closeSubpath()
        context.setFillColor(color.cgColor)
        context.addPath(arrowPath)
        context.fillPath()
    }

    private func buildSmoothPath(points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        if points.count == 1 {
            path.addEllipse(in: CGRect(x: first.x - 1, y: first.y - 1, width: 2, height: 2))
            return path
        }
        if points.count == 2 {
            path.addLine(to: points[1])
            return path
        }
        for i in 1..<(points.count - 1) {
            let p0 = points[i]
            let p1 = points[i + 1]
            let mid = CGPoint(x: (p0.x + p1.x) / 2.0, y: (p0.y + p1.y) / 2.0)
            path.addQuadCurve(to: mid, control: p0)
        }
        if let last = points.last {
            path.addLine(to: last)
        }
        return path
    }

    public func dimensionBadgeFrame() -> CGRect {
        guard !selectionRect.isEmpty else { return .zero }
        let text = SelectionBoxGeometry.formatDimensionBadge(
            width: selectionRect.width,
            height: selectionRect.height,
            scaleFactor: capturedScreen.displayInfo.scaleFactor,
            includeAspectRatio: true
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let str = NSAttributedString(string: text, attributes: attributes)
        let textSize = str.size()
        let badgeSize = CGSize(
            width: max(ToolbarPositionCalculator.badgeSize.width, textSize.width + 16.0),
            height: 22.0
        )
        return ToolbarPositionCalculator.calculateDimensionBadgeFrame(
            selectionRect: selectionRect,
            screenBounds: bounds,
            badgeSize: badgeSize
        )
    }

    public func quickCopyPillFrame() -> CGRect {
        let badgeFrame = dimensionBadgeFrame()
        guard !selectionRect.isEmpty, !badgeFrame.isEmpty else { return .zero }
        let text = LocalizationManager.shared.tr(.quickCopy)
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let str = NSAttributedString(string: text, attributes: attributes)
        let textSize = str.size()
        let pillW = max(56.0, textSize.width + 28.0)
        let pillH = badgeFrame.height

        var x = badgeFrame.maxX + 6.0
        let y = badgeFrame.minY

        if x + pillW > bounds.maxX - 8.0 {
            x = badgeFrame.minX - 6.0 - pillW
        }
        x = max(bounds.minX + 8.0, min(bounds.maxX - 8.0 - pillW, x))

        return CGRect(x: x, y: y, width: pillW, height: pillH)
    }

    private func drawDimensionBadge(in context: CGContext) {
        let text = SelectionBoxGeometry.formatDimensionBadge(
            width: selectionRect.width,
            height: selectionRect.height,
            scaleFactor: capturedScreen.displayInfo.scaleFactor,
            includeAspectRatio: true
        )

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let str = NSAttributedString(string: text, attributes: attributes)
        let textSize = str.size()
        let badgeFrame = dimensionBadgeFrame()

        let badgePath = NSBezierPath(roundedRect: badgeFrame, xRadius: 4.0, yRadius: 4.0)
        let fillColor = isHoveringDimensionBadge ? NSColor.black.withAlphaComponent(0.85) : NSColor.black.withAlphaComponent(0.75)
        fillColor.setFill()
        badgePath.fill()

        if isHoveringDimensionBadge {
            NSColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 0.9).setStroke()
            badgePath.lineWidth = 1.0
            badgePath.stroke()
        }

        let textRect = CGRect(
            x: badgeFrame.midX - textSize.width / 2.0,
            y: badgeFrame.midY - textSize.height / 2.0,
            width: textSize.width,
            height: textSize.height
        )
        str.draw(in: textRect)
    }

    private func drawQuickCopyPill(in context: CGContext) {
        let pillFrame = quickCopyPillFrame()
        guard !pillFrame.isEmpty else { return }

        let pillPath = NSBezierPath(roundedRect: pillFrame, xRadius: 4.0, yRadius: 4.0)
        let fillColor = isHoveringQuickCopyPill
            ? NSColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 0.95)
            : NSColor.black.withAlphaComponent(0.75)
        fillColor.setFill()
        pillPath.fill()

        if isHoveringQuickCopyPill {
            NSColor.white.withAlphaComponent(0.8).setStroke()
            pillPath.lineWidth = 1.0
            pillPath.stroke()
        } else {
            NSColor.white.withAlphaComponent(0.2).setStroke()
            pillPath.lineWidth = 0.5
            pillPath.stroke()
        }

        let text = LocalizationManager.shared.tr(.quickCopy)
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let textSize = str.size()

        var textStartX = pillFrame.minX + 8.0
        let iconSize: CGFloat = 11.0
        if let icon = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil) {
            let iconRect = CGRect(
                x: pillFrame.minX + 7.0,
                y: pillFrame.midY - iconSize / 2.0,
                width: iconSize,
                height: iconSize
            )
            icon.draw(in: iconRect)
            textStartX = iconRect.maxX + 4.0
        }

        let textRect = CGRect(
            x: textStartX,
            y: pillFrame.midY - textSize.height / 2.0,
            width: textSize.width,
            height: textSize.height
        )
        str.draw(in: textRect)
    }

    private func drawInstructionBanner(in context: CGContext) {
        let instruction = LocalizationManager.shared.tr(.captureOverlayInstruction)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let str = NSAttributedString(string: instruction, attributes: attrs)
        let textSize = str.size()
        let padX: CGFloat = 18.0
        let padY: CGFloat = 9.0
        let pillW = textSize.width + padX * 2
        let pillH = textSize.height + padY * 2
        let pillRect = CGRect(
            x: bounds.midX - pillW / 2.0,
            y: bounds.maxY - pillH - 42.0,
            width: pillW,
            height: pillH
        )

        let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: pillH / 2.0, yRadius: pillH / 2.0)
        NSColor.black.withAlphaComponent(0.72).setFill()
        pillPath.fill()

        NSColor.white.withAlphaComponent(0.22).setStroke()
        pillPath.lineWidth = 1.0
        pillPath.stroke()

        str.draw(in: CGRect(
            x: pillRect.minX + padX,
            y: pillRect.minY + padY,
            width: textSize.width,
            height: textSize.height
        ))
    }

    public func showHUDNotification(text: String) {
        toolHUDText = text
        needsDisplay = true
        toolHUDTimer?.invalidate()
        toolHUDTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            self?.toolHUDText = nil
            self?.needsDisplay = true
        }
    }

    public func showStrokeWidthHUD(width: Int) {
        showHUDNotification(text: LocalizationManager.shared.tr(.strokeWidthHUD(width)))
    }

    public func showFontSizeHUD(size: Int) {
        showHUDNotification(text: LocalizationManager.shared.tr(.fontSizeHUD(size)))
    }

    public func updateTextTargetState() {
        let isTextSelected = (annotationEngine.selectedObject?.tool == .text)
        toolbarsViewModel.isTextTargetActive = isTextSelected || (toolbarsViewModel.activeTool == .text)
        if isTextSelected, let sel = annotationEngine.selectedObject {
            toolbarsViewModel.selectedFontSize = sel.fontSize
        } else {
            toolbarsViewModel.selectedFontSize = nil
        }
    }

    private func showToolSelectionHUD(tool: AnnotationToolType) {
        showHUDNotification(text: "\(tool.localizedName) (\(tool.mnemonicKey))")
    }

    private func drawToolFeedbackHUD(text: String, in context: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let textSize = str.size()
        let padX: CGFloat = 14.0
        let padY: CGFloat = 6.0
        let pillW = textSize.width + padX * 2
        let pillH = textSize.height + padY * 2
        let pillRect = CGRect(
            x: bounds.midX - pillW / 2.0,
            y: bounds.maxY - pillH - 72.0,
            width: pillW,
            height: pillH
        )

        let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: pillH / 2.0, yRadius: pillH / 2.0)
        NSColor.black.withAlphaComponent(0.80).setFill()
        pillPath.fill()

        let borderPath = NSBezierPath(roundedRect: pillRect, xRadius: pillH / 2.0, yRadius: pillH / 2.0)
        NSColor.white.withAlphaComponent(0.25).setStroke()
        borderPath.lineWidth = 1.0
        borderPath.stroke()

        let textRect = CGRect(
            x: pillRect.midX - textSize.width / 2.0,
            y: pillRect.midY - textSize.height / 2.0,
            width: textSize.width,
            height: textSize.height
        )
        str.draw(in: textRect)
    }

    private func drawCrosshairGuides(at point: CGPoint, in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
        context.setLineWidth(1.0)
        context.setLineDash(phase: 0, lengths: [4, 4])
        context.strokeLineSegments(between: [
            CGPoint(x: bounds.minX, y: point.y),
            CGPoint(x: bounds.maxX, y: point.y),
            CGPoint(x: point.x, y: bounds.minY),
            CGPoint(x: point.x, y: bounds.maxY)
        ])
        context.restoreGState()
    }

    // MARK: - Mouse & Keyboard Interaction

    public func handleOverlayKeyDown(with event: NSEvent) -> Bool {
        // Tier 0: Handle active drag gestures (Esc cancel, Space pan)
        if dragMode != .none {
            if event.keyCode == 53 { // Esc cancels active drag gesture without closing overlay window
                switch dragMode {
                case .creating:
                    selectionRect = .zero
                    dragMode = .none
                case .resizing:
                    selectionRect = initialResizingRect
                    initialResizingRect = .zero
                    dragMode = .none
                case .moving(_, let originalRect):
                    let dx = originalRect.minX - selectionRect.minX
                    let dy = originalRect.minY - selectionRect.minY
                    for i in 0..<annotationEngine.objects.count {
                        annotationEngine.objects[i].translate(by: CGPoint(x: dx, y: dy))
                    }
                    selectionRect = originalRect
                    dragMode = .none
                case .annotating:
                    annotationEngine.cancelDrag()
                    dragMode = .none
                case .none:
                    break
                }
                spaceKeyDragging = false
                isSpaceKeyPressed = false
                needsDisplay = true
                return true
            }
            if event.keyCode == 49 { // Spacebar during active drag
                if case .creating = dragMode {
                    isSpaceKeyPressed = true
                    spaceKeyDragging = true
                }
                // Always absorb Space during active drag; NEVER trigger scrolling capture!
                return true
            }
            // Absorb any other keyboard shortcuts during active drag
            return true
        }

        // Tier 1: Cancel active inline text editing on Esc, Commit on Return / Enter (Shift/Option+Enter inserts newline)
        if activeTextField != nil {
            if event.keyCode == 53 {
                cancelActiveTextEditing()
                return true
            }
            if event.keyCode == 36 || event.keyCode == 76 {
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if flags.contains(.shift) || flags.contains(.option) {
                    if let editor = activeTextField?.currentEditor() as? NSTextView {
                        editor.insertNewlineIgnoringFieldEditor(nil)
                        adjustActiveTextFieldFrame()
                    } else if let field = activeTextField {
                        field.stringValue += "\n"
                        adjustActiveTextFieldFrame()
                    }
                    return true
                }
                commitActiveTextEditing()
                return true
            }
            return false
        }

        // Tier 2: Escape deselects active vector object if any object is selected
        if event.keyCode == 53 && annotationEngine.selectedObjectID != nil {
            annotationEngine.deselectAll()
            updateTextTargetState()
            needsDisplay = true
            return true
        }

        // Tier 2b: Spacebar (keyCode 49) initiates spacebar repositioning during drag creation
        if event.keyCode == 49 {
            isSpaceKeyPressed = true
            if case .creating = dragMode {
                spaceKeyDragging = true
                return true
            }
        }

        // Tier 3: Escape reverts active drawing tool to .select if another tool is active
        if event.keyCode == 53 && toolbarsViewModel.activeTool != .select {
            toolbarsViewModel.selectTool(.select)
            return true
        }

        // Cmd+D: Duplicate selected vector annotation object
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command && (event.keyCode == 2 || event.charactersIgnoringModifiers?.lowercased() == "d"),
           annotationEngine.selectedObjectID != nil {
            annotationEngine.duplicateSelected(within: selectionRect)
            showHUDNotification(text: LocalizationManager.shared.tr(.hudDuplicate))
            needsDisplay = true
            return true
        }

        // Cmd+A: Immediately select the entire display bounds
        if flags == .command && (event.keyCode == 0 || event.charactersIgnoringModifiers?.lowercased() == "a") {
            selectionRect = bounds
            return true
        }

        // Layer Z-Index Reordering Shortcuts (Cmd+], Cmd+[, Cmd+Shift+], Cmd+Shift+[)
        if annotationEngine.selectedObjectID != nil {
            let chars = event.charactersIgnoringModifiers ?? ""
            let isCloseBracket = (event.keyCode == 30 || chars == "]")
            let isOpenBracket = (event.keyCode == 33 || chars == "[")

            if flags == [.command, .shift] && isCloseBracket {
                if annotationEngine.bringSelectedToFront() {
                    showHUDNotification(text: LocalizationManager.shared.tr(.layerBringToFront))
                    needsDisplay = true
                }
                return true
            }

            if flags == [.command, .shift] && isOpenBracket {
                if annotationEngine.sendSelectedToBack() {
                    showHUDNotification(text: LocalizationManager.shared.tr(.layerSendToBack))
                    needsDisplay = true
                }
                return true
            }

            if flags == .command && isCloseBracket {
                if annotationEngine.bringSelectedForward() {
                    showHUDNotification(text: LocalizationManager.shared.tr(.layerBringForward))
                    needsDisplay = true
                }
                return true
            }

            if flags == .command && isOpenBracket {
                if annotationEngine.sendSelectedBackward() {
                    showHUDNotification(text: LocalizationManager.shared.tr(.layerSendBackward))
                    needsDisplay = true
                }
                return true
            }
        }

        // Tab (keyCode 48) cycles selection across vector annotations when not editing text
        if event.keyCode == 48, activeTextField == nil {
            let reverse = event.modifierFlags.contains(.shift)
            if let selectedID = annotationEngine.selectNextObject(reverse: reverse) {
                if let idx = annotationEngine.objects.firstIndex(where: { $0.id == selectedID }) {
                    let obj = annotationEngine.objects[idx]
                    let total = annotationEngine.objects.count
                    if let toolType = AnnotationToolType.allCases.first(where: { $0.sfSymbol == obj.tool.sfSymbolName }) {
                        showHUDNotification(text: "\(toolType.localizedName) \(idx + 1)/\(total) (\(toolType.mnemonicKey))")
                    } else {
                        showHUDNotification(text: "\(obj.tool.displayName) \(idx + 1)/\(total)")
                    }
                }
                needsDisplay = true
                return true
            } else if !annotationEngine.objects.isEmpty {
                needsDisplay = true
                return true
            }
        }

        // Delete / Backspace removes selected vector annotation object
        if (event.keyCode == 51 || event.keyCode == 117), annotationEngine.selectedObjectID != nil {
            annotationEngine.deleteSelected()
            showHUDNotification(text: LocalizationManager.shared.tr(.hudDelete))
            needsDisplay = true
            return true
        }

        // Arrow keys (123: Left, 124: Right, 125: Down, 126: Up) nudging & Option+Arrow resizing
        let keyCode = event.keyCode
        if keyCode >= 123 && keyCode <= 126 {
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10.0 : 1.0
            let isOption = event.modifierFlags.contains(.option)

            if isOption {
                // Option + Arrow: Resizing
                var deltaW: CGFloat = 0
                var deltaH: CGFloat = 0
                switch keyCode {
                case 123: deltaW = -step // Left: contract width
                case 124: deltaW = step  // Right: expand width
                case 125: deltaH = -step // Down: contract height
                case 126: deltaH = step  // Up: expand height
                default: break
                }

                // If a vector annotation object is selected, resize the object
                if annotationEngine.selectedObjectID != nil {
                    annotationEngine.resizeSelected(
                        deltaWidth: deltaW,
                        deltaHeight: deltaH,
                        minimumDimension: 10.0,
                        boundary: selectionRect.isEmpty ? bounds : selectionRect
                    )
                    if let sel = annotationEngine.selectedObject {
                        let b = sel.bounds
                        showHUDNotification(text: LocalizationManager.shared.tr(.hudResize(Int(round(b.width)), Int(round(b.height)))))
                    }
                    needsDisplay = true
                    return true
                }

                // Otherwise resize the selection box
                if !selectionRect.isEmpty {
                    var newWidth = selectionRect.width
                    var newHeight = selectionRect.height

                    if deltaW > 0 {
                        newWidth = min(bounds.maxX - selectionRect.minX, selectionRect.width + deltaW)
                    } else if deltaW < 0 {
                        newWidth = max(10.0, selectionRect.width + deltaW)
                    }

                    if deltaH > 0 {
                        newHeight = min(bounds.maxY - selectionRect.minY, selectionRect.height + deltaH)
                    } else if deltaH < 0 {
                        newHeight = max(10.0, selectionRect.height + deltaH)
                    }

                    if newWidth != selectionRect.width || newHeight != selectionRect.height {
                        selectionRect = CGRect(origin: selectionRect.origin, size: CGSize(width: newWidth, height: newHeight))
                    }
                    let scale = capturedScreen.displayInfo.scaleFactor
                    let w = Int(round(selectionRect.width * scale))
                    let h = Int(round(selectionRect.height * scale))
                    showHUDNotification(text: LocalizationManager.shared.tr(.hudResize(w, h)))
                    return true
                }
            } else {
                // Arrow keys: Nudging
                var dx: CGFloat = 0
                var dy: CGFloat = 0
                switch keyCode {
                case 123: dx = -step // Left
                case 124: dx = step  // Right
                case 125: dy = -step // Down
                case 126: dy = step  // Up
                default: break
                }

                // If a vector annotation object is selected, nudge the object
                if annotationEngine.selectedObjectID != nil {
                    annotationEngine.moveSelected(by: CGPoint(x: dx, y: dy))
                    showHUDNotification(text: LocalizationManager.shared.tr(.hudNudge(Int(step))))
                    needsDisplay = true
                    return true
                }

                // Otherwise nudge the entire selection box
                if !selectionRect.isEmpty {
                    var newRect = selectionRect.offsetBy(dx: dx, dy: dy)
                    newRect.origin.x = max(bounds.minX, min(newRect.origin.x, bounds.maxX - newRect.width))
                    newRect.origin.y = max(bounds.minY, min(newRect.origin.y, bounds.maxY - newRect.height))
                    let actualDx = newRect.origin.x - selectionRect.origin.x
                    let actualDy = newRect.origin.y - selectionRect.origin.y
                    if actualDx != 0 || actualDy != 0 {
                        for i in 0..<annotationEngine.objects.count {
                            annotationEngine.objects[i].translate(by: CGPoint(x: actualDx, y: actualDy))
                        }
                        selectionRect = newRect
                    }
                    showHUDNotification(text: LocalizationManager.shared.tr(.hudNudge(Int(step))))
                    return true
                }
            }
        }

        if !selectionRect.isEmpty {
            if (event.keyCode == 36 || event.keyCode == 76) && flags.isEmpty && (windowDelegate?.prefersScrollingOnConfirm == true) {
                toolbarsViewModel.triggerScrollCapture()
                return true
            }
            return ToolbarKeyShortcutHandler.handleKeyEvent(event: event, viewModel: toolbarsViewModel)
        }
        return false
    }

    public func handleOverlayKeyUp(with event: NSEvent) -> Bool {
        if event.keyCode == 49 {
            isSpaceKeyPressed = false
            spaceKeyDragging = false
            return true
        }
        return false
    }

    public override func keyUp(with event: NSEvent) {
        if handleOverlayKeyUp(with: event) {
            return
        }
        super.keyUp(with: event)
    }

    // MARK: - Hit Testing & Mouse Event Routing

    public override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = superview != nil ? convert(point, from: superview) : point
        guard bounds.contains(localPoint) else { return nil }

        // Quick Copy pill and Dimension Badge take hit-test precedence over subviews
        if !selectionRect.isEmpty {
            if quickCopyPillFrame().contains(localPoint) || dimensionBadgeFrame().contains(localPoint) {
                return self
            }
        }
        return super.hitTest(point)
    }

    public override func mouseDown(with event: NSEvent) {
        let hadActiveTextField = (activeTextField != nil)
        commitActiveTextEditing()
        let point = convert(event.locationInWindow, from: nil)
        currentMousePoint = point
        previousDragPoint = point
        spaceKeyDragging = false

        // Popovers absorb canvas clicks to dismiss safely
        if toolbarsViewModel.isColorPalettePresented || toolbarsViewModel.isStrokeWidthPresented {
            return
        }

        // 0. Interactive Quick Copy Action Pill & Dimension Badge Click-to-Copy take top priority
        if !selectionRect.isEmpty {
            let copyPill = quickCopyPillFrame()
            if copyPill.contains(point) {
                toolbarsViewModel.triggerCopy()
                return
            }

            let badgeFrame = dimensionBadgeFrame()
            if badgeFrame.contains(point) {
                let dimString = SelectionBoxGeometry.formatDimensionBadge(
                    width: selectionRect.width,
                    height: selectionRect.height,
                    scaleFactor: capturedScreen.displayInfo.scaleFactor,
                    includeAspectRatio: false
                )
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(dimString, forType: .string)
                showHUDNotification(text: LocalizationManager.shared.tr(.copiedDimensions))
                return
            }
        }

        // Guard against clicking over floating toolbars for region moving / annotation drawing
        guard !isPointOverFloatingUI(point) else { return }

        // 1. Selection Box Grab Handles always take priority for resizing the region
        if let handle = SelectionBoxGeometry.hitTestHandle(point: point, in: selectionRect) {
            let anchor = SelectionBoxGeometry.anchorPoint(for: handle, in: selectionRect)
            initialResizingRect = selectionRect
            dragMode = .resizing(handle: handle, anchorPoint: anchor)
            updateCanvasCursor(at: point)
            return
        }

        // 2. Inside Selection Box: Vector Annotation or Region Move
        if selectionRect.contains(point) {
            // Double-click handling
            if event.clickCount == 2 {
                if let hitObj = annotationEngine.selectObject(at: point), hitObj.tool == .text {
                    startInlineTextEditing(for: hitObj, isNew: false)
                    updateTextTargetState()
                    updateCanvasCursor(at: point)
                    needsDisplay = true
                    return
                }
                // Double-click on empty region inside selection box triggers instant copy & dismiss
                toolbarsViewModel.triggerCopy()
                return
            }

            // If user clicked outside an active inline text editor on empty canvas space, only commit the current text
            // without immediately spawning a new blank text box at the clicked position.
            if hadActiveTextField {
                let clickedHandle = (annotationEngine.selectedObject?.handle(at: point) != nil)
                let clickedObject = (annotationEngine.hitObject(at: point) != nil)
                if !clickedHandle && !clickedObject {
                    updateTextTargetState()
                    updateCanvasCursor(at: point)
                    needsDisplay = true
                    return
                }
            }

            if annotationEngine.activeTool != .select {
                dragMode = .annotating
                annotationEngine.startDrag(
                    at: point,
                    tool: annotationEngine.activeTool,
                    colorHex: appSettings.activeColorHex,
                    strokeWidth: CGFloat(appSettings.activeStrokeWidth),
                    fontSize: CGFloat(appSettings.activeFontSize)
                )
                updateTextTargetState()
                updateCanvasCursor(at: point)
                needsDisplay = true
                return
            }

            // When activeTool == .select, check if user clicked an existing annotation handle or object
            if let sel = annotationEngine.selectedObject, sel.handle(at: point) != nil {
                dragMode = .annotating
                annotationEngine.startDrag(
                    at: point,
                    tool: .select,
                    colorHex: appSettings.activeColorHex,
                    strokeWidth: CGFloat(appSettings.activeStrokeWidth),
                    fontSize: CGFloat(appSettings.activeFontSize)
                )
                updateTextTargetState()
                updateCanvasCursor(at: point)
                needsDisplay = true
                return
            }

            if annotationEngine.selectObject(at: point) != nil {
                dragMode = .annotating
                annotationEngine.startDrag(
                    at: point,
                    tool: .select,
                    colorHex: appSettings.activeColorHex,
                    strokeWidth: CGFloat(appSettings.activeStrokeWidth),
                    fontSize: CGFloat(appSettings.activeFontSize)
                )
                updateTextTargetState()
                updateCanvasCursor(at: point)
                needsDisplay = true
                return
            }

            // Otherwise, move the entire selection box
            annotationEngine.deselectAll()
            updateTextTargetState()
            dragMode = .moving(startPoint: point, originalRect: selectionRect)
            updateCanvasCursor(at: point)
            return
        }

        // 3. Outside Selection Box: Start creating a new selection region
        annotationEngine.deselectAll()
        updateTextTargetState()
        dragMode = .creating(startPoint: point)
        selectionRect = CGRect(origin: point, size: CGSize(width: 1, height: 1))
        updateCanvasCursor(at: point)
    }

    public override func mouseDragged(with event: NSEvent) {
        let currentPoint = convert(event.locationInWindow, from: nil)
        currentMousePoint = currentPoint

        switch dragMode {
        case .none:
            break
        case .annotating:
            let clampedPoint = CGPoint(
                x: max(selectionRect.minX, min(currentPoint.x, selectionRect.maxX)),
                y: max(selectionRect.minY, min(currentPoint.y, selectionRect.maxY))
            )
            annotationEngine.updateDrag(
                to: clampedPoint,
                shiftKeyPressed: event.modifierFlags.contains(.shift)
            )
            needsDisplay = true
        case .creating(let startPoint):
            let isSpace = isSpaceKeyPressed || CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(49))
            if isSpace {
                spaceKeyDragging = true
                let prev = previousDragPoint ?? currentPoint
                let dx = currentPoint.x - prev.x
                let dy = currentPoint.y - prev.y
                var newRect = selectionRect.offsetBy(dx: dx, dy: dy)
                if newRect.minX < bounds.minX { newRect.origin.x = bounds.minX }
                if newRect.maxX > bounds.maxX { newRect.origin.x = bounds.maxX - newRect.width }
                if newRect.minY < bounds.minY { newRect.origin.y = bounds.minY }
                if newRect.maxY > bounds.maxY { newRect.origin.y = bounds.maxY - newRect.height }
                let actualDx = newRect.origin.x - selectionRect.origin.x
                let actualDy = newRect.origin.y - selectionRect.origin.y
                selectionRect = newRect
                let newStart = CGPoint(x: startPoint.x + actualDx, y: startPoint.y + actualDy)
                dragMode = .creating(startPoint: newStart)
            } else {
                spaceKeyDragging = false
                updateCreatingSelection(startPoint: startPoint, currentPoint: currentPoint, modifierFlags: event.modifierFlags)
            }
            previousDragPoint = currentPoint
        case .moving(let startPoint, let originalRect):
            let dx = currentPoint.x - startPoint.x
            let dy = currentPoint.y - startPoint.y
            var newRect = originalRect.offsetBy(dx: dx, dy: dy)
            if newRect.minX < bounds.minX { newRect.origin.x = bounds.minX }
            if newRect.maxX > bounds.maxX { newRect.origin.x = bounds.maxX - newRect.width }
            if newRect.minY < bounds.minY { newRect.origin.y = bounds.minY }
            if newRect.maxY > bounds.maxY { newRect.origin.y = bounds.maxY - newRect.height }
            let actualDx = newRect.origin.x - selectionRect.origin.x
            let actualDy = newRect.origin.y - selectionRect.origin.y
            if actualDx != 0 || actualDy != 0 {
                for i in 0..<annotationEngine.objects.count {
                    annotationEngine.objects[i].translate(by: CGPoint(x: actualDx, y: actualDy))
                }
            }
            selectionRect = newRect
        case .resizing(let handle, let anchor):
            let isShift = event.modifierFlags.contains(.shift)
            let isOption = event.modifierFlags.contains(.option)
            selectionRect = SelectionBoxGeometry.calculateResizedRect(
                handle: handle,
                currentPoint: currentPoint,
                anchor: anchor,
                bounds: bounds,
                currentRect: initialResizingRect.isEmpty ? selectionRect : initialResizingRect,
                shiftKeyPressed: isShift,
                optionKeyPressed: isOption
            )
        }
        updateCanvasCursor(at: currentPoint)
    }

    private func updateCreatingSelection(startPoint: CGPoint, currentPoint: CGPoint, modifierFlags: NSEvent.ModifierFlags) {
        let isOption = modifierFlags.contains(.option)
        let isShift = modifierFlags.contains(.shift)

        if isOption {
            selectionRect = SelectionBoxGeometry.calculateCenterRect(
                center: startPoint,
                target: currentPoint,
                bounds: bounds,
                squareConstrained: isShift
            )
        } else if isShift {
            let dx = currentPoint.x - startPoint.x
            let dy = currentPoint.y - startPoint.y
            let side = max(abs(dx), abs(dy))
            let squarePoint = CGPoint(
                x: startPoint.x + (dx >= 0 ? side : -side),
                y: startPoint.y + (dy >= 0 ? side : -side)
            )
            selectionRect = SelectionBoxGeometry.normalizeRect(p1: startPoint, p2: squarePoint, bounds: bounds)
        } else {
            selectionRect = SelectionBoxGeometry.normalizeRect(p1: startPoint, p2: currentPoint, bounds: bounds)
        }
    }

    public override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        currentMousePoint = point
        spaceKeyDragging = false
        previousDragPoint = nil
        isSpaceKeyPressed = false
        if dragMode == .annotating {
            let wasCreatingNewObject = (annotationEngine.activeDragObject != nil)
            let committed = annotationEngine.endDrag(at: point)
            if wasCreatingNewObject, let obj = committed, obj.tool == .text {
                startInlineTextEditing(for: obj, isNew: true)
            }
        }
        dragMode = .none
        initialResizingRect = .zero
        updateTextTargetState()
        updateToolbarPositions()
        updateCanvasCursor(at: point)
        needsDisplay = true
    }

    public override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        switch dragMode {
        case .annotating:
            if let lastPt = currentMousePoint {
                let clampedPoint = CGPoint(
                    x: max(selectionRect.minX, min(lastPt.x, selectionRect.maxX)),
                    y: max(selectionRect.minY, min(lastPt.y, selectionRect.maxY))
                )
                annotationEngine.updateDrag(
                    to: clampedPoint,
                    shiftKeyPressed: event.modifierFlags.contains(.shift)
                )
                needsDisplay = true
            }
        case .creating(let startPoint):
            if let lastPt = currentMousePoint {
                updateCreatingSelection(startPoint: startPoint, currentPoint: lastPt, modifierFlags: event.modifierFlags)
                needsDisplay = true
            }
        case .resizing(let handle, let anchor):
            if let lastPt = currentMousePoint {
                let isShift = event.modifierFlags.contains(.shift)
                let isOption = event.modifierFlags.contains(.option)
                selectionRect = SelectionBoxGeometry.calculateResizedRect(
                    handle: handle,
                    currentPoint: lastPt,
                    anchor: anchor,
                    bounds: bounds,
                    currentRect: initialResizingRect.isEmpty ? selectionRect : initialResizingRect,
                    shiftKeyPressed: isShift,
                    optionKeyPressed: isOption
                )
                needsDisplay = true
            }
        default:
            break
        }
    }

    /// Returns true when the given view point lies over the floating toolbars or when a toolbar popover is open.
    public func isPointOverFloatingUI(_ point: CGPoint) -> Bool {
        if toolbarsViewModel.isColorPalettePresented || toolbarsViewModel.isStrokeWidthPresented {
            return true
        }
        // Exclude interactive Quick Copy pill and Dimension badge so they are never blocked
        if !selectionRect.isEmpty {
            if quickCopyPillFrame().contains(point) || dimensionBadgeFrame().contains(point) {
                return false
            }
        }
        if let vHost = verticalToolbarHost, !vHost.isHidden, vHost.frame.insetBy(dx: -4, dy: -4).contains(point) {
            return true
        }
        if let hHost = horizontalToolbarHost, !hHost.isHidden, hHost.frame.insetBy(dx: -4, dy: -4).contains(point) {
            return true
        }
        return false
    }

    /// Resolves the appropriate AppKit cursor for the given point on the capture overlay canvas.
    /// Returns nil when the point is over a floating toolbar or popover so button cursors are preserved.
    public func resolveCanvasCursor(at point: CGPoint) -> NSCursor? {
        if let tf = activeTextField as? InlineCanvasTextField, tf.frame.contains(point) {
            if tf.isDraggingBorder {
                return .closedHand
            }
            let localPt = tf.convert(point, from: self)
            return tf.isPointInBorderDragZone(localPt) ? .openHand : .iBeam
        } else if let tf = activeTextField, tf.frame.contains(point) {
            return .iBeam
        }

        // 1. Active drag state cursor takes priority during active gesture
        switch dragMode {
        case .moving:
            return .closedHand
        case .resizing(let handle, _):
            return handle.cursor
        case .annotating:
            if let aHandle = annotationEngine.activeResizeHandle {
                return aHandle.cursor(isFlipped: false)
            }
            if annotationEngine.isDraggingExistingObject {
                return .closedHand
            }
            return annotationEngine.activeTool == .text ? .iBeam : .crosshair
        case .creating:
            return .crosshair
        case .none:
            break
        }

        // 2. Interactive Quick Copy action pill & Dimension badge hover cursor
        if !selectionRect.isEmpty {
            if quickCopyPillFrame().contains(point) || dimensionBadgeFrame().contains(point) {
                return .pointingHand
            }
        }

        // 3. Floating toolbars or open popover: return nil to preserve toolbar button cursor
        if isPointOverFloatingUI(point) {
            return nil
        }

        // 4. Hover state over selection box handles
        if let handle = SelectionBoxGeometry.hitTestHandle(point: point, in: selectionRect) {
            return handle.cursor
        }


        // 3. Hover state inside selection box
        if selectionRect.contains(point) {
            if let sel = annotationEngine.selectedObject, editingObjectID != sel.id, let aHandle = sel.handle(at: point) {
                return aHandle.cursor(isFlipped: false)
            }
            switch annotationEngine.activeTool {
            case .select:
                return .openHand
            case .text:
                if let hit = annotationEngine.hitObject(at: point), hit.tool == .text {
                    return .openHand
                }
                return .iBeam
            case .rectangle, .ellipse, .arrow, .line, .pen, .highlighter, .blur:
                return .crosshair
            }
        }

        // 4. Outside selection box
        return .crosshair
    }

    private func updateCanvasCursor(at point: CGPoint) {
        if let resolved = resolveCanvasCursor(at: point) {
            resolved.set()
        } else if NSCursor.current != NSCursor.pointingHand {
            NSCursor.arrow.set()
        }
    }

    public override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        currentMousePoint = point

        let badgeHover = !selectionRect.isEmpty && dimensionBadgeFrame().contains(point)
        let copyHover = !selectionRect.isEmpty && quickCopyPillFrame().contains(point)
        if badgeHover != isHoveringDimensionBadge || copyHover != isHoveringQuickCopyPill {
            isHoveringDimensionBadge = badgeHover
            isHoveringQuickCopyPill = copyHover
            needsDisplay = true
        }

        if selectionRect.isEmpty {
            needsDisplay = true
        }
        updateCanvasCursor(at: point)
    }

    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if isHoveringDimensionBadge || isHoveringQuickCopyPill {
            isHoveringDimensionBadge = false
            isHoveringQuickCopyPill = false
            needsDisplay = true
        }
    }

    // MARK: - Inline Text Editing

    private func startInlineTextEditing(for obj: AnnotationObject, isNew: Bool = false) {
        commitActiveTextEditing()
        self.preEditTextSnapshot = obj.text
        self.preEditBoundsSnapshot = obj.bounds
        self.isNewTextAnnotation = isNew

        let font = NSFont.systemFont(ofSize: obj.fontSize, weight: .semibold)
        let defaultPlaceholder = LocalizationManager.shared.tr(.toolText)
        let initialString = (obj.text == "Text" || obj.text == defaultPlaceholder) ? "" : obj.text

        let field = InlineCanvasTextField(frame: .zero)
        field.stringValue = initialString
        field.placeholderString = defaultPlaceholder
        field.font = font
        field.updateTypographyColor(ColorPreset(name: "", hex: obj.colorHex).toNSColor())
        field.allowedDragBounds = selectionRect.isEmpty ? bounds : selectionRect
        field.delegate = self

        let objID = obj.id
        field.onFrameMoved = { [weak self] delta in
            guard let self = self,
                  let currentObj = self.annotationEngine.objects.first(where: { $0.id == objID }) else { return }
            let movedBounds = currentObj.bounds.offsetBy(dx: delta.x, dy: delta.y)
            self.annotationEngine.updateLiveEditingObject(id: objID, bounds: movedBounds)
            self.needsDisplay = true
        }

        self.activeTextField = field
        self.editingObjectID = obj.id
        adjustActiveTextFieldFrame()

        addSubview(field)
        window?.makeFirstResponder(field)
        field.configureFieldEditor()
        if let editor = field.currentEditor() {
            editor.selectedRange = NSRange(location: (field.stringValue as NSString).length, length: 0)
        }

        updateTextTargetState()
        needsDisplay = true
    }

    public func adjustActiveTextFieldFrame() {
        guard let field = activeTextField,
              let objID = editingObjectID,
              let obj = annotationEngine.objects.first(where: { $0.id == objID }) else { return }

        let liveText = (field.currentEditor() as? NSTextView)?.string ?? field.stringValue
        if field.stringValue != liveText {
            field.stringValue = liveText
        }

        let fontSize = field.font?.pointSize ?? obj.fontSize
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let sample = liveText.isEmpty ? (field.placeholderString ?? "Text") : liveText
        let measured = AnnotationObject.measureTextSize(text: sample, fontSize: fontSize)

        let topAnchorY = obj.bounds.maxY
        let leftAnchorX = obj.bounds.minX
        let updatedObjBounds = CGRect(
            x: leftAnchorX,
            y: topAnchorY - measured.height,
            width: measured.width,
            height: measured.height
        )
        annotationEngine.updateLiveEditingObject(id: objID, bounds: updatedObjBounds)

        let padX = InlineCanvasTextFieldCell.horizontalPadding
        let padY = InlineCanvasTextFieldCell.verticalPadding
        let fieldW = max(72.0, measured.width + padX * 2 + 10.0)
        let fieldH = max(30.0, measured.height + padY * 2)
        let fieldMaxY = topAnchorY - fontSize + font.ascender + padY + 3.0
        var fieldFrame = CGRect(
            x: leftAnchorX - padX,
            y: fieldMaxY - fieldH,
            width: fieldW,
            height: fieldH
        )

        let clampBounds = selectionRect.isEmpty ? bounds : selectionRect
        if !clampBounds.isEmpty {
            if fieldFrame.minX < clampBounds.minX { fieldFrame.origin.x = clampBounds.minX }
            if fieldFrame.maxY > clampBounds.maxY { fieldFrame.origin.y = clampBounds.maxY - fieldFrame.height }
        }

        field.frame = fieldFrame
        (field as? InlineCanvasTextField)?.allowedDragBounds = clampBounds
        (field as? InlineCanvasTextField)?.configureFieldEditor()
        needsDisplay = true
    }

    public func cancelActiveTextEditing() {
        guard let field = activeTextField, let objID = editingObjectID else { return }
        let defaultPlaceholder = LocalizationManager.shared.tr(.toolText)
        let wasNew = isNewTextAnnotation
        let origText = preEditTextSnapshot
        let origBounds = preEditBoundsSnapshot

        field.delegate = nil
        field.removeFromSuperview()
        activeTextField = nil
        editingObjectID = nil
        preEditTextSnapshot = nil
        preEditBoundsSnapshot = nil
        isNewTextAnnotation = false

        if wasNew || (origText ?? "").isEmpty || origText == "Text" || origText == defaultPlaceholder {
            annotationEngine.discardNewInlineTextObject(id: objID)
        } else if let original = origText {
            if let ob = origBounds {
                annotationEngine.updateLiveEditingObject(id: objID, text: original, bounds: ob)
            } else {
                annotationEngine.selectedObjectID = objID
                annotationEngine.updateSelectedText(original, anchorMaxY: true)
            }
        }
        updateTextTargetState()
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    public func commitActiveTextEditing() {
        guard let field = activeTextField, let objID = editingObjectID else { return }
        let liveText = (field.currentEditor() as? NSTextView)?.string ?? field.stringValue
        let trimmed = liveText.trimmingCharacters(in: .whitespacesAndNewlines)
        let wasNew = isNewTextAnnotation
        let origText = preEditTextSnapshot ?? ""
        let origBounds = preEditBoundsSnapshot ?? .zero

        field.delegate = nil
        field.removeFromSuperview()
        activeTextField = nil
        editingObjectID = nil
        preEditTextSnapshot = nil
        preEditBoundsSnapshot = nil
        isNewTextAnnotation = false

        if trimmed.isEmpty {
            if wasNew {
                annotationEngine.discardNewInlineTextObject(id: objID)
            } else {
                annotationEngine.selectedObjectID = objID
                annotationEngine.deleteSelected()
            }
        } else {
            annotationEngine.commitInlineTextEdit(
                id: objID,
                newText: trimmed,
                initialText: origText,
                initialBounds: origBounds,
                isNew: wasNew,
                anchorMaxY: true
            )
        }
        updateTextTargetState()
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    public func controlTextDidChange(_ obj: Notification) {
        adjustActiveTextFieldFrame()
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            let flags = NSApp.currentEvent?.modifierFlags ?? []
            if flags.contains(.shift) || flags.contains(.option) {
                textView.insertNewlineIgnoringFieldEditor(nil)
                adjustActiveTextFieldFrame()
                return true
            }
            commitActiveTextEditing()
            return true
        }
        if commandSelector == #selector(NSResponder.insertLineBreak(_:)) ||
           commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
            textView.insertNewlineIgnoringFieldEditor(nil)
            adjustActiveTextFieldFrame()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelActiveTextEditing()
            return true
        }
        return false
    }

    public func controlTextDidEndEditing(_ obj: Notification) {
        if let win = window {
            let mousePt = convert(win.mouseLocationOutsideOfEventStream, from: nil)
            if isPointOverFloatingUI(mousePt) {
                return
            }
        }
        commitActiveTextEditing()
    }
}
