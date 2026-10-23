import Foundation
import ServiceManagement

// MARK: - LaunchAtLoginManaging Protocol

public protocol LaunchAtLoginManaging: Sendable {
    var isEnabled: Bool { get }
    @discardableResult
    func setEnabled(_ enable: Bool) -> Bool
}

// MARK: - LaunchAtLoginManager Implementation

public final class LaunchAtLoginManager: LaunchAtLoginManaging, @unchecked Sendable {
    public static let shared = LaunchAtLoginManager()

    public init() {}

    public var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    @discardableResult
    public func setEnabled(_ enable: Bool) -> Bool {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if enable {
                    if service.status != .enabled {
                        try service.register()
                    }
                } else {
                    if service.status != .notRegistered && service.status != .notFound {
                        try service.unregister()
                    }
                }
                return true
            } catch {
                NSLog("SuperShot: SMAppService status change notice: \(error.localizedDescription)")
                return false
            }
        }
        return false
    }
}
