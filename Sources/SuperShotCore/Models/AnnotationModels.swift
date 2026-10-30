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

// MARK: - CursorProvider

/// Provides high-DPI vector resize cursors for diagonal and directional manipulation.
public enum CursorProvider {
    /// Diagonal resize cursor for North-West <-> South-East (top-left to bottom-right).
    public static let diagonalNWSE: NSCursor = makeDiagonalCursor(nwToSe: true)

    /// Diagonal resize cursor for North-East <-> South-West (top-right to bottom-left).
    public static let diagonalNESW: NSCursor = makeDiagonalCursor(nwToSe: false)

    private static func makeDiagonalCursor(nwToSe: Bool) -> NSCursor {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()
            ctx.translateBy(x: 9, y: 9)
            ctx.rotate(by: nwToSe ? -.pi / 4.0 : .pi / 4.0)

            // Draw double-headed horizontal arrow centered at origin, rotated by +/-45 deg
            let path = CGMutablePath()
            // Left arrow head + shaft + right arrow head
            path.move(to: CGPoint(x: -7.5, y: 0))
            path.addLine(to: CGPoint(x: -3.2, y: 3.6))
            path.addLine(to: CGPoint(x: -3.2, y: 1.1))
            path.addLine(to: CGPoint(x: 3.2, y: 1.1))
            path.addLine(to: CGPoint(x: 3.2, y: 3.6))
            path.addLine(to: CGPoint(x: 7.5, y: 0))
            path.addLine(to: CGPoint(x: 3.2, y: -3.6))
            path.addLine(to: CGPoint(x: 3.2, y: -1.1))
            path.addLine(to: CGPoint(x: -3.2, y: -1.1))
            path.addLine(to: CGPoint(x: -3.2, y: -3.6))
            path.closeSubpath()

            ctx.addPath(path)
            ctx.setLineWidth(2.2)
            ctx.setLineJoin(.round)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.strokePath()

            ctx.addPath(path)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()

            ctx.restoreGState()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 9, y: 9))
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

    /// Corresponding AppKit cursor for the handle resize direction (defaults to flipped top-left coordinate space).
    public var cursor: NSCursor {
        cursor(isFlipped: true)
    }

    /// Returns the directional resize cursor accounting for whether the host NSView is flipped.
    public func cursor(isFlipped: Bool) -> NSCursor {
        switch self {
        case .topLeft, .bottomRight:
            return isFlipped ? CursorProvider.diagonalNWSE : CursorProvider.diagonalNESW
        case .topRight, .bottomLeft:
            return isFlipped ? CursorProvider.diagonalNESW : CursorProvider.diagonalNWSE
        case .topCenter, .bottomCenter:
            return NSCursor.resizeUpDown
        case .middleLeft, .middleRight:
            return NSCursor.resizeLeftRight
        case .startPoint, .endPoint:
            return NSCursor.pointingHand
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

    /// Tests proximity to arrowhead wings, base segment, and interior filled triangle.
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

        // 1. Proximity to barbed wings or rear base segment
        let d1 = AnnotationObject.distanceToSegment(p: point, v: p2, w: w1)
        let d2 = AnnotationObject.distanceToSegment(p: point, v: p2, w: w2)
        let d3 = AnnotationObject.distanceToSegment(p: point, v: w1, w: w2)
        if min(d1, min(d2, d3)) <= threshold { return true }

        // 2. Point inside filled triangle (p2, w1, w2) via cross-product test
        func sign(pt: CGPoint, v1: CGPoint, v2: CGPoint) -> CGFloat {
            (pt.x - v2.x) * (v1.y - v2.y) - (v1.x - v2.x) * (pt.y - v2.y)
        }
        let s1 = sign(pt: point, v1: p2, v2: w1)
        let s2 = sign(pt: point, v1: w1, v2: w2)
        let s3 = sign(pt: point, v1: w2, v2: p2)
        let hasNeg = (s1 < 0) || (s2 < 0) || (s3 < 0)
        let hasPos = (s1 > 0) || (s2 > 0) || (s3 > 0)
        return !(hasNeg && hasPos)
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

    /// Hit-tests grab handles for this object, returning the closest handle within hitRadius.
    public func handle(at point: CGPoint, hitRadius: CGFloat = 8.0) -> AnnotationHandle? {
        let positions = handlePositions()

        // Scale down hit radius for small objects so handles don't consume the interior
        let minDimension = min(bounds.width, bounds.height)
        let effectiveRadius: CGFloat
        if tool == .line || tool == .arrow {
            if points.count >= 2 {
                let len = hypot(points[1].x - points[0].x, points[1].y - points[0].y)
                effectiveRadius = min(hitRadius, max(3.0, len / 2.0))
            } else {
                effectiveRadius = hitRadius
            }
        } else {
            effectiveRadius = minDimension > 0 ? min(hitRadius, max(3.0, minDimension / 2.5)) : hitRadius
        }

        var closestHandle: AnnotationHandle?
        var minDistance: CGFloat = .infinity

        // Deterministic nearest grab handle (minBy Euclidean distance)
        for (handle, handlePt) in positions {
            let dist = hypot(point.x - handlePt.x, point.y - handlePt.y)
            if dist <= effectiveRadius && dist < minDistance {
                minDistance = dist
                closestHandle = handle
            }
        }
        return closestHandle
    }

    // MARK: - Transformations

    /// Translates object position by delta.
    public mutating func translate(by delta: CGPoint) {
        bounds = bounds.offsetBy(dx: delta.x, dy: delta.y)
        points = points.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
    }

    /// Produces an identical clone of the vector annotation with a new UUID,
    /// translated by offset, marked as selected, and timestamped to Date().
    public func duplicated(
        id: UUID = UUID(),
        offset: CGPoint = CGPoint(x: 16, y: 16)
    ) -> AnnotationObject {
        AnnotationObject(
            id: id,
            tool: self.tool,
            points: self.points.map { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) },
            bounds: self.bounds.offsetBy(dx: offset.x, dy: offset.y),
            colorHex: self.colorHex,
            strokeWidth: self.strokeWidth,
            fontSize: self.fontSize,
            text: self.text,
            blurRadius: self.blurRadius,
            isSelected: true,
            createdAt: Date()
        )
    }

    /// Mathematical angle snapping to nearest multiple of interval (default: pi/4 = 45 degrees).
    /// Supports 0, 45, 90, 135, 180, 225, 270, 315 degrees (all 8 octants), preserving hypotenuse length.
    public static func snapAngle(from: CGPoint, to: CGPoint, interval: CGFloat = .pi / 4.0) -> CGPoint {
        guard interval > 0 else { return to }
        let dx = to.x - from.x
        let dy = to.y - from.y
        let len = hypot(dx, dy)
        guard len > 1.0 else { return to }
        let angle = atan2(dy, dx)
        let snappedAngle = round(angle / interval) * interval
        return CGPoint(x: from.x + len * cos(snappedAngle), y: from.y + len * sin(snappedAngle))
    }

    /// Resizes bounding box by dragging a specified handle to target point.
    public mutating func resize(handle: AnnotationHandle, to target: CGPoint, shiftConstrained: Bool = false) {
        if (tool == .line || tool == .arrow) && points.count >= 2 {
            if handle == .startPoint {
                points[0] = shiftConstrained ? AnnotationObject.snapAngle(from: points[1], to: target) : target
            } else if handle == .endPoint {
                points[1] = shiftConstrained ? AnnotationObject.snapAngle(from: points[0], to: target) : target
            }
            bounds = AnnotationObject.calculateBounds(from: points, strokeWidth: strokeWidth)
            return
        }

        if shiftConstrained {
            let anchor: CGPoint
            switch handle {
            case .topLeft: anchor = CGPoint(x: bounds.maxX, y: bounds.maxY)
            case .topRight: anchor = CGPoint(x: bounds.minX, y: bounds.maxY)
            case .bottomLeft: anchor = CGPoint(x: bounds.maxX, y: bounds.minY)
            case .bottomRight: anchor = CGPoint(x: bounds.minX, y: bounds.minY)
            case .topCenter: anchor = CGPoint(x: bounds.midX, y: bounds.maxY)
            case .bottomCenter: anchor = CGPoint(x: bounds.midX, y: bounds.minY)
            case .middleLeft: anchor = CGPoint(x: bounds.maxX, y: bounds.midY)
            case .middleRight: anchor = CGPoint(x: bounds.minX, y: bounds.midY)
            case .startPoint, .endPoint: anchor = .zero
            }

            let rectX: CGFloat
            let rectY: CGFloat
            let side: CGFloat

            switch handle {
            case .topCenter, .bottomCenter:
                let rawDy = target.y - anchor.y
                side = max(1.0, abs(rawDy))
                rectY = rawDy >= 0 ? anchor.y : anchor.y - side
                rectX = bounds.midX - side / 2.0
            case .middleLeft, .middleRight:
                let rawDx = target.x - anchor.x
                side = max(1.0, abs(rawDx))
                rectX = rawDx >= 0 ? anchor.x : anchor.x - side
                rectY = bounds.midY - side / 2.0
            default:
                let rawDx = target.x - anchor.x
                let rawDy = target.y - anchor.y
                side = max(1.0, max(abs(rawDx), abs(rawDy)))
                rectX = rawDx >= 0 ? anchor.x : anchor.x - side
                rectY = rawDy >= 0 ? anchor.y : anchor.y - side
            }

            let oldBounds = bounds
            bounds = CGRect(x: rectX, y: rectY, width: side, height: side)

            if !points.isEmpty && oldBounds.width > 0 && oldBounds.height > 0 {
                let scaleX = side / oldBounds.width
                let scaleY = side / oldBounds.height
                points = points.map { pt in
                    let relX = (pt.x - oldBounds.minX) * scaleX
                    let relY = (pt.y - oldBounds.minY) * scaleY
                    return CGPoint(x: rectX + relX, y: rectY + relY)
                }
            }
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

        let isFlippedX = maxX < minX
        let isFlippedY = maxY < minY
        let newX = min(minX, maxX)
        let newY = min(minY, maxY)
        let newW = max(1.0, abs(maxX - minX))
        let newH = max(1.0, abs(maxY - minY))

        let oldBounds = bounds
        bounds = CGRect(x: newX, y: newY, width: newW, height: newH)

        if !points.isEmpty {
            let origW = max(1.0, oldBounds.width)
            let origH = max(1.0, oldBounds.height)
            let scaleX = newW / origW
            let scaleY = newH / origH
            points = points.map { pt in
                let normalizedX = pt.x - oldBounds.minX
                let normalizedY = pt.y - oldBounds.minY
                let relX = (isFlippedX ? (oldBounds.width - normalizedX) : normalizedX) * scaleX
                let relY = (isFlippedY ? (oldBounds.height - normalizedY) : normalizedY) * scaleY
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
    case reorder(id: UUID, oldIndex: Int, newIndex: Int)
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
        case .reorder(let id, let oldIndex, let newIndex):
            return .reorder(id: id, oldIndex: newIndex, newIndex: oldIndex)
        case .batch(let actions):
            return .batch(actions.reversed().map { $0.inverted() })
        }
    }
}
