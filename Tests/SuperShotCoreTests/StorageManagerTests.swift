import Foundation
import CoreGraphics
import SuperShotCore

public struct StorageManagerTests {
    // Adapter types for E2E Boundary, Pairwise, and Workload test suites
    public struct TestShotItem: Identifiable, Equatable {
        public let id: UUID
        public var title: String
        public var width: Int
        public var height: Int
        public var isPinned: Bool
        
        public init(id: UUID = UUID(), title: String = "Test", width: Int = 100, height: Int = 100, isPinned: Bool = false) {
            self.id = id
            self.title = title
            self.width = width
            self.height = height
            self.isPinned = isPinned
        }
    }
    
    public class MockStorageManager {
        public let baseDirectory: URL
        public var capacity: Int {
            didSet {
                if capacity < 1 { capacity = 1 }
                enforceCapacity()
            }
        }
        public var items: [TestShotItem] = []
        public var pinnedItems: [TestShotItem] { items.filter { $0.isPinned } }
        public var recentItems: [TestShotItem] { items.filter { !$0.isPinned } }
        
        public init(baseDirectory: URL, capacity: Int = 50) {
            self.baseDirectory = baseDirectory
            self.capacity = max(1, capacity)
            let metadataURL = baseDirectory.appendingPathComponent("metadata.json")
            if FileManager.default.fileExists(atPath: metadataURL.path),
               let data = try? Data(contentsOf: metadataURL) {
                if let _ = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    // valid
                } else {
                    items = []
                }
            }
        }
        
        public func addShot(item: TestShotItem, imageData: Data? = nil) {
            items.insert(item, at: 0)
            enforceCapacity()
        }
        
        public func clearUnpinnedHistory() {
            items.removeAll { !$0.isPinned }
        }
        
        public func search(query: String) -> [TestShotItem] {
            if query.isEmpty { return items }
            return items.filter { $0.title.localizedCaseInsensitiveContains(query) }
        }
        
        private func enforceCapacity() {
            let unpinned = items.filter { !$0.isPinned }
            if unpinned.count > capacity {
                let excess = unpinned.count - capacity
                let toRemove = Array(unpinned.suffix(excess))
                let ids = Set(toRemove.map { $0.id })
                items.removeAll { ids.contains($0.id) }
            }
        }
    }

    private static func createSyntheticImage(width: Int = 100, height: Int = 100, color: CGColor = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(color)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    public static func run(sandboxDir: URL) {
        TestHarness.startSuite("StorageManager Thread-Safe Persistence & Pinned Item Protection")

        // 1. Isolated sandbox initialization
        let storage = StorageManager(baseDirectory: sandboxDir, initialCapacity: 3)
        TestHarness.assertEqual(storage.items.count, 0, "StorageManager initializes with 0 items")
        TestHarness.assertEqual(storage.capacity, 10, "Capacity clamped to minimum boundary of 10")

        // 2. Save image and synchronous read-after-write from NSCache
        let img1 = createSyntheticImage(width: 400, height: 300)
        let savedItem1 = try? storage.save(image: img1, sourceApp: "com.apple.Terminal", captureType: .region, tags: ["cli"])
        TestHarness.assertNotNil(savedItem1, "Image saved successfully")
        TestHarness.assertEqual(storage.items.count, 1, "Storage items count updated to 1")

        // Immediate read-after-write test (synchronous RAM cache hit)
        let retrievedData = storage.getImageData(for: savedItem1!)
        TestHarness.assertNotNil(retrievedData, "Immediate read-after-write retrieves image data from NSCache")
        let retrievedThumb = storage.getThumbnailData(for: savedItem1!)
        TestHarness.assertNotNil(retrievedThumb, "Immediate read-after-write retrieves thumbnail data from NSCache")

        // Flush file IO queue to ensure disk write completes
        storage.flushDiskQueue()

        // 3. Cold restart from disk
        let storage2 = StorageManager(baseDirectory: sandboxDir, initialCapacity: 10)
        TestHarness.assertEqual(storage2.items.count, 1, "Storage reloads persisted item after cold start")
        TestHarness.assertEqual(storage2.items.first?.id, savedItem1?.id, "Reloaded item preserves UUID")
        TestHarness.assertEqual(storage2.items.first?.sourceApp, "com.apple.Terminal", "Reloaded item preserves sourceApp")

        // 4. Pinning and Capacity Eviction Enforcement (§R3)
        storage2.capacity = 10
        // Pin item 1
        storage2.togglePin(id: savedItem1!.id)
        TestHarness.assertTrue(storage2.items.first!.isPinned, "Item 1 is pinned")

        // Add 12 items to exceed capacity limit
        var addedIDs: [UUID] = []
        for i in 1...12 {
            let img = createSyntheticImage(width: 100, height: 100)
            if let item = try? storage2.save(image: img, sourceApp: "App_\(i)") {
                addedIDs.append(item.id)
            }
        }
        storage2.flushDiskQueue()

        // Verify pinned item 1 was NOT evicted
        TestHarness.assertTrue(storage2.items.contains(where: { $0.id == savedItem1!.id }), "Pinned Item 1 permanently protected from capacity trimming (§R3)")
        // Verify unpinned items were trimmed to capacity (10 unpinned + 1 pinned = 11 total)
        TestHarness.assertEqual(storage2.recentItems.count, 10, "Unpinned recent items trimmed exactly to configured capacity 10")
        TestHarness.assertEqual(storage2.pinnedItems.count, 1, "Pinned items remain 1")
        TestHarness.assertEqual(storage2.items.count, 11, "Total items equal pinned + capacity")

        // 5. Clear Unpinned History
        storage2.clearUnpinnedHistory()
        storage2.flushDiskQueue()
        TestHarness.assertEqual(storage2.items.count, 1, "Clear unpinned history leaves only pinned items")
        TestHarness.assertEqual(storage2.items.first?.id, savedItem1!.id, "Only pinned item remains")

        // 6. Delete item
        storage2.deleteItem(id: savedItem1!.id)
        storage2.flushDiskQueue()
        TestHarness.assertEqual(storage2.items.count, 0, "Deleting pinned item leaves empty storage")

        // 7. Search filtering
        let searchImg = createSyntheticImage(width: 50, height: 50)
        _ = try? storage2.save(image: searchImg, sourceApp: "Finder", tags: ["desktop"])
        _ = try? storage2.save(image: searchImg, sourceApp: "Xcode", tags: ["code", "swift"])
        storage2.flushDiskQueue()

        let searchResult = storage2.search(query: "swift")
        TestHarness.assertEqual(searchResult.count, 1, "Search returns matching tagged item")
        TestHarness.assertEqual(searchResult.first?.sourceApp, "Xcode", "Search matched Xcode item")
    }
}
