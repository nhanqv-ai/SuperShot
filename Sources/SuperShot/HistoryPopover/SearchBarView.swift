import SwiftUI
import AppKit

/// SearchBarView provides an instant search text field with an auto-focus guarantee
/// upon presentation in MainShotView.
public struct SearchBarView: View {
    @Binding public var text: String
    public var placeholder: String
    public var onCommit: (() -> Void)?

    @FocusState private var isFieldFocused: Bool

    public init(
        text: Binding<String>,
        placeholder: String = "Search screenshots...",
        onCommit: (() -> Void)? = nil
    ) {
        self._text = text
        self.placeholder = placeholder
        self.onCommit = onCommit
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isFieldFocused)
                .onSubmit { onCommit?() }

            if !text.isEmpty {
                Button(action: {
                    text = ""
                    DispatchQueue.main.async { isFieldFocused = true }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search query")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
                )
        )
        .onAppear { requestFieldFocus() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            requestFieldFocus()
        }
    }

    private func requestFieldFocus() {
        DispatchQueue.main.async {
            self.isFieldFocused = true
        }
    }
}
