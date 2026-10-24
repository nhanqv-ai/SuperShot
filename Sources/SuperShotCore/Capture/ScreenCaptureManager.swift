import Foundation
import CoreGraphics
import AppKit

// MARK: - Capture Display Info

public struct CaptureDisplayInfo: Equatable, Sendable {
    public let displayID: CGDirectDisplayID
    public let name: String
    public let cocoaFrame: CGRect       // Bottom-left origin (points)
    public let cgBounds: CGRect         // Top-left origin (points)
    public let scaleFactor: CGFloat     // 1.0 or 2.0
    public let isMain: Bool
    public let pixelSize: CGSize        // Physical pixels (e.g. 2880 x 1800)

    public init(
        displayID: CGDirectDisplayID,
        name: String = "Display",
        cocoaFrame: CGRect,
        cgBounds: CGRect,
        scaleFactor: CGFloat,
        isMain: Bool,
        pixelSize: CGSize
    ) {
        self.displayID = displayID
        self.name = name
        self.cocoaFrame = cocoaFrame
        self.cgBounds = cgBounds
        self.scaleFactor = scaleFactor
        self.isMain = isMain
        self.pixelSize = pixelSize
    }
}

// MARK: - Captured Screen

public struct CapturedScreen: Sendable {
    public let displayInfo: CaptureDisplayInfo
    public let fullImage: CGImage
    public let timestamp: Date

    public init(displayInfo: CaptureDisplayInfo, fullImage: CGImage, timestamp: Date = Date()) {
        self.displayInfo = displayInfo
        self.fullImage = fullImage
        self.timestamp = timestamp
    }
}

// MARK: - ScreenCaptureProviding Protocol

public protocol ScreenCaptureProviding: AnyObject, Sendable {
    func availableDisplays() -> [CaptureDisplayInfo]
    func captureDisplayImage(displayID: CGDirectDisplayID) -> CGImage?
    func display(containing point: CGPoint) -> CaptureDisplayInfo?
}

// MARK: - Native Screen Capture Provider

public final class NativeScreenCaptureProvider: ScreenCaptureProviding, @unchecked Sendable {
    public init() {}

    public func availableDisplays() -> [CaptureDisplayInfo] {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            let mainID = CGMainDisplayID()
            let bounds = CGDisplayBounds(mainID)
            let mode = CGDisplayCopyDisplayMode(mainID)
            let scale: CGFloat = mode.map { CGFloat($0.pixelWidth) / bounds.width } ?? 2.0
            return [
                CaptureDisplayInfo(
                    displayID: mainID,
                    name: "Main Display",
                    cocoaFrame: bounds,
                    cgBounds: bounds,
                    scaleFactor: scale,
                    isMain: true,
                    pixelSize: CGSize(width: bounds.width * scale, height: bounds.height * scale)
                )
            ]
        }

        return screens.enumerated().map { index, screen in
            let screenNumberKey = NSDeviceDescriptionKey(rawValue: "NSScreenNumber")
            let displayID = (screen.deviceDescription[screenNumberKey] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
            let cgBounds = CGDisplayBounds(displayID)
            let scale = screen.backingScaleFactor
            let pixelWidth = screen.frame.width * scale
            let pixelHeight = screen.frame.height * scale

            return CaptureDisplayInfo(
                displayID: displayID,
                name: screen.localizedName,
                cocoaFrame: screen.frame,
                cgBounds: cgBounds,
                scaleFactor: scale,
                isMain: index == 0,
                pixelSize: CGSize(width: pixelWidth, height: pixelHeight)
            )
        }
    }

    public func captureDisplayImage(displayID: CGDirectDisplayID) -> CGImage? {
        return CGDisplayCreateImage(displayID)
    }

    public func display(containing point: CGPoint) -> CaptureDisplayInfo? {
        let displays = availableDisplays()
        if let match = displays.first(where: { $0.cocoaFrame.contains(point) }) {
            return match
        }
        if let match = displays.first(where: { $0.cgBounds.contains(point) }) {
            return match
        }
        return displays.first(where: { $0.isMain }) ?? displays.first
    }
}

// MARK: - Mock Screen Capture Provider

