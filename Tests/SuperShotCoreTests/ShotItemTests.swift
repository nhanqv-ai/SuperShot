import Foundation
import SuperShotCore

public struct ShotItemTests {
    public static func run() {
        TestHarness.startSuite("ShotItem Model & Metadata Serialization")

        let id = UUID()
        let item = ShotItem(
            id: id,
            timestamp: Date(),
            filePath: "\(id.uuidString).png",
            thumbnailPath: "\(id.uuidString)_thumb.png",
            width: 1920,
            height: 1080,
            byteSize: 204800,
            isPinned: false,
            sourceApp: "com.apple.Safari",
            tags: ["web", "reference"],
            captureType: .region,
            annotationCount: 3
        )

        TestHarness.assertEqual(item.width, 1920, "Width initialized accurately")
        TestHarness.assertEqual(item.height, 1080, "Height initialized accurately")
        TestHarness.assertEqual(item.dimensionsString, "1920 x 1080 px", "Dimension string formatted accurately")
        TestHarness.assertTrue(abs(item.aspectRatio - (1920.0 / 1080.0)) < 0.001, "Aspect ratio calculated accurately")
        TestHarness.assertEqual(item.displayTitle, "com.apple.Safari", "Display title uses source app")
        TestHarness.assertTrue(item.searchableText.contains("safari"), "Searchable text contains lowercase app name")
        TestHarness.assertTrue(item.searchableText.contains("web"), "Searchable text contains tags")

        // Zero height safe aspect ratio test
        let zeroHeightItem = ShotItem(width: 500, height: 0)
        TestHarness.assertTrue(zeroHeightItem.aspectRatio == 1.0, "Zero height returns safe aspect ratio 1.0 without dividing by zero")

        // Codable round-trip with ISO8601
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try? encoder.encode(item)
        TestHarness.assertNotNil(data, "ShotItem encodes to JSON")
        let decoded = data.flatMap { try? decoder.decode(ShotItem.self, from: $0) }
        TestHarness.assertNotNil(decoded, "ShotItem decodes from JSON")
        TestHarness.assertEqual(decoded?.id, item.id, "Decoded id preserved")
        TestHarness.assertEqual(decoded?.tags, item.tags, "Decoded tags preserved")
        TestHarness.assertEqual(decoded?.sourceApp, item.sourceApp, "Decoded source app preserved")
        TestHarness.assertEqual(decoded?.captureType, item.captureType, "Decoded captureType preserved")

        // Backward compatibility with legacy payload having createdAt instead of timestamp
        let legacyJSON = """
        {
            "id": "\(id.uuidString)",
            "createdAt": "2026-10-22T12:00:00Z",
            "filePath": "test.png",
            "thumbnailPath": "test_thumb.png",
            "width": 800,
            "height": 600,
            "byteSize": 1024,
            "isPinned": true,
            "sourceApp": "Terminal"
        }
        """
        if let legacyData = legacyJSON.data(using: .utf8),
           let legacyItem = try? decoder.decode(ShotItem.self, from: legacyData) {
            TestHarness.assertEqual(legacyItem.id, id, "Decoded legacy item preserves UUID")
            TestHarness.assertTrue(legacyItem.isPinned, "Decoded legacy item is pinned")
            TestHarness.assertEqual(legacyItem.sourceApp, "Terminal", "Decoded legacy sourceApp preserved")
            TestHarness.assertEqual(legacyItem.tags.count, 0, "Missing tags defaults to empty array")
        } else {
            TestHarness.recordFail("Legacy Payload Decoding", reason: "Failed to decode legacy JSON with createdAt")
        }
    }
}
