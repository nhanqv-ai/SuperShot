import AppKit
import SwiftUI

/// Window accessor view helper for obtaining the hosting NSWindow in SwiftUI.
public struct WindowAccessor: NSViewRepresentable {
    public let onWindow: (NSWindow?) -> Void

    public init(onWindow: @escaping (NSWindow?) -> Void) {
        self.onWindow = onWindow
    }

    public func makeNSView(context: Context) -> NSView {
        let view = WindowObserverView()
        view.onWindowChange = onWindow
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            onWindow(window)
        }
    }
}

public final class WindowObserverView: NSView {
    public var onWindowChange: ((NSWindow?) -> Void)?

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(self.window)
    }
}
