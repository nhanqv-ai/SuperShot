import AppKit
import Foundation

/// In-memory cache for loaded thumbnail NSImages to avoid repeated disk reads.
public final class ThumbnailImageCache: @unchecked Sendable {
    public static let shared = ThumbnailImageCache()
    private let cache = NSCache<NSURL, NSImage>()

    public init() {
        cache.countLimit = 150
    }

    public func image(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    public func setImage(_ image: NSImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }

    public func removeImage(for url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }

    public func removeAll() {
        cache.removeAllObjects()
    }
}

/// Formatter for displaying human-friendly relative time strings (e.g. "Just now", "2m ago").
public enum RelativeTimeFormatter {
    private static let formatter: RelativeDateTimeFormatter = {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt
    }()

    public static func format(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        if interval < 5 { return "Just now" }
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
