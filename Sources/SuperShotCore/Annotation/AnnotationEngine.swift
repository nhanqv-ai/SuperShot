import Foundation
import CoreGraphics
import AppKit
import Combine

/// State controller managing interactive vector drawing, selection, and command history.
public final class AnnotationEngine: ObservableObject {
    public static let defaultMaxHistoryLimit: Int = 50

    // MARK: - Published Properties

    @Published public var activeTool: AnnotationTool = .select
    @Published public var objects: [AnnotationObject] = []
    @Published public var selectedObjectID: UUID?
    @Published public var activeDragObject: AnnotationObject?
    @Published public private(set) var canUndo: Bool = false
    @Published public private(set) var canRedo: Bool = false

    // MARK: - Internal History Stacks

    public var maxHistoryLimit: Int
    private var undoStack: [AnnotationAction] = []
    private var redoStack: [AnnotationAction] = []

    // Interactive Drag State Tracking
    private var dragStartPoint: CGPoint?
    public private(set) var isDraggingExistingObject: Bool = false
    public private(set) var activeResizeHandle: AnnotationHandle?
    private var preDragObjectSnapshot: AnnotationObject?

    // MARK: - Initialization

    public init(maxHistoryLimit: Int = AnnotationEngine.defaultMaxHistoryLimit) {
        self.maxHistoryLimit = max(10, maxHistoryLimit)
    }

    // MARK: - Selection Accessor

    public var selectedObject: AnnotationObject? {
        guard let id = selectedObjectID else { return nil }
        return objects.first(where: { $0.id == id })
    }

    // MARK: - Object Management

    /// Appends a new vector object to the canvas and records undo action.
    public func addObject(_ object: AnnotationObject) {
        let action = AnnotationAction.create(object)
        execute(action: action)
        selectedObjectID = object.id
    }

    /// Duplicates the currently selected vector object, applying an offset (+16, +16 by default).
    /// Clamps or reverses the offset if boundary is provided and projected bounds exceed boundary.
    /// Automatically records an AnnotationAction.create undo step and selects the new clone.
    @discardableResult
    public func duplicateSelected(
        offset: CGPoint = CGPoint(x: 16, y: 16),
        within boundary: CGRect? = nil
    ) -> AnnotationObject? {
        guard let original = selectedObject else { return nil }

        var effectiveOffset = offset
        if let bounds = boundary {
            let candidateBounds = original.bounds.offsetBy(dx: offset.x, dy: offset.y)
            let outOfBounds = candidateBounds.minX < bounds.minX ||
                              candidateBounds.minY < bounds.minY ||
                              candidateBounds.maxX > bounds.maxX ||
                              candidateBounds.maxY > bounds.maxY
            if outOfBounds {
                // Attempt reverse offset if within boundary
                let reverseBounds = original.bounds.offsetBy(dx: -offset.x, dy: -offset.y)
                if reverseBounds.minX >= bounds.minX && reverseBounds.minY >= bounds.minY &&
                   reverseBounds.maxX <= bounds.maxX && reverseBounds.maxY <= bounds.maxY {
                    effectiveOffset = CGPoint(x: -offset.x, y: -offset.y)
                } else {
                    let clampedX = min(max(candidateBounds.minX, bounds.minX), bounds.maxX - original.bounds.width)
                    let clampedY = min(max(candidateBounds.minY, bounds.minY), bounds.maxY - original.bounds.height)
                    effectiveOffset = CGPoint(x: clampedX - original.bounds.minX, y: clampedY - original.bounds.minY)
                }
            }
        }

        let clone = original.duplicated(offset: effectiveOffset)
        addObject(clone)
        return clone
    }

    /// Non-mutating hit-test returning the topmost object containing point, or nil if none.
    public func hitObject(at point: CGPoint) -> AnnotationObject? {
        for obj in objects.reversed() {
            if obj.contains(point: point) {
                return obj
            }
        }
        return nil
    }

    /// Selects the topmost object containing point. Returns nil if empty space clicked.
    @discardableResult
    public func selectObject(at point: CGPoint) -> AnnotationObject? {
        for obj in objects.reversed() {
            if obj.contains(point: point) {
                selectedObjectID = obj.id
                updateSelectionFlags()
                return obj
            }
        }
        selectedObjectID = nil
        updateSelectionFlags()
        return nil
    }

