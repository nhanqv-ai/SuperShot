import Foundation

public enum ShotCaptureType: String, Codable, CaseIterable, Sendable {
    case region
    case scrolling
    case fullScreen
}

/// Screenshot record model tracking captured image files, dimensions,
/// pin state, tags, and origin application.
public struct ShotItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var timestamp: Date
    public var filePath: String          // e.g. "uuid.png" in images directory
    public var thumbnailPath: String     // e.g. "uuid_thumb.png" in thumbnails directory
    public var width: Int                // Pixel width
    public var height: Int               // Pixel height
    public var byteSize: Int             // File size in bytes
    public var isPinned: Bool
    public var sourceApp: String?        // Bundle ID or application name
    public var tags: [String]
    public var captureType: ShotCaptureType
    public var annotationCount: Int

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        filePath: String? = nil,
        thumbnailPath: String? = nil,
        width: Int = 0,
        height: Int = 0,
        byteSize: Int = 0,
        isPinned: Bool = false,
        sourceApp: String? = nil,
        tags: [String] = [],
        captureType: ShotCaptureType = .region,
        annotationCount: Int = 0
    ) {
        self.id = id
        self.timestamp = timestamp
        self.filePath = filePath ?? "\(id.uuidString).png"
        self.thumbnailPath = thumbnailPath ?? "\(id.uuidString)_thumb.png"
        self.width = max(0, width)
        self.height = max(0, height)
        self.byteSize = max(0, byteSize)
        self.isPinned = isPinned
        self.sourceApp = sourceApp?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tags = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        self.captureType = captureType
        self.annotationCount = max(0, annotationCount)
    }

    // MARK: - Computed Properties & Display Helpers

    public var aspectRatio: CGFloat {
        guard height > 0 else { return 1.0 }
        return CGFloat(width) / CGFloat(height)
    }

    public var dimensionsString: String {
        "\(width) x \(height) px"
    }

    public var formattedByteSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(byteSize))
    }

    public var displayTitle: String {
        if let app = sourceApp, !app.isEmpty {
            return app
        }
        return "Screenshot (\(dimensionsString))"
    }

    public var searchableText: String {
        var components = [displayTitle, dimensionsString]
        if let app = sourceApp { components.append(app) }
        components.append(contentsOf: tags)
        return components.joined(separator: " ").lowercased()
    }

    // MARK: - CodingKeys & Backward Compatibility

    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case createdAt // For backward compatibility with legacy payloads
        case filePath
        case thumbnailPath
        case width
        case height
        case byteSize
        case isPinned
        case sourceApp
        case tags
        case captureType
        case annotationCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        
        // Handle timestamp or legacy createdAt
        if let ts = try container.decodeIfPresent(Date.self, forKey: .timestamp) {
            self.timestamp = ts
        } else if let ca = try container.decodeIfPresent(Date.self, forKey: .createdAt) {
            self.timestamp = ca
        } else {
            self.timestamp = Date()
        }

        self.filePath = try container.decodeIfPresent(String.self, forKey: .filePath) ?? "\(id.uuidString).png"
        self.thumbnailPath = try container.decodeIfPresent(String.self, forKey: .thumbnailPath) ?? "\(id.uuidString)_thumb.png"
        self.width = max(0, try container.decodeIfPresent(Int.self, forKey: .width) ?? 0)
        self.height = max(0, try container.decodeIfPresent(Int.self, forKey: .height) ?? 0)
        self.byteSize = max(0, try container.decodeIfPresent(Int.self, forKey: .byteSize) ?? 0)
        self.isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        self.sourceApp = try container.decodeIfPresent(String.self, forKey: .sourceApp)
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.captureType = try container.decodeIfPresent(ShotCaptureType.self, forKey: .captureType) ?? .region
        self.annotationCount = max(0, try container.decodeIfPresent(Int.self, forKey: .annotationCount) ?? 0)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(filePath, forKey: .filePath)
        try container.encode(thumbnailPath, forKey: .thumbnailPath)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(byteSize, forKey: .byteSize)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encodeIfPresent(sourceApp, forKey: .sourceApp)
        try container.encode(tags, forKey: .tags)
        try container.encode(captureType, forKey: .captureType)
        try container.encode(annotationCount, forKey: .annotationCount)
    }
}
