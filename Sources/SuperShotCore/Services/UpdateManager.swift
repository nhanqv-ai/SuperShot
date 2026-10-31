import Foundation
import AppKit
import Combine
import UserNotifications

/// Representation of a parsed semantic version (e.g. v1.0.3, 1.0.0, 1.0.0-beta.1).
public struct SemanticVersion: Comparable, Equatable, Sendable {
    public let components: [Int]
    public let prerelease: String?
    public let raw: String

    public init(_ versionString: String) {
        let trimmed = versionString.trimmingCharacters(in: .whitespacesAndNewlines)
        self.raw = trimmed

        var clean = trimmed
        if clean.lowercased().hasPrefix("v") {
            clean = String(clean.dropFirst())
        }

        // SemVer 2.0.0: strip build metadata (+...) first, as it must be ignored in precedence
        let buildParts = clean.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: true)
        let versionWithoutBuild = buildParts.first.map(String.init) ?? clean

        let parts = versionWithoutBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)
        let mainPart = parts.first ?? ""
        if parts.count > 1 {
            self.prerelease = String(parts[1])
        } else {
            self.prerelease = nil
        }

        let numParts = mainPart.split(separator: ".").compactMap { Int($0) }
        self.components = numParts.isEmpty ? [0] : numParts
    }

    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let maxCount = max(lhs.components.count, rhs.components.count)
        for i in 0..<maxCount {
            let left = i < lhs.components.count ? lhs.components[i] : 0
            let right = i < rhs.components.count ? rhs.components[i] : 0
            if left != right { return false }
        }
        return lhs.prerelease == rhs.prerelease
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let maxCount = max(lhs.components.count, rhs.components.count)
        for i in 0..<maxCount {
            let left = i < lhs.components.count ? lhs.components[i] : 0
            let right = i < rhs.components.count ? rhs.components[i] : 0
            if left < right { return true }
            if left > right { return false }
        }

        // Standard SemVer: version with prerelease has lower precedence than release without prerelease
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil):
            return false
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case let (.some(lp), .some(rp)):
            return lp.localizedStandardCompare(rp) == .orderedAscending
        }
    }
}

/// Metadata model for a discovered GitHub Release.
public struct ReleaseInfo: Codable, Equatable, Sendable {
    public let tagName: String
    public let name: String
    public let releaseNotes: String
    public let htmlURL: URL
    public let zipAssetURL: URL?
    public let dmgAssetURL: URL?

    public var preferredAssetURL: URL? {
        zipAssetURL ?? dmgAssetURL
    }

    public var versionString: String {
        let trimmed = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("v") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    public init(
        tagName: String,
        name: String,
        releaseNotes: String,
        htmlURL: URL,
        zipAssetURL: URL? = nil,
        dmgAssetURL: URL? = nil
    ) {
        self.tagName = tagName
        self.name = name
        self.releaseNotes = releaseNotes
        self.htmlURL = htmlURL
        self.zipAssetURL = zipAssetURL
        self.dmgAssetURL = dmgAssetURL
    }

    enum CodingKeys: String, CodingKey {
        case tagName
        case name
        case releaseNotes
        case htmlURL
        case zipAssetURL
        case dmgAssetURL
    }
}

/// State of update checking, downloading, and staging.
public enum UpdateStatus: Equatable, Sendable {
    case idle
    case checking
    case upToDate(currentVersion: String)
    case updateAvailable(ReleaseInfo)
    case downloading(progress: Double)
    case readyToRestart(ReleaseInfo)
    case error(message: String)
}

/// Errors occurring during update operations.
public enum UpdateError: LocalizedError, Equatable {
    case invalidReleaseData
    case noAssetFound
    case noReleaseFound
    case rateLimitExceeded
    case httpError(Int)
    case downloadFailed(String)
    case unpackFailed(String)
    case appBundleNotFound
    case binaryNotExecutable
    case signatureVerificationFailed
    case stagingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidReleaseData:
            return "Failed to parse release information from GitHub API."
        case .noAssetFound:
            return "No compatible application zip asset found in release."
        case .noReleaseFound:
            return "No releases found on GitHub."
        case .rateLimitExceeded:
            return "GitHub API rate limit exceeded. Please try again later."
        case .httpError(let code):
            return "GitHub API returned HTTP status \(code)."
        case .downloadFailed(let reason):
            return "Failed to download update: \(reason)"
        case .unpackFailed(let reason):
            return "Failed to unpack application zip: \(reason)"
        case .appBundleNotFound:
            return "SuperShot.app bundle was not found in unpacked archive."
        case .binaryNotExecutable:
            return "SuperShot executable inside bundle is missing or not executable."
        case .signatureVerificationFailed:
            return "Code signature verification failed."
        case .stagingFailed(let reason):
            return "Failed to stage application into destination: \(reason)"
        }
    }
}

/// Centralized manager for GitHub releases update checking, silent download, and staging.
public final class UpdateManager: ObservableObject, @unchecked Sendable {
    public static let shared = UpdateManager()

    // MARK: - Published State