public final class MockScreenCaptureProvider: ScreenCaptureProviding, @unchecked Sendable {
    public var mockDisplays: [CaptureDisplayInfo]
    public var syntheticImageCache: [CGDirectDisplayID: CGImage] = [:]

    public init(displays: [CaptureDisplayInfo]? = nil) {
        if let displays = displays {
            self.mockDisplays = displays
        } else {
            let mainDisplay = CaptureDisplayInfo(
                displayID: 1,
                name: "Built-in Retina Display",
                cocoaFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                cgBounds: CGRect(x: 0, y: 0, width: 1440, height: 900),
                scaleFactor: 2.0,
                isMain: true,
                pixelSize: CGSize(width: 2880, height: 1800)
            )
            let secondaryDisplay = CaptureDisplayInfo(
                displayID: 2,
                name: "External 4K Display",
                cocoaFrame: CGRect(x: 1440, y: -180, width: 1920, height: 1080),
                cgBounds: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
                scaleFactor: 1.0,
                isMain: false,
                pixelSize: CGSize(width: 1920, height: 1080)
            )
            self.mockDisplays = [mainDisplay, secondaryDisplay]
        }
    }

    public func availableDisplays() -> [CaptureDisplayInfo] {
        return mockDisplays
    }

    public func captureDisplayImage(displayID: CGDirectDisplayID) -> CGImage? {
        if let cached = syntheticImageCache[displayID] {
            return cached
        }
        guard let display = mockDisplays.first(where: { $0.displayID == displayID }) else {
            return nil
        }
        let image = Self.createSyntheticImage(size: display.pixelSize, colorHex: "#1E1E1E")
        if let img = image {
            syntheticImageCache[displayID] = img
        }
        return image
    }

    public func display(containing point: CGPoint) -> CaptureDisplayInfo? {
        if let match = mockDisplays.first(where: { $0.cocoaFrame.contains(point) }) {
            return match
        }
        return mockDisplays.first(where: { $0.isMain }) ?? mockDisplays.first
    }

    public static func createSyntheticImage(size: CGSize, colorHex: String = "#1E1E1E") -> CGImage? {
        let width = max(1, Int(size.width))
        let height = max(1, Int(size.height))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }

        context.setFillColor(CGColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        context.setStrokeColor(CGColor(red: 0.25, green: 0.25, blue: 0.28, alpha: 1.0))
        context.setLineWidth(1.0)
        let step = 100
        for x in stride(from: 0, to: width, by: step) {
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: height))
        }
        for y in stride(from: 0, to: height, by: step) {
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: width, y: y))
        }
        context.strokePath()

        return context.makeImage()
    }
}

// MARK: - ScreenCaptureManager

public final class ScreenCaptureManager: @unchecked Sendable {
    public static let shared = ScreenCaptureManager()

    private let providerLock = NSLock()
    private var _provider: ScreenCaptureProviding

    public var provider: ScreenCaptureProviding {
        get {
            providerLock.lock()
            defer { providerLock.unlock() }
            return _provider
        }
        set {
            providerLock.lock()
            defer { providerLock.unlock() }
            _provider = newValue
        }
    }

    public init(provider: ScreenCaptureProviding? = nil) {
        if let provider = provider {
            self._provider = provider
        } else if ProcessInfo.processInfo.environment["SUPER_SHOT_HEADLESS"] != nil {
            self._provider = MockScreenCaptureProvider()
        } else {
            self._provider = NativeScreenCaptureProvider()
        }
    }

    public func captureScreen(at point: CGPoint) -> CapturedScreen? {
        guard let display = provider.display(containing: point) else { return nil }
        guard let fullImage = provider.captureDisplayImage(displayID: display.displayID) else { return nil }
        return CapturedScreen(displayInfo: display, fullImage: fullImage)
    }

    public func captureMainScreen() -> CapturedScreen? {
        let displays = provider.availableDisplays()
        guard let mainDisplay = displays.first(where: { $0.isMain }) ?? displays.first else { return nil }
        guard let fullImage = provider.captureDisplayImage(displayID: mainDisplay.displayID) else { return nil }
        return CapturedScreen(displayInfo: mainDisplay, fullImage: fullImage)
    }

