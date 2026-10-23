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

    private var activeTextField: NSTextField?
    private var editingObjectID: UUID?
    private var cancellables = Set<AnyCancellable>()

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

    public override func mouseDown(with event: NSEvent) {
        commitActiveTextEditing()
        let point = convert(event.locationInWindow, from: nil)

        // Double click on text object initiates in-place text editing
        if event.clickCount == 2, let clickedObj = engine.selectObject(at: point), clickedObj.tool == .text {
            startInlineTextEditing(for: clickedObj)
            return
        }

        engine.startDrag(
            at: point,
            colorHex: currentColorHex,
            strokeWidth: currentStrokeWidth,
            fontSize: currentFontSize
        )
        needsDisplay = true
    }

    public override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let shift = event.modifierFlags.contains(.shift)
        engine.updateDrag(to: point, shiftKeyPressed: shift)
        autoscroll(with: event)
        needsDisplay = true
    }

    public override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let committed = engine.endDrag(at: point)

        // If newly created object is a text box, immediately focus inline editor
        if let created = committed, created.tool == .text, (created.text.isEmpty || created.text == "Text") {
            startInlineTextEditing(for: created)
        }

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
        magnification = 1.0
    }

    public func zoomToFitWidth() {
        guard let doc = documentCanvasView, doc.bounds.width > 0 else { return }
        let visibleW = contentSize.width - 20
        magnification = max(minMagnification, min(maxMagnification, visibleW / doc.bounds.width))
    }
}

// MARK: - Scrollable Canvas View (Host Container with Toolbar)

public final class ScrollableCanvasView: NSView {
    public let scrollView: ScrollableAnnotationScrollView
    public let documentView: ScrollableAnnotationDocumentView
    public let engine: AnnotationEngine
    public let appSettings: AppSettings
    public let toolbarsViewModel: FloatingToolbarsViewModel

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

        super.init(frame: .zero)

        sView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sView)

        let vToolbar = NSHostingView(rootView: VerticalAnnotationToolbarView(viewModel: toolbarsViewModel, appSettings: appSettings))
        let hToolbar = NSHostingView(rootView: HorizontalActionToolbarView(viewModel: toolbarsViewModel))
        vToolbar.translatesAutoresizingMaskIntoConstraints = false
        hToolbar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(vToolbar)
        addSubview(hToolbar)

        NSLayoutConstraint.activate([
            sView.topAnchor.constraint(equalTo: topAnchor),
            sView.bottomAnchor.constraint(equalTo: bottomAnchor),
            sView.leadingAnchor.constraint(equalTo: leadingAnchor),
            sView.trailingAnchor.constraint(equalTo: trailingAnchor),

            vToolbar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            vToolbar.topAnchor.constraint(equalTo: topAnchor, constant: 16),

            hToolbar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            hToolbar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
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
                self.documentView.needsDisplay = true
            }
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

        toolbarsViewModel.onCopyRequested = { [weak self] in
            guard let self = self else { return }
            self.documentView.commitActiveTextEditing()
            self.copyToClipboard()
            self.onCopyRequested?()
        }

        toolbarsViewModel.onSaveRequested = { [weak self] in
            guard let self = self else { return }
            self.documentView.commitActiveTextEditing()
            self.saveToFile(window: self.window)
            self.onSaveRequested?()
        }

        toolbarsViewModel.onShareRequested = { [weak self] anchorView in
            guard let self = self else { return }
            self.documentView.commitActiveTextEditing()
            self.share(from: anchorView)
            self.onShareRequested?(anchorView)
        }

        toolbarsViewModel.onCancelRequested = { [weak self] in
            self?.documentView.commitActiveTextEditing()
            self?.onCloseRequested?()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        self.contentView = canvas
        self.center()

        canvas.onCloseRequested = { [weak self] in
            self?.close()
        }
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

        // Esc: Close window
        if keyCode == 53 {
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

        // Cmd+C / Return: Copy to clipboard
        if (flags == .command && keyCode == 8) || (keyCode == 36 && flags.isEmpty) {
            canvasView.toolbarsViewModel.triggerCopy()
            return
        }

        // Cmd+S: Save to file
        if flags == .command && keyCode == 1 {
            canvasView.toolbarsViewModel.triggerSave()
            return
        }

        if ToolbarKeyShortcutHandler.handleKeyEvent(event: event, viewModel: canvasView.toolbarsViewModel) {
            return
        }

        // Zoom shortcuts: Cmd++ (keyCode 24), Cmd+- (keyCode 27), Cmd+0 (keyCode 29)
        if flags == .command && keyCode == 24 {
            canvasView.scrollView.zoomIn()
            return
        }
        if flags == .command && keyCode == 27 {
            canvasView.scrollView.zoomOut()
            return
        }
        if flags == .command && keyCode == 29 {
            canvasView.scrollView.zoomToActualSize()
            return
        }

        super.keyDown(with: event)
    }
}
