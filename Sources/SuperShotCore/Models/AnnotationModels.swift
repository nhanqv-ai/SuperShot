import Foundation
import CoreGraphics
import AppKit

// MARK: - AnnotationTool

/// Operational modes for vector annotation and canvas interaction.
public enum AnnotationTool: String, Codable, CaseIterable, Sendable {
    case select          // Select, move, and resize existing vector objects
    case rectangle       // Bounded vector rectangle with customizable border
    case ellipse         // Bounded vector ellipse or circle
    case arrow           // Directional arrow with proportional head
    case line            // Straight diagonal or orthogonal line
    case pen             // Freehand smooth antialiased pen stroke
    case highlighter     // Broad semi-transparent marker stroke
    case text            // In-place editable typography block
    case blur            // Obfuscated region (pixelation or gaussian blur)

    /// SF Symbol identifier representing the tool in macOS UI toolbars.
    public var sfSymbolName: String {
        switch self {
        case .select:      return "cursorarrow"
        case .rectangle:   return "rectangle"
        case .ellipse:     return "circle"
        case .arrow:       return "arrow.up.right"
        case .line:        return "line.diagonal"
        case .pen:         return "pencil.tip"
        case .highlighter: return "highlighter"
        case .text:        return "textformat"
        case .blur:        return "checkerboard.rectangle"
        }
    }

    /// English display title for toolbar tooltips and accessibility.
    public var displayName: String {
        switch self {
        case .select:      return "Select & Move"
        case .rectangle:   return "Rectangle"
        case .ellipse:     return "Ellipse"
        case .arrow:       return "Arrow"
        case .line:        return "Line"
        case .pen:         return "Pen"
        case .highlighter: return "Highlighter"
        case .text:        return "Text"
        case .blur:        return "Blur & Pixelate"
        }
    }

    /// True if tool creates new vector content; false if tool modifies existing content.
    public var isDrawingTool: Bool {
        self != .select
    }

    /// True if tool is defined by a two-point bounding box (rect, ellipse, blur, text).
    public var isBoxShape: Bool {
        switch self {
        case .rectangle, .ellipse, .blur, .text:
            return true
        case .select, .arrow, .line, .pen, .highlighter:
            return false
        }
    }

    /// True if tool records continuous stream of mouse drag coordinates.
    public var isContinuousPath: Bool {
        self == .pen || self == .highlighter
    }
}

// MARK: - AnnotationHandle

/// Interactive grab handle positions anchored to a vector object's bounding box.
public enum AnnotationHandle: String, Codable, CaseIterable, Sendable {
    case topLeft
    case topCenter
    case topRight
    case middleRight
    case bottomRight
    case bottomCenter
    case bottomLeft
    case middleLeft

    // Dedicated handles for 2-point objects (line, arrow)
    case startPoint
    case endPoint

    /// Corresponding AppKit cursor for the handle resize direction.
    public var cursor: NSCursor {
        switch self {
        case .topLeft, .bottomRight:
            return NSCursor.crosshair
        case .topRight, .bottomLeft:
            return NSCursor.crosshair
        case .topCenter, .bottomCenter:
            return NSCursor.resizeUpDown
        case .middleLeft, .middleRight:
            return NSCursor.resizeLeftRight
        case .startPoint, .endPoint:
            return NSCursor.crosshair
        }
    }
}

// MARK: - AnnotationObject