    public static func cropImage(
        _ fullImage: CGImage,
        selectionInWindow: CGRect,
        windowSize: CGSize,
        scaleFactor: CGFloat
    ) -> CGImage? {
        guard !selectionInWindow.isEmpty else { return nil }

        let normalizedSelection = CGRect(
            x: max(0, min(selectionInWindow.origin.x, windowSize.width)),
            y: max(0, min(selectionInWindow.origin.y, windowSize.height)),
            width: max(1, min(selectionInWindow.width, windowSize.width - selectionInWindow.origin.x)),
            height: max(1, min(selectionInWindow.height, windowSize.height - selectionInWindow.origin.y))
        )

        let pixelX = round(normalizedSelection.origin.x * scaleFactor)
        let pixelY = round((windowSize.height - (normalizedSelection.origin.y + normalizedSelection.height)) * scaleFactor)
        let pixelW = round(normalizedSelection.width * scaleFactor)
        let pixelH = round(normalizedSelection.height * scaleFactor)

        let cropRect = CGRect(x: pixelX, y: pixelY, width: pixelW, height: pixelH)
        return fullImage.cropping(to: cropRect)
    }
}

// MARK: - Selection Handles & Geometry

public enum SelectionHandle: String, CaseIterable, Sendable {
    case topLeft
    case topCenter
    case topRight
    case middleLeft
    case middleRight
    case bottomLeft
    case bottomCenter
    case bottomRight

    public var cursor: NSCursor {
        switch self {
        case .topLeft, .bottomRight:
            return CursorProvider.diagonalNWSE
        case .topRight, .bottomLeft:
            return CursorProvider.diagonalNESW
        case .topCenter, .bottomCenter:
            return NSCursor.resizeUpDown
        case .middleLeft, .middleRight:
            return NSCursor.resizeLeftRight
        }
    }
}

public struct SelectionBoxGeometry {
    public static let handleRadius: CGFloat = 4.5
    public static let handleHitRadius: CGFloat = 9.0

    public static func handlePositions(for rect: CGRect) -> [SelectionHandle: CGPoint] {
        return [
            .topLeft: CGPoint(x: rect.minX, y: rect.maxY),
            .topCenter: CGPoint(x: rect.midX, y: rect.maxY),
            .topRight: CGPoint(x: rect.maxX, y: rect.maxY),
            .middleLeft: CGPoint(x: rect.minX, y: rect.midY),
            .middleRight: CGPoint(x: rect.maxX, y: rect.midY),
            .bottomLeft: CGPoint(x: rect.minX, y: rect.minY),
            .bottomCenter: CGPoint(x: rect.midX, y: rect.minY),
            .bottomRight: CGPoint(x: rect.maxX, y: rect.minY)
        ]
    }

    public static func hitTestHandle(point: CGPoint, in rect: CGRect, hitRadius: CGFloat = handleHitRadius) -> SelectionHandle? {
        guard !rect.isEmpty else { return nil }
        let positions = handlePositions(for: rect)

        let priorityOrder: [SelectionHandle] = [
            .topLeft, .topRight, .bottomLeft, .bottomRight,
            .topCenter, .bottomCenter, .middleLeft, .middleRight
        ]

        for handle in priorityOrder {
            if let pos = positions[handle] {
                let dist = hypot(point.x - pos.x, point.y - pos.y)
                if dist <= hitRadius {
                    return handle
                }
            }
        }
        return nil
    }

    public static func normalizeRect(p1: CGPoint, p2: CGPoint, bounds: CGRect? = nil) -> CGRect {
        var x1 = min(p1.x, p2.x)
        var y1 = min(p1.y, p2.y)
        var x2 = max(p1.x, p2.x)
        var y2 = max(p1.y, p2.y)

        if let b = bounds {
            x1 = max(b.minX, min(x1, b.maxX))
            y1 = max(b.minY, min(y1, b.maxY))
            x2 = max(b.minX, min(x2, b.maxX))
            y2 = max(b.minY, min(y2, b.maxY))
        }

        let width = max(1.0, x2 - x1)
        let height = max(1.0, y2 - y1)
        return CGRect(x: x1, y: y1, width: width, height: height)
    }