    public func deselectAll() {
        selectedObjectID = nil
        updateSelectionFlags()
    }

    private func updateSelectionFlags() {
        for i in 0..<objects.count {
            objects[i].isSelected = (objects[i].id == selectedObjectID)
        }
    }

    // MARK: - Interactive Drag Lifecycle

    /// Begins interactive mouse drag at point.
    public func startDrag(
        at point: CGPoint,
        tool: AnnotationTool? = nil,
        colorHex: String = "#FF3B30",
        strokeWidth: CGFloat = 3.0,
        fontSize: CGFloat = 18.0
    ) {
        let effectiveTool = tool ?? activeTool
        dragStartPoint = point

        // 1. If activeTool is .select, check if user clicked on a resize handle of selected object
        if effectiveTool == .select, let sel = selectedObject {
            if let handle = sel.handle(at: point) {
                activeResizeHandle = handle
                preDragObjectSnapshot = sel
                return
            }
            if sel.contains(point: point) {
                isDraggingExistingObject = true
                preDragObjectSnapshot = sel
                return
            }
        }

        // 2. Check if user clicked to select another object
        if effectiveTool == .select {
            if let hit = selectObject(at: point) {
                isDraggingExistingObject = true
                preDragObjectSnapshot = hit
            }
            return
        }

        // 3. User is drawing a new vector object
        deselectAll()
        let initialBounds = CGRect(x: point.x, y: point.y, width: 0, height: 0)
        let newObj = AnnotationObject(
            tool: effectiveTool,
            points: [point],
            bounds: initialBounds,
            colorHex: colorHex,
            strokeWidth: strokeWidth,
            fontSize: fontSize,
            text: effectiveTool == .text ? "Text" : "",
            isSelected: true
        )
        activeDragObject = newObj
    }

    /// Updates interactive drag as mouse moves across canvas.
    public func updateDrag(to currentPoint: CGPoint, shiftKeyPressed: Bool = false) {
        guard let startPoint = dragStartPoint else { return }

        // Case A: Resizing existing object via handle
        if let handle = activeResizeHandle, var snapshot = preDragObjectSnapshot,
           let index = objects.firstIndex(where: { $0.id == snapshot.id }) {
            snapshot.resize(handle: handle, to: currentPoint, shiftConstrained: shiftKeyPressed)
            objects[index] = snapshot
            return
        }

        // Case B: Translating / moving selected object
        if isDraggingExistingObject, let snapshot = preDragObjectSnapshot,
           let index = objects.firstIndex(where: { $0.id == snapshot.id }) {
            let delta = CGPoint(x: currentPoint.x - startPoint.x, y: currentPoint.y - startPoint.y)
            var moved = snapshot
            moved.translate(by: delta)
            objects[index] = moved
            return
        }

        // Case C: Interactive new object creation
        guard var draft = activeDragObject else { return }

        switch draft.tool {
        case .rectangle, .ellipse, .blur:
            var minX = min(startPoint.x, currentPoint.x)
            var minY = min(startPoint.y, currentPoint.y)
            var w = abs(currentPoint.x - startPoint.x)
            var h = abs(currentPoint.y - startPoint.y)

            if shiftKeyPressed {
                let side = max(w, h)
                w = side
                h = side
                minX = currentPoint.x < startPoint.x ? startPoint.x - side : startPoint.x
                minY = currentPoint.y < startPoint.y ? startPoint.y - side : startPoint.y
            }

            draft.bounds = CGRect(x: minX, y: minY, width: max(1.0, w), height: max(1.0, h))

        case .line, .arrow:
            var target = currentPoint
            if shiftKeyPressed {
                target = snapAngle(from: startPoint, to: currentPoint)
            }
            draft.points = [startPoint, target]
            draft.bounds = AnnotationObject.calculateBounds(from: draft.points, strokeWidth: draft.strokeWidth)

        case .pen, .highlighter:
            if let last = draft.points.last, hypot(currentPoint.x - last.x, currentPoint.y - last.y) < 1.0 {
                return
            }
            draft.points.append(currentPoint)
            draft.bounds = AnnotationObject.calculateBounds(from: draft.points, strokeWidth: draft.strokeWidth)

        case .text:
            draft.bounds = CGRect(x: startPoint.x, y: startPoint.y, width: max(100.0, currentPoint.x - startPoint.x), height: 40.0)

        case .select:
            break
        }

        activeDragObject = draft
    }

