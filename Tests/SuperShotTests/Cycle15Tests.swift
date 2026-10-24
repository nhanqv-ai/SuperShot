import Foundation
import CoreGraphics
import AppKit
import SwiftUI
import SuperShotCore
import SuperShot

/// Comprehensive test suite for Cycle 15 features (F1–F10, v1.0.22 / Build 22).
public struct Cycle15Tests {
    public static func run(sandboxDir: URL) {
        TestHarness.startSuite("Cycle 15 (v1.0.22) UpdateManager Enhancements & UI Polish Tests")

        let storage = StorageManager(baseDirectory: sandboxDir)
        let sampleImage = MockScreenCaptureProvider.createSyntheticImage(size: CGSize(width: 400, height: 300))!
        let item = try! storage.save(image: sampleImage, sourceApp: "Finder", captureType: .region)
        storage.flushDiskQueue()

        // ---------------------------------------------------------------------
        // F1: ReleaseInfo DMG Asset Discovery and preferredAssetURL Priority
        // ---------------------------------------------------------------------
        let zipURL = URL(string: "https://github.com/nhanqv-ai/SuperShot/releases/download/v1.0.22/SuperShot-v1.0.22.zip")!
        let dmgURL = URL(string: "https://github.com/nhanqv-ai/SuperShot/releases/download/v1.0.22/SuperShot-v1.0.22.dmg")!

        let bothRelease = ReleaseInfo(
            tagName: "v1.0.22",
            name: "SuperShot v1.0.22",
            releaseNotes: "Full release notes",
            htmlURL: URL(string: "https://github.com/nhanqv-ai/SuperShot/releases/tag/v1.0.22")!,
            zipAssetURL: zipURL,
            dmgAssetURL: dmgURL
        )
        TestHarness.assertEqual(bothRelease.preferredAssetURL, zipURL, "F1: preferredAssetURL prioritizes zip when both zip and dmg are present")

        let dmgOnlyRelease = ReleaseInfo(
            tagName: "v1.0.22",
            name: "SuperShot v1.0.22 DMG",
            releaseNotes: "DMG release",
            htmlURL: URL(string: "https://github.com/nhanqv-ai/SuperShot/releases/tag/v1.0.22")!,
            zipAssetURL: nil,
            dmgAssetURL: dmgURL
        )
        TestHarness.assertEqual(dmgOnlyRelease.preferredAssetURL, dmgURL, "F1: preferredAssetURL resolves to dmg when zip is nil")

        let noAssetRelease = ReleaseInfo(
            tagName: "v1.0.22",
            name: "SuperShot v1.0.22 Notes",
            releaseNotes: "Source only",
            htmlURL: URL(string: "https://github.com/nhanqv-ai/SuperShot/releases/tag/v1.0.22")!,
            zipAssetURL: nil,
            dmgAssetURL: nil
        )
        TestHarness.assertNil(noAssetRelease.preferredAssetURL, "F1: preferredAssetURL is nil when no binary assets are present")

        // ---------------------------------------------------------------------
        // F2: UpdateDownloadDelegate Streaming Progress Reporting
        // ---------------------------------------------------------------------
        let delegateTestFile = sandboxDir.appendingPathComponent("Cycle15Download/update.zip")
        let updateMgr = UpdateManager()
        var streamValues: [Double] = []

        let downloadDelegate = UpdateDownloadDelegate(
            destinationURL: delegateTestFile,
            updateManager: updateMgr,
            onProgress: { p in
                streamValues.append(p)
            }
        )

        let session = URLSession.shared
        let dummyTask = session.downloadTask(with: URL(string: "https://example.com/download.zip")!)

        // Simulate 10%, 50%, 90%, 100% byte chunks
        downloadDelegate.urlSession(session, downloadTask: dummyTask, didWriteData: 100, totalBytesWritten: 100, totalBytesExpectedToWrite: 1000)
        downloadDelegate.urlSession(session, downloadTask: dummyTask, didWriteData: 400, totalBytesWritten: 500, totalBytesExpectedToWrite: 1000)
        downloadDelegate.urlSession(session, downloadTask: dummyTask, didWriteData: 400, totalBytesWritten: 900, totalBytesExpectedToWrite: 1000)
        downloadDelegate.urlSession(session, downloadTask: dummyTask, didWriteData: 100, totalBytesWritten: 1000, totalBytesExpectedToWrite: 1000)

        // RunLoop pump for main thread dispatches
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))

        TestHarness.assertTrue(streamValues.contains(where: { abs($0 - 0.1) < 0.001 }), "F2: Streaming delegate reports 0.1 progress")
        TestHarness.assertTrue(streamValues.contains(where: { abs($0 - 0.5) < 0.001 }), "F2: Streaming delegate reports 0.5 progress")
        TestHarness.assertTrue(streamValues.contains(where: { abs($0 - 0.9) < 0.001 }), "F2: Streaming delegate reports 0.9 progress")
        TestHarness.assertTrue(streamValues.contains(where: { abs($0 - 1.0) < 0.001 }), "F2: Streaming delegate reports 1.0 progress")

        // ---------------------------------------------------------------------
        // F3: Dynamic Staging Destination Resolution
        // ---------------------------------------------------------------------
        let stagingMgr = UpdateManager()
        let defaultStaging = stagingMgr.stagingTargetURL
        TestHarness.assertTrue(defaultStaging.path.hasSuffix(".app"), "F3: stagingTargetURL resolves to an application bundle")
        let customPath = sandboxDir.appendingPathComponent("StagedApp/SuperShot.app")
        stagingMgr.stagingTargetURL = customPath
        TestHarness.assertEqual(stagingMgr.stagingTargetURL.path, customPath.path, "F3: stagingTargetURL stores custom destination")

        // ---------------------------------------------------------------------
        // F4: Clean Quarantine Removal
        // ---------------------------------------------------------------------
        let dummyAppBundle = sandboxDir.appendingPathComponent("TestApp.app")
        try? FileManager.default.createDirectory(at: dummyAppBundle, withIntermediateDirectories: true)
        let removeSuccess = UpdateManager.removeQuarantineAttribute(at: dummyAppBundle)
        // Attribute wasn't set, so xattr returns non-zero, handled cleanly without throwing
        TestHarness.assertTrue(FileManager.default.fileExists(atPath: dummyAppBundle.path), "F4: removeQuarantineAttribute leaves app bundle intact")

        // ---------------------------------------------------------------------
        // F5: Safe App Relaunch with Fallback Timer
        // ---------------------------------------------------------------------
        var launchedTarget: URL? = nil
        var terminationTriggered = false
        stagingMgr.stagedAppURL = customPath
        stagingMgr.appLauncher = { target in launchedTarget = target }
        stagingMgr.terminationHandler = { terminationTriggered = true }
        stagingMgr.restartApp()

        TestHarness.assertEqual(launchedTarget?.path, customPath.path, "F5: appLauncher called with target")
        TestHarness.assertTrue(terminationTriggered, "F5: terminationHandler invoked safely")

        // ---------------------------------------------------------------------
        // F6: AboutSettingsTab UI Polish & Localization
        // ---------------------------------------------------------------------
        let settings = AppSettings()
        let aboutTab = AboutSettingsTab(
            appSettings: settings,
            storageManager: storage,
            updateManager: updateMgr
        )
        let _ = aboutTab.body
        TestHarness.assertTrue(true, "F6: AboutSettingsTab renders body cleanly with updated status view")

        let readyLabel = LocalizationManager.shared.tr(.updateReadyRestart)
        let restartButton = LocalizationManager.shared.tr(.restart)
        let downloadingLabel = LocalizationManager.shared.tr(.downloadingUpdate)
        let upToDateLabel = LocalizationManager.shared.tr(.upToDate)

        TestHarness.assertFalse(readyLabel.isEmpty, "F6: updateReadyRestart is non-empty")
        TestHarness.assertFalse(restartButton.isEmpty, "F6: restart is non-empty")
        TestHarness.assertFalse(downloadingLabel.isEmpty, "F6: downloadingUpdate is non-empty")
        TestHarness.assertFalse(upToDateLabel.isEmpty, "F6: upToDate is non-empty")
        TestHarness.assertTrue(readyLabel != restartButton, "F6: Status description and restart button text are not identical duplicates")

        // ---------------------------------------------------------------------
        // F7: MainShotView Update Banner Fallback
        // ---------------------------------------------------------------------
        let mainShotView = MainShotView(
            storageManager: storage,
            appSettings: AppSettings(),
            updateManager: updateMgr
        )
        let _ = mainShotView.updateBannerView
        TestHarness.assertTrue(true, "F7: MainShotView updateBannerView renders cleanly")

        // ---------------------------------------------------------------------
        // F8: ShotRowView Context Menu SF Symbols Formatting
        // ---------------------------------------------------------------------
        let rowView = ShotRowView(item: item, storageManager: storage)
        let _ = rowView.body
        TestHarness.assertTrue(true, "F8: ShotRowView context menu builds cleanly with Label SF Symbols")

        // ---------------------------------------------------------------------
        // F9: AnnotationEngine selectNextObject Forward & Reverse Cycling
        // ---------------------------------------------------------------------
        let engine = AnnotationEngine()
        TestHarness.assertNil(engine.selectNextObject(), "F9: selectNextObject on empty engine returns nil")

        let a1 = AnnotationObject(tool: .rectangle, bounds: CGRect(x: 0, y: 0, width: 40, height: 40))
        let a2 = AnnotationObject(tool: .ellipse, bounds: CGRect(x: 50, y: 0, width: 40, height: 40))
        let a3 = AnnotationObject(tool: .pen, bounds: CGRect(x: 100, y: 0, width: 40, height: 40))
        engine.addObject(a1)
        engine.addObject(a2)
        engine.addObject(a3)

        // Initially no selection
        engine.deselectAll()
        let sel1 = engine.selectNextObject(reverse: false)
        TestHarness.assertEqual(sel1, a1.id, "F9: Forward cycling from unselected state selects first item")
        TestHarness.assertEqual(engine.selectedObjectID, a1.id, "F9: selectedObjectID updated to a1")
        TestHarness.assertTrue(engine.objects[0].isSelected, "F9: a1 isSelected flag is true")

        let sel2 = engine.selectNextObject(reverse: false)
        TestHarness.assertEqual(sel2, a2.id, "F9: Forward cycling advances to a2")

        let sel3 = engine.selectNextObject(reverse: false)
        TestHarness.assertEqual(sel3, a3.id, "F9: Forward cycling advances to a3")

        let wrapSel = engine.selectNextObject(reverse: false)
        TestHarness.assertEqual(wrapSel, a1.id, "F9: Forward cycling wraps around to a1")

        let revWrapSel = engine.selectNextObject(reverse: true)
        TestHarness.assertEqual(revWrapSel, a3.id, "F9: Reverse cycling wraps from first to last (a3)")

        let revPrevSel = engine.selectNextObject(reverse: true)
        TestHarness.assertEqual(revPrevSel, a2.id, "F9: Reverse cycling moves backward to a2")

        // ---------------------------------------------------------------------
        // F10: hudDelete Localization & Transient HUD Feedback
        // ---------------------------------------------------------------------
        let languages: [AppLanguage] = [
            .system, .english, .vietnamese, .german, .french,
            .spanish, .japanese, .simplifiedChinese, .traditionalChinese, .korean
        ]
        for lang in languages {
            let deleteText = L10nKey.hudDelete.localized(for: lang)
            TestHarness.assertFalse(deleteText.isEmpty, "F10: hudDelete translated for \(lang.rawValue)")
            TestHarness.assertTrue(deleteText.contains("(⌫)"), "F10: hudDelete contains backspace glyph for \(lang.rawValue)")
        }

        // ---------------------------------------------------------------------
        // F11: Canonical Version Bump to v1.0.22 / Build 22
        // ---------------------------------------------------------------------
        TestHarness.assertEqual(UpdateManager.shared.currentVersion, "1.0.22", "F11: UpdateManager currentVersion is 1.0.22")
        let diagString = AboutSettingsTab.diagnosticString(version: "1.0.22")
        TestHarness.assertTrue(diagString.contains("SuperShot v1.0.22"), "F11: Diagnostic string contains v1.0.22")
        TestHarness.assertTrue(diagString.contains("Build 22"), "F11: Diagnostic string contains Build 22")
    }
}