    @Published public var status: UpdateStatus = .idle
    @Published public var hasPendingUpdate: Bool = false
    @Published public var isBannerDismissedForSession: Bool = false
    @Published public var downloadProgress: Double = 0.0
    @Published public var latestRelease: ReleaseInfo? = nil
    @Published public var stagedAppURL: URL? = nil

    // MARK: - Configuration & Dependencies

    private var _customVersion: String? = nil
    public var currentVersion: String {
        get {
            _customVersion ?? (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.34")
        }
        set {
            _customVersion = newValue
        }
    }

    public var apiURL: URL = URL(string: "https://api.github.com/repos/nhanqv-ai/SuperShot/releases/latest")!
    public var webReleasesLatestURL: URL = URL(string: "https://github.com/nhanqv-ai/SuperShot/releases/latest")!
    public var enableWebFallbackOnRateLimit: Bool = true
    public var githubToken: String? = {
        let env = ProcessInfo.processInfo.environment
        if let token = env["GITHUB_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            return token
        }
        if let token = env["GH_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            return token
        }
        if let token = UserDefaults.standard.string(forKey: "GitHubAPIToken")?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            return token
        }
        return nil
    }()
    private var _customStagingTargetURL: URL? = nil
    public var stagingTargetURL: URL {
        get {
            if let custom = _customStagingTargetURL {
                return custom
            }
            if Bundle.main.bundleURL.pathExtension.lowercased() == "app" {
                return Bundle.main.bundleURL
            }
            return URL(fileURLWithPath: "/Applications/SuperShot.app")
        }
        set {
            _customStagingTargetURL = newValue
        }
    }
    public var verifyCodeSignature: Bool = true

    private var _customAppLauncher: ((URL) -> Void)? = nil
    public var appLauncher: (URL) -> Void {
        get {
            if let custom = _customAppLauncher {
                return custom
            }
            return { [weak self] targetURL in
                guard let self = self else { return }
                var terminated = false
                let lock = NSLock()
                let doTerminate = {
                    lock.lock()
                    defer { lock.unlock() }
                    guard !terminated else { return }
                    terminated = true
                    DispatchQueue.main.async {
                        self.terminationHandler()
                    }
                }

                // 3.0s fallback timer
                let fallbackTimer = DispatchSource.makeTimerSource(queue: .main)
                fallbackTimer.schedule(deadline: .now() + 3.0)
                fallbackTimer.setEventHandler {
                    doTerminate()
                }
                fallbackTimer.resume()

                let config = NSWorkspace.OpenConfiguration()
                config.createsNewApplicationInstance = true
                NSWorkspace.shared.openApplication(at: targetURL, configuration: config) { _, _ in
                    fallbackTimer.cancel()
                    doTerminate()
                }
            }
        }
        set {
            _customAppLauncher = newValue
        }
    }
    public var terminationHandler: () -> Void = {
        NSApp?.terminate(nil)
    }

    public var urlSession: URLSession
    public weak var appSettings: AppSettings?
    private var periodicTimer: Timer?
    private let lock = NSRecursiveLock()
    private var isCheckTaskInFlight: Bool = false
    private var isCheckUserInitiated: Bool = false
    private var pendingCheckCompletions: [((Result<ReleaseInfo?, Error>) -> Void)] = []
    private var lastETag: String? = nil
    private var lastETagURL: URL? = nil
    private var lastCachedReleaseData: Data? = nil
    private var _activeDownloadTask: URLSessionDownloadTask?
    private var _activeDownloadDir: URL?
    private var _activeDownloadDelegate: UpdateDownloadDelegate?

