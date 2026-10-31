import Foundation
import AppKit
import SwiftUI
import SuperShotCore
import SuperShot

/// Mock URLProtocol to intercept and stub network responses for UpdateManager testing.
final class MockUpdateURLProtocol: URLProtocol {
    static var mockData: Data?
    static var mockResponse: HTTPURLResponse?
    static var mockError: Error?
    static var lastRequest: URLRequest?

    static func reset() {
        mockData = nil
        mockResponse = nil
        mockError = nil
        lastRequest = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        MockUpdateURLProtocol.lastRequest = request

        if let error = MockUpdateURLProtocol.mockError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let response = MockUpdateURLProtocol.mockResponse
            ?? HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

        if let data = MockUpdateURLProtocol.mockData {
            client?.urlProtocol(self, didLoad: data)
        }

        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Comprehensive unit test suite for SuperShot UpdateManager, SemanticVersion,
/// GitHub release parsing, mock URLSession checking, and safe staging.
public struct UpdateManagerTests {
    public static func run(sandboxDir: URL) {
        TestHarness.startSuite("UpdateManager & GitHub Releases Verification")

        // =========================================================================
        // 1. Semantic Version Parser & Comparator Tests
        // =========================================================================
        TestHarness.assertTrue(
            UpdateManager.isVersion("1.0.3", greaterThan: "1.0.2"),
            "1.0.3 is greater than 1.0.2"
        )
        TestHarness.assertFalse(
            UpdateManager.isVersion("1.0.2", greaterThan: "v1.0.2"),
            "1.0.2 is not greater than v1.0.2"
        )
        TestHarness.assertEqual(
            SemanticVersion("1.0.2"),
            SemanticVersion("v1.0.2"),
            "1.0.2 is equal to v1.0.2"
        )
        TestHarness.assertTrue(
            UpdateManager.isVersion("1.1.0", greaterThan: "1.0.9"),
            "1.1.0 is greater than 1.0.9"
        )
        TestHarness.assertTrue(
            UpdateManager.isVersion("v1.1.0", greaterThan: "1.0.9"),
            "v1.1.0 is greater than 1.0.9"
        )
        TestHarness.assertFalse(
            UpdateManager.isVersion("1.0.3", greaterThan: "1.0.3"),
            "Equal versions 1.0.3 and 1.0.3 return false"
        )
        TestHarness.assertFalse(
            UpdateManager.isVersion("1.0.2", greaterThan: "1.0.3"),
            "Older version 1.0.2 is not greater than 1.0.3"
        )
        TestHarness.assertTrue(
            UpdateManager.isVersion("2.0.0", greaterThan: "1.99.99"),
            "Major increment 2.0.0 is greater than 1.99.99"
        )

        // Prerelease handling
        TestHarness.assertTrue(
            UpdateManager.isVersion("1.0.3", greaterThan: "1.0.3-beta.1"),
            "Full release 1.0.3 is greater than 1.0.3-beta.1"
        )
        TestHarness.assertTrue(
            UpdateManager.isVersion("1.0.3-beta.2", greaterThan: "1.0.3-beta.1"),
            "Prerelease beta.2 is greater than beta.1"
        )
        TestHarness.assertTrue(
            UpdateManager.isVersion("1.0.3-beta", greaterThan: "1.0.3-alpha"),
            "Prerelease beta is greater than alpha"
        )
        TestHarness.assertFalse(
            UpdateManager.isVersion("1.0.3-alpha", greaterThan: "1.0.3-beta"),
            "Prerelease alpha is not greater than beta"
        )

        // Build metadata handling (SemVer 2.0.0: ignored in precedence)
        TestHarness.assertEqual(
            SemanticVersion("1.0.3+20261023"),
            SemanticVersion("1.0.3"),
            "1.0.3 with build metadata equals 1.0.3"
        )
        TestHarness.assertEqual(
            SemanticVersion("1.0.3-beta.1+exp.sha.5114f85"),
            SemanticVersion("1.0.3-beta.1"),
            "1.0.3-beta.1 with build metadata equals 1.0.3-beta.1"
        )

        // Whitespace trimming & component zero-padding
        TestHarness.assertTrue(
            UpdateManager.isVersion("  1.0.4  ", greaterThan: "1.0.3"),
            "Trims surrounding whitespace in version string"
        )
        TestHarness.assertEqual(
            SemanticVersion("1.0"),
            SemanticVersion("1.0.0"),
            "1.0 equals 1.0.0 with component zero-padding"
        )

        // =========================================================================
        // 2. GitHub Releases JSON Parsing with Mock Payloads & Asset Discovery
        // =========================================================================
        let mockValidJSON = """
        {
            "tag_name": "v1.0.4",
            "name": "SuperShot 1.0.4 Release",
            "body": "Fixed update checking and UI polish.",
            "html_url": "https://github.com/nhanqv-ai/SuperShot/releases/tag/v1.0.4",
            "assets": [
                {
                    "name": "SuperShot-v1.0.4.zip",
                    "browser_download_url": "https://github.com/nhanqv-ai/SuperShot/releases/download/v1.0.4/SuperShot-v1.0.4.zip"
                },
                {
                    "name": "source.tar.gz",
                    "browser_download_url": "https://github.com/nhanqv-ai/SuperShot/archive/v1.0.4.tar.gz"
                }
            ]
        }
        """.data(using: .utf8)!

        do {
            let release = try UpdateManager.parseRelease(from: mockValidJSON)
            TestHarness.assertEqual(release.tagName, "v1.0.4", "Parsed tag_name matches v1.0.4")
            TestHarness.assertEqual(release.versionString, "1.0.4", "versionString strips leading v")
            TestHarness.assertEqual(release.name, "SuperShot 1.0.4 Release", "Parsed release name matches")
            TestHarness.assertEqual(release.releaseNotes, "Fixed update checking and UI polish.", "Parsed release notes match")
            TestHarness.assertEqual(
                release.htmlURL.absoluteString,
                "https://github.com/nhanqv-ai/SuperShot/releases/tag/v1.0.4",
                "Parsed html_url matches"
            )
            TestHarness.assertNotNil(release.zipAssetURL, "Discovered zip asset URL")
            TestHarness.assertEqual(
                release.zipAssetURL?.absoluteString,
                "https://github.com/nhanqv-ai/SuperShot/releases/download/v1.0.4/SuperShot-v1.0.4.zip",
                "Selected SuperShot-v1.0.4.zip browser_download_url"
            )
        } catch {
            TestHarness.assertTrue(false, "Failed to parse valid GitHub release JSON: \(error)")
        }

        // Release with no assets
        let mockNoAssetJSON = """
        {
            "tag_name": "v1.0.5",
            "name": "SuperShot 1.0.5",
            "body": "Release notes without assets.",
            "html_url": "https://github.com/nhanqv-ai/SuperShot/releases/tag/v1.0.5",
            "assets": []
        }
        """.data(using: .utf8)!

        do {
            let release = try UpdateManager.parseRelease(from: mockNoAssetJSON)
            TestHarness.assertEqual(release.tagName, "v1.0.5", "Parsed tag_name without assets")
            TestHarness.assertNil(release.zipAssetURL, "zipAssetURL is nil when assets array is empty")
        } catch {
            TestHarness.assertTrue(false, "Failed to parse release without assets: \(error)")
        }

        // Release with empty html_url falls back to default repository URL
        let emptyURLJSON = """
        {
            "tag_name": "v1.0.6",
            "name": "SuperShot 1.0.6",
            "body": "Empty html_url test.",
            "html_url": "",
            "assets": []
        }
        """.data(using: .utf8)!

        do {
            let release = try UpdateManager.parseRelease(from: emptyURLJSON)
            TestHarness.assertEqual(
                release.htmlURL.absoluteString,
                "https://github.com/nhanqv-ai/SuperShot/releases",
                "Empty html_url safely falls back to default releases URL"
            )
        } catch {
            TestHarness.assertTrue(false, "Failed to parse release with empty html_url: \(error)")
        }

        // Malformed JSON throws error
        let malformedJSON = "{ bad_json: true ".data(using: .utf8)!
        var threwOnMalformed = false
        do {
            _ = try UpdateManager.parseRelease(from: malformedJSON)
        } catch {
            threwOnMalformed = true
        }
        TestHarness.assertTrue(threwOnMalformed, "Throws error on malformed release JSON")

        // =========================================================================
        // 3. UpdateManager.checkForUpdates with Mock URLSession / URLProtocol
        // =========================================================================
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockUpdateURLProtocol.self]
        let mockSession = URLSession(configuration: config)

        // 3a: Newer Release Available (v1.0.4 > 1.0.3)
        MockUpdateURLProtocol.reset()
        MockUpdateURLProtocol.mockData = mockValidJSON
        MockUpdateURLProtocol.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.github.com/repos/nhanqv-ai/SuperShot/releases/latest")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )

        let mockMgr = UpdateManager(session: mockSession)
        mockMgr.currentVersion = "1.0.3"

        var checkedRelease: ReleaseInfo? = nil
        var didComplete = false

        mockMgr.checkForUpdates(userInitiated: true) { result in
            if case .success(let rel) = result {
                checkedRelease = rel
            }
            didComplete = true
        }

        let deadlineA = Date().addingTimeInterval(3.0)
        while !didComplete && Date() < deadlineA {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        TestHarness.assertTrue(didComplete, "checkForUpdates completed via MockUpdateURLProtocol")
        TestHarness.assertEqual(checkedRelease?.tagName, "v1.0.4", "Discovered newer release v1.0.4")
        TestHarness.assertTrue(mockMgr.hasPendingUpdate, "hasPendingUpdate is true when newer release discovered")
        if case .updateAvailable(let rel) = mockMgr.status {
            TestHarness.assertEqual(rel.tagName, "v1.0.4", "Status is .updateAvailable with v1.0.4")
        } else {
            TestHarness.assertTrue(false, "Expected status .updateAvailable, got: \(mockMgr.status)")
        }

        // Verify request headers
        TestHarness.assertEqual(
            MockUpdateURLProtocol.lastRequest?.value(forHTTPHeaderField: "Accept"),
            "application/vnd.github.v3+json",
            "Request contains GitHub v3 Accept header"
        )
        TestHarness.assertTrue(
            MockUpdateURLProtocol.lastRequest?.value(forHTTPHeaderField: "User-Agent")?.contains("SuperShot") == true,
            "Request contains SuperShot User-Agent header"
        )

        // 3b: Already Up to Date (v1.0.3 == 1.0.3)
        let upToDateJSON = """
        {
            "tag_name": "v1.0.3",
            "name": "SuperShot 1.0.3",
            "body": "Current version.",
            "html_url": "https://github.com/nhanqv-ai/SuperShot/releases/tag/v1.0.3",
            "assets": []
        }
        """.data(using: .utf8)!

        MockUpdateURLProtocol.reset()
        MockUpdateURLProtocol.mockData = upToDateJSON

        let upToDateMgr = UpdateManager(session: mockSession)
        upToDateMgr.currentVersion = "1.0.3"

        var upToDateCompleted = false
        var upToDateResult: ReleaseInfo? = nil

        upToDateMgr.checkForUpdates(userInitiated: true) { result in
            if case .success(let rel) = result {
                upToDateResult = rel
            }
            upToDateCompleted = true
        }

        let deadlineB = Date().addingTimeInterval(3.0)
        while !upToDateCompleted && Date() < deadlineB {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        TestHarness.assertTrue(upToDateCompleted, "Up-to-date check completed")
        TestHarness.assertNil(upToDateResult, "Result release is nil when already up to date")
        TestHarness.assertFalse(upToDateMgr.hasPendingUpdate, "hasPendingUpdate is false when up to date")
        if case .upToDate(let ver) = upToDateMgr.status {
            TestHarness.assertEqual(ver, "1.0.3", "Status is .upToDate with 1.0.3")
        } else {
            TestHarness.assertTrue(false, "Expected status .upToDate, got: \(upToDateMgr.status)")
        }

        // 3c: HTTP 404 No Release Found
        MockUpdateURLProtocol.reset()
        MockUpdateURLProtocol.mockData = "{}".data(using: .utf8)!
        MockUpdateURLProtocol.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.github.com/repos/nhanqv-ai/SuperShot/releases/latest")!,
            statusCode: 404,
            httpVersion: nil,
            headerFields: [:]
        )

        let notFoundMgr = UpdateManager(session: mockSession)
        notFoundMgr.currentVersion = "1.0.3"

        var notFoundCompleted = false
        var notFoundError: Error? = nil

        notFoundMgr.checkForUpdates(userInitiated: true) { result in
            if case .failure(let err) = result {
                notFoundError = err
            }
            notFoundCompleted = true
        }

        let deadlineC = Date().addingTimeInterval(3.0)
        while !notFoundCompleted && Date() < deadlineC {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        TestHarness.assertTrue(notFoundCompleted, "404 check completed")
        TestHarness.assertNotNil(notFoundError, "Error returned on 404")
        if case .error(let msg) = notFoundMgr.status {
            TestHarness.assertEqual(msg, UpdateError.noReleaseFound.errorDescription, "Status is .error with noReleaseFound message")
        } else {
            TestHarness.assertTrue(false, "Expected status .error, got: \(notFoundMgr.status)")
        }

        // 3d: HTTP 403 Rate Limit Exceeded
        MockUpdateURLProtocol.reset()
        MockUpdateURLProtocol.mockData = "{}".data(using: .utf8)!
        MockUpdateURLProtocol.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.github.com/repos/nhanqv-ai/SuperShot/releases/latest")!,
            statusCode: 403,
            httpVersion: nil,
            headerFields: [:]
        )

        let rateLimitMgr = UpdateManager(session: mockSession)
        rateLimitMgr.currentVersion = "1.0.3"

        var rateLimitCompleted = false
        rateLimitMgr.checkForUpdates(userInitiated: true) { _ in
            rateLimitCompleted = true
        }

        let deadlineD = Date().addingTimeInterval(3.0)
        while !rateLimitCompleted && Date() < deadlineD {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        TestHarness.assertTrue(rateLimitCompleted, "Rate limit check completed")
        if case .error(let msg) = rateLimitMgr.status {
            TestHarness.assertEqual(msg, UpdateError.rateLimitExceeded.errorDescription, "Status is .error with rateLimitExceeded message")
        } else {
            TestHarness.assertTrue(false, "Expected status .error, got: \(rateLimitMgr.status)")
        }

        // 3e: Network Connection Failure
        MockUpdateURLProtocol.reset()
        MockUpdateURLProtocol.mockError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: [NSLocalizedDescriptionKey: "The Internet connection appears to be offline."])

        let networkErrorMgr = UpdateManager(session: mockSession)
        networkErrorMgr.currentVersion = "1.0.3"

        var networkErrorCompleted = false
        networkErrorMgr.checkForUpdates(userInitiated: true) { _ in
            networkErrorCompleted = true
        }

        let deadlineE = Date().addingTimeInterval(3.0)
        while !networkErrorCompleted && Date() < deadlineE {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        TestHarness.assertTrue(networkErrorCompleted, "Network error check completed")
        if case .error = networkErrorMgr.status {
            TestHarness.assertTrue(true, "Status transitioned to .error on network failure")
        } else {
            TestHarness.assertTrue(false, "Expected status .error, got: \(networkErrorMgr.status)")
        }

        // =========================================================================
        // 4. UpdateManager Instance States & Session Dismissal
        // =========================================================================
        let stateMgr = UpdateManager()
        stateMgr.currentVersion = "1.0.3"

        TestHarness.assertEqual(stateMgr.status, .idle, "Initial status is .idle")
        TestHarness.assertFalse(stateMgr.hasPendingUpdate, "Initially hasPendingUpdate is false")
        TestHarness.assertFalse(stateMgr.shouldShowBanner, "Initially shouldShowBanner is false")
        TestHarness.assertFalse(stateMgr.isBannerDismissedForSession, "Initially isBannerDismissedForSession is false")

        let fakeRelease = ReleaseInfo(
            tagName: "v1.0.4",
            name: "SuperShot v1.0.4",
            releaseNotes: "Minor update",
            htmlURL: URL(string: "https://github.com/nhanqv-ai/SuperShot")!,
            zipAssetURL: URL(string: "https://github.com/nhanqv-ai/SuperShot/SuperShot-v1.0.4.zip")
        )

        stateMgr.status = .updateAvailable(fakeRelease)
        stateMgr.hasPendingUpdate = true

        TestHarness.assertTrue(stateMgr.shouldShowBanner, "shouldShowBanner is true when updateAvailable")
        TestHarness.assertTrue(stateMgr.hasPendingUpdate, "hasPendingUpdate is true when updateAvailable")

        stateMgr.dismissBannerForSession()
        TestHarness.assertTrue(stateMgr.isBannerDismissedForSession, "isBannerDismissedForSession is true after dismissal")
        TestHarness.assertFalse(stateMgr.shouldShowBanner, "shouldShowBanner is false after dismissal")
        TestHarness.assertTrue(stateMgr.hasPendingUpdate, "hasPendingUpdate remains true so settings badge dot stays visible")

        // =========================================================================
        // 5. Background Startup Check Logic via AppSettings
        // =========================================================================
        let settingsFile = sandboxDir.appendingPathComponent("UpdateSettingsTest.json")
        let appSettings = AppSettings(settingsURL: settingsFile)

        // When automaticallyCheckForUpdates is false, no check is triggered
        appSettings.automaticallyCheckForUpdates = false

        let dummySession = URLSession(configuration: .ephemeral)
        let startupCheckMgr = UpdateManager(session: dummySession)
        startupCheckMgr.apiURL = URL(string: "https://127.0.0.1:9/invalid")!
        startupCheckMgr.checkOnStartupIfNeeded(appSettings: appSettings)
        TestHarness.assertEqual(startupCheckMgr.status, .idle, "Startup check skipped when automaticallyCheckForUpdates is false")

        // When automaticallyCheckForUpdates is true but checked recently (< 24h)
        appSettings.automaticallyCheckForUpdates = true
        appSettings.lastUpdateCheckDate = Date().addingTimeInterval(-3600) // 1 hour ago
        startupCheckMgr.checkOnStartupIfNeeded(appSettings: appSettings)
        TestHarness.assertEqual(startupCheckMgr.status, .idle, "Startup check skipped when checked within 24 hours")

        // =========================================================================
        // 6. Safe Archive Unpack, Integrity Verification & Atomic Staging
        // =========================================================================
        let stagingDir = sandboxDir.appendingPathComponent("StagingTest")
        try? FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        let mockAppDir = stagingDir.appendingPathComponent("MockSourceApp.app")
        let macosDir = mockAppDir.appendingPathComponent("Contents/MacOS")
        try? FileManager.default.createDirectory(at: macosDir, withIntermediateDirectories: true)

        let mockBinary = macosDir.appendingPathComponent("SuperShot")
        let shellScript = "#!/bin/sh\nexit 0\n"
        try? shellScript.write(to: mockBinary, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mockBinary.path)

        let mockPlist = mockAppDir.appendingPathComponent("Contents/Info.plist")
        let plistData = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\"><dict><key>CFBundleExecutable</key><string>SuperShot</string></dict></plist>"
        try? plistData.write(to: mockPlist, atomically: true, encoding: .utf8)

        // Create zip archive containing MockSourceApp.app
        let zipURL = stagingDir.appendingPathComponent("MockUpdate.zip")
        let zipProcess = Process()
        zipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        zipProcess.arguments = ["-c", "-k", "--keepParent", mockAppDir.path, zipURL.path]
        try? zipProcess.run()
        zipProcess.waitUntilExit()

        TestHarness.assertTrue(FileManager.default.fileExists(atPath: zipURL.path), "Mock update zip successfully created")

        // Unpack, verify, and stage to target location
        let targetAppLocation = stagingDir.appendingPathComponent("Destination/SuperShot.app")
        let stageMgr = UpdateManager()
        stageMgr.verifyCodeSignature = false // Skip signature for mock shell script test binary

        do {
            let stagedURL = try stageMgr.unpackAndVerify(zipURL: zipURL, destinationURL: targetAppLocation)
            TestHarness.assertTrue(
                FileManager.default.fileExists(atPath: stagedURL.path),
                "Application bundle safely staged into destination"
            )
            let binaryPath = stagedURL.appendingPathComponent("Contents/MacOS/SuperShot").path
            TestHarness.assertTrue(
                FileManager.default.isExecutableFile(atPath: binaryPath),
                "Staged application executable is present and executable"
            )
        } catch {
            TestHarness.assertTrue(false, "Unpack and staging threw unexpected error: \(error)")
        }

        // Test restart trigger invokes appLauncher and terminationHandler
        var launcherTarget: URL? = nil
        var terminationCalled = false
        stageMgr.stagedAppURL = targetAppLocation
        stageMgr.appLauncher = { target in launcherTarget = target }
        stageMgr.terminationHandler = { terminationCalled = true }
        stageMgr.restartApp()

        TestHarness.assertEqual(launcherTarget?.path, targetAppLocation.path, "appLauncher called with staged app destination")
        TestHarness.assertTrue(terminationCalled, "terminationHandler called cleanly on restart")

        // =========================================================================
        // 7. Missing Executable Rejection
        // =========================================================================
        let corruptAppDir = stagingDir.appendingPathComponent("CorruptApp.app")
        let corruptContents = corruptAppDir.appendingPathComponent("Contents/MacOS")
        try? FileManager.default.createDirectory(at: corruptContents, withIntermediateDirectories: true)
        // Note: SuperShot executable is intentionally missing

        let corruptZip = stagingDir.appendingPathComponent("Corrupt.zip")
        let corruptDitto = Process()
        corruptDitto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        corruptDitto.arguments = ["-c", "-k", "--keepParent", corruptAppDir.path, corruptZip.path]
        try? corruptDitto.run()
        corruptDitto.waitUntilExit()

        var caughtCorrupt = false
        do {
            _ = try stageMgr.unpackAndVerify(
                zipURL: corruptZip,
                destinationURL: stagingDir.appendingPathComponent("CorruptDest/SuperShot.app")
            )
        } catch UpdateError.binaryNotExecutable {
            caughtCorrupt = true
        } catch {
            // Other error
        }
        TestHarness.assertTrue(caughtCorrupt, "Unpack and verify cleanly rejects corrupt bundle missing executable")

        // =========================================================================
        // 8. Error Descriptions
        // =========================================================================
        TestHarness.assertEqual(UpdateError.noReleaseFound.errorDescription, "No releases found on GitHub.", "noReleaseFound description matches")
        TestHarness.assertEqual(UpdateError.rateLimitExceeded.errorDescription, "GitHub API rate limit exceeded. Please try again later.", "rateLimitExceeded description matches")
        TestHarness.assertEqual(UpdateError.httpError(404).errorDescription, "GitHub API returned HTTP status 404.", "httpError description matches")

        // Notification safety in CLI process (bundleIdentifier is nil)
        stageMgr.postUpdateNotification(release: fakeRelease)
        stageMgr.postUpToDateNotification(currentVersion: "1.0.4")
        TestHarness.assertTrue(true, "Notifications execute safely outside app bundle without crashing")

        // =========================================================================
        // 9. hasUpdateAvailable Computed Property Verification
        // =========================================================================
        let checkAliasMgr = UpdateManager(session: mockSession)
        TestHarness.assertFalse(checkAliasMgr.hasUpdateAvailable, "Initial hasUpdateAvailable is false")
        TestHarness.assertEqual(checkAliasMgr.hasUpdateAvailable, checkAliasMgr.hasPendingUpdate, "hasUpdateAvailable matches hasPendingUpdate initially")

        checkAliasMgr.status = .updateAvailable(fakeRelease)
        checkAliasMgr.hasPendingUpdate = true
        TestHarness.assertTrue(checkAliasMgr.hasUpdateAvailable, "hasUpdateAvailable is true when hasPendingUpdate is true")
        TestHarness.assertEqual(checkAliasMgr.hasUpdateAvailable, checkAliasMgr.hasPendingUpdate, "hasUpdateAvailable accurately mirrors hasPendingUpdate")

        checkAliasMgr.status = .upToDate(currentVersion: "1.0.4")
        checkAliasMgr.hasPendingUpdate = false
        TestHarness.assertFalse(checkAliasMgr.hasUpdateAvailable, "hasUpdateAvailable is false when up to date")

        // =========================================================================
        // 10. Async/Await API Wrappers Verification
        // =========================================================================
        MockUpdateURLProtocol.reset()
        MockUpdateURLProtocol.mockData = mockValidJSON
        MockUpdateURLProtocol.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.github.com/repos/nhanqv-ai/SuperShot/releases/latest")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )
        let asyncUpdateMgr = UpdateManager(session: mockSession)
        asyncUpdateMgr.currentVersion = "1.0.3"

        var asyncFinished = false
        var asyncReleaseResult: ReleaseInfo? = nil
        var asyncErrorResult: Error? = nil

        Task {
            do {
                let release = try await asyncUpdateMgr.checkForUpdates(userInitiated: true)
                asyncReleaseResult = release
            } catch {
                asyncErrorResult = error
            }
            asyncFinished = true
        }

        let asyncDeadline = Date().addingTimeInterval(3.0)
        while !asyncFinished && Date() < asyncDeadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        TestHarness.assertNil(asyncErrorResult, "async checkForUpdates completed without error")
        TestHarness.assertNotNil(asyncReleaseResult, "async checkForUpdates returned release info")
        TestHarness.assertEqual(asyncReleaseResult?.tagName, "v1.0.4", "async checkForUpdates discovered v1.0.4")
        TestHarness.assertTrue(asyncUpdateMgr.hasPendingUpdate, "async checkForUpdates set hasPendingUpdate to true")
        TestHarness.assertTrue(asyncUpdateMgr.hasUpdateAvailable, "async checkForUpdates set hasUpdateAvailable to true")

        // Async download and install using mock local zip
        let asyncStageMgr = UpdateManager(session: mockSession)
        asyncStageMgr.verifyCodeSignature = false
        let asyncDest = stagingDir.appendingPathComponent("AsyncStaged/SuperShot.app")
        var asyncInstallFinished = false
        var asyncStagedURL: URL? = nil
        var asyncInstallError: Error? = nil

        let localZipRelease = ReleaseInfo(
            tagName: "v1.0.4",
            name: "SuperShot v1.0.4",
            releaseNotes: "Local test release",
            htmlURL: fakeRelease.htmlURL,
            zipAssetURL: zipURL
        )

        Task {
            do {
                let staged = try await asyncStageMgr.downloadAndInstall(release: localZipRelease, targetURL: asyncDest)
                asyncStagedURL = staged
            } catch {
                asyncInstallError = error
            }
            asyncInstallFinished = true
        }

        let asyncInstallDeadline = Date().addingTimeInterval(3.0)
        while !asyncInstallFinished && Date() < asyncInstallDeadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        TestHarness.assertNil(asyncInstallError, "async downloadAndInstall completed without error")
        TestHarness.assertEqual(asyncStagedURL?.path, asyncDest.path, "async downloadAndInstall staged to target destination")
        TestHarness.assertTrue(FileManager.default.fileExists(atPath: asyncDest.path), "Async staged application exists at target destination")

        // =========================================================================
        // 11. updateCheckIntervalDays Clamping, Persistence & Startup Scheduling
        // =========================================================================
        let intervalSettingsURL = sandboxDir.appendingPathComponent("interval_settings.json")
        let intervalSettings = AppSettings(settingsURL: intervalSettingsURL)

        TestHarness.assertEqual(intervalSettings.updateCheckIntervalDays, 1, "Default updateCheckIntervalDays is 1 day")

        intervalSettings.updateCheckIntervalDays = 7
        TestHarness.assertEqual(intervalSettings.updateCheckIntervalDays, 7, "updateCheckIntervalDays updated to 7 (weekly)")

        intervalSettings.updateCheckIntervalDays = 30
        TestHarness.assertEqual(intervalSettings.updateCheckIntervalDays, 30, "updateCheckIntervalDays updated to 30 (monthly)")

        // Lower boundary clamping (< 1 -> 1)
        intervalSettings.updateCheckIntervalDays = 0
        TestHarness.assertEqual(intervalSettings.updateCheckIntervalDays, 1, "updateCheckIntervalDays 0 clamped to 1")
        intervalSettings.updateCheckIntervalDays = -10
        TestHarness.assertEqual(intervalSettings.updateCheckIntervalDays, 1, "updateCheckIntervalDays negative clamped to 1")

        // Upper boundary clamping (> 30 -> 30)
        intervalSettings.updateCheckIntervalDays = 31
        TestHarness.assertEqual(intervalSettings.updateCheckIntervalDays, 30, "updateCheckIntervalDays 31 clamped to 30")
        intervalSettings.updateCheckIntervalDays = 365
        TestHarness.assertEqual(intervalSettings.updateCheckIntervalDays, 30, "updateCheckIntervalDays 365 clamped to 30")

        // Persistence round-trip
        intervalSettings.updateCheckIntervalDays = 7
        try? intervalSettings.saveSynchronously()
        let reloadedIntervalSettings = AppSettings(settingsURL: intervalSettingsURL)
        TestHarness.assertEqual(reloadedIntervalSettings.updateCheckIntervalDays, 7, "Reloaded updateCheckIntervalDays persisted as 7")

        // Backward compatibility: decoding older JSON without updateCheckIntervalDays
        let olderJSON = """
        {
            "activeColorHex": "#FF3B30",
            "activeStrokeWidth": 3.0,
            "activeFontSize": 18.0,
            "presets": [],
            "autoSaveEnabled": false,
            "autoSaveDirectoryPath": "/tmp",
            "saveFormat": "png",
            "jpegQuality": 0.9,
            "maxScrollHeightPx": 15000,
            "capacity": 50,
            "launchAtLogin": false,
            "language": "system",
            "autoPasteOnSelection": true,
            "regionHotKeyKeyCode": 1,
            "regionHotKeyModifiers": 2048,
            "scrollHotKeyKeyCode": 1,
            "scrollHotKeyModifiers": 2560,
            "automaticallyCheckForUpdates": true
        }
        """.data(using: .utf8)!

        let decodedOlder = try? JSONDecoder().decode(AppSettingsSnapshot.self, from: olderJSON)
        TestHarness.assertNotNil(decodedOlder, "Successfully decoded older AppSettingsSnapshot without updateCheckIntervalDays")
        TestHarness.assertEqual(decodedOlder?.updateCheckIntervalDays, 1, "Older AppSettingsSnapshot defaulted updateCheckIntervalDays to 1")

        // Startup evaluation with custom intervals
        let startupEvalMgr = UpdateManager(session: mockSession)
        startupEvalMgr.apiURL = URL(string: "https://api.github.com/mock")!

        // Sub-test A: interval = 7 days, checked 3 days ago -> should skip
        intervalSettings.automaticallyCheckForUpdates = true
        intervalSettings.updateCheckIntervalDays = 7
        intervalSettings.lastUpdateCheckDate = Date().addingTimeInterval(-3 * 86400) // 3 days ago

        startupEvalMgr.status = .idle
        startupEvalMgr.checkOnStartupIfNeeded(appSettings: intervalSettings)
        TestHarness.assertEqual(startupEvalMgr.status, .idle, "Startup check skipped when last check (3 days ago) < 7 days interval")

        // Sub-test B: interval = 7 days, checked 8 days ago -> should execute check
        MockUpdateURLProtocol.reset()
        MockUpdateURLProtocol.mockData = mockValidJSON
        intervalSettings.lastUpdateCheckDate = Date().addingTimeInterval(-8 * 86400) // 8 days ago

        startupEvalMgr.status = .idle
        startupEvalMgr.checkOnStartupIfNeeded(appSettings: intervalSettings)
        TestHarness.assertTrue(
            startupEvalMgr.status == .checking || startupEvalMgr.status == .updateAvailable(fakeRelease),
            "Startup check triggered when last check (8 days ago) >= 7 days interval"
        )

        // =========================================================================
        // 12. MainShotView Update Banner View States
        // =========================================================================
        let bannerStorage = StorageManager(baseDirectory: sandboxDir.appendingPathComponent("BannerStorage"), initialCapacity: 10)
        let bannerUpdateMgr = UpdateManager(session: mockSession)
        let mainShotView = MainShotView(
            storageManager: bannerStorage,
            appSettings: intervalSettings,
            updateManager: bannerUpdateMgr
        )

        // State A: Idle (banner should not show)
        bannerUpdateMgr.status = .idle
        TestHarness.assertFalse(bannerUpdateMgr.shouldShowBanner, "shouldShowBanner is false in .idle")

        // State B: Update Available
        bannerUpdateMgr.status = .updateAvailable(fakeRelease)
        bannerUpdateMgr.latestRelease = fakeRelease
        bannerUpdateMgr.hasPendingUpdate = true
        TestHarness.assertTrue(bannerUpdateMgr.shouldShowBanner, "shouldShowBanner is true in .updateAvailable")
        TestHarness.assertTrue(bannerUpdateMgr.hasPendingUpdate, "hasPendingUpdate is true in .updateAvailable")
        let _ = mainShotView.updateBannerView
        TestHarness.assertTrue(true, "MainShotView.updateBannerView renders cleanly for .updateAvailable")

        // State C: Downloading
        bannerUpdateMgr.status = .downloading(progress: 0.5)
        TestHarness.assertTrue(bannerUpdateMgr.shouldShowBanner, "shouldShowBanner is true in .downloading")
        let _ = mainShotView.updateBannerView
        TestHarness.assertTrue(true, "MainShotView.updateBannerView renders cleanly for .downloading")

        // State D: Ready to Restart
        bannerUpdateMgr.status = .readyToRestart(fakeRelease)
        TestHarness.assertTrue(bannerUpdateMgr.shouldShowBanner, "shouldShowBanner is true in .readyToRestart")
        let _ = mainShotView.updateBannerView
        TestHarness.assertTrue(true, "MainShotView.updateBannerView renders cleanly for .readyToRestart")

        // State E: Error with latest release
        bannerUpdateMgr.status = .error(message: "Download Failed")
        TestHarness.assertTrue(bannerUpdateMgr.shouldShowBanner, "shouldShowBanner is true in .error when latestRelease is present")
        let _ = mainShotView.updateBannerView
        TestHarness.assertTrue(true, "MainShotView.updateBannerView renders cleanly for .error")

        // State F: Banner Dismissal for Session
        bannerUpdateMgr.dismissBannerForSession()
        TestHarness.assertFalse(bannerUpdateMgr.shouldShowBanner, "shouldShowBanner is false after dismissBannerForSession")
        TestHarness.assertTrue(bannerUpdateMgr.hasPendingUpdate, "hasPendingUpdate remains true after banner dismissal so gear badge dot stays visible")

        // =========================================================================
        // 14. DMG Asset Parsing, preferredAssetURL, and Streaming UpdateDownloadDelegate (v1.0.22)
        // =========================================================================
        let dmgReleaseJSON = """
        {
            "tag_name": "v1.0.22",
            "name": "SuperShot v1.0.22",
            "body": "Universal 2 DMG and ZIP release",
            "html_url": "https://github.com/nhanqv-ai/SuperShot/releases/tag/v1.0.22",
            "assets": [
                {
                    "name": "SuperShot-v1.0.22.dmg",
                    "browser_download_url": "https://github.com/nhanqv-ai/SuperShot/releases/download/v1.0.22/SuperShot-v1.0.22.dmg"
                },
                {
                    "name": "SuperShot-v1.0.22.zip",
                    "browser_download_url": "https://github.com/nhanqv-ai/SuperShot/releases/download/v1.0.22/SuperShot-v1.0.22.zip"
                }
            ]
        }
        """.data(using: .utf8)!

        let parsedDmgAndZip = try! UpdateManager.parseRelease(from: dmgReleaseJSON)
        TestHarness.assertNotNil(parsedDmgAndZip.zipAssetURL, "parseRelease discovered zipAssetURL")
        TestHarness.assertNotNil(parsedDmgAndZip.dmgAssetURL, "parseRelease discovered dmgAssetURL")
        TestHarness.assertEqual(
            parsedDmgAndZip.preferredAssetURL?.absoluteString,
            "https://github.com/nhanqv-ai/SuperShot/releases/download/v1.0.22/SuperShot-v1.0.22.zip",
            "preferredAssetURL prioritizes zip when both exist"
        )

        // Test release with ONLY dmg asset
        let dmgOnlyJSON = """
        {
            "tag_name": "v1.0.22",
            "name": "SuperShot v1.0.22 DMG Only",
            "body": "Standalone disk image release",
            "html_url": "https://github.com/nhanqv-ai/SuperShot/releases/tag/v1.0.22",
            "assets": [
                {
                    "name": "SuperShot-v1.0.22.dmg",
                    "browser_download_url": "https://github.com/nhanqv-ai/SuperShot/releases/download/v1.0.22/SuperShot-v1.0.22.dmg"
                }
            ]
        }
        """.data(using: .utf8)!

        let parsedDmgOnly = try! UpdateManager.parseRelease(from: dmgOnlyJSON)
        TestHarness.assertNil(parsedDmgOnly.zipAssetURL, "zipAssetURL is nil for DMG-only release")
        TestHarness.assertNotNil(parsedDmgOnly.dmgAssetURL, "dmgAssetURL is discovered for DMG-only release")
        TestHarness.assertEqual(
            parsedDmgOnly.preferredAssetURL?.absoluteString,
            "https://github.com/nhanqv-ai/SuperShot/releases/download/v1.0.22/SuperShot-v1.0.22.dmg",
            "preferredAssetURL falls back to dmgAssetURL when zip is absent"
        )

        // Test streaming UpdateDownloadDelegate byte reporting
        let testDest = sandboxDir.appendingPathComponent("DelegateTest/SuperShot-test.zip")
        let streamingMgr = UpdateManager()
        var reportedProgress: [Double] = []

        let delegate = UpdateDownloadDelegate(
            destinationURL: testDest,
            updateManager: streamingMgr,
            onProgress: { p in
                reportedProgress.append(p)
            }
        )

        let streamTestSession = URLSession.shared
        let streamTestTask = streamTestSession.downloadTask(with: URL(string: "https://example.com/asset.zip")!)

        // 25% progress event
        delegate.urlSession(streamTestSession, downloadTask: streamTestTask, didWriteData: 250, totalBytesWritten: 250, totalBytesExpectedToWrite: 1000)
        // 100% progress event
        delegate.urlSession(streamTestSession, downloadTask: streamTestTask, didWriteData: 750, totalBytesWritten: 1000, totalBytesExpectedToWrite: 1000)

        // Pump main run loop to process dispatched blocks
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))

        TestHarness.assertTrue(reportedProgress.contains(where: { abs($0 - 0.25) < 0.001 }), "Delegate reported 0.25 progress")
        TestHarness.assertTrue(reportedProgress.contains(where: { abs($0 - 1.0) < 0.001 }), "Delegate reported 1.0 progress")

        // Dynamic stagingTargetURL tests
        let dynamicMgr = UpdateManager()
        TestHarness.assertTrue(dynamicMgr.stagingTargetURL.path.hasSuffix(".app"), "Default stagingTargetURL points to .app bundle")
        let customStaging = sandboxDir.appendingPathComponent("Custom/SuperShot.app")
        dynamicMgr.stagingTargetURL = customStaging
        TestHarness.assertEqual(dynamicMgr.stagingTargetURL.path, customStaging.path, "stagingTargetURL can be customized")

        // Quarantine removal helper test on sandboxed file
        let sampleFile = sandboxDir.appendingPathComponent("quarantine_test.txt")
        try? "test data".write(to: sampleFile, atomically: true, encoding: .utf8)
        let _ = UpdateManager.removeQuarantineAttribute(at: sampleFile)
        TestHarness.assertTrue(FileManager.default.fileExists(atPath: sampleFile.path), "removeQuarantineAttribute safely executes without corrupting file")

        // Web redirect release parsing test (rate-limit fallback)
        let redirectURL = URL(string: "https://github.com/nhanqv-ai/SuperShot/releases/tag/v1.0.33")!
        let parsedRedirect = UpdateManager.parseReleaseFromWebRedirectURL(redirectURL)
        TestHarness.assertEqual(parsedRedirect?.tagName, "v1.0.33", "parseReleaseFromWebRedirectURL extracts v1.0.33 tag")
        TestHarness.assertEqual(
            parsedRedirect?.zipAssetURL?.absoluteString,
            "https://github.com/nhanqv-ai/SuperShot/releases/download/v1.0.33/SuperShot-v1.0.33.zip",
            "parseReleaseFromWebRedirectURL builds canonical zip asset URL"
        )
        TestHarness.assertEqual(
            parsedRedirect?.dmgAssetURL?.absoluteString,
            "https://github.com/nhanqv-ai/SuperShot/releases/download/v1.0.33/SuperShot-v1.0.33.dmg",
            "parseReleaseFromWebRedirectURL builds canonical dmg asset URL"
        )

        // ETag / If-None-Match (HTTP 304 Not Modified) & Authorization: Bearer header test
        class RateLimitResilienceProtocol: URLProtocol {
            static let lock = NSLock()
            static var requestCount = 0
            static var lastIfNoneMatch: String?
            static var lastAuthHeader: String?
            static var statusCode = 200
            static var etagHeader: String? = "\"etag-supershot-1.0.33\""
            static var payload: Data?
            static var simulateRedirectFallback = false

            override class func canInit(with request: URLRequest) -> Bool { true }
            override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
            override func startLoading() {
                Self.lock.lock()
                Self.requestCount += 1
                Self.lastIfNoneMatch = request.value(forHTTPHeaderField: "If-None-Match")
                Self.lastAuthHeader = request.value(forHTTPHeaderField: "Authorization")
                let code = Self.statusCode
                let etag = Self.etagHeader
                let data = Self.payload
                let fallback = Self.simulateRedirectFallback
                Self.lock.unlock()

                if fallback && request.url?.host != "api.github.com" {
                    let redirected = URL(string: "https://github.com/nhanqv-ai/SuperShot/releases/tag/v1.0.33")!
                    let resp = HTTPURLResponse(
                        url: redirected,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Location": redirected.absoluteString]
                    )!
                    client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
                    client?.urlProtocolDidFinishLoading(self)
                    return
                }

                var headers: [String: String] = ["Content-Type": "application/json"]
                if let etag = etag { headers["ETag"] = etag }
                let resp = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: headers)!
                client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
                if code != 304, let data = data {
                    client?.urlProtocol(self, didLoad: data)
                }
                client?.urlProtocolDidFinishLoading(self)
            }
            override func stopLoading() {}
        }

        RateLimitResilienceProtocol.payload = """
        {
            "tag_name": "v1.0.33",
            "name": "SuperShot v1.0.33",
            "body": "Notes",
            "html_url": "https://github.com/nhanqv-ai/SuperShot/releases/tag/v1.0.33",
            "assets": [
                {
                    "name": "SuperShot-v1.0.33.zip",
                    "browser_download_url": "https://github.com/nhanqv-ai/SuperShot/releases/download/v1.0.33/SuperShot-v1.0.33.zip"
                }
            ]
        }
        """.data(using: .utf8)!

        let resilienceConfig = URLSessionConfiguration.ephemeral
        resilienceConfig.protocolClasses = [RateLimitResilienceProtocol.self]
        let resilienceMgr = UpdateManager(session: URLSession(configuration: resilienceConfig))
        resilienceMgr.currentVersion = "1.0.32"
        resilienceMgr.githubToken = "ghp_supershot_token"

        // 1) Initial 200 OK caches ETag and sends Authorization: Bearer
        RateLimitResilienceProtocol.statusCode = 200
        RateLimitResilienceProtocol.simulateRedirectFallback = false
        var etagStep1Done = false
        resilienceMgr.checkForUpdates(userInitiated: true) { _ in etagStep1Done = true }
        let etagDl1 = Date().addingTimeInterval(2.0)
        while !etagStep1Done && Date() < etagDl1 {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        TestHarness.assertEqual(RateLimitResilienceProtocol.lastAuthHeader, "Bearer ghp_supershot_token", "checkForUpdates sends Authorization Bearer header when githubToken is set")

        // 2) Subsequent 304 Not Modified sends If-None-Match and reuses cached release
        RateLimitResilienceProtocol.statusCode = 304
        var etagStep2Done = false
        var etagRelease: ReleaseInfo?
        resilienceMgr.checkForUpdates(userInitiated: true) { res in
            if case .success(let rel) = res { etagRelease = rel }
            etagStep2Done = true
        }
        let etagDl2 = Date().addingTimeInterval(2.0)
        while !etagStep2Done && Date() < etagDl2 {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        TestHarness.assertEqual(RateLimitResilienceProtocol.lastIfNoneMatch, "\"etag-supershot-1.0.33\"", "Second check sends If-None-Match with cached ETag")
        TestHarness.assertEqual(etagRelease?.tagName, "v1.0.33", "HTTP 304 reuses cached release metadata")

        // 3) 403 Rate Limit falls back to GitHub web redirect
        let fallbackMgr = UpdateManager(session: URLSession(configuration: resilienceConfig))
        fallbackMgr.currentVersion = "1.0.32"
        RateLimitResilienceProtocol.statusCode = 403
        RateLimitResilienceProtocol.simulateRedirectFallback = true
        var fallbackDone = false
        var fallbackRelease: ReleaseInfo?
        fallbackMgr.checkForUpdates(userInitiated: true) { res in
            if case .success(let rel) = res { fallbackRelease = rel }
            fallbackDone = true
        }
        let fbDl = Date().addingTimeInterval(2.0)
        while !fallbackDone && Date() < fbDl {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        TestHarness.assertEqual(fallbackRelease?.tagName, "v1.0.33", "403 rate limit falls back to web release redirect and resolves v1.0.33")
    }
}