    /// Commits interactive drag upon mouse up.
    @discardableResult
    public func endDrag(at endPoint: CGPoint) -> AnnotationObject? {
        defer {
            dragStartPoint = nil
            isDraggingExistingObject = false
            activeResizeHandle = nil
            preDragObjectSnapshot = nil
            activeDragObject = nil
        }

        // Case A: Finished resizing via handle
        if let _ = activeResizeHandle, let snapshot = preDragObjectSnapshot,
           let updated = objects.first(where: { $0.id == snapshot.id }) {
            let action = AnnotationAction.resize(
                id: updated.id,
                oldBounds: snapshot.bounds,
                newBounds: updated.bounds,
                oldPoints: snapshot.points,
                newPoints: updated.points
            )
            pushUndo(action)
            return updated
        }

        // Case B: Finished moving existing object
        if isDraggingExistingObject, let snapshot = preDragObjectSnapshot,
           let updated = objects.first(where: { $0.id == snapshot.id }) {
            let delta = CGPoint(x: updated.bounds.minX - snapshot.bounds.minX, y: updated.bounds.minY - snapshot.bounds.minY)
            if hypot(delta.x, delta.y) > 0.5 {
                let action = AnnotationAction.move(id: updated.id, delta: delta)
                pushUndo(action)
            }
            return updated
        }

        // Case C: Finished drawing new object
        guard let draft = activeDragObject else { return nil }

        if draft.tool != .text && draft.bounds.width < 2.0 && draft.bounds.height < 2.0 && draft.points.count < 2 {
            return nil
        }

        addObject(draft)
        return draft
    }

    // MARK: - Mutations on Selected Object

    public func moveSelected(by delta: CGPoint) {
        guard let id = selectedObjectID, let idx = objects.firstIndex(where: { $0.id == id }) else { return }
        objects[idx].translate(by: delta)
        let action = AnnotationAction.move(id: id, delta: delta)
        pushUndo(action)
    }

    public func recolorSelected(newHex: String) {
        guard let id = selectedObjectID, let idx = objects.firstIndex(where: { $0.id == id }) else { return }
        let oldHex = objects[idx].colorHex
        let normalized = ColorPreset.normalize(hex: newHex)
        guard oldHex != normalized else { return }
        objects[idx].colorHex = normalized
        let action = AnnotationAction.recolor(id: id, oldHex: oldHex, newHex: normalized)
        pushUndo(action)
    }

    public func updateSelectedStrokeWidth(_ newWidth: CGFloat) {
        guard let id = selectedObjectID, let idx = objects.firstIndex(where: { $0.id == id }) else { return }
        let oldWidth = objects[idx].strokeWidth
        objects[idx].strokeWidth = max(1.0, newWidth)
        let action = AnnotationAction.updateStrokeWidth(id: id, oldWidth: oldWidth, newWidth: objects[idx].strokeWidth)
        pushUndo(action)
    }

    public func updateSelectedFontSize(_ newSize: CGFloat) {
        guard let id = selectedObjectID, let idx = objects.firstIndex(where: { $0.id == id }) else { return }
        let oldSize = objects[idx].fontSize
        objects[idx].fontSize = max(9.0, min(newSize, 144.0))
        let action = AnnotationAction.updateFontSize(id: id, oldSize: oldSize, newSize: objects[idx].fontSize)
        pushUndo(action)
    }

    public func updateSelectedText(_ newText: String) {
        guard let id = selectedObjectID, let idx = objects.firstIndex(where: { $0.id == id }) else { return }
        let oldText = objects[idx].text
        let oldBounds = objects[idx].bounds
        objects[idx].text = newText
        let action = AnnotationAction.editText(id: id, oldText: oldText, newText: newText, oldBounds: oldBounds, newBounds: objects[idx].bounds)
        pushUndo(action)
    }

