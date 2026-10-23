import Foundation
import Combine

public enum ImageSaveFormat: String, Codable, CaseIterable, Sendable {
    case png
    case jpeg
}

public enum SaveMode: String, Codable, CaseIterable, Sendable {
    case prompt
    case autoSave
}

/// Thread-safe, serializable snapshot of application settings.
public struct AppSettingsSnapshot: Codable, Equatable, Sendable {
    public var activeColorHex: String
    public var activeStrokeWidth: Double
    public var activeFontSize: Double
    public var presets: [ColorPreset]
    public var autoSaveEnabled: Bool
    public var autoSaveDirectoryPath: String
    public var saveFormat: ImageSaveFormat
    public var jpegQuality: Double
    public var maxScrollHeightPx: Int
    public var capacity: Int
    public var launchAtLogin: Bool
    public var language: String
    public var autoPasteOnSelection: Bool
    public var regionHotKeyKeyCode: UInt32
    public var regionHotKeyModifiers: UInt32
    public var scrollHotKeyKeyCode: UInt32
    public var scrollHotKeyModifiers: UInt32
    public var automaticallyCheckForUpdates: Bool
    public var lastUpdateCheckDate: Date?

    public static let `default` = AppSettingsSnapshot(
        activeColorHex: "#FF3B30",
        activeStrokeWidth: 3.0,
        activeFontSize: 18.0,
        presets: ColorPreset.defaults,
        autoSaveEnabled: false,
        autoSaveDirectoryPath: ("~/Pictures/SuperShot" as NSString).expandingTildeInPath,
        saveFormat: .png,
        jpegQuality: 0.9,
        maxScrollHeightPx: 15000,
        capacity: 50,
        launchAtLogin: false,
        language: "system",
        autoPasteOnSelection: true,
        regionHotKeyKeyCode: 1,      // kVK_ANSI_S
        regionHotKeyModifiers: 2048, // optionKey
        scrollHotKeyKeyCode: 1,      // kVK_ANSI_S
        scrollHotKeyModifiers: 2560, // optionKey | shiftKey
        automaticallyCheckForUpdates: true,
        lastUpdateCheckDate: nil
    )
}

/// Observable preferences store managing user configuration and JSON persistence.
public final class AppSettings: ObservableObject {
    public static let maxPresetsCount: Int = 16

    @Published public var activeColorHex: String {
        didSet { scheduleAutoSave() }
    }
    @Published public var activeStrokeWidth: Double {
        didSet {
            let clamped = max(1.0, min(activeStrokeWidth, 30.0))
            if activeStrokeWidth != clamped { activeStrokeWidth = clamped }
            scheduleAutoSave()
        }
    }
    @Published public var activeFontSize: Double {
        didSet {
            let clamped = max(10.0, min(activeFontSize, 96.0))
            if activeFontSize != clamped { activeFontSize = clamped }
            scheduleAutoSave()
        }
    }
    @Published public private(set) var presets: [ColorPreset] {
        didSet { scheduleAutoSave() }
    }
    @Published public var autoSaveEnabled: Bool {
        didSet { scheduleAutoSave() }
    }
    @Published public var autoSaveDirectory: URL {
        didSet { scheduleAutoSave() }
    }
    @Published public var saveFormat: ImageSaveFormat {
        didSet { scheduleAutoSave() }
    }
    @Published public var jpegQuality: Double {
        didSet {
            let clamped = max(0.1, min(jpegQuality, 1.0))
            if jpegQuality != clamped { jpegQuality = clamped }
            scheduleAutoSave()
        }
    }
    @Published public var maxScrollHeightPx: Int {
        didSet {
            let clamped = max(5000, min(maxScrollHeightPx, 30000))
            if maxScrollHeightPx != clamped { maxScrollHeightPx = clamped }
            scheduleAutoSave()
        }
    }
    @Published public var capacity: Int {
        didSet {
            let clamped = max(10, min(capacity, 500))
            if capacity != clamped { capacity = clamped }
            scheduleAutoSave()
        }
    }
    @Published public var launchAtLogin: Bool {
        didSet { scheduleAutoSave() }
    }
    @Published public var language: String {
        didSet { scheduleAutoSave() }
    }
    @Published public var autoPasteOnSelection: Bool {
        didSet { scheduleAutoSave() }
    }
    @Published public var regionHotKeyKeyCode: UInt32 {
        didSet { scheduleAutoSave() }
    }
    @Published public var regionHotKeyModifiers: UInt32 {
        didSet { scheduleAutoSave() }
    }
    @Published public var scrollHotKeyKeyCode: UInt32 {
        didSet { scheduleAutoSave() }
    }
    @Published public var scrollHotKeyModifiers: UInt32 {
        didSet { scheduleAutoSave() }
    }
    @Published public var automaticallyCheckForUpdates: Bool {
        didSet { scheduleAutoSave() }
    }
    @Published public var lastUpdateCheckDate: Date? {
        didSet { scheduleAutoSave() }
    }

    public let settingsURL: URL
    private let fileQueue = DispatchQueue(label: "com.supershot.settings.fileio", qos: .utility)
    private var saveDebounceTimer: DispatchWorkItem?

