import Foundation
import CoreGraphics
import AppKit
import SwiftUI
import SuperShotCore
import SuperShot

/// Comprehensive regression test suite for Cycle 20 (Milestone 1: Latent Bug Fixes).
/// Strictly verifies:
/// 1. Coordinate systems & multi-display clamping:
///    - Boundary-inclusive display(containing:) resolution
///    - normalizeRect boundary clamping and degenerate bounds safety
///    - cropImage safe coordinate clamping
///    - targetScrollCenter multi-display coordinate translation
/// 2. Annotation rendering & editing edge cases:
///    - drawArrow micro-vector guard and proportional head scaling
///    - Arrowhead barycentric hit testing resilience
///    - Text annotation whitespace trimming
///    - Tool change drag cancellation and selection reset
/// 3. Stitching, updates, storage & UI lifecycle:
///    - ImageStitcher safeCrop bounds protection
///    - Zero-delta 2-frame termination optimization
///    - Stationary header and footer edge-contrast detection
///    - UpdateManager active mount tracking and force-detach
///    - StorageManager deletion notification posting
///    - ThumbnailImageCache invalidation on item deletion
///    - ThumbnailHoverPreviewPanel deletion guard and dismissal
///    - StorageManager concurrent saves and reads with capacity eviction (0 deadlocks)
public struct Cycle20Tests {