    public func updateSelectedObject(_ transform: (inout AnnotationObject) -> Void) {
        guard let id = selectedObjectID, let idx = objects.firstIndex(where: { $0.id == id }) else { return }
        let oldObj = objects[idx]
        var newObj = oldObj
        transform(&newObj)
        objects[idx] = newObj
        if oldObj.text != newObj.text {
            let action = AnnotationAction.editText(id: id, oldText: oldObj.text, newText: newObj.text, oldBounds: oldObj.bounds, newBounds: newObj.bounds)
            pushUndo(action)
        }
    }

    @discardableResult
    public func deleteSelected() -> AnnotationObject? {
        guard let id = selectedObjectID, let idx = objects.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = objects.remove(at: idx)
        selectedObjectID = nil
        let action = AnnotationAction.delete(removed, index: idx)
        pushUndo(action)
        return removed
    }

    /// Resizes the currently selected vector object by delta width and delta height.
    /// Clamps to minimumDimension (default: 10.0pt) and optional boundary.
    /// Pushes an AnnotationAction.resize undo action so changes can be reverted.
    @discardableResult
    public func resizeSelected(
        deltaWidth: CGFloat,
        deltaHeight: CGFloat,
        minimumDimension: CGFloat = 10.0,
        boundary: CGRect? = nil
    ) -> Bool {
        guard let id = selectedObjectID, let idx = objects.firstIndex(where: { $0.id == id }) else { return false }
        let oldObj = objects[idx]
        let oldBounds = oldObj.bounds

        var newW = max(minimumDimension, oldBounds.width + deltaWidth)
        var newH = max(minimumDimension, oldBounds.height + deltaHeight)

        if let b = boundary {
            newW = min(newW, max(minimumDimension, b.maxX - oldBounds.minX))
            newH = min(newH, max(minimumDimension, b.maxY - oldBounds.minY))
        }

        guard newW != oldBounds.width || newH != oldBounds.height else { return false }

        var newObj = oldObj
        newObj.bounds = CGRect(x: oldBounds.minX, y: oldBounds.minY, width: newW, height: newH)

        if (oldObj.tool == .line || oldObj.tool == .arrow) && oldObj.points.count >= 2 {
            let p1 = oldObj.points[0]
            let p2 = oldObj.points[1]
            let newP2 = CGPoint(x: p2.x + (newW - oldBounds.width), y: p2.y + (newH - oldBounds.height))
            newObj.points = [p1, newP2]
            newObj.bounds = AnnotationObject.calculateBounds(from: newObj.points, strokeWidth: newObj.strokeWidth)
        } else if !oldObj.points.isEmpty && oldBounds.width > 0 && oldBounds.height > 0 {
            let scaleX = newW / oldBounds.width
            let scaleY = newH / oldBounds.height
            newObj.points = oldObj.points.map { pt in
                let relX = (pt.x - oldBounds.minX) * scaleX
                let relY = (pt.y - oldBounds.minY) * scaleY
                return CGPoint(x: oldBounds.minX + relX, y: oldBounds.minY + relY)
            }
        }

        objects[idx] = newObj
        let action = AnnotationAction.resize(
            id: id,
            oldBounds: oldBounds,
            newBounds: newObj.bounds,
            oldPoints: oldObj.points,
            newPoints: newObj.points
        )
        pushUndo(action)
        return true
    }

    /// Clears all vector annotations from the canvas with full undo/redo support.
    /// Returns the number of annotations that were removed.
    @discardableResult
    public func clearAll() -> Int {
        guard !objects.isEmpty else { return 0 }
        let count = objects.count
        let currentObjects = objects
        // Store delete actions in reverse order so undo (.create) reconstructs in forward order
        let deleteActions = currentObjects.enumerated().reversed().map { idx, obj in
            AnnotationAction.delete(obj, index: idx)
        }
        selectedObjectID = nil
        objects.removeAll()
        updateSelectionFlags()
        pushUndo(.batch(deleteActions))
        return count
    }

    // MARK: - Layer Z-Index Reordering

    /// Moves the currently selected annotation to the top of the z-order (front-most layer).
    @discardableResult
    public func bringSelectedToFront() -> Bool {
        guard let id = selectedObjectID,
              let currentIndex = objects.firstIndex(where: { $0.id == id }) else { return false }
        let targetIndex = objects.count - 1
        guard currentIndex < targetIndex else { return false }
        execute(action: .reorder(id: id, oldIndex: currentIndex, newIndex: targetIndex))
        return true
    }

