import Foundation
import CoreGraphics
import AppKit
import SuperShotCore

/// Unit and integration tests for AnnotationEngine and ImageRenderer vector operations:
/// Creating, hit-testing/selecting, moving, resizing, recoloring, editing text,
/// region blurring, deleting, and Undo/Redo command history across standard and tall canvases.
public struct AnnotationEngineTests {

    // MARK: - Backwards Compatibility Types for M1 Suites (PairwiseTests, WorkloadTests)

    public enum ToolType: String, CaseIterable {
        case select
        case rectangle
        case ellipse
        case arrow
        case line
        case pen
        case highlighter
        case text
        case blur
    }

    public struct VectorObject: Identifiable, Equatable {
        public let id: UUID
        public var tool: ToolType
        public var rect: CGRect
        public var colorHex: String
        public var strokeWidth: CGFloat
        public var textContent: String?
        public var points: [CGPoint]

        public init(
            id: UUID = UUID(),
            tool: ToolType,
            rect: CGRect,
            colorHex: String = "#FF3B30",
            strokeWidth: CGFloat = 3.0,
            textContent: String? = nil,
            points: [CGPoint] = []
        ) {
            self.id = id
            self.tool = tool
            self.rect = rect
            self.colorHex = colorHex
            self.strokeWidth = strokeWidth
            self.textContent = textContent
            self.points = points
        }

        public func contains(point: CGPoint) -> Bool {
            switch tool {
            case .rectangle, .blur, .text:
                return rect.insetBy(dx: -4, dy: -4).contains(point)
            case .ellipse:
                let rx = rect.width / 2.0
                let ry = rect.height / 2.0
                if rx <= 0 || ry <= 0 { return false }
                let cx = rect.midX
                let cy = rect.midY
                let dx = (point.x - cx) / rx
                let dy = (point.y - cy) / ry
                let dist = (dx * dx) + (dy * dy)
                return dist <= 1.2 && dist >= 0.7
            case .line, .arrow:
                guard points.count >= 2 else { return rect.contains(point) }
                return distanceToSegment(p: point, v: points[0], w: points[1]) <= max(strokeWidth / 2.0 + 4.0, 8.0)
            case .pen, .highlighter:
                if points.count >= 2 {
                    for i in 0..<(points.count - 1) {
                        if distanceToSegment(p: point, v: points[i], w: points[i+1]) <= max(strokeWidth / 2.0 + 4.0, 8.0) {
                            return true
                        }
                    }
                }
                return rect.contains(point)
            case .select:
                return false
            }
        }

        private func distanceToSegment(p: CGPoint, v: CGPoint, w: CGPoint) -> CGFloat {
            let l2 = pow(w.x - v.x, 2) + pow(w.y - v.y, 2)
            if l2 == 0 { return hypot(p.x - v.x, p.y - v.y) }
            let t = max(0, min(1, ((p.x - v.x) * (w.x - v.x) + (p.y - v.y) * (w.y - v.y)) / l2))
            let projection = CGPoint(x: v.x + t * (w.x - v.x), y: v.y + t * (w.y - v.y))
            return hypot(p.x - projection.x, p.y - projection.y)
        }
    }

    public class MockAnnotationEngine {
        public var activeTool: ToolType = .select
        public var objects: [VectorObject] = []
        public var selectedObjectID: UUID?

        private var undoStack: [[VectorObject]] = []
        private var redoStack: [[VectorObject]] = []

        public var canUndo: Bool { !undoStack.isEmpty }
        public var canRedo: Bool { !redoStack.isEmpty }

        public init() {}

        public func addObject(_ object: VectorObject) {
            pushUndo()
            objects.append(object)
            redoStack.removeAll()
        }

        public func selectObject(at point: CGPoint) -> VectorObject? {
            for obj in objects.reversed() {
                if obj.contains(point: point) {
                    selectedObjectID = obj.id
                    return obj
                }
            }
            selectedObjectID = nil
            return nil
        }

