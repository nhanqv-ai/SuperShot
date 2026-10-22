import AppKit
import Foundation

// MARK: - SuperShot App Icon Generator
// Generates a vibrant, multi-resolution macOS AppIcon (.icns) conforming to macOS design standards.
// Features a dynamic Emerald Cyan -> Royal Indigo -> Violet gradient, glassmorphic depth,
// camera aperture lens, and crisp screenshot crop corners.
// Strictly 0 emojis permitted. SF Symbols compliant.

struct IconGenerator {
    let outputURL: URL

    static let iconSpecs: [(name: String, pixelSize: Int)] = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024)
    ]

    func generate() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SuperShot_\(UUID().uuidString).iconset")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        print("Generating iconset bitmaps in \(tempDir.path)...")
        for spec in Self.iconSpecs {
            guard let pngData = renderIcon(pixelSize: spec.pixelSize) else {
                throw NSError(
                    domain: "IconGenerator",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to render \(spec.name)"]
                )
            }
            let fileURL = tempDir.appendingPathComponent(spec.name)
            try pngData.write(to: fileURL)
            print("  Created \(spec.name) (\(spec.pixelSize)x\(spec.pixelSize)px)")

            if spec.name == "icon_512x512.png" {
                let assetsURL = URL(fileURLWithPath: "Assets/AppIcon.png")
                try? FileManager.default.createDirectory(at: assetsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? pngData.write(to: assetsURL)
                print("  Exported standalone asset: \(assetsURL.path)")
            }
        }

        let outputParent = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: outputParent, withIntermediateDirectories: true)

        print("Compiling iconset to ICNS: \(outputURL.path)...")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", "-o", outputURL.path, tempDir.path]

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw NSError(
                domain: "IconGenerator",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "iconutil failed with code \(process.terminationStatus): \(errorString)"]
            )
        }

        print("Successfully generated icon: \(outputURL.path)")
    }

    private func renderIcon(pixelSize: Int) -> Data? {
        let size = NSSize(width: pixelSize, height: pixelSize)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        NSGraphicsContext.current = context

        let fullRect = NSRect(origin: .zero, size: size)
        NSColor.clear.setFill()
        fullRect.fill()

        let margin = CGFloat(pixelSize) * 0.082
        let iconRect = fullRect.insetBy(dx: margin, dy: margin)
        let cornerRadius = iconRect.width * 0.224

        if pixelSize >= 32 {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(calibratedRed: 0.06, green: 0.10, blue: 0.30, alpha: 0.38)
            shadow.shadowBlurRadius = CGFloat(pixelSize) * 0.06
            shadow.shadowOffset = NSSize(width: 0, height: -CGFloat(pixelSize) * 0.025)
            shadow.set()

            let shadowPath = NSBezierPath(roundedRect: iconRect, xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor(calibratedRed: 0.08, green: 0.18, blue: 0.45, alpha: 0.2).setFill()
            shadowPath.fill()
            NSShadow().set()
        }

        let baseClipPath = NSBezierPath(roundedRect: iconRect, xRadius: cornerRadius, yRadius: cornerRadius)

        NSGraphicsContext.saveGraphicsState()
        baseClipPath.addClip()

        let backgroundGradient = NSGradient(
            colors: [
                NSColor(calibratedRed: 0.04, green: 0.84, blue: 0.96, alpha: 1.0),
                NSColor(calibratedRed: 0.16, green: 0.42, blue: 0.96, alpha: 1.0),
                NSColor(calibratedRed: 0.50, green: 0.20, blue: 0.90, alpha: 1.0),
                NSColor(calibratedRed: 0.30, green: 0.10, blue: 0.60, alpha: 1.0)
            ],
            atLocations: [0.0, 0.38, 0.78, 1.0],
            colorSpace: .deviceRGB
        )
        backgroundGradient?.draw(in: iconRect, angle: -45.0)

        let sheenCenter = NSPoint(x: iconRect.midX, y: iconRect.maxY)
        let sheenGradient = NSGradient(
            colors: [
                NSColor(white: 1.0, alpha: 0.32),
                NSColor(white: 1.0, alpha: 0.08),
                NSColor(white: 1.0, alpha: 0.0)
            ],
            atLocations: [0.0, 0.45, 1.0],
            colorSpace: .deviceRGB
        )
        sheenGradient?.draw(
            fromCenter: sheenCenter,
            radius: 0.0,
            toCenter: sheenCenter,
            radius: iconRect.width * 0.75,
            options: []
        )

        NSGraphicsContext.restoreGraphicsState()

        let rimPath = NSBezierPath(
            roundedRect: iconRect.insetBy(dx: 0.75, dy: 0.75),
            xRadius: cornerRadius - 0.75,
            yRadius: cornerRadius - 0.75
        )
        rimPath.lineWidth = max(1.0, CGFloat(pixelSize) * 0.012)
        NSColor(white: 1.0, alpha: 0.35).setStroke()
        rimPath.stroke()

        drawScreenshotViewfinderGraphic(in: iconRect, pixelSize: pixelSize)

        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    private func drawScreenshotViewfinderGraphic(in rect: NSRect, pixelSize: Int) {
        let frameSize = rect.width * 0.62
        let frameRect = NSRect(
            x: rect.midX - frameSize / 2.0,
            y: rect.midY - frameSize / 2.0,
            width: frameSize,
            height: frameSize
        )

        // Inner frosted card representing captured region
        let cardInset = frameSize * 0.08
        let cardRect = frameRect.insetBy(dx: cardInset, dy: cardInset)
        let cardRadius = cardRect.width * 0.16
        let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: cardRadius, yRadius: cardRadius)

        if pixelSize >= 32 {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(calibratedRed: 0.03, green: 0.05, blue: 0.20, alpha: 0.40)
            shadow.shadowBlurRadius = CGFloat(pixelSize) * 0.045
            shadow.shadowOffset = NSSize(width: 0, height: -CGFloat(pixelSize) * 0.018)
            shadow.set()
        }

        let cardGradient = NSGradient(
            colors: [
                NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.30, alpha: 0.94),
                NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.20, alpha: 0.96)
            ],
            atLocations: [0.0, 1.0],
            colorSpace: .deviceRGB
        )
        cardGradient?.draw(in: cardPath, angle: -90.0)
        NSShadow().set()

        // Aperture / Lens ring inside card
        let lensRadius = cardRect.width * 0.28
        let lensRect = NSRect(
            x: cardRect.midX - lensRadius,
            y: cardRect.midY - lensRadius,
            width: lensRadius * 2.0,
            height: lensRadius * 2.0
        )
        let lensPath = NSBezierPath(ovalIn: lensRect)
        let lensGradient = NSGradient(
            colors: [
                NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.15, alpha: 1.0),
                NSColor(calibratedRed: 1.0, green: 0.48, blue: 0.05, alpha: 1.0),
                NSColor(calibratedRed: 0.94, green: 0.22, blue: 0.38, alpha: 1.0)
            ],
            atLocations: [0.0, 0.5, 1.0],
            colorSpace: .deviceRGB
        )
        lensGradient?.draw(in: lensPath, angle: -65.0)

        let innerLensRect = lensRect.insetBy(dx: lensRadius * 0.36, dy: lensRadius * 0.36)
        let innerLensPath = NSBezierPath(ovalIn: innerLensRect)
        NSColor(calibratedRed: 0.09, green: 0.12, blue: 0.24, alpha: 0.95).setFill()
        innerLensPath.fill()

        let glintSize = lensRadius * 0.26
        let glintRect = NSRect(
            x: innerLensRect.midX - glintSize * 0.85,
            y: innerLensRect.midY + glintSize * 0.15,
            width: glintSize,
            height: glintSize
        )
        NSColor(white: 1.0, alpha: 0.88).setFill()
        NSBezierPath(ovalIn: glintRect).fill()

        // 4 Crisp White Viewfinder Crop Brackets around the frame
        let bracketLen = frameSize * 0.24
        let strokeW = max(1.5, CGFloat(pixelSize) * 0.036)
        let cornerR = frameSize * 0.08
        let bracketPath = NSBezierPath()
        bracketPath.lineWidth = strokeW
        bracketPath.lineCapStyle = .round
        bracketPath.lineJoinStyle = .round

        let minX = frameRect.minX
        let maxX = frameRect.maxX
        let minY = frameRect.minY
        let maxY = frameRect.maxY

        // Top-Left
        bracketPath.move(to: NSPoint(x: minX, y: maxY - bracketLen))
        bracketPath.line(to: NSPoint(x: minX, y: maxY - cornerR))
        bracketPath.curve(to: NSPoint(x: minX + cornerR, y: maxY),
                          controlPoint1: NSPoint(x: minX, y: maxY),
                          controlPoint2: NSPoint(x: minX, y: maxY))
        bracketPath.line(to: NSPoint(x: minX + bracketLen, y: maxY))

        // Top-Right
        bracketPath.move(to: NSPoint(x: maxX - bracketLen, y: maxY))
        bracketPath.line(to: NSPoint(x: maxX - cornerR, y: maxY))
        bracketPath.curve(to: NSPoint(x: maxX, y: maxY - cornerR),
                          controlPoint1: NSPoint(x: maxX, y: maxY),
                          controlPoint2: NSPoint(x: maxX, y: maxY))
        bracketPath.line(to: NSPoint(x: maxX, y: maxY - bracketLen))

        // Bottom-Left
        bracketPath.move(to: NSPoint(x: minX, y: minY + bracketLen))
        bracketPath.line(to: NSPoint(x: minX, y: minY + cornerR))
        bracketPath.curve(to: NSPoint(x: minX + cornerR, y: minY),
                          controlPoint1: NSPoint(x: minX, y: minY),
                          controlPoint2: NSPoint(x: minX, y: minY))
        bracketPath.line(to: NSPoint(x: minX + bracketLen, y: minY))

        // Bottom-Right
        bracketPath.move(to: NSPoint(x: maxX - bracketLen, y: minY))
        bracketPath.line(to: NSPoint(x: maxX - cornerR, y: minY))
        bracketPath.curve(to: NSPoint(x: maxX, y: minY + cornerR),
                          controlPoint1: NSPoint(x: maxX, y: minY),
                          controlPoint2: NSPoint(x: maxX, y: minY))
        bracketPath.line(to: NSPoint(x: maxX, y: minY + bracketLen))

        NSColor.white.setStroke()
        bracketPath.stroke()
    }
}

let arguments = CommandLine.arguments
let destinationPath: String
if arguments.count > 1 {
    destinationPath = arguments[1]
} else {
    destinationPath = ".build/Resources/AppIcon.icns"
}

let generator = IconGenerator(outputURL: URL(fileURLWithPath: destinationPath))
do {
    try generator.generate()
    print("AppIcon generation completed successfully.")
} catch {
    fputs("Error generating AppIcon: \(error.localizedDescription)\n", stderr)
    exit(1)
}
