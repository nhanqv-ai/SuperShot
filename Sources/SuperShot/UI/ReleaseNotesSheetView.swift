import AppKit
import SwiftUI
import SuperShotCore

/// ReleaseNotesSheetView presents formatted release notes in a clean native modal sheet.
public struct ReleaseNotesSheetView: View {
    public let release: ReleaseInfo
    public var onDismiss: () -> Void

    @ObservedObject private var localizationManager = LocalizationManager.shared

    public init(release: ReleaseInfo, onDismiss: @escaping () -> Void) {
        self.release = release
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(localizationManager.tr(.releaseNotesSheetTitle(release.tagName)))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)

                    if !release.name.isEmpty, release.name != release.tagName {
                        Text(release.name)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help(localizationManager.tr(.closeButton))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Scrollable Content
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    let notes = release.releaseNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                    if notes.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 28, weight: .light))
                                .foregroundColor(.secondary)
                            Text(localizationManager.tr(.releaseNotesFallback))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 180)
                    } else {
                        Text(notes)
                            .font(.system(size: 12))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
            .background(Color(NSColor.textBackgroundColor).opacity(0.5))

            Divider()

            // Footer
            HStack {
                Button(action: {
                    NSWorkspace.shared.open(release.htmlURL)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.system(size: 11))
                        Text(release.htmlURL.absoluteString)
                            .font(.system(size: 10))
                            .lineLimit(1)
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()

                Spacer()

                Button(localizationManager.tr(.closeButton)) {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .pointingHandCursor()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 480, height: 380)
    }
}
