import AppKit
import SwiftUI
import Combine
import CoreText
import SuperShotCore

// MARK: - Scrollable Annotation Document View

/// Custom tall canvas document view rendering base stitched image and vector annotations.
/// Optimized for ultra-tall screenshots (up to 30,000 px) with O(1) memory overhead by rendering
/// strictly within the visible dirtyRect slice and avoiding monolithic CALayer textures.
public final class ScrollableAnnotationDocumentView: NSView, NSTextFieldDelegate {
    public let baseImage: CGImage
    public let engine: AnnotationEngine
    public var scale: CGFloat = 2.0

    public override var isFlipped: Bool { true }

    public var currentColorHex: String = "#FF3B30"
    public var currentStrokeWidth: CGFloat = 3.0
    public var currentFontSize: CGFloat = 18.0

    public var hasActiveTextEditing: Bool { activeTextField != nil }
    private var activeTextField: NSTextField?
    private var editingObjectID: UUID?
    private var trackingAreaRef: NSTrackingArea?
    private var isDraggingOnCanvas: Bool = false
    public var isPointOverFloatingToolbar: ((CGPoint) -> Bool)?
    private var cancellables = Set<AnyCancellable>()
    private var toolHUDText: String? = nil
    private var toolHUDTimer: Timer? = nil

    public init(baseImage: CGImage, engine: AnnotationEngine, scale: CGFloat = 2.0) {
        self.baseImage = baseImage
        self.engine = engine
        self.scale = max(1.0, scale)

        let width = CGFloat(baseImage.width) / self.scale
        let height = CGFloat(baseImage.height) / self.scale
        let canvasFrame = NSRect(x: 0, y: 0, width: width, height: height)

        super.init(frame: canvasFrame)

        // Listen to engine updates for live redraw
        engine.objectWillChange.sink { [weak self] _ in
            self?.needsDisplay = true
        }.store(in: &cancellables)
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

    /// Resolves the appropriate AppKit cursor for the given document point in the scrollable canvas.
    /// Returns nil when the point is over a floating toolbar or popover.
    public func resolveCanvasCursor(at point: CGPoint, windowPoint: CGPoint? = nil) -> NSCursor? {
        if let winPt = windowPoint, isPointOverFloatingToolbar?(winPt) == true {
            return nil
        }
        if let tf = activeTextField, tf.frame.contains(point) {
            return .iBeam
        }

        if isDraggingOnCanvas {
            if let aHandle = engine.activeResizeHandle {
                return aHandle.cursor(isFlipped: true)
            }
            if engine.isDraggingExistingObject {
                return .closedHand
            }
            return engine.activeTool == .text ? .iBeam : (engine.activeTool == .select ? .arrow : .crosshair)
        }

        if let sel = engine.selectedObject, let aHandle = sel.handle(at: point) {
            return aHandle.cursor(isFlipped: true)
        }

        switch engine.activeTool {
        case .select:
            if engine.hitObject(at: point) != nil {
                return .openHand
            }
            return .arrow
        case .text:
            return .iBeam
        case .rectangle, .ellipse, .arrow, .line, .pen, .highlighter, .blur:
            return .crosshair
        }
    }

    private func updateCanvasCursor(with event: NSEvent) {
        let winPt = event.locationInWindow
        let docPt = convert(winPt, from: nil)
        if let resolved = resolveCanvasCursor(at: docPt, windowPoint: winPt) {
            resolved.set()
        } else if NSCursor.current != NSCursor.pointingHand {
            NSCursor.arrow.set()
        }
    }

    public func updateCanvasCursor(at docPoint: CGPoint? = nil) {
        let winPt = window?.mouseLocationOutsideOfEventStream ?? .zero
        let pt = docPoint ?? convert(winPt, from: nil)
        if let resolved = resolveCanvasCursor(at: pt, windowPoint: winPt) {
            resolved.set()
        } else if NSCursor.current != NSCursor.pointingHand {
            NSCursor.arrow.set()
        }
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

    public func showToolSelectionHUD(tool: AnnotationToolType) {
        showHUDNotification(text: "\(tool.localizedName) (\(tool.mnemonicKey))")
    }

    private func drawToolFeedbackHUD(text: String, in visibleRect: CGRect, context: CGContext) {
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
            x: visibleRect.midX - pillW / 2.0,
            y: visibleRect.minY + 24.0,
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

    // MARK: - Viewport Drawing

    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // 1. Draw base image slice in flipped coordinates
        context.saveGState()
        context.clip(to: dirtyRect)
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1.0, y: -1.0)
        context.draw(baseImage, in: CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height))
        context.restoreGState()

        // 2. Draw Region Blur annotations intersecting dirtyRect
        for obj in engine.objects where obj.tool == .blur && obj.bounds.intersects(dirtyRect) {
            drawBlurOverlay(obj: obj, context: context)
        }

        // 3. Draw Vector Annotations intersecting dirtyRect
        for obj in engine.objects where obj.tool != .blur && obj.bounds.intersects(dirtyRect) {
            drawVectorObject(obj: obj, context: context)
        }

        // 4. Draw Active Drag Draft
        if let draft = engine.activeDragObject, draft.bounds.intersects(dirtyRect) {
            if draft.tool == .blur {
                drawBlurOverlay(obj: draft, context: context)
            } else {
                drawVectorObject(obj: draft, context: context)
            }
        }

        // 5. Draw Selection Outlines & Grab Handles
        if let selected = engine.selectedObject, selected.bounds.intersects(dirtyRect) {
            drawSelectionHighlight(for: selected, context: context)
        }

        // 6. Draw Tool Selection Feedback HUD
        if let hudText = toolHUDText {
            let visRect = enclosingScrollView?.documentVisibleRect ?? bounds
            drawToolFeedbackHUD(text: hudText, in: visRect, context: context)
        }
    }