        public func moveSelected(by delta: CGPoint) {
            guard let id = selectedObjectID, let idx = objects.firstIndex(where: { $0.id == id }) else { return }
            pushUndo()
            objects[idx].rect = objects[idx].rect.offsetBy(dx: delta.x, dy: delta.y)
            objects[idx].points = objects[idx].points.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
            redoStack.removeAll()
        }

        public func recolorSelected(newHex: String) {
            guard let id = selectedObjectID, let idx = objects.firstIndex(where: { $0.id == id }) else { return }
            pushUndo()
            objects[idx].colorHex = newHex
            redoStack.removeAll()
        }

        public func updateSelectedText(_ newText: String) {
            guard let id = selectedObjectID, let idx = objects.firstIndex(where: { $0.id == id }) else { return }
            pushUndo()
            objects[idx].textContent = newText
            redoStack.removeAll()
        }

        public func deleteSelected() {
            guard let id = selectedObjectID, let idx = objects.firstIndex(where: { $0.id == id }) else { return }
            pushUndo()
            objects.remove(at: idx)
            selectedObjectID = nil
            redoStack.removeAll()
        }

        public func undo() {
            guard canUndo else { return }
            redoStack.append(objects)
            objects = undoStack.removeLast()
        }

        public func redo() {
            guard canRedo else { return }
            undoStack.append(objects)
            objects = redoStack.removeLast()
        }

        private func pushUndo() {
            undoStack.append(objects)
            if undoStack.count > 50 { undoStack.removeFirst() }
        }
    }

    // MARK: - Test Suite Execution

    public static func run() {
        TestHarness.startSuite("AnnotationEngine & Vector Tools")

        // Run M1 compatibility tests first
        runM1CompatibilityTests()

        // Run full M2 Production AnnotationEngine & ImageRenderer tests
        runM2ProductionTests()
    }