    public static func calculateCenterRect(
        center: CGPoint,
        target: CGPoint,
        bounds: CGRect? = nil,
        squareConstrained: Bool = false
    ) -> CGRect {
        let dx = abs(target.x - center.x)
        let dy = abs(target.y - center.y)
        let halfWidth: CGFloat
        let halfHeight: CGFloat

        if squareConstrained {
            let side = max(dx, dy)
            halfWidth = side
            halfHeight = side
        } else {
            halfWidth = dx
            halfHeight = dy
        }

        let p1 = CGPoint(x: center.x - halfWidth, y: center.y - halfHeight)
        let p2 = CGPoint(x: center.x + halfWidth, y: center.y + halfHeight)
        return normalizeRect(p1: p1, p2: p2, bounds: bounds)
    }

    public static func anchorPoint(for handle: SelectionHandle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: return CGPoint(x: rect.maxX, y: rect.minY)
        case .topCenter: return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.minX, y: rect.minY)
        case .middleLeft: return CGPoint(x: rect.maxX, y: rect.midY)
        case .middleRight: return CGPoint(x: rect.minX, y: rect.midY)
        case .bottomLeft: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottomCenter: return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.minX, y: rect.maxY)
        }
    }

    public static func calculateResizedRect(
        handle: SelectionHandle,
        currentPoint: CGPoint,
        anchor: CGPoint,
        bounds: CGRect,
        currentRect: CGRect = .zero,
        shiftKeyPressed: Bool = false,
        optionKeyPressed: Bool = false
    ) -> CGRect {
        var p = currentPoint
        p.x = max(bounds.minX, min(p.x, bounds.maxX))
        p.y = max(bounds.minY, min(p.y, bounds.maxY))

        if optionKeyPressed {
            let center = currentRect.isEmpty ? anchor : CGPoint(x: currentRect.midX, y: currentRect.midY)
            switch handle {
            case .topLeft, .topRight, .bottomLeft, .bottomRight:
                return calculateCenterRect(
                    center: center,
                    target: p,
                    bounds: bounds,
                    squareConstrained: shiftKeyPressed
                )
            case .topCenter, .bottomCenter:
                let dy = abs(p.y - center.y)
                if shiftKeyPressed {
                    return calculateCenterRect(
                        center: center,
                        target: CGPoint(x: center.x + dy, y: p.y),
                        bounds: bounds,
                        squareConstrained: true
                    )
                } else {
                    let halfW = currentRect.isEmpty ? 0 : currentRect.width / 2.0
                    let p1 = CGPoint(x: center.x - halfW, y: center.y - dy)
                    let p2 = CGPoint(x: center.x + halfW, y: center.y + dy)
                    return normalizeRect(p1: p1, p2: p2, bounds: bounds)
                }
            case .middleLeft, .middleRight:
                let dx = abs(p.x - center.x)
                if shiftKeyPressed {
                    return calculateCenterRect(
                        center: center,
                        target: CGPoint(x: p.x, y: center.y + dx),
                        bounds: bounds,
                        squareConstrained: true
                    )
                } else {
                    let halfH = currentRect.isEmpty ? 0 : currentRect.height / 2.0
                    let p1 = CGPoint(x: center.x - dx, y: center.y - halfH)
                    let p2 = CGPoint(x: center.x + dx, y: center.y + halfH)
                    return normalizeRect(p1: p1, p2: p2, bounds: bounds)
                }
            }
        }

        switch handle {
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            if shiftKeyPressed {
                let dx = p.x - anchor.x
                let dy = p.y - anchor.y
                let side = max(abs(dx), abs(dy))
                let squarePoint = CGPoint(
                    x: anchor.x + (dx >= 0 ? side : -side),
                    y: anchor.y + (dy >= 0 ? side : -side)
                )
                return normalizeRect(p1: anchor, p2: squarePoint, bounds: bounds)
            }
            return normalizeRect(p1: anchor, p2: p, bounds: bounds)
        case .topCenter, .bottomCenter:
            let y1 = min(anchor.y, p.y)
            let y2 = max(anchor.y, p.y)
            let h = max(1.0, y2 - y1)
            let x = currentRect.isEmpty ? anchor.x : currentRect.origin.x
            let w = currentRect.isEmpty ? 0 : currentRect.width
            return CGRect(x: x, y: y1, width: w, height: h)
        case .middleLeft, .middleRight:
            let x1 = min(anchor.x, p.x)
            let x2 = max(anchor.x, p.x)
            let w = max(1.0, x2 - x1)
            let y = currentRect.isEmpty ? anchor.y : currentRect.origin.y
            let h = currentRect.isEmpty ? 0 : currentRect.height
            return CGRect(x: x1, y: y, width: w, height: h)
        }
    }

    public static func detectAspectRatio(width: CGFloat, height: CGFloat) -> String? {
        guard width > 10, height > 10 else { return nil }
        let ratio = width / height
        let tolerance: CGFloat = 0.025
        let standardRatios: [(name: String, value: CGFloat)] = [
            ("1:1", 1.0),
            ("16:9", 16.0 / 9.0),
            ("4:3", 4.0 / 3.0),
            ("16:10", 16.0 / 10.0),
            ("3:2", 3.0 / 2.0),
            ("21:9", 21.0 / 9.0),
            ("9:16", 9.0 / 16.0),
            ("3:4", 3.0 / 4.0),
            ("2:3", 2.0 / 3.0)
        ]
        for (name, val) in standardRatios {
            if abs(ratio - val) / val <= tolerance { return name }
        }
        return nil
    }

    public static func formatDimensionBadge(
        width: CGFloat,
        height: CGFloat,
        scaleFactor: CGFloat,
        includeAspectRatio: Bool = false
    ) -> String {
        let wPx = Int(round(max(1.0, width) * scaleFactor))
        let hPx = Int(round(max(1.0, height) * scaleFactor))
        if includeAspectRatio, let aspect = detectAspectRatio(width: width, height: height) {
            return "\(wPx) x \(hPx) px (\(aspect))"
        }
        return "\(wPx) x \(hPx) px"
    }
}