    /// Moves the currently selected annotation to the bottom of the z-order (back-most layer).
    @discardableResult
    public func sendSelectedToBack() -> Bool {
        guard let id = selectedObjectID,
              let currentIndex = objects.firstIndex(where: { $0.id == id }) else { return false }
        let targetIndex = 0
        guard currentIndex > targetIndex else { return false }
        execute(action: .reorder(id: id, oldIndex: currentIndex, newIndex: targetIndex))
        return true
    }

    /// Moves the currently selected annotation one step forward towards the front.
    @discardableResult
    public func bringSelectedForward() -> Bool {
        guard let id = selectedObjectID,
              let currentIndex = objects.firstIndex(where: { $0.id == id }) else { return false }
        let targetIndex = currentIndex + 1
        guard targetIndex < objects.count else { return false }
        execute(action: .reorder(id: id, oldIndex: currentIndex, newIndex: targetIndex))
        return true
    }

    /// Moves the currently selected annotation one step backward towards the back.
    @discardableResult
    public func sendSelectedBackward() -> Bool {
        guard let id = selectedObjectID,
              let currentIndex = objects.firstIndex(where: { $0.id == id }) else { return false }
        let targetIndex = currentIndex - 1
        guard targetIndex >= 0 else { return false }
        execute(action: .reorder(id: id, oldIndex: currentIndex, newIndex: targetIndex))
        return true
    }

    // MARK: - Command Pattern Undo / Redo

    public func undo() {
        guard canUndo, let action = undoStack.popLast() else { return }
        applyInverse(action: action)
        redoStack.append(action)
        updateStackFlags()
    }

    public func redo() {
        guard canRedo, let action = redoStack.popLast() else { return }
        applyForward(action: action)
        undoStack.append(action)
        updateStackFlags()
    }

    private func execute(action: AnnotationAction) {
        applyForward(action: action)
        pushUndo(action)
    }

    private func pushUndo(_ action: AnnotationAction) {
        undoStack.append(action)
        if undoStack.count > maxHistoryLimit {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        updateStackFlags()
    }

    private func updateStackFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    private func applyForward(action: AnnotationAction) {
        switch action {
        case .create(let object):
            objects.append(object)
            selectedObjectID = object.id
        case .delete(let object, _):
            objects.removeAll(where: { $0.id == object.id })
            if selectedObjectID == object.id { selectedObjectID = nil }
        case .move(let id, let delta):
            if let idx = objects.firstIndex(where: { $0.id == id }) {
                objects[idx].translate(by: delta)
            }
        case .resize(let id, _, let newBounds, _, let newPoints):
            if let idx = objects.firstIndex(where: { $0.id == id }) {
                objects[idx].bounds = newBounds
                objects[idx].points = newPoints
            }
        case .recolor(let id, _, let newHex):
            if let idx = objects.firstIndex(where: { $0.id == id }) {
                objects[idx].colorHex = newHex
            }
        case .updateStrokeWidth(let id, _, let newWidth):
            if let idx = objects.firstIndex(where: { $0.id == id }) {
                objects[idx].strokeWidth = newWidth
            }
        case .updateFontSize(let id, _, let newSize):
            if let idx = objects.firstIndex(where: { $0.id == id }) {
                objects[idx].fontSize = newSize
            }
        case .editText(let id, _, let newText, _, let newBounds):
            if let idx = objects.firstIndex(where: { $0.id == id }) {
                objects[idx].text = newText
                objects[idx].bounds = newBounds
            }
        case .reorder(let id, _, let newIndex):
            if let currentIndex = objects.firstIndex(where: { $0.id == id }) {
                let obj = objects.remove(at: currentIndex)
                let clampedIndex = max(0, min(newIndex, objects.count))
                objects.insert(obj, at: clampedIndex)
                selectedObjectID = id
            }
        case .batch(let actions):
            actions.forEach { applyForward(action: $0) }
        }
        updateSelectionFlags()
    }

    private func applyInverse(action: AnnotationAction) {
        applyForward(action: action.inverted())
    }

    // MARK: - Geometry Utilities

    private func snapAngle(from: CGPoint, to: CGPoint) -> CGPoint {
        AnnotationObject.snapAngle(from: from, to: to)
    }
}