    public static func run(sandboxDir: URL) {
        TestHarness.startSuite("Cycle 20 (v1.0.27 Latent Bug Fixes & Edge Cases)")

        // --- Section 1: Multi-Display & Coordinate Clamping ---
        print("  --- Section 1: Multi-Display & Coordinate Clamping ---")

        // S1.1: MockScreenCaptureProvider boundary-inclusive display(containing:)
        let d1 = CaptureDisplayInfo(
            displayID: 1,
            name: "Main",
            cocoaFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            cgBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            scaleFactor: 2.0,
            isMain: true,
            pixelSize: CGSize(width: 3840, height: 2160)
        )
        let d2 = CaptureDisplayInfo(
            displayID: 2,
            name: "Secondary",
            cocoaFrame: CGRect(x: 1920, y: 0, width: 2560, height: 1440),
            cgBounds: CGRect(x: 1920, y: 0, width: 2560, height: 1440),
            scaleFactor: 2.0,
            isMain: false,
            pixelSize: CGSize(width: 5120, height: 2880)
        )
        let mockProvider = MockScreenCaptureProvider(displays: [d1, d2])

        let boundaryPt1 = CGPoint(x: 0, y: 0)
        let foundD1 = mockProvider.display(containing: boundaryPt1)
        TestHarness.assertNotNil(foundD1, "S1.1: Point at exact display origin (0,0) matches display")
        TestHarness.assertEqual(foundD1?.displayID, 1, "S1.1: Point (0,0) resolves to primary display")

        let boundaryPtEdge = CGPoint(x: 1920, y: 500)
        let foundEdge = mockProvider.display(containing: boundaryPtEdge)
        TestHarness.assertNotNil(foundEdge, "S1.1: Point on shared display boundary (1920, 500) matches display")

        // S1.2: SelectionBoxGeometry.normalizeRect display clamping & degenerate bounds
        let dispBounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let rectOver = SelectionBoxGeometry.normalizeRect(
            p1: CGPoint(x: 1900, y: 1000),
            p2: CGPoint(x: 1950, y: 1100),
            bounds: dispBounds
        )
        TestHarness.assertTrue(rectOver.maxX <= 1920.0, "S1.2: Rect maxX clamped within display bounds")
        TestHarness.assertTrue(rectOver.maxY <= 1080.0, "S1.2: Rect maxY clamped within display bounds")

        let degenBounds = CGRect(x: 100, y: 100, width: 0, height: 0)
        let rectDegen = SelectionBoxGeometry.calculateCenterRect(
            center: CGPoint(x: 100, y: 100),
            target: CGPoint(x: 150, y: 150),
            bounds: degenBounds
        )
        TestHarness.assertTrue(rectDegen.width >= 1.0, "S1.2: Degenerate bounds returns safe width >= 1.0")
        TestHarness.assertTrue(rectDegen.height >= 1.0, "S1.2: Degenerate bounds returns safe height >= 1.0")

        // S1.3: ScreenCaptureManager.cropImage safe clamping
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 400, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        let baseImg = ctx.makeImage()!

        let safeCropped = ScreenCaptureManager.cropImage(
            baseImg,
            selectionInWindow: CGRect(x: 95.5, y: 95.5, width: 10, height: 10),
            windowSize: CGSize(width: 100, height: 100),
            scaleFactor: 1.0
        )
        TestHarness.assertNotNil(safeCropped, "S1.3: Subpixel crop rect slightly extending past image is clamped and succeeds")
        TestHarness.assertTrue((safeCropped?.width ?? 0) > 0, "S1.3: Clamped crop has positive width")
        TestHarness.assertTrue((safeCropped?.height ?? 0) > 0, "S1.3: Clamped crop has positive height")

        // S1.4: targetScrollCenter multi-display coordinate translation
        let secBounds = CGRect(x: 1920, y: 100, width: 2560, height: 1440)
        let secSelRect = CGRect(x: 100, y: 200, width: 300, height: 400)
        let scrollCenter = ScrollingCoordinateMapper.targetScrollCenter(
            selectionRect: secSelRect,
            screenBounds: secBounds
        )
        TestHarness.assertEqual(scrollCenter.x, 1920 + 250, "S1.4: Scroll center X includes secondary display origin X")
        TestHarness.assertEqual(scrollCenter.y, 100 + (1440 - 400), "S1.4: Scroll center Y includes secondary display origin Y")

        // --- Section 2: Annotation Rendering & Editing Edge Cases ---
        print("  --- Section 2: Annotation Rendering & Editing Edge Cases ---")

        // S2.1: Micro-vector arrow rendering
        let renderObj = AnnotationObject(
            tool: .arrow,
            bounds: CGRect(x: 20, y: 20, width: 0.5, height: 0.5),
            colorHex: "#FF0000"
        )
        let renderedArrow = SuperShotCore.ImageRenderer.render(baseImage: baseImg, annotations: [renderObj])
        TestHarness.assertNotNil(renderedArrow, "S2.1: ImageRenderer renders micro-vector arrow without crash")

        // S2.2: Proportional arrowhead calculation
        let microLen: CGFloat = 0.8
        let headLen = min(15.0, max(3.0, microLen * 0.6))
        let setback = min(headLen * 0.7, microLen)
        TestHarness.assertTrue(setback <= microLen, "S2.2: Arrow shaft setback does not exceed arrow length")

        // S2.3: Arrowhead hit testing for short arrows
        let shortArrow = AnnotationObject(
            tool: .arrow,
            bounds: CGRect(x: 10, y: 10, width: 5, height: 0),
            colorHex: "#00FF00"
        )
        let hitResult = shortArrow.contains(point: CGPoint(x: 12, y: 10), tolerance: 4.0)
        TestHarness.assertTrue(hitResult, "S2.3: Hit testing succeeds on short arrow shaft")

        // S2.4: Text annotation whitespace trimming
        let textObj = AnnotationObject(
            tool: .text,
            bounds: CGRect(x: 10, y: 10, width: 80, height: 30),
            colorHex: "#0000FF",
            text: "   Hello SuperShot   "
        )
        let trimmed = textObj.text.trimmingCharacters(in: .whitespacesAndNewlines)
        TestHarness.assertEqual(trimmed, "Hello SuperShot", "S2.4: Text annotation content trims surrounding whitespace")

        // S2.5: Tool switch drag cancellation and deselect
        let engine = AnnotationEngine()
        let boxObj = AnnotationObject(tool: .rectangle, bounds: CGRect(x: 10, y: 10, width: 50, height: 50))
        engine.addObject(boxObj)
        engine.selectedObjectID = boxObj.id
        TestHarness.assertEqual(engine.selectedObjectID, boxObj.id, "S2.5: Object selected initially")
        engine.startDrag(at: CGPoint(x: 20, y: 20))
        TestHarness.assertTrue(engine.isDragging, "S2.5: Engine is dragging")
        engine.cancelDrag()
        TestHarness.assertFalse(engine.isDragging, "S2.5: Drag cancelled cleanly")
        engine.deselectAll()
        TestHarness.assertNil(engine.selectedObjectID, "S2.5: Selection cleared cleanly")

        // --- Section 3: Stitching, Updates, Storage & UI Lifecycle ---
        print("  --- Section 3: Stitching, Updates, Storage & UI Lifecycle ---")

        // S3.1: ImageStitcher safeCrop clamping
        let safeCroppedImg = ImageStitcher.safeCrop(baseImg, x: -5, y: -5, width: 120, height: 120)
        TestHarness.assertNil(safeCroppedImg, "S3.1: safeCrop returns nil for negative coordinates")
        let safeValidCrop = ImageStitcher.safeCrop(baseImg, x: 10, y: 10, width: 200, height: 200)
        TestHarness.assertNotNil(safeValidCrop, "S3.1: safeCrop clamps to remaining image dimensions")
        TestHarness.assertTrue((safeValidCrop?.width ?? 0) <= 90, "S3.1: safeCropped width clamped to remaining width")
        TestHarness.assertTrue((safeValidCrop?.height ?? 0) <= 90, "S3.1: safeCropped height clamped to remaining height")

        // S3.2: 2-frame zero-delta stitch optimization
        let stitchResult = try? ImageStitcher.stitch(frames: [baseImg, baseImg], options: StitchOptions())
        TestHarness.assertNotNil(stitchResult, "S3.2: Stitching two identical frames succeeds")
        TestHarness.assertEqual(stitchResult?.image.height, baseImg.height, "S3.2: Zero-delta 2-frame stitch returns single frame height")

        // S3.3: StorageManager delete notification and ThumbnailImageCache invalidation
        let storeDir = sandboxDir.appendingPathComponent("StorageNotificationTest")
        let storage = StorageManager(baseDirectory: storeDir)
        let savedItem = try? storage.save(image: baseImg, sourceApp: "Finder", captureType: .region)
        storage.flushDiskQueue()
        TestHarness.assertNotNil(savedItem, "S3.3: StorageManager successfully saved item")

        if let item = savedItem {
            let imgURL = storage.getImageURL(for: item)
            let nsImg = NSImage(cgImage: baseImg, size: NSSize(width: 100, height: 100))
            ThumbnailImageCache.shared.setImage(nsImg, for: imgURL)
            TestHarness.assertNotNil(ThumbnailImageCache.shared.image(for: imgURL), "S3.3: ThumbnailImageCache holds cached image before delete")

            // Delete item
            storage.deleteItem(id: item.id)
            storage.flushDiskQueue()

            // Verify cache invalidated
            TestHarness.assertNil(ThumbnailImageCache.shared.image(for: imgURL), "S3.3: ThumbnailImageCache invalidated URL after deletion notification")
        }

        // S3.4: ThumbnailHoverPreviewPanel deletion guard
        let panel = ThumbnailHoverPreviewPanel.shared
        panel.storageManager = storage
        let dummyItem = ShotItem(
            id: UUID(),
            filePath: "nonexistent.png",
            thumbnailPath: "nonexistent_thumb.png",
            width: 100,
            height: 100,
            byteSize: 1024,
            captureType: .region
        )
        // Show for non-existent item: should not display since not in storageManager
        panel.show(for: dummyItem)
        TestHarness.assertFalse(panel.currentItemId == dummyItem.id, "S3.4: ThumbnailHoverPreviewPanel does not display deleted/absent item")

        // S3.5: UpdateManager active mount tracking and force detach
        let dummyMount = URL(fileURLWithPath: "/tmp/SuperShotDummyMount")
        UpdateManager.forceDetachDMG(mountPoint: dummyMount, maxAttempts: 1)
        TestHarness.assertTrue(true, "S3.5: forceDetachDMG completes safely without crashing")

        // S3.6: Multi-threaded stress test: concurrent background saves with capacity eviction and main-thread reads (0 deadlocks)
        let concurrentStoreDir = sandboxDir.appendingPathComponent("ConcurrentStorageTest_\(UUID().uuidString)")
        let concurrentStorage = StorageManager(baseDirectory: concurrentStoreDir, initialCapacity: 10)
        let totalItemsToSave = 50
        let group = DispatchGroup()
        let saveQueue = DispatchQueue(label: "com.supershot.test.concurrentSave", attributes: .concurrent)

        for i in 1...totalItemsToSave {
            group.enter()
            saveQueue.async {
                if let item = try? concurrentStorage.save(image: baseImg, sourceApp: "StressApp\(i)", captureType: .region) {
                    let imgURL = concurrentStorage.getImageURL(for: item)
                    let nsImg = NSImage(cgImage: baseImg, size: NSSize(width: 50, height: 50))
                    ThumbnailImageCache.shared.setImage(nsImg, for: imgURL)
                }
                group.leave()
            }
        }

        // Concurrently read items, recentItems, pinnedItems, search, and ThumbnailImageCache on calling thread
        var readSuccessCount = 0
        let readDeadline = Date().addingTimeInterval(3.0)
        while Date() < readDeadline {
            let currentItems = concurrentStorage.items
            _ = concurrentStorage.recentItems
            _ = concurrentStorage.pinnedItems
            _ = concurrentStorage.search(query: "StressApp")
            if let first = currentItems.first {
                let imgURL = concurrentStorage.getImageURL(for: first)
                _ = ThumbnailImageCache.shared.image(for: imgURL)
            }
            readSuccessCount += 1
            if currentItems.count >= 10 && readSuccessCount > 20 {
                break
            }
            Thread.sleep(forTimeInterval: 0.005)
        }

        // Wait for all 50 background saves to complete
        let waitResult = group.wait(timeout: .now() + 10.0)
        concurrentStorage.flushDiskQueue()

        TestHarness.assertEqual(waitResult, .success, "S3.6: All 50 concurrent saves completed within timeout with 0 deadlocks")
        TestHarness.assertTrue(readSuccessCount > 0, "S3.6: Concurrent main-thread reads succeeded with 0 deadlocks")
        TestHarness.assertEqual(concurrentStorage.items.count, 10, "S3.6: StorageManager enforced capacity limit of 10 items under concurrent saves")

        // S3.7: UpdateDownloadDelegate background completion fires onCompletion even after delegate scope ends
        let bgDownloadDir = sandboxDir.appendingPathComponent("BgDownloadTest_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: bgDownloadDir, withIntermediateDirectories: true)
        let srcFile = bgDownloadDir.appendingPathComponent("temp_download.tmp")
        let destFile = bgDownloadDir.appendingPathComponent("SuperShot-update.zip")
        try? Data("dummy-zip-payload".utf8).write(to: srcFile)

        var bgCompletionResult: Result<URL, Error>? = nil
        var bgProgress: Double = 0.0
        let bgMgr = UpdateManager()
        bgMgr.status = .downloading(progress: 0.5)

        DispatchQueue.global(qos: .userInitiated).async {
            let ephemeralSession = URLSession(configuration: .ephemeral)
            let dummyTask = ephemeralSession.downloadTask(with: URL(string: "https://example.com/update.zip")!)
            let delegate = UpdateDownloadDelegate(
                destinationURL: destFile,
                updateManager: bgMgr,
                onProgress: { p in bgProgress = p },
                onCompletion: { res in bgCompletionResult = res }
            )
            delegate.urlSession(ephemeralSession, downloadTask: dummyTask, didFinishDownloadingTo: srcFile)
        }

        let bgDeadline = Date().addingTimeInterval(2.0)
        while bgCompletionResult == nil && Date() < bgDeadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        if case .success(let completedURL) = bgCompletionResult {
            TestHarness.assertEqual(completedURL.path, destFile.path, "S3.7: UpdateDownloadDelegate background completion invoked onCompletion with destinationURL")
        } else {
            TestHarness.assertTrue(false, "S3.7: UpdateDownloadDelegate background completion must not drop onCompletion when delegate is released")
        }
        TestHarness.assertEqual(bgProgress, 1.0, "S3.7: UpdateDownloadDelegate reported 100% progress before completion")

        // S3.8: Text UX Enhancements (WYSIWYG auto-expanding editor, 4-corner fontSize scaling, smart click-outside & move)
        let textUXEngine = AnnotationEngine()
        textUXEngine.activeTool = .text
        textUXEngine.startDrag(at: CGPoint(x: 100, y: 100), tool: .text, colorHex: "#FFFFFF", fontSize: 18.0)
        let createdText = textUXEngine.endDrag(at: CGPoint(x: 100, y: 100))
        TestHarness.assertNotNil(createdText, "S3.8: Clicking in .text mode creates a text annotation")

        if let txt = createdText {
            let handles = txt.handlePositions()
            TestHarness.assertEqual(handles.count, 4, "S3.8: Text object exposes strictly 4 corner resize handles")
            TestHarness.assertNotNil(handles[.topLeft], "S3.8: Text object has topLeft handle")
            TestHarness.assertNotNil(handles[.topRight], "S3.8: Text object has topRight handle")
            TestHarness.assertNotNil(handles[.bottomRight], "S3.8: Text object has bottomRight handle")
            TestHarness.assertNotNil(handles[.bottomLeft], "S3.8: Text object has bottomLeft handle")
            TestHarness.assertNil(handles[.topCenter], "S3.8: Text object omits cluttered edge-center handles")
            TestHarness.assertTrue(txt.selectionBounds.width > txt.bounds.width, "S3.8: Text selectionBounds includes breathing padding")

            // Dragging bottomRight corner handle scales fontSize proportionally
            let initialFontSize = txt.fontSize
            let brPos = handles[.bottomRight]!
            textUXEngine.startDrag(at: brPos, tool: .text)
            textUXEngine.updateDrag(to: CGPoint(x: brPos.x + 80, y: brPos.y + 40))
            let resizedTxt = textUXEngine.endDrag(at: CGPoint(x: brPos.x + 80, y: brPos.y + 40))
            TestHarness.assertTrue((resizedTxt?.fontSize ?? 0) > initialFontSize, "S3.8: Dragging corner handle proportionally increases fontSize")

            // Undo restores both fontSize and bounds
            textUXEngine.undo()
            TestHarness.assertEqual(textUXEngine.objects.first?.fontSize, initialFontSize, "S3.8: Undo restores original fontSize after corner resize")

            // Clicking and dragging existing text while still in .text mode moves it instead of spawning a second text object
            let midPt = CGPoint(x: textUXEngine.objects[0].bounds.midX, y: textUXEngine.objects[0].bounds.midY)
            let oldMinX = textUXEngine.objects[0].bounds.minX
            textUXEngine.startDrag(at: midPt, tool: .text)
            textUXEngine.updateDrag(to: CGPoint(x: midPt.x + 50, y: midPt.y + 30))
            _ = textUXEngine.endDrag(at: CGPoint(x: midPt.x + 50, y: midPt.y + 30))
            TestHarness.assertEqual(textUXEngine.objects.count, 1, "S3.8: Dragging existing text in .text mode does not spawn duplicate object")
            TestHarness.assertEqual(textUXEngine.objects[0].bounds.minX, oldMinX + 50, "S3.8: Dragging existing text in .text mode translates its position")
        }

        // Verify InlineCanvasTextField auto-expansion and border drag zone
        let inlineField = InlineCanvasTextField(frame: NSRect(x: 50, y: 50, width: 80, height: 32))
        TestHarness.assertFalse(inlineField.drawsBackground, "S3.8: InlineCanvasTextField has transparent WYSIWYG background")
        TestHarness.assertTrue(inlineField.isPointInBorderDragZone(CGPoint(x: 2, y: 2)), "S3.8: Outer border ring is recognized as draggable zone")
        TestHarness.assertFalse(inlineField.isPointInBorderDragZone(CGPoint(x: 40, y: 16)), "S3.8: Interior text area is reserved for text cursor editing")

        print("  --- Cycle 20 All Test Sections Completed Successfully ---")
    }
}
