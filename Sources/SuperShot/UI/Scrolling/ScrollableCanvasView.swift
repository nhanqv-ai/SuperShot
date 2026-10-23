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
        context.saveGState()
        let blockSize: CGFloat = 12.0
        let cols = max(1, Int(ceil(obj.bounds.width / blockSize)))
        let rows = max(1, Int(ceil(obj.bounds.height / blockSize)))
        for r in 0..<rows {
            for c in 0..<cols {
                let cell = CGRect(
                    x: obj.bounds.minX + CGFloat(c) * blockSize,
                    y: obj.bounds.minY + CGFloat(r) * blockSize,
                    width: min(blockSize, obj.bounds.maxX - (obj.bounds.minX + CGFloat(c) * blockSize)),
                    height: min(blockSize, obj.bounds.maxY - (obj.bounds.minY + CGFloat(r) * blockSize))
                )
                let shade = ((r + c) % 2 == 0) ? 0.45 : 0.55
                context.setFillColor(gray: shade, alpha: 0.90)
                context.fill(cell)
            }
        }
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
        for i in 1..<points.count {
            path.addLine(to: points[i])
        }
        return path
    }

    private func drawText(obj: AnnotationObject, context: CGContext) {
        guard !obj.text.isEmpty else { return }
        let font = NSFont.systemFont(ofSize: obj.fontSize, weight: .semibold)
        let nsColor = ColorPreset(name: "", hex: obj.colorHex).toNSColor()
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: nsColor]
        let attrStr = NSAttributedString(string: obj.text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attrStr)

        context.saveGState()
        context.translateBy(x: obj.bounds.minX, y: obj.bounds.minY + obj.fontSize)
        context.scaleBy(x: 1.0, y: -1.0)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
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
        engine.endDrag(at: point)

        // If newly created object is a text box, immediately focus inline editor
        if engine.activeTool == .text, let last = engine.objects.last, last.tool == .text, last.text.isEmpty {
            startInlineTextEditing(for: last)
        }

        needsDisplay = true
    }

    // MARK: - Inline Text Editing

    private func startInlineTextEditing(for obj: AnnotationObject) {
        commitActiveTextEditing()

        let field = NSTextField(frame: obj.bounds)
        field.stringValue = obj.text
        field.font = NSFont.systemFont(ofSize: obj.fontSize, weight: .semibold)
        field.textColor = ColorPreset(name: "", hex: obj.colorHex).toNSColor()
        field.isBordered = true
        field.drawsBackground = true
        field.backgroundColor = NSColor.black.withAlphaComponent(0.7)
        field.focusRingType = .none
        field.delegate = self

        addSubview(field)
        window?.makeFirstResponder(field)

        self.activeTextField = field
        self.editingObjectID = obj.id
    }

    public func commitActiveTextEditing() {
        guard let field = activeTextField, let objID = editingObjectID else { return }
        let newText = field.stringValue
        engine.selectedObjectID = objID
        engine.updateSelectedText(newText)
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

    public var onCopyRequested: (() -> Void)?
    public var onSaveRequested: (() -> Void)?
    public var onShareRequested: ((NSView) -> Void)?
    public var onCloseRequested: (() -> Void)?

    public init(baseImage: CGImage, scale: CGFloat = 2.0) {
        let engine = AnnotationEngine()
        self.engine = engine
        let docView = ScrollableAnnotationDocumentView(baseImage: baseImage, engine: engine, scale: scale)
        self.documentView = docView
        let sView = ScrollableAnnotationScrollView(documentCanvasView: docView)
        self.scrollView = sView

        super.init(frame: .zero)

        sView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sView)

        NSLayoutConstraint.activate([
            sView.topAnchor.constraint(equalTo: topAnchor),
            sView.bottomAnchor.constraint(equalTo: bottomAnchor),
            sView.leadingAnchor.constraint(equalTo: leadingAnchor),
            sView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
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

    public init(baseImage: CGImage, scale: CGFloat = 2.0) {
        let canvas = ScrollableCanvasView(baseImage: baseImage, scale: scale)
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
        self.contentView = canvas
        self.center()

        canvas.onCloseRequested = { [weak self] in
            self?.close()
        }
    }

    public override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = event.keyCode

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
            canvasView.copyToClipboard()
            return
        }

        // Cmd+S: Save to file
        if flags == .command && keyCode == 1 {
            canvasView.saveToFile(window: self)
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
