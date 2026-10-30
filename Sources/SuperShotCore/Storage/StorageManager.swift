import Foundation
import CoreGraphics
import ImageIO
import AppKit
import UniformTypeIdentifiers

public protocol StorageManaging: AnyObject, ObservableObject {
    var items: [ShotItem] { get }
    var capacity: Int { get set }
    var pinnedItems: [ShotItem] { get }
    var recentItems: [ShotItem] { get }
    
    func save(image: CGImage, sourceApp: String?, captureType: ShotCaptureType, tags: [String], format: ImageSaveFormat) throws -> ShotItem
    func save(image: CGImage, sourceApp: String?, captureType: ShotCaptureType, tags: [String], format: ImageSaveFormat, jpegQuality: Double) throws -> ShotItem
    func save(imageData: Data, thumbnailData: Data, item: ShotItem)
    func loadCGImage(for item: ShotItem) -> CGImage?
    func loadThumbnailCGImage(for item: ShotItem) -> CGImage?
    func getImageData(for item: ShotItem) -> Data?
    func getThumbnailData(for item: ShotItem) -> Data?
    func getImageURL(for item: ShotItem) -> URL
    func getThumbnailURL(for item: ShotItem) -> URL
    func togglePin(id: UUID)
    func deleteItem(id: UUID)
    func clearUnpinnedHistory()
    func search(query: String) -> [ShotItem]
    func flushDiskQueue()
    func load(id: UUID) -> CGImage?
    func load(id: UUID) async -> CGImage?
    func delete(id: UUID) throws
    func delete(id: UUID) async throws
}

public final class StorageManager: ObservableObject, StorageManaging {
    private let lock = NSRecursiveLock()
    private var _items: [ShotItem] = []
    private var _capacity: Int

    public var items: [ShotItem] {
        lock.lock()
        defer { lock.unlock() }
        return _items
    }

    public var pinnedItems: [ShotItem] {
        lock.lock()
        defer { lock.unlock() }
        return _items.filter { $0.isPinned }
    }

    public var recentItems: [ShotItem] {
        lock.lock()
        defer { lock.unlock() }
        return _items.filter { !$0.isPinned }
    }