    private static func runM1CompatibilityTests() {
        let engine = MockAnnotationEngine()

        let rectObj = VectorObject(tool: .rectangle, rect: CGRect(x: 100, y: 100, width: 200, height: 150))
        engine.addObject(rectObj)
        TestHarness.assertEqual(engine.objects.count, 1, "Added Rectangle vector object")

        let ellipseObj = VectorObject(tool: .ellipse, rect: CGRect(x: 350, y: 100, width: 120, height: 120))
        engine.addObject(ellipseObj)
        TestHarness.assertEqual(engine.objects.count, 2, "Added Ellipse vector object")

        let arrowObj = VectorObject(
            tool: .arrow,
            rect: CGRect(x: 100, y: 300, width: 150, height: 100),
            points: [CGPoint(x: 100, y: 300), CGPoint(x: 250, y: 400)]
        )
        engine.addObject(arrowObj)
        TestHarness.assertEqual(engine.objects.count, 3, "Added Arrow vector object")

        let lineObj = VectorObject(
            tool: .line,
            rect: CGRect(x: 300, y: 300, width: 100, height: 0),
            points: [CGPoint(x: 300, y: 300), CGPoint(x: 400, y: 300)]
        )
        engine.addObject(lineObj)
        TestHarness.assertEqual(engine.objects.count, 4, "Added Line vector object")

        let penObj = VectorObject(
            tool: .pen,
            rect: CGRect(x: 50, y: 500, width: 80, height: 80),
            points: [CGPoint(x: 50, y: 500), CGPoint(x: 70, y: 520), CGPoint(x: 90, y: 510), CGPoint(x: 130, y: 580)]
        )
        engine.addObject(penObj)
        TestHarness.assertEqual(engine.objects.count, 5, "Added Freehand Pen vector object")

        let highlighterObj = VectorObject(
            tool: .highlighter,
            rect: CGRect(x: 200, y: 500, width: 200, height: 24),
            strokeWidth: 20.0,
            points: [CGPoint(x: 200, y: 512), CGPoint(x: 400, y: 512)]
        )
        engine.addObject(highlighterObj)
        TestHarness.assertEqual(engine.objects.count, 6, "Added Highlighter vector object")

        let textObj = VectorObject(
            tool: .text,
            rect: CGRect(x: 100, y: 650, width: 250, height: 40),
            textContent: "Sample Error Description"
        )
        engine.addObject(textObj)
        TestHarness.assertEqual(engine.objects.count, 7, "Added Editable Text vector object")

        let blurObj = VectorObject(
            tool: .blur,
            rect: CGRect(x: 400, y: 650, width: 180, height: 50)
        )
        engine.addObject(blurObj)
        TestHarness.assertEqual(engine.objects.count, 8, "Added Region Blur vector object")

        let hitRect = engine.selectObject(at: CGPoint(x: 150, y: 150))
        TestHarness.assertEqual(hitRect?.id, rectObj.id, "Hit test correctly selects Rectangle at (150, 150)")

        let hitText = engine.selectObject(at: CGPoint(x: 120, y: 660))
        TestHarness.assertEqual(hitText?.id, textObj.id, "Hit test correctly selects Text object at (120, 660)")

        let hitLine = engine.selectObject(at: CGPoint(x: 350, y: 300))
        TestHarness.assertEqual(hitLine?.id, lineObj.id, "Hit test correctly selects Line along segment")

        let hitMiss = engine.selectObject(at: CGPoint(x: 9999, y: 9999))
        TestHarness.assertNil(hitMiss, "Hit test at empty coordinates returns nil")

        _ = engine.selectObject(at: CGPoint(x: 150, y: 150))
        let originalOrigin = engine.objects.first(where: { $0.id == rectObj.id })?.rect.origin
        engine.moveSelected(by: CGPoint(x: 50, y: 30))
        let movedOrigin = engine.objects.first(where: { $0.id == rectObj.id })?.rect.origin
        TestHarness.assertEqual(movedOrigin?.x, (originalOrigin?.x ?? 0) + 50, "Moved rectangle X shifted by 50pt")
        TestHarness.assertEqual(movedOrigin?.y, (originalOrigin?.y ?? 0) + 30, "Moved rectangle Y shifted by 30pt")

        _ = engine.selectObject(at: CGPoint(x: 200, y: 180))
        engine.recolorSelected(newHex: "#007AFF")
        let updatedColor = engine.objects.first(where: { $0.id == rectObj.id })?.colorHex
        TestHarness.assertEqual(updatedColor, "#007AFF", "Recolored rectangle to Blue (#007AFF)")

        _ = engine.selectObject(at: CGPoint(x: 120, y: 660))
        engine.updateSelectedText("Updated Text After Review")
        let updatedText = engine.objects.first(where: { $0.id == textObj.id })?.textContent
        TestHarness.assertEqual(updatedText, "Updated Text After Review", "Updated text content in-place")

        _ = engine.selectObject(at: CGPoint(x: 410, y: 660))
        engine.deleteSelected()
        TestHarness.assertEqual(engine.objects.count, 7, "Deleted blur object reduces count to 7")
        TestHarness.assertFalse(engine.objects.contains(where: { $0.id == blurObj.id }), "Blur object is completely removed")

        TestHarness.assertTrue(engine.canUndo, "Engine canUndo is true after operations")
        engine.undo()
        TestHarness.assertEqual(engine.objects.count, 8, "Undo restores deleted blur object")
        TestHarness.assertTrue(engine.canRedo, "Engine canRedo is true after undo")

        engine.redo()
        TestHarness.assertEqual(engine.objects.count, 7, "Redo re-applies deletion")

        let deepTallObject = VectorObject(
            tool: .rectangle,
            rect: CGRect(x: 100, y: 14500, width: 300, height: 200)
        )
        engine.addObject(deepTallObject)
        let hitTall = engine.selectObject(at: CGPoint(x: 150, y: 14600))
        TestHarness.assertEqual(hitTall?.id, deepTallObject.id, "Hit test resolves correctly at deep scroll offset 14,600px")
    }

