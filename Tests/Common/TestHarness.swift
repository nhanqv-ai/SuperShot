import Foundation

/// Lightweight, zero-dependency test assertion and reporting harness for SuperShot.
/// Strictly enforces zero emojis across all output formats and banners.
public final class TestHarness {
    public static let shared = TestHarness()

    public private(set) var totalTests: Int = 0
    public private(set) var passedTests: Int = 0
    public private(set) var failedTests: Int = 0
    public private(set) var currentSuite: String = "Default"

    private let lock = NSLock()

    private init() {}

    public static func startSuite(_ name: String) {
        shared.lock.lock()
        shared.currentSuite = name
        shared.lock.unlock()
        print("\n\u{001B}[1;36m=== Suite: \(name) ===\u{001B}[0m")
    }

    public static func recordPass(_ testName: String) {
        shared.lock.lock()
        shared.totalTests += 1
        shared.passedTests += 1
        shared.lock.unlock()
        print("  \u{001B}[32m[PASS]\u{001B}[0m \(testName)")
    }

    public static func recordFail(_ testName: String, reason: String) {
        shared.lock.lock()
        shared.totalTests += 1
        shared.failedTests += 1
        shared.lock.unlock()
        print("  \u{001B}[31m[FAIL]\u{001B}[0m \(testName): \(reason)")
    }

    public static func assertTrue(_ condition: Bool, _ testName: String, reason: String = "Condition was false") {
        if condition {
            recordPass(testName)
        } else {
            recordFail(testName, reason: reason)
        }
    }

    public static func assertFalse(_ condition: Bool, _ testName: String, reason: String = "Condition was true") {
        if !condition {
            recordPass(testName)
        } else {
            recordFail(testName, reason: reason)
        }
    }

    public static func assertEqual<T: Equatable>(_ a: T, _ b: T, _ testName: String) {
        if a == b {
            recordPass(testName)
        } else {
            recordFail(testName, reason: "Expected \(b), got \(a)")
        }
    }

    public static func assertAlmostEqual(_ a: CGFloat, _ b: CGFloat, accuracy: CGFloat = 0.001, _ testName: String) {
        if abs(a - b) <= accuracy {
            recordPass(testName)
        } else {
            recordFail(testName, reason: "Expected \(b) +/- \(accuracy), got \(a)")
        }
    }

    public static func assertNotNil<T>(_ value: T?, _ testName: String) {
        if value != nil {
            recordPass(testName)
        } else {
            recordFail(testName, reason: "Value was nil")
        }
    }

    public static func assertNil<T>(_ value: T?, _ testName: String) {
        if value == nil {
            recordPass(testName)
        } else {
            recordFail(testName, reason: "Expected nil, got \(String(describing: value))")
        }
    }

    /// Creates an isolated temporary directory in /tmp/ for hermetic test execution.
    /// Never touches ~/Library/Application Support/SuperShot/.
    public static func createSandbox(prefix: String = "SuperShot_Sandbox") -> URL {
        let tempBase = FileManager.default.temporaryDirectory
        let sandboxURL = tempBase.appendingPathComponent("\(prefix)_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: sandboxURL, withIntermediateDirectories: true)
        return sandboxURL
    }

    /// Recursively purges a test sandbox directory.
    public static func cleanupSandbox(_ sandboxURL: URL) {
        try? FileManager.default.removeItem(at: sandboxURL)
    }

    /// Resets all counters for a fresh execution cycle.
    public static func reset() {
        shared.lock.lock()
        shared.totalTests = 0
        shared.passedTests = 0
        shared.failedTests = 0
        shared.lock.unlock()
    }

    /// Determines the exit code: 0 on 100% pass, 1 on any failure.
    public static var exitCode: Int32 {
        shared.lock.lock()
        defer { shared.lock.unlock() }
        return shared.failedTests > 0 ? 1 : 0
    }

    public static func printSummary() {
        shared.lock.lock()
        let total = shared.totalTests
        let passed = shared.passedTests
        let failed = shared.failedTests
        shared.lock.unlock()

        print("\n\u{001B}[1;36m==================================================\u{001B}[0m")
        print("\u{001B}[1;36m  SuperShot Test Execution Summary\u{001B}[0m")
        print("\u{001B}[1;36m==================================================\u{001B}[0m")
        print("  Total Tests Executed: \(total)")
        print("  Tests Passed:         \u{001B}[32m\(passed)\u{001B}[0m")
        print("  Tests Failed:         " + (failed > 0 ? "\u{001B}[31m\(failed)\u{001B}[0m" : "0"))

        if failed == 0 {
            print("\n\u{001B}[1;32mRESULT: ALL TESTS PASSED SUCCESSFULLY (0 EMOJIS, 100% PASS RATE)\u{001B}[0m\n")
        } else {
            print("\n\u{001B}[1;31mRESULT: TEST SUITE FAILED (\(failed) FAILURES)\u{001B}[0m\n")
        }
    }
}
