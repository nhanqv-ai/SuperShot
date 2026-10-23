import SwiftUI
import AppKit
import SuperShotCore

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
                        .padding(3)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help(LocalizationManager.shared.tr(.clearSearchTooltip))
            } else {
                Text("/")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.65))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color(nsColor: .separatorColor).opacity(0.18))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)
                            )
                    )
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
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SuperShotFocusSearchField"))) { _ in
            requestFieldFocus()
        }
    }

    private func requestFieldFocus() {
        DispatchQueue.main.async {
            self.isFieldFocused = true
        }
    }
}