    private static func runM2ProductionTests() {
        let prodEngine = AnnotationEngine(maxHistoryLimit: 50)

        // 1. Production Model Creation for all tools
        let rect = AnnotationObject(tool: .rectangle, bounds: CGRect(x: 20, y: 20, width: 100, height: 60), colorHex: "#FF3B30", strokeWidth: 2.0)
        prodEngine.addObject(rect)
        TestHarness.assertEqual(prodEngine.objects.count, 1, "M2 Production: Added Rectangle")

        let ellipse = AnnotationObject(tool: .ellipse, bounds: CGRect(x: 150, y: 20, width: 80, height: 80), colorHex: "#FF9500")
        prodEngine.addObject(ellipse)
        TestHarness.assertEqual(prodEngine.objects.count, 2, "M2 Production: Added Ellipse")

        let arrow = AnnotationObject(tool: .arrow, points: [CGPoint(x: 50, y: 120), CGPoint(x: 150, y: 180)], colorHex: "#007AFF")
        prodEngine.addObject(arrow)
        TestHarness.assertEqual(prodEngine.objects.count, 3, "M2 Production: Added Arrow")

        let line = AnnotationObject(tool: .line, points: [CGPoint(x: 200, y: 120), CGPoint(x: 300, y: 120)], colorHex: "#34C759")
        prodEngine.addObject(line)
        TestHarness.assertEqual(prodEngine.objects.count, 4, "M2 Production: Added Line")

        let pen = AnnotationObject(tool: .pen, points: [CGPoint(x: 10, y: 220), CGPoint(x: 30, y: 240), CGPoint(x: 60, y: 230)])
        prodEngine.addObject(pen)
        TestHarness.assertEqual(prodEngine.objects.count, 5, "M2 Production: Added Pen")

        let highlighter = AnnotationObject(tool: .highlighter, points: [CGPoint(x: 100, y: 230), CGPoint(x: 250, y: 230)], strokeWidth: 16.0)
        prodEngine.addObject(highlighter)
        TestHarness.assertEqual(prodEngine.objects.count, 6, "M2 Production: Added Highlighter")

        let text = AnnotationObject(tool: .text, bounds: CGRect(x: 20, y: 300, width: 200, height: 30), fontSize: 18.0, text: "Initial Text")
        prodEngine.addObject(text)
        TestHarness.assertEqual(prodEngine.objects.count, 7, "M2 Production: Added Text")

        let blur = AnnotationObject(tool: .blur, bounds: CGRect(x: 250, y: 300, width: 100, height: 40))
        prodEngine.addObject(blur)
        TestHarness.assertEqual(prodEngine.objects.count, 8, "M2 Production: Added Blur")

        // 2. Hit-testing & Selection
        let hitRect = prodEngine.selectObject(at: CGPoint(x: 50, y: 40))
        TestHarness.assertEqual(hitRect?.id, rect.id, "M2 Production: Hit-test selected Rectangle")
        TestHarness.assertEqual(prodEngine.selectedObjectID, rect.id, "M2 Production: selectedObjectID updated")

        // 3. Move & Recolor Mutations
        prodEngine.moveSelected(by: CGPoint(x: 10, y: 15))
        TestHarness.assertEqual(prodEngine.selectedObject?.bounds.origin.x, 30.0, "M2 Production: Move shifted origin.x to 30")
        TestHarness.assertEqual(prodEngine.selectedObject?.bounds.origin.y, 35.0, "M2 Production: Move shifted origin.y to 35")

        prodEngine.recolorSelected(newHex: "#007AFF")
        TestHarness.assertEqual(prodEngine.selectedObject?.colorHex, "#007AFF", "M2 Production: Recolor updated colorHex to #007AFF")

        prodEngine.updateSelectedStrokeWidth(6.0)
        TestHarness.assertEqual(prodEngine.selectedObject?.strokeWidth, 6.0, "M2 Production: Stroke width updated to 6.0")

        // 4. In-place text editing
        _ = prodEngine.selectObject(at: CGPoint(x: 30, y: 310))
        prodEngine.updateSelectedText("Edited Typography Content")
        TestHarness.assertEqual(prodEngine.selectedObject?.text, "Edited Typography Content", "M2 Production: In-place text edited")

        prodEngine.updateSelectedFontSize(24.0)
        TestHarness.assertEqual(prodEngine.selectedObject?.fontSize, 24.0, "M2 Production: Font size updated to 24.0")

        // 5. Handle Detection & Resizing
        let handles = rect.handlePositions()
        TestHarness.assertEqual(handles.count, 8, "M2 Production: Rect produces exactly 8 grab handles")
        let arrowHandles = arrow.handlePositions()
        TestHarness.assertEqual(arrowHandles.count, 2, "M2 Production: Arrow produces startPoint and endPoint handles")

        // 6. Delete & Undo / Redo
        _ = prodEngine.selectObject(at: CGPoint(x: 260, y: 310)) // Blur
        prodEngine.deleteSelected()
        TestHarness.assertEqual(prodEngine.objects.count, 7, "M2 Production: Delete removed Blur object")

        TestHarness.assertTrue(prodEngine.canUndo, "M2 Production: canUndo is true")
        prodEngine.undo()
        TestHarness.assertEqual(prodEngine.objects.count, 8, "M2 Production: Undo restored Blur object")
        TestHarness.assertTrue(prodEngine.canRedo, "M2 Production: canRedo is true")

        prodEngine.redo()
        TestHarness.assertEqual(prodEngine.objects.count, 7, "M2 Production: Redo re-deleted Blur object")

        // 7. Interactive Drag Lifecycle
        prodEngine.activeTool = .rectangle
        prodEngine.startDrag(at: CGPoint(x: 400, y: 400))
        prodEngine.updateDrag(to: CGPoint(x: 460, y: 460), shiftKeyPressed: true)
        let createdSquare = prodEngine.endDrag(at: CGPoint(x: 460, y: 460))
        TestHarness.assertNotNil(createdSquare, "M2 Production: Interactive drag produced square")
        TestHarness.assertEqual(createdSquare?.bounds.width, 60.0, "M2 Production: Shift drag width is 60")
        TestHarness.assertEqual(createdSquare?.bounds.height, 60.0, "M2 Production: Shift drag height is 60")

        // 8. ImageRenderer Rasterization
        testImageRendererRasterization()
    }

