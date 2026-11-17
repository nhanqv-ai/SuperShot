import AppKit
import Foundation

// MARK: - Cooperative & Legacy App Activation Plan

public struct AppActivationAction: Equatable, @unchecked Sendable {
    public let yieldsCooperativeActivation: Bool
    public let options: NSApplication.ActivationOptions

    public init(yieldsCooperativeActivation: Bool, options: NSApplication.ActivationOptions) {
        self.yieldsCooperativeActivation = yieldsCooperativeActivation
        self.options = options
    }
}

// MARK: - PreviousAppTracking Protocol

public protocol PreviousAppTracking: AnyObject, Sendable {
    var previousApp: NSRunningApplication? { get }
    func captureFrontmostApplication()
    func setPreviousApp(_ app: NSRunningApplication?)
    @discardableResult
    func activatePreviousApp() -> Bool
    func clear()
}

extension PreviousAppTracking {
    @discardableResult
    public func activatePreviousApp() -> Bool {
        guard let app = previousApp, !app.isTerminated else { return false }
        let plan = PreviousAppTracker.currentPlatformActivationPlan()
        return PreviousAppTracker.performDefaultActivation(app: app, plan: plan)
    }
}

// MARK: - PreviousAppTracker Implementation

public final class PreviousAppTracker: PreviousAppTracking, @unchecked Sendable {
    public static let shared = PreviousAppTracker()

    private let lock = NSLock()
    private weak var _previousApp: NSRunningApplication?
    private var _processIdentifier: pid_t?
    private let activator: @Sendable (NSRunningApplication, AppActivationAction) -> Bool

    public init(
        activator: @escaping @Sendable (NSRunningApplication, AppActivationAction) -> Bool = { app, plan in
            PreviousAppTracker.performDefaultActivation(app: app, plan: plan)
        }
    ) {
        self.activator = activator
    }

    public static func activationPlan(isMacOS14OrNewer: Bool) -> AppActivationAction {
        if isMacOS14OrNewer {
            return AppActivationAction(yieldsCooperativeActivation: true, options: [])
        } else {
            return AppActivationAction(yieldsCooperativeActivation: false, options: [.activateIgnoringOtherApps])
        }
    }

    public static func currentPlatformActivationPlan() -> AppActivationAction {
        if #available(macOS 14.0, *) {
            return activationPlan(isMacOS14OrNewer: true)
        } else {
            return activationPlan(isMacOS14OrNewer: false)
        }
    }

    public static func performDefaultActivation(app: NSRunningApplication, plan: AppActivationAction) -> Bool {
        if #available(macOS 14.0, *), plan.yieldsCooperativeActivation {
            NSApp?.yieldActivation(to: app)
        }
        return app.activate(options: plan.options)
    }

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

    @discardableResult
    public func activatePreviousApp() -> Bool {
        guard let app = previousApp, !app.isTerminated else { return false }
        let plan = Self.currentPlatformActivationPlan()
        return activator(app, plan)
    }

    public func clear() {
        setPreviousApp(nil)
    }
}
