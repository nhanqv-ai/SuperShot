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

    private var verticalToolbarHost: NSHostingView<VerticalAnnotationToolbarView>?
    private var horizontalToolbarHost: NSHostingView<HorizontalActionToolbarView>?
    private var activeTextField: NSTextField?
    private var editingObjectID: UUID?
    public var currentMousePoint: CGPoint?
    private var trackingAreaRef: NSTrackingArea?
    private var cancellables = Set<AnyCancellable>()

    public init(
        frame: NSRect,
        capturedScreen: CapturedScreen,
        appSettings: AppSettings = AppSettings(),
        windowDelegate: CaptureOverlayWindow
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
    }

    private func setupBindings() {
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
            self.annotationEngine.activeTool = Self.mapTool(toolType)
        }

        toolbarsViewModel.onColorSelected = { [weak self] hex in
            guard let self = self else { return }
            if self.annotationEngine.selectedObjectID != nil {
                self.annotationEngine.recolorSelected(newHex: hex)
                self.needsDisplay = true
            }
        }

        toolbarsViewModel.onStrokeWidthSelected = { [weak self] width in
            guard let self = self else { return }
            if self.annotationEngine.selectedObjectID != nil {
                self.annotationEngine.updateSelectedStrokeWidth(width)
                self.needsDisplay = true
            }
        }

        toolbarsViewModel.onFontSizeSelected = { [weak self] size in
            guard let self = self else { return }
            if self.annotationEngine.selectedObjectID != nil {
                self.annotationEngine.updateSelectedFontSize(size)
                self.needsDisplay = true
            }
        }

        toolbarsViewModel.onUndoRequested = { [weak self] in
            self?.commitActiveTextEditing()
            self?.annotationEngine.undo()
            self?.needsDisplay = true
        }

        toolbarsViewModel.onRedoRequested = { [weak self] in
            self?.commitActiveTextEditing()
            self?.annotationEngine.redo()
            self?.needsDisplay = true
        }

        toolbarsViewModel.onCopyRequested = { [weak self] in
            guard let self = self, !self.selectionRect.isEmpty else { return }
            self.commitActiveTextEditing()
            self.windowDelegate?.captureDelegate?.overlayDidConfirmSelection(
                rect: self.selectionRect,
                display: self.capturedScreen.displayInfo
            )
            self.windowDelegate?.close()
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
        let topLeftCropRect = CGRect(
            x: max(0, min(selectionRect.minX, bounds.width)),
            y: max(0, min(windowH - selectionRect.maxY, windowH)),
            width: max(1, min(selectionRect.width, bounds.width - selectionRect.minX)),
            height: max(1, min(selectionRect.height, windowH - (windowH - selectionRect.maxY)))
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

            // Step 5: Draw live dimension badge
            drawDimensionBadge(in: context)
        }
        context.restoreGState()
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

        // 4. Selection handles on selected vector annotation
        if let selected = annotationEngine.selectedObject {
            context.saveGState()
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(1.5)
            context.stroke(selected.bounds.insetBy(dx: -2, dy: -2))

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
        let cropInPixels = CGRect(
            x: rect.minX * scale,
            y: (windowH - rect.maxY) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )

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
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: nsColor]
            let attrStr = NSAttributedString(string: obj.text, attributes: attrs)
            let textSize = attrStr.size()
            attrStr.draw(in: CGRect(
                x: obj.bounds.minX,
                y: obj.bounds.minY,
                width: max(textSize.width + 12, obj.bounds.width),
                height: max(textSize.height + 8, obj.bounds.height)
            ))
        case .blur, .select:
            break
        }
        context.restoreGState()
    }

    private func drawArrow(p1: CGPoint, p2: CGPoint, strokeWidth: CGFloat, color: NSColor, context: CGContext) {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        let len = hypot(dx, dy)
        guard len > 1.0 else { return }
        let theta = atan2(dy, dx)
        let headLen = max(12.0, min(len * 0.5, strokeWidth * 4.0))
        let wingAngle: CGFloat = 0.488
        let shaftEnd = CGPoint(x: p2.x - (headLen * 0.7) * cos(theta), y: p2.y - (headLen * 0.7) * sin(theta))
        let w1 = CGPoint(x: p2.x - headLen * cos(theta - wingAngle), y: p2.y - headLen * sin(theta - wingAngle))
        let w2 = CGPoint(x: p2.x - headLen * cos(theta + wingAngle), y: p2.y - headLen * sin(theta + wingAngle))

        context.strokeLineSegments(between: [p1, shaftEnd])
        let arrowPath = CGMutablePath()
        arrowPath.move(to: p2)
        arrowPath.addLine(to: w1)
        arrowPath.addLine(to: w2)
        arrowPath.closeSubpath()
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

    private func drawDimensionBadge(in context: CGContext) {
        let badgeFrame = ToolbarPositionCalculator.calculateDimensionBadgeFrame(
            selectionRect: selectionRect,
            screenBounds: bounds
        )
        let text = SelectionBoxGeometry.formatDimensionBadge(
            width: selectionRect.width,
            height: selectionRect.height,
            scaleFactor: capturedScreen.displayInfo.scaleFactor
        )

        let badgePath = NSBezierPath(roundedRect: badgeFrame, xRadius: 4.0, yRadius: 4.0)
        NSColor.black.withAlphaComponent(0.75).setFill()
        badgePath.fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let str = NSAttributedString(string: text, attributes: attributes)
        let textSize = str.size()
        let textRect = CGRect(
            x: badgeFrame.midX - textSize.width / 2.0,
            y: badgeFrame.midY - textSize.height / 2.0,
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
        if activeTextField != nil {
            if event.keyCode == 53 || event.keyCode == 36 || event.keyCode == 76 {
                commitActiveTextEditing()
                return true
            }
            return false
        }

        // Delete / Backspace removes selected vector annotation object
        if (event.keyCode == 51 || event.keyCode == 117), annotationEngine.selectedObjectID != nil {
            annotationEngine.deleteSelected()
            needsDisplay = true
            return true
        }

        if !selectionRect.isEmpty {
            return ToolbarKeyShortcutHandler.handleKeyEvent(event: event, viewModel: toolbarsViewModel)
        }
        return false
    }

    public override func mouseDown(with event: NSEvent) {
        commitActiveTextEditing()
        let point = convert(event.locationInWindow, from: nil)

        // 1. Selection Box Grab Handles always take priority for resizing the region
        if let handle = SelectionBoxGeometry.hitTestHandle(point: point, in: selectionRect) {
            let anchor = SelectionBoxGeometry.anchorPoint(for: handle, in: selectionRect)
            dragMode = .resizing(handle: handle, anchorPoint: anchor)
            return
        }

        // 2. Inside Selection Box: Vector Annotation or Region Move
        if selectionRect.contains(point) {
            // Double-click on an existing text object edits it in place
            if event.clickCount == 2,
               let hitObj = annotationEngine.selectObject(at: point),
               hitObj.tool == .text {
                startInlineTextEditing(for: hitObj)
                needsDisplay = true
                return
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
                needsDisplay = true
                return
            }

            // Otherwise, move the entire selection box
            annotationEngine.deselectAll()
            dragMode = .moving(startPoint: point, originalRect: selectionRect)
            return
        }

        // 3. Outside Selection Box: Start creating a new selection region
        annotationEngine.deselectAll()
        dragMode = .creating(startPoint: point)
        selectionRect = CGRect(origin: point, size: CGSize(width: 1, height: 1))
    }

    public override func mouseDragged(with event: NSEvent) {
        let currentPoint = convert(event.locationInWindow, from: nil)

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
            selectionRect = SelectionBoxGeometry.normalizeRect(p1: startPoint, p2: currentPoint, bounds: bounds)
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
            switch handle {
            case .topLeft, .topRight, .bottomLeft, .bottomRight:
                selectionRect = SelectionBoxGeometry.normalizeRect(p1: anchor, p2: currentPoint, bounds: bounds)
            case .topCenter, .bottomCenter:
                let y1 = min(anchor.y, currentPoint.y)
                let y2 = max(anchor.y, currentPoint.y)
                let clampedY1 = max(bounds.minY, min(y1, bounds.maxY))
                let clampedY2 = max(bounds.minY, min(y2, bounds.maxY))
                selectionRect = CGRect(x: selectionRect.origin.x, y: clampedY1, width: selectionRect.width, height: max(1.0, clampedY2 - clampedY1))
            case .middleLeft, .middleRight:
                let x1 = min(anchor.x, currentPoint.x)
                let x2 = max(anchor.x, currentPoint.x)
                let clampedX1 = max(bounds.minX, min(x1, bounds.maxX))
                let clampedX2 = max(bounds.minX, min(x2, bounds.maxX))
                selectionRect = CGRect(x: clampedX1, y: selectionRect.origin.y, width: max(1.0, clampedX2 - clampedX1), height: selectionRect.height)
            }
        }
    }

    public override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if dragMode == .annotating {
            let committed = annotationEngine.endDrag(at: point)
            if let obj = committed, obj.tool == .text {
                startInlineTextEditing(for: obj)
            }
        }
        dragMode = .none
        updateToolbarPositions()
        needsDisplay = true
    }

    public override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        currentMousePoint = point
        if selectionRect.isEmpty {
            needsDisplay = true
        }
        if let handle = SelectionBoxGeometry.hitTestHandle(point: point, in: selectionRect) {
            handle.cursor.set()
        } else if selectionRect.contains(point) {
            if annotationEngine.activeTool == .select {
                NSCursor.openHand.set()
            } else if annotationEngine.activeTool == .text {
                NSCursor.iBeam.set()
            } else {
                NSCursor.crosshair.set()
            }
        } else {
            NSCursor.crosshair.set()
        }
    }

    // MARK: - Inline Text Editing

    private func startInlineTextEditing(for obj: AnnotationObject) {
        commitActiveTextEditing()

        let fieldFrame = CGRect(
            x: obj.bounds.minX,
            y: obj.bounds.minY,
            width: max(140, obj.bounds.width),
            height: max(obj.fontSize + 12, obj.bounds.height)
        )
        let field = NSTextField(frame: fieldFrame)
        field.stringValue = obj.text == "Text" ? "" : obj.text
        field.placeholderString = "Text"
        field.font = NSFont.systemFont(ofSize: obj.fontSize, weight: .semibold)
        field.textColor = ColorPreset(name: "", hex: obj.colorHex).toNSColor()
        field.isBordered = true
        field.drawsBackground = true
        field.backgroundColor = NSColor.black.withAlphaComponent(0.75)
        field.focusRingType = .none
        field.delegate = self

        addSubview(field)
        window?.makeFirstResponder(field)

        self.activeTextField = field
        self.editingObjectID = obj.id
    }

    public func commitActiveTextEditing() {
        guard let field = activeTextField, let objID = editingObjectID else { return }
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        annotationEngine.selectedObjectID = objID
        if trimmed.isEmpty {
            annotationEngine.deleteSelected()
        } else {
            annotationEngine.updateSelectedText(field.stringValue)
        }
        field.removeFromSuperview()
        activeTextField = nil
        editingObjectID = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    public func controlTextDidEndEditing(_ obj: Notification) {
        commitActiveTextEditing()
    }
}