/// An immutable/mutable vector annotation element rendered on the canvas.
public struct AnnotationObject: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var tool: AnnotationTool
    public var points: [CGPoint]       // Path control points or [start, end]
    public var bounds: CGRect          // Bounding rectangle in canvas points
    public var colorHex: String        // Normalized hex code (e.g. "#FF3B30")
    public var strokeWidth: CGFloat    // Border or line thickness
    public var fontSize: CGFloat       // Text font point size
    public var text: String            // Text content for .text tool
    public var blurRadius: CGFloat     // Blur intensity or pixel block size
    public var isSelected: Bool        // Active selection state in UI
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        tool: AnnotationTool,
        points: [CGPoint] = [],
        bounds: CGRect = .zero,
        colorHex: String = "#FF3B30",
        strokeWidth: CGFloat = 3.0,
        fontSize: CGFloat = 18.0,
        text: String = "",
        blurRadius: CGFloat = 10.0,
        isSelected: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.tool = tool
        self.points = points
        self.bounds = bounds.standardized
        self.colorHex = ColorPreset.normalize(hex: colorHex)
        self.strokeWidth = max(1.0, strokeWidth)
        self.fontSize = max(9.0, min(fontSize, 144.0))
        self.text = text
        self.blurRadius = max(1.0, blurRadius)
        self.isSelected = isSelected
        self.createdAt = createdAt

        // If bounds is zero but points exist, derive bounds from points
        if self.bounds.isEmpty && !points.isEmpty {
            self.bounds = AnnotationObject.calculateBounds(from: points, strokeWidth: self.strokeWidth)
        }
    }

    // MARK: - Bounds Calculation

    /// Computes enclosing bounding box enclosing an array of points with stroke padding.
    public static func calculateBounds(from points: [CGPoint], strokeWidth: CGFloat = 0) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y

        for pt in points.dropFirst() {
            minX = min(minX, pt.x)
            maxX = max(maxX, pt.x)
            minY = min(minY, pt.y)
            maxY = max(maxY, pt.y)
        }

        let width = max(1.0, maxX - minX)
        let height = max(1.0, maxY - minY)
        let rect = CGRect(x: minX, y: minY, width: width, height: height)
        return strokeWidth > 0 ? rect.insetBy(dx: -strokeWidth / 2.0, dy: -strokeWidth / 2.0) : rect
    }

    // MARK: - Hit-Testing

    /// Determines if a canvas point falls on or sufficiently near the object for selection.
    public func contains(point: CGPoint, tolerance: CGFloat = 8.0) -> Bool {
        let hitThreshold = max(strokeWidth / 2.0 + 4.0, tolerance)

        switch tool {
        case .rectangle:
            return bounds.insetBy(dx: -hitThreshold, dy: -hitThreshold).contains(point)

        case .blur, .text:
            return bounds.insetBy(dx: -hitThreshold, dy: -hitThreshold).contains(point)

        case .ellipse:
            let rx = bounds.width / 2.0
            let ry = bounds.height / 2.0
            guard rx > 0, ry > 0 else { return bounds.contains(point) }
            let cx = bounds.midX
            let cy = bounds.midY
            let dx = (point.x - cx) / rx
            let dy = (point.y - cy) / ry
            let distSq = (dx * dx) + (dy * dy)
            return distSq >= 0.65 && distSq <= 1.35

        case .line, .arrow:
            guard points.count >= 2 else {
                return bounds.insetBy(dx: -hitThreshold, dy: -hitThreshold).contains(point)
            }
            let p1 = points[0]
            let p2 = points[1]
            let segDist = AnnotationObject.distanceToSegment(p: point, v: p1, w: p2)
            if segDist <= hitThreshold { return true }
            if tool == .arrow {
                return isNearArrowHead(point: point, p1: p1, p2: p2, threshold: hitThreshold)
            }
            return false

        case .pen, .highlighter:
            guard points.count >= 2 else {
                if let single = points.first {
                    return hypot(point.x - single.x, point.y - single.y) <= hitThreshold
                }
                return bounds.contains(point)
            }
            let checkWidth = tool == .highlighter ? max(strokeWidth / 2.0 + 4.0, 12.0) : hitThreshold
            for i in 0..<(points.count - 1) {
                if AnnotationObject.distanceToSegment(p: point, v: points[i], w: points[i+1]) <= checkWidth {
                    return true
                }
            }
            return false

        case .select:
            return false
        }
    }

    /// Mathematical distance from point p to line segment (v -> w).
    public static func distanceToSegment(p: CGPoint, v: CGPoint, w: CGPoint) -> CGFloat {
        let l2 = pow(w.x - v.x, 2) + pow(w.y - v.y, 2)
        if l2 == 0 { return hypot(p.x - v.x, p.y - v.y) }
        let t = max(0, min(1, ((p.x - v.x) * (w.x - v.x) + (p.y - v.y) * (w.y - v.y)) / l2))
        let projection = CGPoint(x: v.x + t * (w.x - v.x), y: v.y + t * (w.y - v.y))
        return hypot(p.x - projection.x, p.y - projection.y)
    }

    /// Tests proximity to arrowhead wings.
    private func isNearArrowHead(point: CGPoint, p1: CGPoint, p2: CGPoint, threshold: CGFloat) -> Bool {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        let len = hypot(dx, dy)
        guard len > 1.0 else { return false }
        let theta = atan2(dy, dx)
        let headLen = max(12.0, min(len * 0.5, strokeWidth * 4.0))
        let wingAngle: CGFloat = 0.488 // ~28 degrees

        let w1 = CGPoint(
            x: p2.x - headLen * cos(theta - wingAngle),
            y: p2.y - headLen * sin(theta - wingAngle)
        )
        let w2 = CGPoint(
            x: p2.x - headLen * cos(theta + wingAngle),
            y: p2.y - headLen * sin(theta + wingAngle)
        )

        let d1 = AnnotationObject.distanceToSegment(p: point, v: p2, w: w1)
        let d2 = AnnotationObject.distanceToSegment(p: point, v: p2, w: w2)
        return min(d1, d2) <= threshold
    }

    // MARK: - Handle Detection & Positions

    /// Returns handle coordinates mapped around the object.
    public func handlePositions() -> [AnnotationHandle: CGPoint] {
        if tool == .line || tool == .arrow {
            guard points.count >= 2 else { return [:] }
            return [
                .startPoint: points[0],
                .endPoint: points[1]
            ]
        }

        let b = bounds
        return [
            .topLeft: CGPoint(x: b.minX, y: b.minY),
            .topCenter: CGPoint(x: b.midX, y: b.minY),
            .topRight: CGPoint(x: b.maxX, y: b.minY),
            .middleRight: CGPoint(x: b.maxX, y: b.midY),
            .bottomRight: CGPoint(x: b.maxX, y: b.maxY),
            .bottomCenter: CGPoint(x: b.midX, y: b.maxY),
            .bottomLeft: CGPoint(x: b.minX, y: b.maxY),
            .middleLeft: CGPoint(x: b.minX, y: b.midY)
        ]
    }

    /// Hit-tests grab handles for this object.
    public func handle(at point: CGPoint, hitRadius: CGFloat = 8.0) -> AnnotationHandle? {
        for (handle, handlePt) in handlePositions() {
            if hypot(point.x - handlePt.x, point.y - handlePt.y) <= hitRadius {
                return handle
            }
        }
        return nil
    }

    // MARK: - Transformations

    /// Translates object position by delta.
    public mutating func translate(by delta: CGPoint) {
        bounds = bounds.offsetBy(dx: delta.x, dy: delta.y)
        points = points.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
    }

    /// Resizes bounding box by dragging a specified handle to target point.
    public mutating func resize(handle: AnnotationHandle, to target: CGPoint, shiftConstrained: Bool = false) {
        if (tool == .line || tool == .arrow) && points.count >= 2 {
            if handle == .startPoint {
                points[0] = target
            } else if handle == .endPoint {
                points[1] = target
            }
            bounds = AnnotationObject.calculateBounds(from: points, strokeWidth: strokeWidth)
            return
        }

        var minX = bounds.minX
        var maxX = bounds.maxX
        var minY = bounds.minY
        var maxY = bounds.maxY

        switch handle {
        case .topLeft:
            minX = target.x
            minY = target.y
        case .topCenter:
            minY = target.y
        case .topRight:
            maxX = target.x
            minY = target.y
        case .middleRight:
            maxX = target.x
        case .bottomRight:
            maxX = target.x
            maxY = target.y
        case .bottomCenter:
            maxY = target.y
        case .bottomLeft:
            minX = target.x
            maxY = target.y
        case .middleLeft:
            minX = target.x
        case .startPoint, .endPoint:
            break
        }

        let newX = min(minX, maxX)
        let newY = min(minY, maxY)
        var newW = max(1.0, abs(maxX - minX))
        var newH = max(1.0, abs(maxY - minY))

        if shiftConstrained || tool == .ellipse {
            let side = max(newW, newH)
            newW = side
            newH = side
        }

        let oldBounds = bounds
        bounds = CGRect(x: newX, y: newY, width: newW, height: newH)

        if !points.isEmpty && oldBounds.width > 0 && oldBounds.height > 0 {
            let scaleX = newW / oldBounds.width
            let scaleY = newH / oldBounds.height
            points = points.map { pt in
                let relX = (pt.x - oldBounds.minX) * scaleX
                let relY = (pt.y - oldBounds.minY) * scaleY
                return CGPoint(x: newX + relX, y: newY + relY)
            }
        }
    }
}