    public init(settingsURL: URL? = nil, initialSnapshot: AppSettingsSnapshot? = nil) {
        let defaultURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SuperShot", isDirectory: true)
            .appendingPathComponent("settings.json")
        let targetURL = settingsURL ?? defaultURL
        self.settingsURL = targetURL

        let snapshot: AppSettingsSnapshot
        if let initial = initialSnapshot {
            snapshot = initial
        } else if FileManager.default.fileExists(atPath: targetURL.path),
                  let data = try? Data(contentsOf: targetURL),
                  let loaded = try? JSONDecoder().decode(AppSettingsSnapshot.self, from: data) {
            snapshot = loaded
        } else {
            snapshot = .default
        }

        self.activeColorHex = ColorPreset.normalize(hex: snapshot.activeColorHex)
        self.activeStrokeWidth = max(1.0, min(snapshot.activeStrokeWidth, 30.0))
        self.activeFontSize = max(10.0, min(snapshot.activeFontSize, 96.0))
        self.presets = Array(snapshot.presets.prefix(AppSettings.maxPresetsCount))
        self.autoSaveEnabled = snapshot.autoSaveEnabled
        self.autoSaveDirectory = URL(fileURLWithPath: snapshot.autoSaveDirectoryPath, isDirectory: true)
        self.saveFormat = snapshot.saveFormat
        self.jpegQuality = max(0.1, min(snapshot.jpegQuality, 1.0))
        self.maxScrollHeightPx = max(5000, min(snapshot.maxScrollHeightPx, 30000))
        self.capacity = max(10, min(snapshot.capacity, 500))
        self.launchAtLogin = snapshot.launchAtLogin
        self.language = snapshot.language
        self.autoPasteOnSelection = snapshot.autoPasteOnSelection
        self.regionHotKeyKeyCode = snapshot.regionHotKeyKeyCode
        self.regionHotKeyModifiers = snapshot.regionHotKeyModifiers
        self.scrollHotKeyKeyCode = snapshot.scrollHotKeyKeyCode
        self.scrollHotKeyModifiers = snapshot.scrollHotKeyModifiers
        self.automaticallyCheckForUpdates = snapshot.automaticallyCheckForUpdates
        self.lastUpdateCheckDate = snapshot.lastUpdateCheckDate
    }

    // MARK: - Presets Management

    /// Adds a new color preset or updates an existing preset's name in-place if the hex already exists.
    /// Returns false if preset count is already at the 16 maximum limit and the preset does not already exist.
    @discardableResult
    public func addPreset(_ preset: ColorPreset) -> Bool {
        let normalizedHex = ColorPreset.normalize(hex: preset.hex)
        // If color hex already exists in presets, update its name instead of duplicating
        if let index = presets.firstIndex(where: { $0.hex.caseInsensitiveCompare(normalizedHex) == .orderedSame }) {
            presets[index].name = preset.name
            return true
        }
        guard presets.count < AppSettings.maxPresetsCount else {
            return false
        }
        let newPreset = ColorPreset(id: preset.id, name: preset.name, hex: normalizedHex)
        presets.append(newPreset)
        return true
    }

    /// Deletes a preset by UUID. Returns false if not found.
    @discardableResult
    public func deletePreset(id: UUID) -> Bool {
        guard let index = presets.firstIndex(where: { $0.id == id }) else {
            return false
        }
        presets.remove(at: index)
        return true
    }

    /// Resets presets to the 8 standard high-contrast defaults.
    public func resetPresets() {
        presets = ColorPreset.defaults
    }

    // MARK: - Snapshot & Persistence

    public func makeSnapshot() -> AppSettingsSnapshot {
        AppSettingsSnapshot(
            activeColorHex: activeColorHex,
            activeStrokeWidth: activeStrokeWidth,
            activeFontSize: activeFontSize,
            presets: presets,
            autoSaveEnabled: autoSaveEnabled,
            autoSaveDirectoryPath: autoSaveDirectory.path,
            saveFormat: saveFormat,
            jpegQuality: jpegQuality,
            maxScrollHeightPx: maxScrollHeightPx,
            capacity: capacity,
            launchAtLogin: launchAtLogin,
            language: language,
            autoPasteOnSelection: autoPasteOnSelection,
            regionHotKeyKeyCode: regionHotKeyKeyCode,
            regionHotKeyModifiers: regionHotKeyModifiers,
            scrollHotKeyKeyCode: scrollHotKeyKeyCode,
            scrollHotKeyModifiers: scrollHotKeyModifiers,
            automaticallyCheckForUpdates: automaticallyCheckForUpdates,
            lastUpdateCheckDate: lastUpdateCheckDate
        )
    }

    public func saveSynchronously(to url: URL? = nil) throws {
        let target = url ?? settingsURL
        let dir = target.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let snapshot = makeSnapshot()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: target, options: .atomic)
    }

    private func scheduleAutoSave() {
        saveDebounceTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            try? self.saveSynchronously()
        }
        saveDebounceTimer = item
        fileQueue.asyncAfter(deadline: .now() + 0.1, execute: item)
    }

    public func flushDiskQueue() {
        fileQueue.sync {}
    }
}
