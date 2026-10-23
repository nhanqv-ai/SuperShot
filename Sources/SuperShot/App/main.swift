import SwiftUI
import AppKit
import SuperShotCore

@main
public struct SuperShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    public init() {}

    public var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