    // MARK: - Annotation Drawing Helpers

    private func drawBlurOverlay(obj: AnnotationObject, context: CGContext) {
        let rect = obj.bounds.intersection(bounds)
        guard rect.width > 1 && rect.height > 1 else { return }

        context.saveGState()
        context.clip(to: rect)

        let blockSize: CGFloat = 12.0
        let pixelRect = CGRect(
            x: floor(rect.minX * scale),
            y: floor(rect.minY * scale),
            width: max(1, ceil(rect.width * scale)),
            height: max(1, ceil(rect.height * scale))
        ).intersection(CGRect(x: 0, y: 0, width: CGFloat(baseImage.width), height: CGFloat(baseImage.height)))

        let smallW = max(1, Int(ceil(rect.width / blockSize)))
        let smallH = max(1, Int(ceil(rect.height / blockSize)))
        let colorSpace = baseImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()

        if pixelRect.width >= 1,
           pixelRect.height >= 1,
           let cropped = baseImage.cropping(to: pixelRect),
           let smallCtx = CGContext(
               data: nil,
               width: smallW,
               height: smallH,
               bitsPerComponent: 8,
               bytesPerRow: 0,
               space: colorSpace,
               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
           ) {
            smallCtx.interpolationQuality = .low
            smallCtx.draw(cropped, in: CGRect(x: 0, y: 0, width: CGFloat(smallW), height: CGFloat(smallH)))
            if let pixelated = smallCtx.makeImage() {
                context.saveGState()
                context.interpolationQuality = .none
                context.translateBy(x: rect.minX, y: rect.maxY)
                context.scaleBy(x: 1.0, y: -1.0)
                context.draw(pixelated, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
                context.restoreGState()
            }
        } else {
            let cols = max(1, Int(ceil(rect.width / blockSize)))
            let rows = max(1, Int(ceil(rect.height / blockSize)))
            for r in 0..<rows {
                for c in 0..<cols {
                    let cell = CGRect(
                        x: rect.minX + CGFloat(c) * blockSize,
                        y: rect.minY + CGFloat(r) * blockSize,
                        width: min(blockSize, rect.maxX - (rect.minX + CGFloat(c) * blockSize)),
                        height: min(blockSize, rect.maxY - (rect.minY + CGFloat(r) * blockSize))
                    )
                    let shade = ((r + c) % 2 == 0) ? 0.45 : 0.55
                    context.setFillColor(gray: shade, alpha: 0.90)
                    context.fill(cell)
                }
            }
        }

        context.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
        context.setLineWidth(1.0)
        context.setLineDash(phase: 0, lengths: [3, 3])
        context.stroke(rect)
        context.restoreGState()
    }

    private func drawVectorObject(obj: AnnotationObject, context: CGContext) {
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
            drawText(obj: obj, context: context)
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

    private func drawText(obj: AnnotationObject, context: CGContext) {
        guard !obj.text.isEmpty, editingObjectID != obj.id else { return }
        let font = NSFont.systemFont(ofSize: obj.fontSize, weight: .semibold)
        let nsColor = ColorPreset(name: "", hex: obj.colorHex).toNSColor()
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: nsColor]

        let lines = obj.text.components(separatedBy: .newlines)
        let lineHeight = obj.fontSize * 1.25

        for (index, rawLine) in lines.enumerated() {
            guard !rawLine.isEmpty else { continue }
            let attrStr = NSAttributedString(string: rawLine, attributes: attrs)
            let line = CTLineCreateWithAttributedString(attrStr)

            context.saveGState()
            context.translateBy(x: obj.bounds.minX, y: obj.bounds.minY + obj.fontSize + CGFloat(index) * lineHeight)
            context.scaleBy(x: 1.0, y: -1.0)
            context.textPosition = .zero
            CTLineDraw(line, context)
            context.restoreGState()
        }
    }

    private func drawSelectionHighlight(for obj: AnnotationObject, context: CGContext) {
        context.saveGState()
        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(1.5)
        context.stroke(obj.bounds.insetBy(dx: -2, dy: -2))

        for (_, pos) in obj.handlePositions() {
            let handleRect = CGRect(x: pos.x - 4, y: pos.y - 4, width: 8, height: 8)
            context.setFillColor(NSColor.white.cgColor)
            context.fillEllipse(in: handleRect)
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(1.5)
            context.strokeEllipse(in: handleRect)
        }
        context.restoreGState()
    }

    // MARK: - Interactive Mouse Events

    public override func mouseMoved(with event: NSEvent) {
        updateCanvasCursor(with: event)
    }

    public override func mouseDown(with event: NSEvent) {
        commitActiveTextEditing()
        let point = convert(event.locationInWindow, from: nil)

        // Double click on text object initiates in-place text editing
        if event.clickCount == 2, let clickedObj = engine.selectObject(at: point), clickedObj.tool == .text {
            startInlineTextEditing(for: clickedObj)
            updateCanvasCursor(with: event)
            return
        }

        isDraggingOnCanvas = true
        engine.startDrag(
            at: point,
            colorHex: currentColorHex,
            strokeWidth: currentStrokeWidth,
            fontSize: currentFontSize
        )
        updateCanvasCursor(with: event)
        needsDisplay = true
    }

    public override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let shift = event.modifierFlags.contains(.shift)
        engine.updateDrag(to: point, shiftKeyPressed: shift)
        autoscroll(with: event)
        updateCanvasCursor(with: event)
        needsDisplay = true
    }

