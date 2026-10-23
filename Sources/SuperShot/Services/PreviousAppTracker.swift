import AppKit
import Foundation

// MARK: - PreviousAppTracking Protocol

public protocol PreviousAppTracking: AnyObject, Sendable {
    var previousApp: NSRunningApplication? { get }
    func captureFrontmostApplication()
    func setPreviousApp(_ app: NSRunningApplication?)
    func clear()
}

// MARK: - PreviousAppTracker Implementation

public final class PreviousAppTracker: PreviousAppTracking, @unchecked Sendable {
    public static let shared = PreviousAppTracker()

    private let lock = NSLock()
    private weak var _previousApp: NSRunningApplication?
    private var _processIdentifier: pid_t?

    public init() {}

    public var previousApp: NSRunningApplication? {
        lock.lock()
        defer { lock.unlock() }

        if let app = _previousApp, !app.isTerminated {
            return app
        }
        if let pid = _processIdentifier,
           let app = NSRunningApplication(processIdentifier: pid),
           !app.isTerminated {
            return app
        }
        return nil
    }

    public func setPreviousApp(_ app: NSRunningApplication?) {
        lock.lock()
        defer { lock.unlock() }

        if let app = app {
            if app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                self._previousApp = app
                self._processIdentifier = app.processIdentifier
            }
        } else {
            self._previousApp = nil
            self._processIdentifier = nil
        }
    }

    public func captureFrontmostApplication() {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return }
        if frontmost.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return
        }
        setPreviousApp(frontmost)
    }

    public func clear() {
        setPreviousApp(nil)
    }
}