    public var activeDownloadTask: URLSessionDownloadTask? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _activeDownloadTask
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _activeDownloadTask = newValue
        }
    }

    public var activeDownloadDir: URL? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _activeDownloadDir
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _activeDownloadDir = newValue
        }
    }


    // MARK: - Computed Properties

    public var hasUpdateAvailable: Bool {
        hasPendingUpdate
    }

    public var isBusy: Bool {
        switch status {
        case .checking, .downloading:
            return true
        default:
            return false
        }
    }

    public var shouldShowBanner: Bool {
        guard !isBannerDismissedForSession else { return false }
        switch status {
        case .updateAvailable, .downloading, .readyToRestart:
            return true
        case .error:
            return latestRelease != nil
        default:
            return false
        }
    }

    // MARK: - Initialization

    public init(session: URLSession? = nil) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 60.0
        self.urlSession = session ?? URLSession(configuration: config)
    }

    deinit {
        stopPeriodicCheck()
    }

    // MARK: - Semantic Version Comparison

    public static func isVersion(_ v1: String, greaterThan v2: String) -> Bool {
        let sem1 = SemanticVersion(v1)
        let sem2 = SemanticVersion(v2)
        return sem1 > sem2
    }

    // MARK: - GitHub Releases API Parsing

    public static func parseRelease(from data: Data) throws -> ReleaseInfo {
        struct GHAsset: Decodable {
            let name: String?
            let browserDownloadUrl: String?

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadUrl = "browser_download_url"
            }
        }

        struct GHRelease: Decodable {
            let tagName: String
            let name: String?
            let body: String?
            let htmlUrl: String?
            let assets: [GHAsset]?

            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name"
                case name
                case body
                case htmlUrl = "html_url"
                case assets
            }
        }

        let decoder = JSONDecoder()
        let release = try decoder.decode(GHRelease.self, from: data)

        let releaseName = release.name ?? release.tagName
        let notes = release.body ?? ""
        let defaultURL = URL(string: "https://github.com/nhanqv-ai/SuperShot/releases")!
        let htmlURL: URL
        if let raw = release.htmlUrl, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let parsed = URL(string: raw) {
            htmlURL = parsed
        } else {
            htmlURL = defaultURL
        }

        var zipURL: URL? = nil
        var dmgURL: URL? = nil
        if let assets = release.assets {
            // Find zip asset matching supershot or ending in .zip
            if let match = assets.first(where: {
                let n = $0.name?.lowercased() ?? ""
                return n.contains("supershot") && n.hasSuffix(".zip")
            }) ?? assets.first(where: { $0.name?.lowercased().hasSuffix(".zip") == true }) {
                if let raw = match.browserDownloadUrl, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let url = URL(string: raw) {
                    zipURL = url
                }
            }

            // Find dmg asset matching supershot or ending in .dmg
            if let match = assets.first(where: {
                let n = $0.name?.lowercased() ?? ""
                return n.contains("supershot") && n.hasSuffix(".dmg")
            }) ?? assets.first(where: { $0.name?.lowercased().hasSuffix(".dmg") == true }) {
                if let raw = match.browserDownloadUrl, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let url = URL(string: raw) {
                    dmgURL = url
                }
            }
        }

        return ReleaseInfo(
            tagName: release.tagName,
            name: releaseName,
            releaseNotes: notes,
            htmlURL: htmlURL,
            zipAssetURL: zipURL,
            dmgAssetURL: dmgURL
        )
    }

    public static func parseReleaseFromWebRedirectURL(_ redirectURL: URL) -> ReleaseInfo? {
        let path = redirectURL.path
        guard let range = path.range(of: "/releases/tag/") else { return nil }
        let rawTag = String(path[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "/ \t\n\r"))
        let tag = (rawTag.removingPercentEncoding ?? rawTag).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return nil }

        let htmlURL = URL(string: "https://github.com/nhanqv-ai/SuperShot/releases/tag/\(tag)") ?? redirectURL
        let zipURL = URL(string: "https://github.com/nhanqv-ai/SuperShot/releases/download/\(tag)/SuperShot-\(tag).zip")
        let dmgURL = URL(string: "https://github.com/nhanqv-ai/SuperShot/releases/download/\(tag)/SuperShot-\(tag).dmg")
        return ReleaseInfo(
            tagName: tag,
            name: "SuperShot \(tag)",
            releaseNotes: "",
            htmlURL: htmlURL,
            zipAssetURL: zipURL,
            dmgAssetURL: dmgURL
        )
    }

    private func fetchLatestReleaseViaWebRedirect(completion: @escaping (ReleaseInfo?) -> Void) {
        var request = URLRequest(url: webReleasesLatestURL)
        request.httpMethod = "HEAD"
        let sanitizedVersion = currentVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        request.setValue("SuperShot/\(sanitizedVersion) (macOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15.0

        let task = urlSession.dataTask(with: request) { _, response, error in
            guard error == nil, let httpResponse = response as? HTTPURLResponse else {
                completion(nil)
                return
            }

            if let location = httpResponse.value(forHTTPHeaderField: "Location"),
               let locationURL = URL(string: location, relativeTo: self.webReleasesLatestURL)?.absoluteURL,
               let release = Self.parseReleaseFromWebRedirectURL(locationURL) {
                completion(release)
                return
            }

            if (200...399).contains(httpResponse.statusCode),
               let finalURL = httpResponse.url,
               let release = Self.parseReleaseFromWebRedirectURL(finalURL) {
                completion(release)
                return
            }

            completion(nil)
        }
        task.resume()
    }

    // MARK: - Checking for Updates

    @discardableResult
    public func checkForUpdates(userInitiated: Bool = true) async throws -> ReleaseInfo? {
        try await withCheckedThrowingContinuation { continuation in
            self.checkForUpdates(userInitiated: userInitiated) { result in
                continuation.resume(with: result)
            }
        }
    }

    public func checkForUpdates(userInitiated: Bool = false, completion: ((Result<ReleaseInfo?, Error>) -> Void)? = nil) {
        lock.lock()
        if case .downloading = status {
            let rel = latestRelease
            lock.unlock()
            completion?(.success(rel))
            return
        }

        if isCheckTaskInFlight {
            if userInitiated {
                isCheckUserInitiated = true
            }
            if let completion = completion {
                pendingCheckCompletions.append(completion)
            }
            lock.unlock()
            return
        }

        if case .checking = status {
            let rel = latestRelease
            lock.unlock()
            completion?(.success(rel))
            return
        }

        // If an update is already downloaded and staged, background checks should not disturb it
        if !userInitiated, case .readyToRestart(let release) = status {
            lock.unlock()
            completion?(.success(release))
            return
        }

        let previousStatus = self.status
        isCheckTaskInFlight = true
        isCheckUserInitiated = userInitiated
        if let completion = completion {
            pendingCheckCompletions.append(completion)
        }
        let cachedETag = (lastETagURL == apiURL && lastCachedReleaseData != nil) ? lastETag : nil
        lock.unlock()

        if Thread.isMainThread {
            self.status = .checking
        } else {
            DispatchQueue.main.async {
                self.status = .checking
            }
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        let sanitizedVersion = currentVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        request.setValue("SuperShot/\(sanitizedVersion) (macOS)", forHTTPHeaderField: "User-Agent")
        if let token = githubToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let etag = cachedETag, !etag.isEmpty {
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        request.timeoutInterval = 15.0

        let finishCallbacks: (Result<ReleaseInfo?, Error>) -> Void = { [weak self] result in
            guard let self = self else { return }
            self.lock.lock()
            self.isCheckTaskInFlight = false
            self.isCheckUserInitiated = false
            let callbacks = self.pendingCheckCompletions
            self.pendingCheckCompletions.removeAll()
            self.lock.unlock()
            for cb in callbacks {
                cb(result)
            }
        }

        let applyRelease: (ReleaseInfo) -> Void = { [weak self] release in
            guard let self = self else { return }
            self.lock.lock()
            let effectiveUserInitiated = self.isCheckUserInitiated
            self.lock.unlock()
            let isNewer = Self.isVersion(release.tagName, greaterThan: self.currentVersion)
            DispatchQueue.main.async {
                let previousLatestTag = self.latestRelease?.tagName
                if isNewer {
                    self.latestRelease = release
                    // If this release is already staged, preserve readyToRestart state
                    if case .readyToRestart(let staged) = previousStatus, staged.tagName == release.tagName {
                        self.status = previousStatus
                        self.hasPendingUpdate = true
                        if effectiveUserInitiated {
                            self.isBannerDismissedForSession = false
                        }
                        self.updateLastCheckDate()
                        finishCallbacks(.success(release))
                        return
                    }
                    if let stagedURL = self.stagedAppURL,
                       FileManager.default.fileExists(atPath: stagedURL.path),
                       previousLatestTag == release.tagName {
                        self.status = .readyToRestart(release)
                        self.hasPendingUpdate = true
                        self.isBannerDismissedForSession = false
                        self.updateLastCheckDate()
                        finishCallbacks(.success(release))
                        return
                    }

                    self.status = .updateAvailable(release)
                    self.hasPendingUpdate = true
                    self.isBannerDismissedForSession = false
                    self.postUpdateNotification(release: release)
                    self.updateLastCheckDate()
                    finishCallbacks(.success(release))
                } else {
                    if case .readyToRestart = previousStatus {
                        self.status = previousStatus
                        finishCallbacks(.success(nil))
                        return
                    }
                    self.latestRelease = nil
                    self.status = .upToDate(currentVersion: self.currentVersion)
                    self.hasPendingUpdate = false
                    if effectiveUserInitiated {
                        self.postUpToDateNotification(currentVersion: self.currentVersion)
                    }
                    self.updateLastCheckDate()
                    finishCallbacks(.success(nil))
                }
            }
        }

        let task = urlSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    if case .readyToRestart = previousStatus {
                        self.status = previousStatus
                    } else {
                        self.status = .error(message: error.localizedDescription)
                    }
                    finishCallbacks(.failure(error))
                }
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 304 {
                    self.lock.lock()
                    let cachedData = self.lastCachedReleaseData
                    self.lock.unlock()
                    if let cachedData = cachedData, let release = try? Self.parseRelease(from: cachedData) {
                        applyRelease(release)
                        return
                    }
                } else if httpResponse.statusCode == 404 {
                    let err = UpdateError.noReleaseFound
                    DispatchQueue.main.async {
                        if case .readyToRestart = previousStatus {
                            self.status = previousStatus
                        } else {
                            self.status = .error(message: err.localizedDescription)
                        }
                        finishCallbacks(.failure(err))
                    }
                    return
                } else if httpResponse.statusCode == 403 || httpResponse.statusCode == 429 {
                    if self.enableWebFallbackOnRateLimit && self.apiURL.host?.lowercased() == "api.github.com" {
                        self.fetchLatestReleaseViaWebRedirect { fallbackRelease in
                            if let fallbackRelease = fallbackRelease {
                                applyRelease(fallbackRelease)
                            } else {
                                let err = UpdateError.rateLimitExceeded
                                DispatchQueue.main.async {
                                    self.updateLastCheckDate()
                                    if case .readyToRestart = previousStatus {
                                        self.status = previousStatus
                                    } else {
                                        self.status = .error(message: err.localizedDescription)
                                    }
                                    finishCallbacks(.failure(err))
                                }
                            }
                        }
                        return
                    }
                    let err = UpdateError.rateLimitExceeded
                    DispatchQueue.main.async {
                        self.updateLastCheckDate()
                        if case .readyToRestart = previousStatus {
                            self.status = previousStatus
                        } else {
                            self.status = .error(message: err.localizedDescription)
                        }
                        finishCallbacks(.failure(err))
                    }
                    return
                } else if !(200...299).contains(httpResponse.statusCode) {
                    let err = UpdateError.httpError(httpResponse.statusCode)
                    DispatchQueue.main.async {
                        if case .readyToRestart = previousStatus {
                            self.status = previousStatus
                        } else {
                            self.status = .error(message: err.localizedDescription)
                        }
                        finishCallbacks(.failure(err))
                    }
                    return
                }
            }

            guard let data = data else {
                let err = UpdateError.invalidReleaseData
                DispatchQueue.main.async {
                    if case .readyToRestart = previousStatus {
                        self.status = previousStatus
                    } else {
                        self.status = .error(message: err.localizedDescription)
                    }
                    finishCallbacks(.failure(err))
                }
                return
            }

            do {
                let release = try Self.parseRelease(from: data)
                if let httpResponse = response as? HTTPURLResponse,
                   let etag = httpResponse.value(forHTTPHeaderField: "ETag")?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !etag.isEmpty {
                    self.lock.lock()
                    self.lastETag = etag
                    self.lastETagURL = self.apiURL
                    self.lastCachedReleaseData = data
                    self.lock.unlock()
                }
                applyRelease(release)
            } catch {
                DispatchQueue.main.async {
                    if case .readyToRestart = previousStatus {
                        self.status = previousStatus
                    } else {
                        self.status = .error(message: error.localizedDescription)
                    }
                    finishCallbacks(.failure(error))
                }
            }
        }
        task.resume()
    }

    private func updateLastCheckDate() {
        if let appSettings = appSettings {
            appSettings.lastUpdateCheckDate = Date()
        }
    }

    // MARK: - Banner Session Dismissal

    public func dismissBannerForSession() {
        isBannerDismissedForSession = true
    }

    // MARK: - Startup & Periodic Scheduling

    public func checkOnStartupIfNeeded(appSettings: AppSettings) {
        self.appSettings = appSettings
        guard appSettings.automaticallyCheckForUpdates else { return }

        let now = Date()
        if let lastCheck = appSettings.lastUpdateCheckDate {
            let intervalDays = max(1, appSettings.updateCheckIntervalDays)
            let intervalSeconds = Double(intervalDays * 86400)
            if now.timeIntervalSince(lastCheck) < intervalSeconds {
                return
            }
        }

        checkForUpdates(userInitiated: false)
    }

    public func startPeriodicCheck(interval: TimeInterval = 86400, appSettings: AppSettings? = nil) {
        if let appSettings = appSettings {
            self.appSettings = appSettings
        }
        stopPeriodicCheck()

        periodicTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.appSettings?.automaticallyCheckForUpdates ?? true {
                self.checkForUpdates(userInitiated: false)
            }
        }
    }

    public func stopPeriodicCheck() {
        periodicTimer?.invalidate()
        periodicTimer = nil
    }

    // MARK: - Native macOS Notifications

    public func postUpdateNotification(release: ReleaseInfo) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            let send = {
                let content = UNMutableNotificationContent()
                content.title = "SuperShot Update Available"
                content.body = "SuperShot \(release.tagName) is now available."
                content.sound = .default

                let request = UNNotificationRequest(
                    identifier: "com.supershot.update.\(release.tagName)",
                    content: content,
                    trigger: nil
                )
                center.add(request, withCompletionHandler: nil)
            }

            switch settings.authorizationStatus {
            case .authorized, .provisional:
                send()
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { send() }
                }
            default:
                break
            }
        }
    }

    public func postUpToDateNotification(currentVersion: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            let send = {
                let content = UNMutableNotificationContent()
                content.title = "SuperShot is Up to Date"
                content.body = "SuperShot \(currentVersion) is currently the latest version."
                content.sound = .default

                let request = UNNotificationRequest(
                    identifier: "com.supershot.update.uptodate",
                    content: content,
                    trigger: nil
                )
                center.add(request, withCompletionHandler: nil)
            }

            switch settings.authorizationStatus {
            case .authorized, .provisional:
                send()
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { send() }
                }
            default:
                break
            }
        }
    }

    // MARK: - Silent Download & Safe Staging

    public func startDownloadAndInstall(
        release: ReleaseInfo,
        targetURL: URL? = nil,
        autoRestart: Bool = false,
        completion: ((Result<URL, Error>) -> Void)? = nil
    ) {
        lock.lock()
        guard let assetURL = release.preferredAssetURL else {
            self.status = .error(message: UpdateError.noAssetFound.localizedDescription)
            lock.unlock()
            completion?(.failure(UpdateError.noAssetFound))
            return
        }

        if let prevTask = _activeDownloadTask {
            prevTask.cancel()
            _activeDownloadTask = nil
        }
        _activeDownloadDelegate = nil
        if let prevDir = _activeDownloadDir {
            try? FileManager.default.removeItem(at: prevDir)
            _activeDownloadDir = nil
        }

        self.status = .downloading(progress: 0.0)
        self.downloadProgress = 0.0
        defer { lock.unlock() }

        downloadAsset(from: assetURL) { [weak self] progress in
            let applyProgress: () -> Void = { [weak self] in
                guard let self = self else { return }
                self.lock.lock()
                self.downloadProgress = progress
                if case .downloading = self.status {
                    self.status = .downloading(progress: progress)
                }
                self.lock.unlock()
            }
            if Thread.isMainThread {
                applyProgress()
            } else {
                DispatchQueue.main.async(execute: applyProgress)
            }
        } completion: { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let err):
                DispatchQueue.main.async {
                    self.lock.lock()
                    self._activeDownloadTask = nil
                    self._activeDownloadDelegate = nil
                    self._activeDownloadDir = nil
                    if (err as? URLError)?.code == .cancelled {
                        self.lock.unlock()
                        completion?(.failure(err))
                        return
                    }
                    self.status = .error(message: err.localizedDescription)
                    self.lock.unlock()
                    completion?(.failure(err))
                }

            case .success(let downloadedPath):
                DispatchQueue.main.async {
                    self.lock.lock()
                    self._activeDownloadTask = nil
                    self._activeDownloadDelegate = nil
                    self._activeDownloadDir = nil
                    self.lock.unlock()
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    defer {
                        let downloadDir = downloadedPath.deletingLastPathComponent()
                        if downloadDir.lastPathComponent.hasPrefix("SuperShot-Update-") {
                            try? FileManager.default.removeItem(at: downloadDir)
                        } else {
                            try? FileManager.default.removeItem(at: downloadedPath)
                        }
                    }
                    do {
                        let stagedURL = try self.unpackAndVerify(
                            archiveURL: downloadedPath,
                            destinationURL: targetURL ?? self.stagingTargetURL
                        )
                        DispatchQueue.main.async {
                            self.lock.lock()
                            self.stagedAppURL = stagedURL
                            self.status = .readyToRestart(release)
                            self.isBannerDismissedForSession = false
                            self.lock.unlock()
                            completion?(.success(stagedURL))
                            if autoRestart {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                                    self?.restartApp()
                                }
                            }
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.lock.lock()
                            self.status = .error(message: error.localizedDescription)
                            self.lock.unlock()
                            completion?(.failure(error))
                        }
                    }
                }
            }
        }
    }

    private static var activeMountPoints: Set<URL> = []
    private static let mountLock = NSLock()

    /// Forcefully detaches a mounted disk image with retry and unlinks mount directory.
    public static func forceDetachDMG(mountPoint: URL, maxAttempts: Int = 3) {
        for attempt in 1...maxAttempts {
            let detach = Process()
            detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            detach.arguments = ["detach", mountPoint.path, "-force"]
            let detachPipe = Pipe()
            detach.standardOutput = detachPipe
            detach.standardError = detachPipe
            try? detach.run()
            detach.waitUntilExit()
            if detach.terminationStatus == 0 {
                try? FileManager.default.removeItem(at: mountPoint)
                return
            }
            if attempt < maxAttempts {
                Thread.sleep(forTimeInterval: 0.1 * Double(attempt))
            }
        }
        try? FileManager.default.removeItem(at: mountPoint)
    }

    /// Cancels any in-progress update download and cleans up staging resources.
    public func cancelDownload() {
        lock.lock()
        let taskToCancel = _activeDownloadTask
        _activeDownloadTask = nil
        _activeDownloadDelegate = nil
        let dirToRemove = _activeDownloadDir
        _activeDownloadDir = nil
        self.downloadProgress = 0.0
        if let release = self.latestRelease {
            self.status = .updateAvailable(release)
        } else {
            self.status = .idle
        }
        lock.unlock()

        taskToCancel?.cancel()
        if let dir = dirToRemove {
            try? FileManager.default.removeItem(at: dir)
        }

        Self.mountLock.lock()
        let mounts = Array(Self.activeMountPoints)
        Self.activeMountPoints.removeAll()
        Self.mountLock.unlock()
        for mountDir in mounts {
            Self.forceDetachDMG(mountPoint: mountDir)
        }
    }

    @discardableResult
    public func downloadAndInstall(release: ReleaseInfo, targetURL: URL? = nil) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.startDownloadAndInstall(release: release, targetURL: targetURL) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func downloadAsset(
        from url: URL,
        progressHandler: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        if url.isFileURL {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SuperShot-Update-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            self.activeDownloadDir = tempDir
            let dest = tempDir.appendingPathComponent(url.lastPathComponent)
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: url, to: dest)
                progressHandler(1.0)
                completion(.success(dest))
            } catch {
                try? FileManager.default.removeItem(at: tempDir)
                completion(.failure(error))
            }
            return
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SuperShot-Update-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let filename = url.lastPathComponent.isEmpty ? "SuperShot-update.zip" : url.lastPathComponent
        let dest = tempDir.appendingPathComponent(filename)

        let delegate = UpdateDownloadDelegate(
            destinationURL: dest,
            updateManager: self,
            onProgress: progressHandler,
            onCompletion: completion
        )

        let session = URLSession(configuration: self.urlSession.configuration, delegate: delegate, delegateQueue: nil)
        let task = session.downloadTask(with: url)
        lock.lock()
        _activeDownloadDir = tempDir
        _activeDownloadDelegate = delegate
        _activeDownloadTask = task
        lock.unlock()
        task.resume()
    }

    @discardableResult
    public func unpackAndVerify(zipURL: URL, destinationURL: URL? = nil) throws -> URL {
        try unpackAndVerify(archiveURL: zipURL, destinationURL: destinationURL)
    }

    @discardableResult
    public func unpackAndVerify(archiveURL: URL, destinationURL: URL? = nil) throws -> URL {
        let fm = FileManager.default
        let unpackDir = fm.temporaryDirectory.appendingPathComponent("SuperShot-Unpacked-\(UUID().uuidString)")
        try fm.createDirectory(at: unpackDir, withIntermediateDirectories: true)

        defer {
            try? fm.removeItem(at: unpackDir)
        }

        let isDMG = archiveURL.pathExtension.lowercased() == "dmg"
        var foundAppURL: URL? = nil

        if isDMG {
            let mountDir = fm.temporaryDirectory.appendingPathComponent("SuperShot-DMG-\(UUID().uuidString)")
            try fm.createDirectory(at: mountDir, withIntermediateDirectories: true)

            Self.mountLock.lock()
            Self.activeMountPoints.insert(mountDir)
            Self.mountLock.unlock()

            defer {
                Self.forceDetachDMG(mountPoint: mountDir)
                Self.mountLock.lock()
                Self.activeMountPoints.remove(mountDir)
                Self.mountLock.unlock()
            }

            let attach = Process()
            attach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            attach.arguments = ["attach", "-nobrowse", "-readonly", archiveURL.path, "-mountpoint", mountDir.path]
            let attachPipe = Pipe()
            attach.standardOutput = attachPipe
            attach.standardError = attachPipe
            try attach.run()
            attach.waitUntilExit()

            if attach.terminationStatus != 0 {
                throw UpdateError.unpackFailed("hdiutil failed to mount disk image.")
            }

            let topItems = (try? fm.contentsOfDirectory(at: mountDir, includingPropertiesForKeys: nil)) ?? []
            if let topApp = topItems.first(where: { $0.pathExtension == "app" }) {
                foundAppURL = topApp
            } else {
                for item in topItems {
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                        let subItems = (try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)) ?? []
                        if let subApp = subItems.first(where: { $0.pathExtension == "app" }) {
                            foundAppURL = subApp
                            break
                        }
                    }
                }
            }

            guard let discoveredApp = foundAppURL else {
                throw UpdateError.appBundleNotFound
            }

            let stagedCopy = unpackDir.appendingPathComponent(discoveredApp.lastPathComponent)
            try fm.copyItem(at: discoveredApp, to: stagedCopy)
            foundAppURL = stagedCopy
        } else {
            // 1. Unpack with ditto to preserve bundle attributes & code signatures
            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-xk", archiveURL.path, unpackDir.path]
            let dittoPipe = Pipe()
            ditto.standardOutput = dittoPipe
            ditto.standardError = dittoPipe
            try ditto.run()
            ditto.waitUntilExit()

            if ditto.terminationStatus != 0 {
                // Fallback to unzip if ditto returns non-zero
                let unzip = Process()
                unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                unzip.arguments = ["-q", "-o", archiveURL.path, "-d", unpackDir.path]
                let unzipPipe = Pipe()
                unzip.standardOutput = unzipPipe
                unzip.standardError = unzipPipe
                try unzip.run()
                unzip.waitUntilExit()
                if unzip.terminationStatus != 0 {
                    throw UpdateError.unpackFailed("ditto and unzip failed to extract archive.")
                }
            }

            // 2. Discover .app bundle (top-level or in immediate subdirectories)
            let topItems = try fm.contentsOfDirectory(at: unpackDir, includingPropertiesForKeys: nil)
            if let topApp = topItems.first(where: { $0.pathExtension == "app" }) {
                foundAppURL = topApp
            } else {
                for item in topItems {
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                        let subItems = (try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)) ?? []
                        if let subApp = subItems.first(where: { $0.pathExtension == "app" }) {
                            foundAppURL = subApp
                            break
                        }
                    }
                }
            }
        }

        guard let extractedAppURL = foundAppURL else {
            throw UpdateError.appBundleNotFound
        }

        // 3. Verify bundle integrity
        let binaryURL = Bundle(url: extractedAppURL)?.executableURL
            ?? extractedAppURL.appendingPathComponent("Contents/MacOS/SuperShot")
        guard fm.fileExists(atPath: binaryURL.path) && fm.isExecutableFile(atPath: binaryURL.path) else {
            throw UpdateError.binaryNotExecutable
        }

        // 4. Verify code signature
        if verifyCodeSignature {
            let codesign = Process()
            codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            codesign.arguments = ["-v", "--deep", "--strict", extractedAppURL.path]
            let codesignPipe = Pipe()
            codesign.standardOutput = codesignPipe
            codesign.standardError = codesignPipe
            try codesign.run()
            codesign.waitUntilExit()
            if codesign.terminationStatus != 0 {
                throw UpdateError.signatureVerificationFailed
            }
        }

        // 5. Atomically stage into destination
        let target = destinationURL ?? stagingTargetURL
        let targetParent = target.deletingLastPathComponent()

        if !fm.fileExists(atPath: targetParent.path) {
            try fm.createDirectory(at: targetParent, withIntermediateDirectories: true)
        }

        if fm.fileExists(atPath: target.path) {
            let backupName = "SuperShot.app.bak-\(UUID().uuidString)"
            let backupURL = targetParent.appendingPathComponent(backupName)
            do {
                _ = try fm.replaceItemAt(target, withItemAt: extractedAppURL, backupItemName: backupName, options: .usingNewMetadataOnly)
                try? fm.removeItem(at: backupURL)
            } catch {
                do {
                    try fm.moveItem(at: target, to: backupURL)
                } catch {
                    throw UpdateError.stagingFailed(error.localizedDescription)
                }
                do {
                    try fm.copyItem(at: extractedAppURL, to: target)
                    try? fm.removeItem(at: backupURL)
                } catch {
                    try? fm.moveItem(at: backupURL, to: target)
                    throw UpdateError.stagingFailed(error.localizedDescription)
                }
            }
        } else {
            do {
                try fm.copyItem(at: extractedAppURL, to: target)
            } catch {
                throw UpdateError.stagingFailed(error.localizedDescription)
            }
        }

        // 6. Clean quarantine removal on staged bundle
        Self.removeQuarantineAttribute(at: target)

        return target
    }

    /// Removes com.apple.quarantine extended attribute from the application bundle.
    @discardableResult
    public static func removeQuarantineAttribute(at url: URL) -> Bool {
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-r", "-d", "com.apple.quarantine", url.path]
        let pipe = Pipe()
        xattr.standardOutput = pipe
        xattr.standardError = pipe
        do {
            try xattr.run()
            xattr.waitUntilExit()
            return xattr.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - Restart Application

    public func restartApp() {
        let target = stagedAppURL ?? stagingTargetURL
        if let custom = _customAppLauncher {
            custom(target)
            terminationHandler()
        } else {
            appLauncher(target)
        }
    }
}

/// Streaming download delegate reporting progressive byte delivery for application update assets.
public final class UpdateDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    public let destinationURL: URL
    public weak var updateManager: UpdateManager?
    public var onProgress: ((Double) -> Void)?
    public var onCompletion: ((Result<URL, Error>) -> Void)?
    private var hasCompleted = false
    private let lock = NSLock()

    public init(
        destinationURL: URL,
        updateManager: UpdateManager? = nil,
        onProgress: ((Double) -> Void)? = nil,
        onCompletion: ((Result<URL, Error>) -> Void)? = nil
    ) {
        self.destinationURL = destinationURL
        self.updateManager = updateManager
        self.onProgress = onProgress
        self.onCompletion = onCompletion
        super.init()
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = min(1.0, max(0.0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        let updateManager = self.updateManager
        let onProgress = self.onProgress
        let updateBlock: () -> Void = {
            if let mgr = updateManager {
                mgr.downloadProgress = progress
                if case .downloading = mgr.status {
                    mgr.status = .downloading(progress: progress)
                }
            }
            onProgress?(progress)
        }
        if Thread.isMainThread {
            updateBlock()
        } else {
            DispatchQueue.main.async(execute: updateBlock)
        }
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasCompleted else { return }

        let updateManager = self.updateManager
        let onProgress = self.onProgress
        let onCompletion = self.onCompletion
        let destURL = self.destinationURL

        if let response = downloadTask.response as? HTTPURLResponse, !(200...299).contains(response.statusCode) {
            hasCompleted = true
            session.finishTasksAndInvalidate()
            let err = UpdateError.downloadFailed("HTTP error \(response.statusCode)")
            let failBlock: () -> Void = {
                onCompletion?(.failure(err))
            }
            if Thread.isMainThread {
                failBlock()
            } else {
                DispatchQueue.main.async(execute: failBlock)
            }
            return
        }

        do {
            let fm = FileManager.default
            let parentDir = destURL.deletingLastPathComponent()
            if !fm.fileExists(atPath: parentDir.path) {
                try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }
            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            try fm.moveItem(at: location, to: destURL)
            hasCompleted = true
            session.finishTasksAndInvalidate()
            let completeBlock: () -> Void = {
                updateManager?.downloadProgress = 1.0
                onProgress?(1.0)
                onCompletion?(.success(destURL))
            }
            if Thread.isMainThread {
                completeBlock()
            } else {
                DispatchQueue.main.async(execute: completeBlock)
            }
        } catch {
            hasCompleted = true
            session.finishTasksAndInvalidate()
            let failBlock: () -> Void = {
                onCompletion?(.failure(error))
            }
            if Thread.isMainThread {
                failBlock()
            } else {
                DispatchQueue.main.async(execute: failBlock)
            }
        }
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasCompleted else { return }

        if let error = error {
            hasCompleted = true
            let onCompletion = self.onCompletion
            session.finishTasksAndInvalidate()
            let failBlock: () -> Void = {
                onCompletion?(.failure(error))
            }
            if Thread.isMainThread {
                failBlock()
            } else {
                DispatchQueue.main.async(execute: failBlock)
            }
        }
    }
}