    public override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        isDraggingOnCanvas = false
        let committed = engine.endDrag(at: point)

        // If newly created object is a text box, immediately focus inline editor
        if let created = committed, created.tool == .text, (created.text.isEmpty || created.text == "Text") {
            startInlineTextEditing(for: created)
        }

        updateCanvasCursor(with: event)
        needsDisplay = true
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
        engine.selectedObjectID = objID
        if trimmed.isEmpty {
            engine.deleteSelected()
        } else {
            engine.updateSelectedText(field.stringValue)
        }
        field.removeFromSuperview()
        activeTextField = nil
        editingObjectID = nil
        needsDisplay = true
    }

    public func controlTextDidEndEditing(_ obj: Notification) {
        commitActiveTextEditing()
    }
}

// MARK: - Scrollable Annotation Scroll View

public final class ScrollableAnnotationScrollView: NSScrollView {
    public private(set) var documentCanvasView: ScrollableAnnotationDocumentView?

    public init(documentCanvasView: ScrollableAnnotationDocumentView) {
        self.documentCanvasView = documentCanvasView
        super.init(frame: .zero)

        self.documentView = documentCanvasView
        self.hasVerticalScroller = true
        self.hasHorizontalScroller = true
        self.autohidesScrollers = true
        self.drawsBackground = false
        self.backgroundColor = .clear

        self.allowsMagnification = true
        self.minMagnification = 0.1
        self.maxMagnification = 4.0
    }