    public var capacity: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _capacity
        }
        set {
            lock.lock()
            let clamped = max(10, min(newValue, 500))
            _capacity = clamped
            enforceCapacity()
            saveMetadata()
            lock.unlock()
            notifyChange()
        }
    }

    public let baseDirectory: URL
    public let imagesDirectory: URL
    public let thumbnailsDirectory: URL
    public let metadataURL: URL
    public var backupMetadataURL: URL {
        metadataURL.appendingPathExtension("bak")
    }
    public let settingsURL: URL

    private let fileQueue = DispatchQueue(label: "com.supershot.storage.fileio", qos: .utility)
    private let imageCache = NSCache<NSString, NSData>()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // MARK: - Initializer & Sandboxing

    public init(baseDirectory: URL? = nil, initialCapacity: Int = 50) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = baseDirectory ?? appSupport.appendingPathComponent("SuperShot", isDirectory: true)
        self.baseDirectory = dir
        self.imagesDirectory = dir.appendingPathComponent("images", isDirectory: true)
        self.thumbnailsDirectory = dir.appendingPathComponent("thumbnails", isDirectory: true)
        self.metadataURL = dir.appendingPathComponent("metadata.json")
        self.settingsURL = dir.appendingPathComponent("settings.json")
        self._capacity = max(10, min(initialCapacity, 500))

        imageCache.countLimit = 100 // Cache up to 100 images/thumbnails in RAM

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        createDirectoriesIfNeeded()
        loadFromDisk()
    }

    private func createDirectoriesIfNeeded() {
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
    }

    private func notifyChange() {
        if Thread.isMainThread {
            self.objectWillChange.send()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.objectWillChange.send()
            }
        }
    }

    // MARK: - Image Saving Operations

    /// Saves a newly captured CGImage directly, creating thumbnails and ShotItem record.
    public func save(
        image: CGImage,
        sourceApp: String? = nil,
        captureType: ShotCaptureType = .region,
        tags: [String] = [],
        format: ImageSaveFormat = .png
    ) throws -> ShotItem {
        try save(image: image, sourceApp: sourceApp, captureType: captureType, tags: tags, format: format, jpegQuality: 0.9)
    }

    /// Saves a newly captured CGImage with explicit JPEG quality, creating thumbnails and ShotItem record.
    public func save(
        image: CGImage,
        sourceApp: String?,
        captureType: ShotCaptureType,
        tags: [String],
        format: ImageSaveFormat,
        jpegQuality: Double
    ) throws -> ShotItem {
        let id = UUID()
        let ext = format == .png ? "png" : "jpg"
        let imgName = "\(id.uuidString).\(ext)"
        let thumbName = "\(id.uuidString)_thumb.\(ext)"

        // Encode full-size image to Data
        guard let fullData = StorageManager.encodeCGImage(image, format: format, quality: jpegQuality) else {
            throw NSError(domain: "com.supershot.storage", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode full-size image"])
        }

        // Generate and encode thumbnail
        let thumbMaxDimension: CGFloat = 200.0
        let thumbnail = StorageManager.createThumbnail(from: image, maxPixelSize: thumbMaxDimension) ?? image
        guard let thumbData = StorageManager.encodeCGImage(thumbnail, format: format, quality: 0.8) else {
            throw NSError(domain: "com.supershot.storage", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to encode thumbnail image"])
        }

        let item = ShotItem(
            id: id,
            timestamp: Date(),
            filePath: imgName,
            thumbnailPath: thumbName,
            width: image.width,
            height: image.height,
            byteSize: fullData.count,
            isPinned: false,
            sourceApp: sourceApp,
            tags: tags,
            captureType: captureType,
            annotationCount: 0
        )

        save(imageData: fullData, thumbnailData: thumbData, item: item)
        return item
    }

    /// Stores pre-encoded image and thumbnail data into cache and asynchronously persists to disk.
    public func save(imageData: Data, thumbnailData: Data, item: ShotItem) {
        lock.lock()
        defer { lock.unlock() }

        // 1. Populate RAM cache immediately to guarantee synchronous read-after-write
        imageCache.setObject(imageData as NSData, forKey: item.filePath as NSString)
        imageCache.setObject(thumbnailData as NSData, forKey: item.thumbnailPath as NSString)

        // 2. Offload disk writing to dedicated serial queue
        let imgURL = imagesDirectory.appendingPathComponent(item.filePath)
        let thURL = thumbnailsDirectory.appendingPathComponent(item.thumbnailPath)
        fileQueue.async {
            try? imageData.write(to: imgURL, options: .atomic)
            try? thumbnailData.write(to: thURL, options: .atomic)
        }

        // 3. Prepend item to chronological history (newest at index 0)
        _items.insert(item, at: 0)

        // 4. Enforce capacity trimming (protecting pinned items permanently)
        enforceCapacity()

        // 5. Asynchronously persist metadata snapshot
        saveMetadata()
        notifyChange()
    }

    // MARK: - Image Retrieval Operations

    public func getImageData(for item: ShotItem) -> Data? {
        if let cached = imageCache.object(forKey: item.filePath as NSString) {
            return cached as Data
        }
        let url = imagesDirectory.appendingPathComponent(item.filePath)
        return fileQueue.sync {
            if let data = try? Data(contentsOf: url) {
                self.imageCache.setObject(data as NSData, forKey: item.filePath as NSString)
                return data
            }
            return nil
        }
    }

    public func getThumbnailData(for item: ShotItem) -> Data? {
        if let cached = imageCache.object(forKey: item.thumbnailPath as NSString) {
            return cached as Data
        }
        let url = thumbnailsDirectory.appendingPathComponent(item.thumbnailPath)
        return fileQueue.sync {
            if let data = try? Data(contentsOf: url) {
                self.imageCache.setObject(data as NSData, forKey: item.thumbnailPath as NSString)
                return data
            }
            return nil
        }
    }

    public func loadCGImage(for item: ShotItem) -> CGImage? {
        guard let data = getImageData(for: item) else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    public func loadThumbnailCGImage(for item: ShotItem) -> CGImage? {
        guard let data = getThumbnailData(for: item) else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    public func getImageURL(for item: ShotItem) -> URL {
        imagesDirectory.appendingPathComponent(item.filePath)
    }

    public func getThumbnailURL(for item: ShotItem) -> URL {
        thumbnailsDirectory.appendingPathComponent(item.thumbnailPath)
    }

    // MARK: - Item Management & Pinning

    public func togglePin(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        guard let index = _items.firstIndex(where: { $0.id == id }) else { return }
        _items[index].isPinned.toggle()
        enforceCapacity()
        saveMetadata()
        notifyChange()
    }

    public func deleteItem(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        guard let index = _items.firstIndex(where: { $0.id == id }) else { return }
        let item = _items.remove(at: index)
        cleanupFiles(for: item)
        saveMetadata()
        notifyChange()
    }

    public func clearUnpinnedHistory() {
        lock.lock()
        defer { lock.unlock() }
        let unpinned = _items.filter { !$0.isPinned }
        for item in unpinned {
            cleanupFiles(for: item)
        }
        _items.removeAll { !$0.isPinned }
        saveMetadata()
        notifyChange()
    }

    // MARK: - Convenience Load & Delete Overloads (Reviewer 1 Polish)

    /// Synchronous convenience overload to retrieve CGImage directly by UUID.
    public func load(id: UUID) -> CGImage? {
        lock.lock()
        let item = _items.first(where: { $0.id == id })
        lock.unlock()
        guard let item = item else { return nil }
        return loadCGImage(for: item)
    }

    /// Asynchronous convenience overload to retrieve CGImage directly by UUID.
    public func load(id: UUID) async -> CGImage? {
        guard let item = self.items.first(where: { $0.id == id }) else { return nil }
        return loadCGImage(for: item)
    }

    /// Synchronous convenience overload to delete shot and clean disk assets by UUID.
    public func delete(id: UUID) throws {
        deleteItem(id: id)
    }

    /// Asynchronous convenience overload to delete shot and clean disk assets by UUID.
    public func delete(id: UUID) async throws {
        deleteItem(id: id)
    }

    // MARK: - Capacity Trimming with Pinned Item Protection (§R3)

    /// Enforces capacity limit on unpinned items.
    /// Pinned items are permanently protected and NEVER evicted.
    private func enforceCapacity() {
        let unpinned = _items.filter { !$0.isPinned }
        if unpinned.count > _capacity {
            let excess = unpinned.count - _capacity
            // Items are in descending chronological order (newest at index 0)
            // Oldest unpinned items are at the tail end
            let toEvict = Array(unpinned.suffix(excess))
            let toEvictIDs = Set(toEvict.map { $0.id })
            for item in toEvict {
                cleanupFiles(for: item)
            }
            _items.removeAll { toEvictIDs.contains($0.id) }
        }
    }

    private func cleanupFiles(for item: ShotItem) {
        imageCache.removeObject(forKey: item.filePath as NSString)
        imageCache.removeObject(forKey: item.thumbnailPath as NSString)
        let imgURL = imagesDirectory.appendingPathComponent(item.filePath)
        let thURL = thumbnailsDirectory.appendingPathComponent(item.thumbnailPath)
        fileQueue.async {
            try? FileManager.default.removeItem(at: imgURL)
            try? FileManager.default.removeItem(at: thURL)
        }
    }

    // MARK: - Search Engine

    public func search(query: String) -> [ShotItem] {
        lock.lock()
        defer { lock.unlock() }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return _items }
        return _items.filter { $0.searchableText.contains(trimmed) }
    }

    // MARK: - Synchronization & Persistence

    public func flushDiskQueue() {
        fileQueue.sync {}
    }

    private func saveMetadata() {
        let snapshot = self._items
        let url = self.metadataURL
        let backupURL = self.backupMetadataURL
        let enc = self.encoder
        fileQueue.async {
            if let data = try? enc.encode(snapshot) {
                // If previous valid metadata file exists on disk, create/update backup
                if FileManager.default.fileExists(atPath: url.path) {
                    try? FileManager.default.removeItem(at: backupURL)
                    try? FileManager.default.copyItem(at: url, to: backupURL)
                }
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func loadFromDisk() {
        let urlsToTry = [metadataURL, backupMetadataURL]
        for url in urlsToTry {
            if FileManager.default.fileExists(atPath: url.path),
               let data = try? Data(contentsOf: url),
               let loaded = try? decoder.decode([ShotItem].self, from: data) {
                self._items = loaded
                return
            }
        }
        // Graceful corrupt recovery
        self._items = []
    }

    // MARK: - Image Utilities

    public static func encodeCGImage(_ image: CGImage, format: ImageSaveFormat, quality: Double = 0.9) -> Data? {
        let uti: CFString = format == .png ? UTType.png.identifier as CFString : UTType.jpeg.identifier as CFString
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, uti, 1, nil) else {
            return nil
        }
        var options: [CFString: Any] = [:]
        if format == .jpeg {
            options[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }

    public static func createThumbnail(from image: CGImage, maxPixelSize: CGFloat) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        guard width > 0, height > 0 else { return nil }
        let scale = min(maxPixelSize / width, maxPixelSize / height, 1.0)
        let targetWidth = max(1, Int(width * scale))
        let targetHeight = max(1, Int(height * scale))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return context.makeImage()
    }
}
