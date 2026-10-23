import Foundation
import AppKit
import SuperShotCore

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
        stageMgr.postUpToDateNotification(currentVersion: "1.0.3")
        TestHarness.assertTrue(true, "Notifications execute safely outside app bundle without crashing")
    }
}