// MARK: - Toolbar Position Calculator

public struct ToolbarPositionCalculator {
    public static let verticalToolbarSize = CGSize(width: 36, height: 320)
    public static let horizontalToolbarSize = CGSize(width: 220, height: 36)
    public static let badgeSize = CGSize(width: 96, height: 22)
    public static let spacing: CGFloat = 8.0
    public static let margin: CGFloat = 8.0

    public static func calculateDimensionBadgeFrame(
        selectionRect: CGRect,
        screenBounds: CGRect,
        badgeSize: CGSize = badgeSize
    ) -> CGRect {
        var originX = selectionRect.minX
        var originY = selectionRect.maxY + 6.0

        // When horizontal toolbar flips above selectionRect.maxY in bottom-screen selections,
        // position the dimension badge above horizontalToolbar.maxY + 6pt to prevent overlap
        let horizFlipped = (selectionRect.minY - spacing - horizontalToolbarSize.height < screenBounds.minY + margin)
        if horizFlipped {
            let horizFrame = calculateHorizontalToolbarFrame(selectionRect: selectionRect, screenBounds: screenBounds)
            if horizFrame.minY >= selectionRect.maxY {
                originY = horizFrame.maxY + 6.0
            }
        }

        if originY + badgeSize.height > screenBounds.maxY - margin {
            originY = selectionRect.maxY - badgeSize.height - 6.0
            if originY < selectionRect.minY {
                originY = selectionRect.minY - badgeSize.height - 6.0
            }
        }

        if originX + badgeSize.width > screenBounds.maxX - margin {
            originX = screenBounds.maxX - badgeSize.width - margin
        }
        if originX < screenBounds.minX + margin {
            originX = screenBounds.minX + margin
        }

        if originY < screenBounds.minY + margin {
            originY = screenBounds.minY + margin
        }
        if originY + badgeSize.height > screenBounds.maxY - margin {
            originY = screenBounds.maxY - badgeSize.height - margin
        }

        return CGRect(origin: CGPoint(x: originX, y: originY), size: badgeSize)
    }

