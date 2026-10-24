import Foundation
import CoreGraphics
import AppKit
import SuperShotCore
import SuperShot

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

        // 7b. Free-aspect Ellipse vs Shift-constrained Circle
        prodEngine.activeTool = .ellipse
        prodEngine.startDrag(at: CGPoint(x: 100, y: 100))
        prodEngine.updateDrag(to: CGPoint(x: 220, y: 160), shiftKeyPressed: false)
        let freeEllipse = prodEngine.endDrag(at: CGPoint(x: 220, y: 160))
        TestHarness.assertEqual(freeEllipse?.bounds.width, 120.0, "Free-aspect ellipse preserves width 120")
        TestHarness.assertEqual(freeEllipse?.bounds.height, 60.0, "Free-aspect ellipse preserves height 60")

        prodEngine.startDrag(at: CGPoint(x: 100, y: 100))
        prodEngine.updateDrag(to: CGPoint(x: 220, y: 160), shiftKeyPressed: true)
        let shiftCircle = prodEngine.endDrag(at: CGPoint(x: 220, y: 160))
        TestHarness.assertEqual(shiftCircle?.bounds.width, 120.0, "Shift-constrained ellipse width is 120")
        TestHarness.assertEqual(shiftCircle?.bounds.height, 120.0, "Shift-constrained ellipse height is 120")

        // 8. ImageRenderer Rasterization
        testImageRendererRasterization()

        // 9. M13: Annotation Object Duplication
        testAnnotationObjectDuplicationPropertiesAndOffset()
        testAnnotationObjectDuplicationUndoRedo()
        testAnnotationObjectDuplicationBoundaryClamping()

        // 10. M13: Shift-Constrained Angle Snapping & Resizing
        testShiftConstrainedAngleSnappingAllOctants()
        testShiftConstrainedHandleResizeFixedAnchor()

        // 11. M13: Zoom Step Calculations & Clamping
        testScrollableZoomStepCalculationsAndClamping()

        // 12. M13: MainShotView Keyboard Shortcuts & Navigation
        testMainShotViewKeyboardShortcuts()

        // 13. M34: Vector Layer Z-Index Reordering & Undo/Redo
        testLayerZIndexReorderingAndUndoRedo()
    }

    private static func makeTestCGImage(width: Int = 400, height: Int = 300) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo) else {
            fatalError("Failed to allocate test context")
        }
        ctx.setFillColor(gray: 0.9, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    private static func testImageRendererRasterization() {
        let baseCGImage = makeTestCGImage(width: 400, height: 300)

        let annotations = [
            AnnotationObject(tool: .rectangle, bounds: CGRect(x: 10, y: 10, width: 80, height: 50), colorHex: "#FF3B30", strokeWidth: 3.0),
            AnnotationObject(tool: .arrow, points: [CGPoint(x: 100, y: 50), CGPoint(x: 180, y: 120)], colorHex: "#007AFF"),
            AnnotationObject(tool: .text, bounds: CGRect(x: 50, y: 20, width: 100, height: 50), fontSize: 16.0, text: "Line 1\nLine 2"),
            AnnotationObject(tool: .blur, bounds: CGRect(x: 60, y: 60, width: 80, height: 40))
        ]

        let rendered = ImageRenderer.render(baseImage: baseCGImage, annotations: annotations, cropRect: nil, scale: 2.0)
        TestHarness.assertNotNil(rendered, "ImageRenderer produced non-nil composited CGImage")
        TestHarness.assertEqual(rendered?.width, 400, "Retina @2x scale width is accurate")
        TestHarness.assertEqual(rendered?.height, 300, "Retina @2x scale height is accurate")

        // Subregion cropRect with offset origin (50, 20, 100x80 points -> 200x160 pixels at 2x)
        let croppedRendered = ImageRenderer.render(
            baseImage: baseCGImage,
            annotations: annotations,
            cropRect: CGRect(x: 50, y: 20, width: 100, height: 80),
            scale: 2.0
        )
        TestHarness.assertNotNil(croppedRendered, "ImageRenderer produced non-nil cropped & composited CGImage")
        TestHarness.assertEqual(croppedRendered?.width, 200, "Cropped Retina @2x width is 200px (100pt * 2)")
        TestHarness.assertEqual(croppedRendered?.height, 160, "Cropped Retina @2x height is 160px (80pt * 2)")
    }

    private static func testAnnotationObjectDuplicationPropertiesAndOffset() {
        let engine = AnnotationEngine()
        TestHarness.assertNil(engine.duplicateSelected(), "No selection returns nil on duplication")

        // 1. Rectangle duplication
        let rect = AnnotationObject(
            tool: .rectangle,
            bounds: CGRect(x: 100, y: 100, width: 200, height: 150),
            colorHex: "#FF3B30",
            strokeWidth: 4.0
        )
        engine.addObject(rect)
        engine.selectedObjectID = rect.id

        let dupRect = engine.duplicateSelected(offset: CGPoint(x: 16, y: 16))
        TestHarness.assertNotNil(dupRect, "Duplicated rectangle is non-nil")
        TestHarness.assertTrue(dupRect?.id != rect.id, "Duplicated rectangle has distinct UUID")
        TestHarness.assertEqual(dupRect?.bounds.origin.x, 116.0, "Duplicated rect origin x offset by +16")
        TestHarness.assertEqual(dupRect?.bounds.origin.y, 116.0, "Duplicated rect origin y offset by +16")
        TestHarness.assertEqual(dupRect?.bounds.width, 200.0, "Duplicated rect width preserved")
        TestHarness.assertEqual(dupRect?.bounds.height, 150.0, "Duplicated rect height preserved")
        TestHarness.assertEqual(dupRect?.colorHex, "#FF3B30", "Duplicated rect color preserved")
        TestHarness.assertEqual(dupRect?.strokeWidth, 4.0, "Duplicated rect strokeWidth preserved")
        TestHarness.assertEqual(dupRect?.tool, .rectangle, "Duplicated rect tool preserved")
        TestHarness.assertTrue(dupRect?.isSelected == true, "Duplicated rect marked as selected")
        TestHarness.assertEqual(engine.selectedObjectID, dupRect?.id, "Engine selectedObjectID transferred to duplicate")
        TestHarness.assertEqual(engine.objects.count, 2, "Engine now contains 2 objects")

        // 2. Arrow path duplication
        let arrow = AnnotationObject(
            tool: .arrow,
            points: [CGPoint(x: 50, y: 50), CGPoint(x: 200, y: 150)],
            colorHex: "#007AFF"
        )
        engine.addObject(arrow)
        engine.selectedObjectID = arrow.id

        let dupArrow = engine.duplicateSelected(offset: CGPoint(x: 16, y: 16))
        TestHarness.assertNotNil(dupArrow, "Duplicated arrow is non-nil")
        TestHarness.assertEqual(dupArrow?.points.count, 2, "Duplicated arrow has 2 points")
        TestHarness.assertEqual(dupArrow?.points[0].x, 66.0, "Duplicated arrow start x is 66")
        TestHarness.assertEqual(dupArrow?.points[0].y, 66.0, "Duplicated arrow start y is 66")
        TestHarness.assertEqual(dupArrow?.points[1].x, 216.0, "Duplicated arrow end x is 216")
        TestHarness.assertEqual(dupArrow?.points[1].y, 166.0, "Duplicated arrow end y is 166")

        // 3. Text and Blur duplication
        let textObj = AnnotationObject(
            tool: .text,
            bounds: CGRect(x: 50, y: 50, width: 120, height: 40),
            fontSize: 22.0,
            text: "Hello World"
        )
        engine.addObject(textObj)
        engine.selectedObjectID = textObj.id
        let dupText = engine.duplicateSelected()
        TestHarness.assertEqual(dupText?.text, "Hello World", "Duplicated text string preserved")
        TestHarness.assertEqual(dupText?.fontSize, 22.0, "Duplicated text fontSize preserved")

        let blurObj = AnnotationObject(
            tool: .blur,
            bounds: CGRect(x: 80, y: 80, width: 100, height: 60),
            blurRadius: 14.0
        )
        engine.addObject(blurObj)
        engine.selectedObjectID = blurObj.id
        let dupBlur = engine.duplicateSelected()
        TestHarness.assertEqual(dupBlur?.blurRadius, 14.0, "Duplicated blur radius preserved")
    }

    private static func testAnnotationObjectDuplicationUndoRedo() {
        let engine = AnnotationEngine()
        let rect = AnnotationObject(
            tool: .rectangle,
            bounds: CGRect(x: 50, y: 50, width: 100, height: 80)
        )
        engine.addObject(rect)
        TestHarness.assertEqual(engine.objects.count, 1, "Engine initialized with 1 object")

        engine.selectedObjectID = rect.id
        let dup = engine.duplicateSelected()
        TestHarness.assertEqual(engine.objects.count, 2, "Duplication added second object")
        TestHarness.assertEqual(engine.selectedObjectID, dup?.id, "Selection on duplicate")

        // Undo removes duplicate and clears its selection
        engine.undo()
        TestHarness.assertEqual(engine.objects.count, 1, "Undo removed duplicated object")
        TestHarness.assertEqual(engine.objects.first?.id, rect.id, "Original object remains intact")

        // Redo restores duplicate
        engine.redo()
        TestHarness.assertEqual(engine.objects.count, 2, "Redo restored duplicated object")
        TestHarness.assertEqual(engine.objects[1].id, dup?.id, "Restored object has identical UUID")

        // Multi-level cascading duplication
        let dup2 = engine.duplicateSelected(offset: CGPoint(x: 16, y: 16))
        let dup3 = engine.duplicateSelected(offset: CGPoint(x: 16, y: 16))
        TestHarness.assertNotNil(dup2, "dup2 is non-nil")
        TestHarness.assertNotNil(dup3, "dup3 is non-nil")
        TestHarness.assertEqual(engine.objects.count, 4, "Cascading duplications produced 4 objects")

        engine.undo() // reverts dup3
        engine.undo() // reverts dup2
        TestHarness.assertEqual(engine.objects.count, 2, "Undoing twice reverts to 2 objects")
        engine.redo() // restores dup2
        TestHarness.assertEqual(engine.objects.count, 3, "Redoing restores dup2")
        TestHarness.assertEqual(engine.objects.last?.id, dup2?.id, "Restored dup2 matches")
    }

    private static func testAnnotationObjectDuplicationBoundaryClamping() {
        let engine = AnnotationEngine()
        let boundary = CGRect(x: 0, y: 0, width: 500, height: 400)

        // Near bottom-right edge: candidate bounds exceed boundary, offset should reverse (-16, -16)
        let nearEdge = AnnotationObject(
            tool: .rectangle,
            bounds: CGRect(x: 450, y: 350, width: 40, height: 40)
        )
        engine.addObject(nearEdge)
        engine.selectedObjectID = nearEdge.id

        let dup = engine.duplicateSelected(offset: CGPoint(x: 16, y: 16), within: boundary)
        TestHarness.assertNotNil(dup, "Duplicate produced near edge")
        TestHarness.assertEqual(dup?.bounds.origin.x, 434.0, "Duplicate reversed x offset to 434")
        TestHarness.assertEqual(dup?.bounds.origin.y, 334.0, "Duplicate reversed y offset to 334")
        TestHarness.assertTrue(boundary.contains(dup!.bounds), "Duplicate fits entirely within boundary")

        // Object flush with boundary: clamping keeps it inside
        let flush = AnnotationObject(
            tool: .rectangle,
            bounds: CGRect(x: 470, y: 100, width: 25, height: 30)
        )
        engine.addObject(flush)
        engine.selectedObjectID = flush.id

        let dupFlush = engine.duplicateSelected(offset: CGPoint(x: 16, y: 16), within: boundary)
        TestHarness.assertNotNil(dupFlush, "Flush duplicate produced")
        TestHarness.assertTrue(dupFlush!.bounds.maxX <= boundary.maxX, "Flush duplicate maxX clamped <= 500")

        // Defect Remediation: Negative offsets and boundary breaches across minX, minY, maxX, maxY
        // 1. Negative offset breaching minX (< 0): reversal (+20, +0) fits inside boundary
        let nearMinX = AnnotationObject(
            tool: .rectangle,
            bounds: CGRect(x: 10, y: 100, width: 40, height: 40)
        )
        engine.addObject(nearMinX)
        engine.selectedObjectID = nearMinX.id
        let dupMinX = engine.duplicateSelected(offset: CGPoint(x: -20, y: 0), within: boundary)
        TestHarness.assertNotNil(dupMinX, "Negative offset minX duplicate produced")
        TestHarness.assertEqual(dupMinX?.bounds.origin.x, 30.0, "Reversed negative x offset from 10 to 30")
        TestHarness.assertTrue(dupMinX!.bounds.minX >= boundary.minX, "dupMinX minX >= boundary minX")

        // 2. Negative offset breaching minY (< 0): reversal (0, +20) fits inside boundary
        let nearMinY = AnnotationObject(
            tool: .rectangle,
            bounds: CGRect(x: 100, y: 10, width: 40, height: 40)
        )
        engine.addObject(nearMinY)
        engine.selectedObjectID = nearMinY.id
        let dupMinY = engine.duplicateSelected(offset: CGPoint(x: 0, y: -20), within: boundary)
        TestHarness.assertNotNil(dupMinY, "Negative offset minY duplicate produced")
        TestHarness.assertEqual(dupMinY?.bounds.origin.y, 30.0, "Reversed negative y offset from 10 to 30")
        TestHarness.assertTrue(dupMinY!.bounds.minY >= boundary.minY, "dupMinY minY >= boundary minY")

        // 3. Negative offset breaching both minX and minY with reversal
        let nearOrigin = AnnotationObject(
            tool: .rectangle,
            bounds: CGRect(x: 10, y: 10, width: 40, height: 40)
        )
        engine.addObject(nearOrigin)
        engine.selectedObjectID = nearOrigin.id
        let dupOrigin = engine.duplicateSelected(offset: CGPoint(x: -20, y: -20), within: boundary)
        TestHarness.assertNotNil(dupOrigin, "Negative offset origin duplicate produced")
        TestHarness.assertEqual(dupOrigin?.bounds.origin.x, 30.0, "Reversed negative offset x to 30")
        TestHarness.assertEqual(dupOrigin?.bounds.origin.y, 30.0, "Reversed negative offset y to 30")
        TestHarness.assertTrue(boundary.contains(dupOrigin!.bounds), "dupOrigin contained within boundary")

        // 4. Clamping when both forward and reverse are out of bounds (large object)
        let largeBoundary = CGRect(x: 0, y: 0, width: 200, height: 200)
        let largeObj = AnnotationObject(
            tool: .rectangle,
            bounds: CGRect(x: 5, y: 5, width: 190, height: 190)
        )
        engine.addObject(largeObj)
        engine.selectedObjectID = largeObj.id
        // Forward (+16, +16) pushes maxX to 211 > 200, reverse (-16, -16) pushes minX to -11 < 0
        let dupLargeClamped = engine.duplicateSelected(offset: CGPoint(x: 16, y: 16), within: largeBoundary)
        TestHarness.assertNotNil(dupLargeClamped, "Large object clamped duplicate produced")
        TestHarness.assertEqual(dupLargeClamped?.bounds, CGRect(x: 10, y: 10, width: 190, height: 190), "Large object clamped to bounds.maxX - width and bounds.maxY - height")

        // Negative offset on large object clamped to minX and minY
        let dupLargeNegClamped = engine.duplicateSelected(offset: CGPoint(x: -16, y: -16), within: largeBoundary)
        TestHarness.assertNotNil(dupLargeNegClamped, "Large object negative clamped duplicate produced")
        TestHarness.assertEqual(dupLargeNegClamped?.bounds, CGRect(x: 0, y: 0, width: 190, height: 190), "Large object clamped to bounds.minX and bounds.minY")

        // 5. 100 sequential duplications with negative offset stay within boundary
        let seqEngine = AnnotationEngine(maxHistoryLimit: 200)
        let seqSeed = AnnotationObject(tool: .rectangle, bounds: CGRect(x: 150, y: 150, width: 30, height: 30))
        seqEngine.addObject(seqSeed)
        seqEngine.selectedObjectID = seqSeed.id
        var allInside = true
        for _ in 1...100 {
            guard let clone = seqEngine.duplicateSelected(offset: CGPoint(x: -16, y: -16), within: largeBoundary) else {
                allInside = false
                break
            }
            if clone.bounds.minX < largeBoundary.minX || clone.bounds.minY < largeBoundary.minY ||
               clone.bounds.maxX > largeBoundary.maxX || clone.bounds.maxY > largeBoundary.maxY {
                allInside = false
                break
            }
        }
        TestHarness.assertTrue(allInside, "100 sequential negative-offset duplications remain inside boundary")
    }

    private static func testShiftConstrainedAngleSnappingAllOctants() {
        let center = CGPoint(x: 100, y: 100)
        let tolerance: CGFloat = 0.05

        // Defensive interval guard test: interval <= 0 returns target unchanged
        let testTarget = CGPoint(x: 150, y: 120)
        let zeroInterval = AnnotationObject.snapAngle(from: center, to: testTarget, interval: 0)
        TestHarness.assertEqual(zeroInterval, testTarget, "snapAngle with interval 0 returns target")
        let negInterval = AnnotationObject.snapAngle(from: center, to: testTarget, interval: -0.5)
        TestHarness.assertEqual(negInterval, testTarget, "snapAngle with negative interval returns target")

        // Octant 0: 0 degrees (East) - slight upward drift
        let east = AnnotationObject.snapAngle(from: center, to: CGPoint(x: 200, y: 105))
        TestHarness.assertEqual(round(east.x), 200.0, "0 deg snap x is 200")
        TestHarness.assertEqual(round(east.y), 100.0, "0 deg snap y is 100")

        // Octant 1: 45 degrees (South-East)
        let se = AnnotationObject.snapAngle(from: center, to: CGPoint(x: 172, y: 168))
        let seDx = abs(se.x - center.x)
        let seDy = abs(se.y - center.y)
        TestHarness.assertTrue(abs(seDx - seDy) < tolerance, "45 deg snap dx == dy")

        // Octant 2: 90 degrees (South)
        let south = AnnotationObject.snapAngle(from: center, to: CGPoint(x: 104, y: 200))
        TestHarness.assertEqual(round(south.x), 100.0, "90 deg snap x is 100")
        TestHarness.assertEqual(round(south.y), 200.0, "90 deg snap y is 200")

        // Octant 3: 135 degrees (South-West)
        let sw = AnnotationObject.snapAngle(from: center, to: CGPoint(x: 28, y: 172))
        let swDx = abs(sw.x - center.x)
        let swDy = abs(sw.y - center.y)
        TestHarness.assertTrue(abs(swDx - swDy) < tolerance, "135 deg snap dx == dy")

        // Octant 4: 180 degrees (West)
        let west = AnnotationObject.snapAngle(from: center, to: CGPoint(x: 0, y: 104))
        TestHarness.assertEqual(round(west.x), 0.0, "180 deg snap x is 0")
        TestHarness.assertEqual(round(west.y), 100.0, "180 deg snap y is 100")

        // Octant 5: 225 degrees (North-West)
        let nw = AnnotationObject.snapAngle(from: center, to: CGPoint(x: 28, y: 28))
        let nwDx = abs(nw.x - center.x)
        let nwDy = abs(nw.y - center.y)
        TestHarness.assertTrue(abs(nwDx - nwDy) < tolerance, "225 deg snap dx == dy")

        // Octant 6: 270 degrees (North)
        let north = AnnotationObject.snapAngle(from: center, to: CGPoint(x: 103, y: 0))
        TestHarness.assertEqual(round(north.x), 100.0, "270 deg snap x is 100")
        TestHarness.assertEqual(round(north.y), 0.0, "270 deg snap y is 0")

        // Octant 7: 315 degrees (North-East)
        let ne = AnnotationObject.snapAngle(from: center, to: CGPoint(x: 172, y: 28))
        let neDx = abs(ne.x - center.x)
        let neDy = abs(ne.y - center.y)
        TestHarness.assertTrue(abs(neDx - neDy) < tolerance, "315 deg snap dx == dy")

        // Length preservation
        let target = CGPoint(x: 234.5, y: 167.8)
        let snapped = AnnotationObject.snapAngle(from: center, to: target)
        let originalLen = hypot(target.x - center.x, target.y - center.y)
        let snappedLen = hypot(snapped.x - center.x, snapped.y - center.y)
        TestHarness.assertTrue(abs(originalLen - snappedLen) < 0.001, "Hypotenuse length preserved within 0.001")

        // Sub-pixel guard (< 1.0pt) returns target without crashing
        let micro = AnnotationObject.snapAngle(from: center, to: CGPoint(x: 100.5, y: 100.4))
        TestHarness.assertEqual(micro.x, 100.5, "Sub-pixel snap x preserved")
        TestHarness.assertEqual(micro.y, 100.4, "Sub-pixel snap y preserved")
    }

    private static func testShiftConstrainedHandleResizeFixedAnchor() {
        // 1. Box resize via bottomRight with Shift preserves topLeft anchor
        var rect = AnnotationObject(
            tool: .rectangle,
            bounds: CGRect(x: 100, y: 100, width: 200, height: 100)
        )
        // Drag bottomRight handle to (350, 250) -> rawDx = 250, rawDy = 150 -> side = 250
        rect.resize(handle: .bottomRight, to: CGPoint(x: 350, y: 250), shiftConstrained: true)
        TestHarness.assertEqual(rect.bounds.minX, 100.0, "BottomRight resize preserves minX (topLeft anchor)")
        TestHarness.assertEqual(rect.bounds.minY, 100.0, "BottomRight resize preserves minY (topLeft anchor)")
        TestHarness.assertEqual(rect.bounds.width, 250.0, "Shift-constrained box width is 250")
        TestHarness.assertEqual(rect.bounds.height, 250.0, "Shift-constrained box height is 250")

        // 2. Box resize via topLeft with Shift preserves bottomRight anchor
        // Current bounds: (100, 100, 250, 250) -> bottomRight anchor is (350, 350)
        // Drag topLeft handle to (50, 80) -> rawDx = -300, rawDy = -270 -> side = 300
        rect.resize(handle: .topLeft, to: CGPoint(x: 50, y: 80), shiftConstrained: true)
        TestHarness.assertEqual(rect.bounds.maxX, 350.0, "TopLeft resize preserves maxX (bottomRight anchor)")
        TestHarness.assertEqual(rect.bounds.maxY, 350.0, "TopLeft resize preserves maxY (bottomRight anchor)")
        TestHarness.assertEqual(rect.bounds.width, 300.0, "Shift-constrained box width is 300")
        TestHarness.assertEqual(rect.bounds.height, 300.0, "Shift-constrained box height is 300")

        // 3. Arrow line handle resize with Shift snaps angle relative to opposite endpoint
        var arrow = AnnotationObject(
            tool: .arrow,
            points: [CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 100)]
        )
        // Drag endPoint handle with slight angle to (200, 105)
        arrow.resize(handle: .endPoint, to: CGPoint(x: 200, y: 105), shiftConstrained: true)
        TestHarness.assertEqual(arrow.points[0], CGPoint(x: 100, y: 100), "StartPoint remains fixed at (100, 100)")
        TestHarness.assertEqual(round(arrow.points[1].x), 200.0, "EndPoint snaps x to 200")
        TestHarness.assertEqual(round(arrow.points[1].y), 100.0, "EndPoint snaps y to 100 (horizontal 0 deg)")
    }

    private static func testScrollableZoomStepCalculationsAndClamping() {
        let dummyImage = makeTestCGImage(width: 400, height: 300)
        let engine = AnnotationEngine()
        let docView = ScrollableAnnotationDocumentView(baseImage: dummyImage, engine: engine)
        let scrollView = ScrollableAnnotationScrollView(documentCanvasView: docView)

        TestHarness.assertEqual(scrollView.magnification, 1.0, "Initial magnification is 1.0")

        // Geometric step up (1.25x)
        scrollView.zoomIn()
        TestHarness.assertEqual(scrollView.magnification, 1.25, "zoomIn step is 1.25")
        scrollView.zoomIn()
        TestHarness.assertEqual(scrollView.magnification, 1.5625, "zoomIn step 2 is 1.5625")

        // Geometric step down
        scrollView.zoomOut()
        TestHarness.assertEqual(scrollView.magnification, 1.25, "zoomOut step 1 is 1.25")
        scrollView.zoomOut()
        TestHarness.assertTrue(abs(scrollView.magnification - 1.0) < 1e-6, "Round-trip zoomIn/zoomOut returns to 1.0")

        // Max ceiling clamping (4.0)
        for _ in 0..<15 {
            scrollView.zoomIn()
        }
        TestHarness.assertEqual(scrollView.magnification, 4.0, "zoomIn clamped strictly to max 4.0")

        // Actual size reset
        scrollView.zoomToActualSize()
        TestHarness.assertEqual(scrollView.magnification, 1.0, "zoomToActualSize resets to 1.0")

        // Min floor clamping (0.1)
        for _ in 0..<20 {
            scrollView.zoomOut()
        }
        TestHarness.assertEqual(scrollView.magnification, 0.1, "zoomOut clamped strictly to min 0.1")

        // Zoom ViewModel HUD
        let zModel = ScrollableZoomViewModel(magnification: 1.0)
        TestHarness.assertEqual(zModel.magnification, 1.0, "Zoom ViewModel initialized to 1.0")
        var zoomInTriggered = false
        zModel.onZoomIn = { zoomInTriggered = true }
        zModel.onZoomIn?()
        TestHarness.assertTrue(zoomInTriggered, "Zoom ViewModel onZoomIn callback fired")
    }

    private static func testMainShotViewKeyboardShortcuts() {
        // Circular keyboard navigation stepDown & stepUp
        let visibleCount = 5
        let downFromZero = ShortcutNavigator.stepDown(currentIndex: 0, visibleCount: visibleCount)
        TestHarness.assertEqual(downFromZero, 1, "stepDown from 0 is 1")

        let downFromEnd = ShortcutNavigator.stepDown(currentIndex: 4, visibleCount: visibleCount)
        TestHarness.assertEqual(downFromEnd, 0, "stepDown from 4 wraps circular to 0")

        let upFromZero = ShortcutNavigator.stepUp(currentIndex: 0, visibleCount: visibleCount)
        TestHarness.assertEqual(upFromZero, 4, "stepUp from 0 wraps circular to 4")

        let upFromNil = ShortcutNavigator.stepUp(currentIndex: nil, visibleCount: visibleCount)
        TestHarness.assertEqual(upFromNil, 4, "stepUp from nil selects last item (4)")

        let downFromNil = ShortcutNavigator.stepDown(currentIndex: nil, visibleCount: visibleCount)
        TestHarness.assertEqual(downFromNil, 0, "stepDown from nil selects first item (0)")

        // 1..9 quick mapping
        let digitEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "3",
            charactersIgnoringModifiers: "3",
            isARepeat: false,
            keyCode: 20
        )
        if let event = digitEvent {
            let digit = ShortcutNavigator.parseShortcut(from: event, searchFieldHasFocus: false)
            TestHarness.assertEqual(digit, 3, "Parsed digit 3 from key event")
        }
    }

    private static func testLayerZIndexReorderingAndUndoRedo() {
        let engine = AnnotationEngine(maxHistoryLimit: 50)
        let objA = AnnotationObject(tool: .rectangle, bounds: CGRect(x: 10, y: 10, width: 50, height: 50))
        let objB = AnnotationObject(tool: .ellipse, bounds: CGRect(x: 20, y: 20, width: 50, height: 50))
        let objC = AnnotationObject(tool: .arrow, points: [CGPoint(x: 30, y: 30), CGPoint(x: 60, y: 60)])
        let objD = AnnotationObject(tool: .text, bounds: CGRect(x: 40, y: 40, width: 50, height: 20), text: "D")

        engine.addObject(objA)
        engine.addObject(objB)
        engine.addObject(objC)
        engine.addObject(objD)

        TestHarness.assertEqual(engine.objects.map { $0.id }, [objA.id, objB.id, objC.id, objD.id], "Initial order A, B, C, D")

        // Select objB (index 1)
        engine.selectedObjectID = objB.id

        // 1. Bring forward (index 1 -> index 2)
        let broughtForward = engine.bringSelectedForward()
        TestHarness.assertTrue(broughtForward, "bringSelectedForward succeeded")
        TestHarness.assertEqual(engine.objects.map { $0.id }, [objA.id, objC.id, objB.id, objD.id], "Order after bring forward: A, C, B, D")

        // 2. Bring to front (index 2 -> index 3)
        let broughtToFront = engine.bringSelectedToFront()
        TestHarness.assertTrue(broughtToFront, "bringSelectedToFront succeeded")
        TestHarness.assertEqual(engine.objects.map { $0.id }, [objA.id, objC.id, objD.id, objB.id], "Order after bring to front: A, C, D, B")

        // Bring to front again when already at front returns false (no-op)
        TestHarness.assertFalse(engine.bringSelectedToFront(), "bringSelectedToFront at front returns false")

        // 3. Send backward (index 3 -> index 2)
        let sentBackward = engine.sendSelectedBackward()
        TestHarness.assertTrue(sentBackward, "sendSelectedBackward succeeded")
        TestHarness.assertEqual(engine.objects.map { $0.id }, [objA.id, objC.id, objB.id, objD.id], "Order after send backward: A, C, B, D")

        // 4. Send to back (index 2 -> index 0)
        let sentToBack = engine.sendSelectedToBack()
        TestHarness.assertTrue(sentToBack, "sendSelectedToBack succeeded")
        TestHarness.assertEqual(engine.objects.map { $0.id }, [objB.id, objA.id, objC.id, objD.id], "Order after send to back: B, A, C, D")

        // Send to back again when already at back returns false (no-op)
        TestHarness.assertFalse(engine.sendSelectedToBack(), "sendSelectedToBack at back returns false")

        // 5. Test Undo/Redo symmetry
        // Undo send to back (0 -> 2)
        TestHarness.assertTrue(engine.canUndo, "Can undo send to back")
        engine.undo()
        TestHarness.assertEqual(engine.objects.map { $0.id }, [objA.id, objC.id, objB.id, objD.id], "Undo send to back restores A, C, B, D")

        // Undo send backward (2 -> 3)
        engine.undo()
        TestHarness.assertEqual(engine.objects.map { $0.id }, [objA.id, objC.id, objD.id, objB.id], "Undo send backward restores A, C, D, B")

        // Undo bring to front (3 -> 2)
        engine.undo()
        TestHarness.assertEqual(engine.objects.map { $0.id }, [objA.id, objC.id, objB.id, objD.id], "Undo bring to front restores A, C, B, D")

        // Undo bring forward (2 -> 1)
        engine.undo()
        TestHarness.assertEqual(engine.objects.map { $0.id }, [objA.id, objB.id, objC.id, objD.id], "Undo bring forward restores initial A, B, C, D")

        // Redo bring forward (1 -> 2)
        TestHarness.assertTrue(engine.canRedo, "Can redo")
        engine.redo()
        TestHarness.assertEqual(engine.objects.map { $0.id }, [objA.id, objC.id, objB.id, objD.id], "Redo bring forward restores A, C, B, D")

        // =========================================================================
        // Tab / Shift+Tab Selection Cycling (selectNextObject) Tests (v1.0.22)
        // =========================================================================
        let cyclingEngine = AnnotationEngine()
        TestHarness.assertNil(cyclingEngine.selectNextObject(), "selectNextObject returns nil on empty engine")
        TestHarness.assertNil(cyclingEngine.selectNextObject(reverse: true), "selectNextObject(reverse: true) returns nil on empty engine")

        let obj1 = AnnotationObject(tool: .rectangle, bounds: CGRect(x: 10, y: 10, width: 50, height: 50))
        let obj2 = AnnotationObject(tool: .ellipse, bounds: CGRect(x: 70, y: 10, width: 50, height: 50))
        let obj3 = AnnotationObject(tool: .arrow, bounds: CGRect(x: 130, y: 10, width: 50, height: 50))
        cyclingEngine.addObject(obj1)
        cyclingEngine.addObject(obj2)
        cyclingEngine.addObject(obj3)
        cyclingEngine.deselectAll()

        // Forward cycling from unselected state picks first object (obj1)
        let firstSelected = cyclingEngine.selectNextObject(reverse: false)
        TestHarness.assertEqual(firstSelected, obj1.id, "selectNextObject selects obj1 from unselected state")
        TestHarness.assertEqual(cyclingEngine.selectedObjectID, obj1.id, "selectedObjectID is obj1")
        TestHarness.assertTrue(cyclingEngine.objects[0].isSelected, "obj1 isSelected is true")
        TestHarness.assertFalse(cyclingEngine.objects[1].isSelected, "obj2 isSelected is false")

        // Forward cycle to obj2
        let secondSelected = cyclingEngine.selectNextObject(reverse: false)
        TestHarness.assertEqual(secondSelected, obj2.id, "selectNextObject advances to obj2")
        TestHarness.assertEqual(cyclingEngine.selectedObjectID, obj2.id, "selectedObjectID is obj2")

        // Forward cycle to obj3
        let thirdSelected = cyclingEngine.selectNextObject(reverse: false)
        TestHarness.assertEqual(thirdSelected, obj3.id, "selectNextObject advances to obj3")

        // Forward cycle wraps around to obj1
        let wrappedSelected = cyclingEngine.selectNextObject(reverse: false)
        TestHarness.assertEqual(wrappedSelected, obj1.id, "selectNextObject wraps around to obj1")

        // Reverse cycle from obj1 wraps to obj3
        let reverseWrapped = cyclingEngine.selectNextObject(reverse: true)
        TestHarness.assertEqual(reverseWrapped, obj3.id, "selectNextObject(reverse: true) from obj1 wraps to obj3")

        // Reverse cycle from obj3 to obj2
        let reversePrev = cyclingEngine.selectNextObject(reverse: true)
        TestHarness.assertEqual(reversePrev, obj2.id, "selectNextObject(reverse: true) steps backward to obj2")

        // Reverse from unselected state picks last object (obj3)
        cyclingEngine.deselectAll()
        let reverseFromNone = cyclingEngine.selectNextObject(reverse: true)
        TestHarness.assertEqual(reverseFromNone, obj3.id, "selectNextObject(reverse: true) selects obj3 from unselected state")
    }
}