    public var onMagnificationChanged: ((CGFloat) -> Void)?
    public override var magnification: CGFloat {
        didSet {
            onMagnificationChanged?(magnification)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func zoomIn() {
        magnification = min(maxMagnification, magnification * 1.25)
    }

    public func zoomOut() {
        magnification = max(minMagnification, magnification / 1.25)
    }

    public func zoomToActualSize() {
        guard let _ = documentCanvasView else {
            magnification = 1.0
            return
        }
        let visibleRect = documentVisibleRect
        let centerPoint = NSPoint(x: visibleRect.midX, y: visibleRect.midY)
        setMagnification(1.0, centeredAt: centerPoint)
    }

    public func zoomToFitWidth() {
        guard let doc = documentCanvasView, doc.bounds.width > 0 else { return }
        let visibleW = contentSize.width - 20
        magnification = max(minMagnification, min(maxMagnification, visibleW / doc.bounds.width))
    }
}

// MARK: - Floating Quick Zoom HUD

public final class ScrollableZoomViewModel: ObservableObject {
    @Published public var magnification: CGFloat = 1.0
    public var onZoomIn: (() -> Void)?
    public var onZoomOut: (() -> Void)?
    public var onActualSize: (() -> Void)?
    public var onFitWidth: (() -> Void)?

    public init(magnification: CGFloat = 1.0) {
        self.magnification = magnification
    }
}

public struct ScrollableZoomControlsView: View {
    @ObservedObject public var viewModel: ScrollableZoomViewModel

    public init(viewModel: ScrollableZoomViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 4) {
            Button(action: { viewModel.onZoomOut?() }) {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help(LocalizationManager.shared.tr(.zoomOutTooltip))

            Button(action: { viewModel.onActualSize?() }) {
                Text("\(Int(round(viewModel.magnification * 100)))%")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .frame(minWidth: 42, minHeight: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help(LocalizationManager.shared.tr(.zoomActualSizeTooltip))

            Button(action: { viewModel.onZoomIn?() }) {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help(LocalizationManager.shared.tr(.zoomInTooltip))

            Divider()
                .frame(height: 14)
                .padding(.horizontal, 2)

            Button(action: { viewModel.onFitWidth?() }) {
                Image(systemName: "arrow.left.and.right.to.lines")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help(LocalizationManager.shared.tr(.zoomFitWidthTooltip))

            Button(action: { viewModel.onActualSize?() }) {
                Image(systemName: "1.magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help(LocalizationManager.shared.tr(.zoomActualSizeTooltip))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 3)
        )
    }
}

// MARK: - Scrollable Canvas View (Host Container with Toolbar)

public final class ScrollableCanvasView: NSView {
    public let scrollView: ScrollableAnnotationScrollView
    public let documentView: ScrollableAnnotationDocumentView
    public let engine: AnnotationEngine
    public let appSettings: AppSettings
    public let toolbarsViewModel: FloatingToolbarsViewModel
    public let zoomViewModel: ScrollableZoomViewModel
    public let zoomHUD: NSHostingView<ScrollableZoomControlsView>

    public var onCopyRequested: (() -> Void)?
    public var onSaveRequested: (() -> Void)?
    public var onShareRequested: ((NSView) -> Void)?
    public var onCloseRequested: (() -> Void)?

    private var cancellables = Set<AnyCancellable>()

    public init(baseImage: CGImage, scale: CGFloat = 2.0, appSettings: AppSettings = AppSettings()) {
        let engine = AnnotationEngine()
        self.engine = engine
        self.appSettings = appSettings
        self.toolbarsViewModel = FloatingToolbarsViewModel(appSettings: appSettings)
        let docView = ScrollableAnnotationDocumentView(baseImage: baseImage, engine: engine, scale: scale)
        docView.currentColorHex = appSettings.activeColorHex
        docView.currentStrokeWidth = CGFloat(appSettings.activeStrokeWidth)
        docView.currentFontSize = CGFloat(appSettings.activeFontSize)
        self.documentView = docView
        let sView = ScrollableAnnotationScrollView(documentCanvasView: docView)
        self.scrollView = sView

        let zModel = ScrollableZoomViewModel(magnification: sView.magnification)
        self.zoomViewModel = zModel
        let zHUD = NSHostingView(rootView: ScrollableZoomControlsView(viewModel: zModel))
        self.zoomHUD = zHUD

        super.init(frame: .zero)

        sView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sView)

        let vToolbar = NSHostingView(rootView: VerticalAnnotationToolbarView(viewModel: toolbarsViewModel, appSettings: appSettings))
        let hToolbar = NSHostingView(rootView: HorizontalActionToolbarView(viewModel: toolbarsViewModel, showScrollCapture: false))
        vToolbar.translatesAutoresizingMaskIntoConstraints = false
        hToolbar.translatesAutoresizingMaskIntoConstraints = false
        zHUD.translatesAutoresizingMaskIntoConstraints = false
        addSubview(vToolbar)
        addSubview(hToolbar)
        addSubview(zHUD)

        sView.onMagnificationChanged = { [weak zModel] mag in
            zModel?.magnification = mag
        }
        zModel.onZoomIn = { [weak sView] in
            sView?.zoomIn()
        }
        zModel.onZoomOut = { [weak sView] in
            sView?.zoomOut()
        }
        zModel.onActualSize = { [weak sView] in
            sView?.zoomToActualSize()
        }
        zModel.onFitWidth = { [weak sView] in
            sView?.zoomToFitWidth()
        }

        docView.isPointOverFloatingToolbar = { [weak self, weak vToolbar, weak hToolbar, weak zHUD] winPt in
            guard let self = self else { return false }
            if self.toolbarsViewModel.isColorPalettePresented || self.toolbarsViewModel.isStrokeWidthPresented {
                return true
            }
            let localPt = self.convert(winPt, from: nil)
            if let v = vToolbar, !v.isHidden, v.frame.insetBy(dx: -4, dy: -4).contains(localPt) {
                return true
            }
            if let h = hToolbar, !h.isHidden, h.frame.insetBy(dx: -4, dy: -4).contains(localPt) {
                return true
            }
            if let z = zHUD, !z.isHidden, z.frame.insetBy(dx: -4, dy: -4).contains(localPt) {
                return true
            }
            return false
        }

        NSLayoutConstraint.activate([
            sView.topAnchor.constraint(equalTo: topAnchor),
            sView.bottomAnchor.constraint(equalTo: bottomAnchor),
            sView.leadingAnchor.constraint(equalTo: leadingAnchor),
            sView.trailingAnchor.constraint(equalTo: trailingAnchor),

            vToolbar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            vToolbar.topAnchor.constraint(equalTo: topAnchor, constant: 16),

            hToolbar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            hToolbar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),

            zHUD.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            zHUD.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])

        setupToolbarBindings()
    }

    private func setupToolbarBindings() {
        engine.$canUndo
            .sink { [weak self] canUndo in
                self?.toolbarsViewModel.canUndo = canUndo
            }
            .store(in: &cancellables)

        engine.$canRedo
            .sink { [weak self] canRedo in
                self?.toolbarsViewModel.canRedo = canRedo
            }
            .store(in: &cancellables)

        toolbarsViewModel.onToolChanged = { [weak self] toolType in
            guard let self = self else { return }
            self.documentView.commitActiveTextEditing()
            switch toolType {
            case .select: self.engine.activeTool = .select
            case .rectangle: self.engine.activeTool = .rectangle
            case .ellipse: self.engine.activeTool = .ellipse
            case .arrow: self.engine.activeTool = .arrow
            case .line: self.engine.activeTool = .line
            case .pen: self.engine.activeTool = .pen
            case .highlighter: self.engine.activeTool = .highlighter
            case .text: self.engine.activeTool = .text
            case .blur: self.engine.activeTool = .blur
            }
            self.documentView.updateCanvasCursor()
            self.documentView.showToolSelectionHUD(tool: toolType)
        }

        toolbarsViewModel.onColorSelected = { [weak self] hex in
            guard let self = self else { return }
            self.documentView.currentColorHex = hex
            if self.engine.selectedObjectID != nil {
                self.engine.recolorSelected(newHex: hex)
                self.documentView.needsDisplay = true
            }
        }

        toolbarsViewModel.onStrokeWidthSelected = { [weak self] width in
            guard let self = self else { return }
            self.documentView.currentStrokeWidth = width
            if self.engine.selectedObjectID != nil {
                self.engine.updateSelectedStrokeWidth(width)
            }
            self.showStrokeWidthHUD(width: Int(width))
            self.documentView.needsDisplay = true
        }

        toolbarsViewModel.onFontSizeSelected = { [weak self] size in
            guard let self = self else { return }
            self.documentView.currentFontSize = size
            if self.engine.selectedObjectID != nil {
                self.engine.updateSelectedFontSize(size)
                self.documentView.needsDisplay = true
            }
        }

        toolbarsViewModel.onUndoRequested = { [weak self] in
            self?.documentView.commitActiveTextEditing()
            self?.engine.undo()
            self?.documentView.needsDisplay = true
        }

        toolbarsViewModel.onRedoRequested = { [weak self] in
            self?.documentView.commitActiveTextEditing()
            self?.engine.redo()
            self?.documentView.needsDisplay = true
        }

        toolbarsViewModel.onDuplicateRequested = { [weak self] in
            guard let self = self else { return }
            self.documentView.commitActiveTextEditing()
            if self.engine.selectedObjectID != nil {
                self.engine.duplicateSelected(within: self.documentView.bounds)
                self.documentView.needsDisplay = true
            }
        }

        toolbarsViewModel.onCopyRequested = { [weak self] in
            guard let self = self else { return }
            self.documentView.commitActiveTextEditing()
            self.copyToClipboard()
            self.documentView.showHUDNotification(text: LocalizationManager.shared.tr(.copiedToClipboard))
            self.onCopyRequested?()
        }

        toolbarsViewModel.onSaveRequested = { [weak self] in
            guard let self = self else { return }
            self.documentView.commitActiveTextEditing()
            self.saveToFile(window: self.window)
            self.documentView.showHUDNotification(text: LocalizationManager.shared.tr(.savedToFile))
            self.onSaveRequested?()
        }

        toolbarsViewModel.onShareRequested = { [weak self] anchorView in
            guard let self = self else { return }
            self.documentView.commitActiveTextEditing()
            self.share(from: anchorView)
            self.onShareRequested?(anchorView)
        }

        toolbarsViewModel.defaultAnchorView = self

        toolbarsViewModel.onClearAllRequested = { [weak self] in
            guard let self = self else { return }
            self.documentView.commitActiveTextEditing()
            let count = self.engine.clearAll()
            if count > 0 {
                self.documentView.showHUDNotification(text: LocalizationManager.shared.tr(.annotationsCleared))
                self.documentView.needsDisplay = true
            }
        }

        toolbarsViewModel.onCancelRequested = { [weak self] in
            self?.documentView.commitActiveTextEditing()
            self?.onCloseRequested?()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func showHUDNotification(text: String) {
        documentView.showHUDNotification(text: text)
    }

    public func showStrokeWidthHUD(width: Int) {
        documentView.showStrokeWidthHUD(width: width)
    }

    public func copyToClipboard() {
        guard let rendered = ImageRenderer.render(
            baseImage: documentView.baseImage,
            annotations: engine.objects,
            scale: documentView.scale
        ) else { return }

        let rep = NSBitmapImageRep(cgImage: rendered)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let pngData = rep.representation(using: .png, properties: [:]) {
            pasteboard.setData(pngData, forType: .png)
        }
        if let tiffData = rep.tiffRepresentation {
            pasteboard.setData(tiffData, forType: .tiff)
        }
    }

    public func saveToFile(window: NSWindow?) {
        guard let rendered = ImageRenderer.render(
            baseImage: documentView.baseImage,
            annotations: engine.objects,
            scale: documentView.scale
        ) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = "Save Tall Stitched Screenshot"
        panel.nameFieldStringValue = "SuperShot_\(Int(Date().timeIntervalSince1970)).png"

        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let targetURL = panel.url else { return }
            let rep = NSBitmapImageRep(cgImage: rendered)
            let ext = targetURL.pathExtension.lowercased()
            let format: NSBitmapImageRep.FileType = (ext == "jpg" || ext == "jpeg") ? .jpeg : .png
            if let data = rep.representation(using: format, properties: [:]) {
                try? data.write(to: targetURL, options: .atomic)
            }
        }

        if let win = window {
            panel.beginSheetModal(for: win, completionHandler: handler)
        } else {
            let res = panel.runModal()
            handler(res)
        }
    }

    public func share(from view: NSView) {
        guard let rendered = ImageRenderer.render(
            baseImage: documentView.baseImage,
            annotations: engine.objects,
            scale: documentView.scale
        ) else { return }

        let image = NSImage(cgImage: rendered, size: NSSize(width: rendered.width, height: rendered.height))
        let picker = NSSharingServicePicker(items: [image])
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
}

// MARK: - Scrollable Annotation Window

public final class ScrollableAnnotationWindow: NSWindow {
    public let canvasView: ScrollableCanvasView

    public init(baseImage: CGImage, scale: CGFloat = 2.0, appSettings: AppSettings = AppSettings()) {
        let canvas = ScrollableCanvasView(baseImage: baseImage, scale: scale, appSettings: appSettings)
        self.canvasView = canvas

        let defaultRect = NSRect(x: 100, y: 100, width: 1200, height: 850)
        super.init(
            contentRect: defaultRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        self.title = "SuperShot — Tall Scrolling Screenshot"
        self.minSize = NSSize(width: 600, height: 400)
        self.isReleasedWhenClosed = false
        self.acceptsMouseMovedEvents = true
        self.contentView = canvas
        self.center()

        canvas.onCloseRequested = { [weak self] in
            self?.close()
        }
    }

    public override func close() {
        NSCursor.arrow.set()
        super.close()
    }

    public override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = event.keyCode

        // Delete / Backspace removes selected annotation
        if (keyCode == 51 || keyCode == 117), canvasView.engine.selectedObjectID != nil {
            canvasView.engine.deleteSelected()
            canvasView.documentView.needsDisplay = true
            return
        }

        // Esc: Hierarchical 4-Tier Escape Key
        if keyCode == 53 {
            // Tier 1: Commit active inline text editing on Esc
            if canvasView.documentView.hasActiveTextEditing {
                canvasView.documentView.commitActiveTextEditing()
                return
            }
            // Tier 2: Deselect active vector object if any object is selected
            if canvasView.engine.selectedObjectID != nil {
                canvasView.engine.deselectAll()
                canvasView.documentView.needsDisplay = true
                return
            }
            // Tier 3: Revert active drawing tool to .select if another tool is active
            if canvasView.toolbarsViewModel.activeTool != .select {
                canvasView.toolbarsViewModel.selectTool(.select)
                return
            }
            // Tier 4: Dismiss / close window
            close()
            return
        }

        // Cmd+Z: Undo
        if flags == .command && keyCode == 6 {
            canvasView.engine.undo()
            return
        }

        // Cmd+Shift+Z: Redo
        if flags == [.command, .shift] && keyCode == 6 {
            canvasView.engine.redo()
            return
        }

        // Cmd+C / Return / Keypad Enter: Copy to clipboard
        if (flags == .command && keyCode == 8) || ((keyCode == 36 || keyCode == 76) && flags.isEmpty) {
            canvasView.toolbarsViewModel.triggerCopy()
            return
        }

        // Cmd+S: Save to file
        if flags == .command && keyCode == 1 {
            canvasView.toolbarsViewModel.triggerSave()
            return
        }

        // Cmd+D: Duplicate Selected Annotation
        if flags == .command && (keyCode == 2 || event.charactersIgnoringModifiers?.lowercased() == "d"),
           canvasView.engine.selectedObjectID != nil {
            canvasView.engine.duplicateSelected(within: canvasView.documentView.bounds)
            canvasView.documentView.needsDisplay = true
            return
        }

        // Cmd+E: Share / Export
        if flags == .command && (keyCode == 14 || event.charactersIgnoringModifiers?.lowercased() == "e") {
            canvasView.toolbarsViewModel.triggerShare(from: canvasView)
            return
        }

        // Cmd+Shift+K: Clear All Annotations
        if flags == [.command, .shift] && (keyCode == 40 || event.charactersIgnoringModifiers?.lowercased() == "k") {
            let count = canvasView.engine.clearAll()
            if count > 0 {
                canvasView.showHUDNotification(text: LocalizationManager.shared.tr(.annotationsCleared))
                canvasView.documentView.needsDisplay = true
            }
            return
        }

        // Arrow keys (123: Left, 124: Right, 125: Down, 126: Up) nudging & Option+Arrow resizing on selected annotation
        if canvasView.engine.selectedObjectID != nil && keyCode >= 123 && keyCode <= 126 {
            let step: CGFloat = flags.contains(.shift) ? 10.0 : 1.0
            if flags.contains(.option) {
                var deltaW: CGFloat = 0
                var deltaH: CGFloat = 0
                switch keyCode {
                case 123: deltaW = -step // Left: contract width
                case 124: deltaW = step  // Right: expand width
                case 125: deltaH = -step // Down: contract height
                case 126: deltaH = step  // Up: expand height
                default: break
                }
                canvasView.engine.resizeSelected(
                    deltaWidth: deltaW,
                    deltaHeight: deltaH,
                    minimumDimension: 10.0,
                    boundary: canvasView.documentView.bounds
                )
            } else {
                var dx: CGFloat = 0
                var dy: CGFloat = 0
                switch keyCode {
                case 123: dx = -step // Left
                case 124: dx = step  // Right
                case 125: dy = step  // Down (flipped canvas: positive Y is down)
                case 126: dy = -step // Up (flipped canvas: negative Y is up)
                default: break
                }
                canvasView.engine.moveSelected(by: CGPoint(x: dx, y: dy))
            }
            canvasView.documentView.needsDisplay = true
            return
        }

        if ToolbarKeyShortcutHandler.handleKeyEvent(event: event, viewModel: canvasView.toolbarsViewModel, allowScrollCapture: false) {
            return
        }

        // Zoom shortcuts: Cmd + / Cmd = / Cmd Shift = / Keypad +; Cmd - / Keypad -; Cmd 0 / Keypad 0; Cmd 9 / Keypad 9
        let isCmd = flags.contains(.command)
        if isCmd {
            let chars = event.charactersIgnoringModifiers ?? ""
            if chars == "+" || chars == "=" || keyCode == 24 || keyCode == 69 {
                canvasView.scrollView.zoomIn()
                return
            }
            if chars == "-" || keyCode == 27 || keyCode == 78 {
                canvasView.scrollView.zoomOut()
                return
            }
            if chars == "0" || keyCode == 29 || keyCode == 82 {
                canvasView.scrollView.zoomToActualSize()
                return
            }
            if chars == "9" || keyCode == 25 || keyCode == 92 {
                canvasView.scrollView.zoomToFitWidth()
                return
            }
        }

        super.keyDown(with: event)
    }
}