    public static func calculateVerticalToolbarFrame(
        selectionRect: CGRect,
        screenBounds: CGRect,
        toolbarSize: CGSize = verticalToolbarSize
    ) -> CGRect {
        var originX = selectionRect.maxX + spacing
        var originY = selectionRect.maxY - toolbarSize.height

        if originX + toolbarSize.width > screenBounds.maxX - margin {
            originX = selectionRect.minX - spacing - toolbarSize.width
        }

        if originX < screenBounds.minX + margin {
            originX = screenBounds.minX + margin
        }
        if originX + toolbarSize.width > screenBounds.maxX - margin {
            originX = screenBounds.maxX - toolbarSize.width - margin
        }

        if originY < screenBounds.minY + margin {
            originY = screenBounds.minY + margin
        }
        if originY + toolbarSize.height > screenBounds.maxY - margin {
            originY = screenBounds.maxY - toolbarSize.height - margin
        }

        return CGRect(origin: CGPoint(x: originX, y: originY), size: toolbarSize)
    }

    public static func calculateHorizontalToolbarFrame(
        selectionRect: CGRect,
        screenBounds: CGRect,
        toolbarSize: CGSize = horizontalToolbarSize
    ) -> CGRect {
        var originX = selectionRect.maxX - toolbarSize.width
        var originY = selectionRect.minY - spacing - toolbarSize.height

        if originY < screenBounds.minY + margin {
            originY = selectionRect.maxY + spacing
        }

        if originY + toolbarSize.height > screenBounds.maxY - margin {
            originY = screenBounds.maxY - toolbarSize.height - margin
        }
        if originY < screenBounds.minY + margin {
            originY = screenBounds.minY + margin
        }

        if originX < screenBounds.minX + margin {
            originX = screenBounds.minX + margin
        }
        if originX + toolbarSize.width > screenBounds.maxX - margin {
            originX = screenBounds.maxX - toolbarSize.width - margin
        }

        return CGRect(origin: CGPoint(x: originX, y: originY), size: toolbarSize)
    }

    public static func resolveToolbarFrames(
        selectionRect: CGRect,
        screenBounds: CGRect,
        vertSize: CGSize = verticalToolbarSize,
        horizSize: CGSize = horizontalToolbarSize
    ) -> (vertical: CGRect, horizontal: CGRect) {
        var vert = calculateVerticalToolbarFrame(selectionRect: selectionRect, screenBounds: screenBounds, toolbarSize: vertSize)
        var horiz = calculateHorizontalToolbarFrame(selectionRect: selectionRect, screenBounds: screenBounds, toolbarSize: horizSize)

        if vert.intersects(horiz) {
            let shiftedLeftX = vert.minX - spacing - horizSize.width
            let shiftedRightX = vert.maxX + spacing
            let shiftedBelowY = vert.minY - spacing - horizSize.height
            let shiftedAboveY = vert.maxY + spacing

            if shiftedLeftX >= screenBounds.minX + margin {
                horiz.origin.x = shiftedLeftX
            } else if shiftedRightX + horizSize.width <= screenBounds.maxX - margin {
                horiz.origin.x = shiftedRightX
            } else if shiftedBelowY >= screenBounds.minY + margin {
                horiz.origin.y = shiftedBelowY
            } else if shiftedAboveY + horizSize.height <= screenBounds.maxY - margin {
                horiz.origin.y = shiftedAboveY
            } else {
                if vert.minX - screenBounds.minX >= screenBounds.maxX - vert.maxX {
                    horiz.origin.x = max(screenBounds.minX + margin, vert.minX - spacing - horizSize.width)
                } else {
                    horiz.origin.x = min(screenBounds.maxX - margin - horizSize.width, vert.maxX + spacing)
                }
            }

            horiz.origin.x = max(screenBounds.minX + margin, min(horiz.origin.x, screenBounds.maxX - margin - horizSize.width))
            horiz.origin.y = max(screenBounds.minY + margin, min(horiz.origin.y, screenBounds.maxY - margin - horizSize.height))
            vert.origin.x = max(screenBounds.minX + margin, min(vert.origin.x, screenBounds.maxX - margin - vertSize.width))
            vert.origin.y = max(screenBounds.minY + margin, min(vert.origin.y, screenBounds.maxY - margin - vertSize.height))
        }

        return (vertical: vert, horizontal: horiz)
    }
}
