import Foundation
import CoreGraphics
import AppKit

#if canImport(SuperShotCore)
import SuperShotCore
#endif

/// Tier 4: Real-World Application Workload Scenarios Test Suite
public struct WorkloadTests {
    public static func run(sandboxDir: URL) {
        TestHarness.startSuite("Tier 4: Real-World Application Workload Scenarios")
        
        // Scenario 1: Developer Bug Report & Code Annotation Workflow
        let devEngine = AnnotationEngineTests.MockAnnotationEngine()
        // 1. Rectangle over code error
        devEngine.addObject(AnnotationEngineTests.VectorObject(
            tool: .rectangle,
            rect: CGRect(x: 100, y: 150, width: 600, height: 40),
            colorHex: "#FF3B30",
            strokeWidth: 3.0
        ))
        // 2. Arrow pointing to error
        devEngine.addObject(AnnotationEngineTests.VectorObject(
            tool: .arrow,
            rect: CGRect(x: 50, y: 120, width: 45, height: 30),
            points: [CGPoint(x: 50, y: 120), CGPoint(x: 95, y: 150)]
        ))
        // 3. Text note
        devEngine.addObject(AnnotationEngineTests.VectorObject(
            tool: .text,
            rect: CGRect(x: 50, y: 80, width: 300, height: 30),
            textContent: "Fix race condition in fileQueue"
        ))
        // 4. Region blur over secret token
        devEngine.addObject(AnnotationEngineTests.VectorObject(
            tool: .blur,
            rect: CGRect(x: 100, y: 250, width: 200, height: 25)
        ))
        TestHarness.assertEqual(devEngine.objects.count, 4, "Scenario 1: Ingested 4 diverse bug report annotations")
        
        // Test undoing and retyping text
        devEngine.undo() // Undoes blur
        TestHarness.assertEqual(devEngine.objects.count, 3, "Scenario 1: Undid blur annotation")
        devEngine.redo() // Redoes blur
        TestHarness.assertEqual(devEngine.objects.count, 4, "Scenario 1: Redid blur annotation")
        
        // Scenario 2: Web Designer Long-Page Scrolling & Vector Annotation
        let tallCanvasEngine = AnnotationEngineTests.MockAnnotationEngine()
        // Annotation placed deep down at scroll offset 12,000 px
        let deepMarker = AnnotationEngineTests.VectorObject(
            tool: .highlighter,
            rect: CGRect(x: 100, y: 12000, width: 400, height: 30),
            colorHex: "#FFCC00",
            strokeWidth: 20.0
        )
        tallCanvasEngine.addObject(deepMarker)
        let hitDeep = tallCanvasEngine.selectObject(at: CGPoint(x: 150, y: 12015))
        TestHarness.assertEqual(hitDeep?.id, deepMarker.id, "Scenario 2: Hit-test resolved on tall canvas at offset 12,015 px")
        
        // Scenario 3: Security & Compliance Auditor Redaction Session
        let securityStorage = StorageManagerTests.MockStorageManager(
            baseDirectory: sandboxDir.appendingPathComponent("SecuritySession"),
            capacity: 10
        )
        for i in 1...15 {
            let item = StorageManagerTests.TestShotItem(
                title: "Confidential Audit Log \(i)",
                isPinned: (i <= 3) // Pin first 3
            )
            securityStorage.addShot(item: item, imageData: nil)
        }
        TestHarness.assertEqual(securityStorage.pinnedItems.count, 3, "Scenario 3: Auditor pinned 3 critical compliance screenshots")
        securityStorage.clearUnpinnedHistory()
        TestHarness.assertEqual(securityStorage.items.count, 3, "Scenario 3: Only the 3 pinned screenshots remain; 12 unpinned deleted")
        
        // Scenario 4: Power User Keyboard-Only Multi-Monitor & History Workflow
        let powerStorage = StorageManagerTests.MockStorageManager(
            baseDirectory: sandboxDir.appendingPathComponent("PowerSession"),
            capacity: 20
        )
        for i in 1...10 {
            let title = (i % 2 == 0) ? "Terminal Error \(i)" : "Browser Page \(i)"
            powerStorage.addShot(item: StorageManagerTests.TestShotItem(title: title), imageData: nil)
        }
        let termMatches = powerStorage.search(query: "terminal")
        TestHarness.assertEqual(termMatches.count, 5, "Scenario 4: Search filtered instantly to 5 terminal matches")
        
        // Scenario 5: High-Frequency Rapid Capture Burst & Storage Eviction Stress
        let burstStorage = StorageManagerTests.MockStorageManager(
            baseDirectory: sandboxDir.appendingPathComponent("BurstSession"),
            capacity: 25
        )
        let startTime = Date()
        for i in 1...100 {
            let isTargetPin = (i == 10 || i == 20 || i == 30 || i == 40 || i == 50)
            let item = StorageManagerTests.TestShotItem(
                title: "Burst Shot \(i)",
                isPinned: isTargetPin
            )
            burstStorage.addShot(item: item, imageData: nil)
        }
        let elapsed = Date().timeIntervalSince(startTime)
        TestHarness.assertTrue(elapsed < 2.0, "Scenario 5: 100 rapid screenshot additions executed in \(String(format: "%.3f", elapsed))s (< 2.0s)")
        TestHarness.assertEqual(burstStorage.pinnedItems.count, 5, "Scenario 5: All 5 pinned burst items survived capacity eviction")
        TestHarness.assertEqual(burstStorage.recentItems.count, 25, "Scenario 5: Unpinned burst items capped strictly at capacity 25")
        TestHarness.assertEqual(burstStorage.items.count, 30, "Scenario 5: Total items = 25 unpinned + 5 pinned = 30 items")
    }
}