// MARK: - AnnotationAction

/// Command action tracking mutations on vector objects for lossless undo and redo.
public enum AnnotationAction: Equatable {
    case create(AnnotationObject)
    case delete(AnnotationObject, index: Int)
    case move(id: UUID, delta: CGPoint)
    case resize(id: UUID, oldBounds: CGRect, newBounds: CGRect, oldPoints: [CGPoint], newPoints: [CGPoint])
    case recolor(id: UUID, oldHex: String, newHex: String)
    case updateStrokeWidth(id: UUID, oldWidth: CGFloat, newWidth: CGFloat)
    case updateFontSize(id: UUID, oldSize: CGFloat, newSize: CGFloat)
    case editText(id: UUID, oldText: String, newText: String, oldBounds: CGRect, newBounds: CGRect)
    case batch([AnnotationAction])

    /// Inverts the command action, producing an exact symmetrical inverse action.
    public func inverted() -> AnnotationAction {
        switch self {
        case .create(let object):
            return .delete(object, index: -1)
        case .delete(let object, _):
            return .create(object)
        case .move(let id, let delta):
            return .move(id: id, delta: CGPoint(x: -delta.x, y: -delta.y))
        case .resize(let id, let oldBounds, let newBounds, let oldPoints, let newPoints):
            return .resize(id: id, oldBounds: newBounds, newBounds: oldBounds, oldPoints: newPoints, newPoints: oldPoints)
        case .recolor(let id, let oldHex, let newHex):
            return .recolor(id: id, oldHex: newHex, newHex: oldHex)
        case .updateStrokeWidth(let id, let oldWidth, let newWidth):
            return .updateStrokeWidth(id: id, oldWidth: newWidth, newWidth: oldWidth)
        case .updateFontSize(let id, let oldSize, let newSize):
            return .updateFontSize(id: id, oldSize: newSize, newSize: oldSize)
        case .editText(let id, let oldText, let newText, let oldBounds, let newBounds):
            return .editText(id: id, oldText: newText, newText: oldText, oldBounds: newBounds, newBounds: oldBounds)
        case .batch(let actions):
            return .batch(actions.reversed().map { $0.inverted() })
        }
    }
}
