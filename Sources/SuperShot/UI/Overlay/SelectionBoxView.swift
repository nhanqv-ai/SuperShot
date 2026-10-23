import Foundation
import AppKit
import SuperShotCore

public enum DragMode: Equatable {
    case none
    case creating(startPoint: CGPoint)
    case moving(startPoint: CGPoint, originalRect: CGRect)
    case resizing(handle: SelectionHandle, anchorPoint: CGPoint)
}

public class CaptureOverlayContentView: NSView {
    public let capturedScreen: CapturedScreen
    public weak var windowDelegate: CaptureOverlayWindow?

    public var selectionRect: CGRect = .zero {
        didSet {
            needsDisplay = true
        }
    }

    private var dragMode: DragMode = .none

    public init(frame: NSRect, capturedScreen: CapturedScreen, windowDelegate: CaptureOverlayWindow) {
        self.capturedScreen = capturedScreen
        self.windowDelegate = windowDelegate
        super.init(frame: frame)
        self.wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

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
        } else {
            let dimPath = NSBezierPath(rect: bounds)
            dimPath.append(NSBezierPath(rect: selectionRect))
            dimPath.windingRule = .evenOdd
            dimPath.fill()

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

    public override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if let handle = SelectionBoxGeometry.hitTestHandle(point: point, in: selectionRect) {
            let anchor = SelectionBoxGeometry.anchorPoint(for: handle, in: selectionRect)
            dragMode = .resizing(handle: handle, anchorPoint: anchor)
            return
        }

        if selectionRect.contains(point) {
            dragMode = .moving(startPoint: point, originalRect: selectionRect)
            return
        }

        dragMode = .creating(startPoint: point)
        selectionRect = CGRect(origin: point, size: CGSize(width: 1, height: 1))
    }

    public override func mouseDragged(with event: NSEvent) {
        let currentPoint = convert(event.locationInWindow, from: nil)

        switch dragMode {
        case .none:
            break
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
        dragMode = .none
    }

    public override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let handle = SelectionBoxGeometry.hitTestHandle(point: point, in: selectionRect) {
            handle.cursor.set()
        } else if selectionRect.contains(point) {
            NSCursor.openHand.set()
        } else {
            NSCursor.crosshair.set()
        }
    }
}