    private static func testImageRendererRasterization() {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 400 * 4, space: colorSpace, bitmapInfo: bitmapInfo) else {
            TestHarness.recordFail("ImageRenderer Test", reason: "Failed to create base test context")
            return
        }
        ctx.setFillColor(gray: 0.9, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        guard let baseCGImage = ctx.makeImage() else {
            TestHarness.recordFail("ImageRenderer Test", reason: "Failed to make test CGImage")
            return
        }

        let annotations = [
            AnnotationObject(tool: .rectangle, bounds: CGRect(x: 10, y: 10, width: 80, height: 50), colorHex: "#FF3B30", strokeWidth: 3.0),
            AnnotationObject(tool: .arrow, points: [CGPoint(x: 100, y: 50), CGPoint(x: 180, y: 120)], colorHex: "#007AFF"),
            AnnotationObject(tool: .text, bounds: CGRect(x: 200, y: 20, width: 100, height: 30), fontSize: 16.0, text: "Test"),
            AnnotationObject(tool: .blur, bounds: CGRect(x: 250, y: 150, width: 80, height: 40))
        ]

        let rendered = ImageRenderer.render(baseImage: baseCGImage, annotations: annotations, cropRect: nil, scale: 2.0)
        TestHarness.assertNotNil(rendered, "ImageRenderer produced non-nil composited CGImage")
        TestHarness.assertEqual(rendered?.width, 400, "Retina @2x scale width is accurate")
        TestHarness.assertEqual(rendered?.height, 300, "Retina @2x scale height is accurate")
    }
}
