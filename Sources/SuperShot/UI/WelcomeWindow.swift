import AppKit
import SwiftUI
import SuperShotCore

/// WelcomeView provides a first-class onboarding experience highlighting key SuperShot capabilities.
public struct WelcomeView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @State private var isScreenRecordingGranted: Bool = PermissionManager.shared.isScreenRecordingGranted
    @State private var isAccessibilityGranted: Bool = PermissionManager.shared.isAccessibilityGranted
    public var onDismiss: (() -> Void)?

    public init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    public var appVersionString: String {
        let bundleVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return "v\(bundleVersion ?? "1.0.13")"
    }

    public var body: some View {
        VStack(spacing: 14) {
            // Header
            headerSection

            // Feature Cards
            featureCardsSection

            // Permissions Card
            permissionsCard

            Spacer(minLength: 0)

            // Bottom Actions
            actionsSection
        }
        .padding(20)
        .frame(width: 520, height: 460)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        )
        .onAppear {
            refreshPermissions()
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(localizationManager.tr(.welcomeTitle))
                        .font(.system(size: 16, weight: .bold))
                    Text(appVersionString)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        .foregroundColor(.accentColor)
                }

                Text(localizationManager.tr(.welcomeSubtitle))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
    }

    // MARK: - Feature Cards Section
    private var featureCardsSection: some View {
        VStack(spacing: 8) {
            featureCard(
                icon: "camera.viewfinder",
                title: LocalizationManager.shared.tr(.welcomeFeature1Title),
                description: LocalizationManager.shared.tr(.welcomeFeature1Desc)
            )

            featureCard(
                icon: "arrow.up.and.down.text.horizontal",
                title: LocalizationManager.shared.tr(.welcomeFeature2Title),
                description: LocalizationManager.shared.tr(.welcomeFeature2Desc)
            )

            featureCard(
                icon: "clock.arrow.circlepath",
                title: LocalizationManager.shared.tr(.welcomeFeature3Title),
                description: LocalizationManager.shared.tr(.welcomeFeature3Desc)
            )
        }
    }

    private func featureCard(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.accentColor)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.primary)
                Text(description)
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
    }

    // MARK: - Permissions Card
    private var permissionsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localizationManager.tr(.permissionsSectionTitle))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                // Screen Recording
                HStack(spacing: 6) {
                    Image(systemName: isScreenRecordingGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(isScreenRecordingGranted ? .green : .orange)
                        .font(.system(size: 11))
                    Text(localizationManager.tr(.screenRecordingPermission))
                        .font(.system(size: 10.5))
                    if !isScreenRecordingGranted {
                        Button(action: {
                            _ = PermissionManager.shared.requestScreenRecording()
                            refreshPermissions()
                        }) {
                            Text(localizationManager.tr(.grantPermissionButton))
                                .font(.system(size: 9.5))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .pointingHandCursor()
                    }
                }

                Spacer()

                // Accessibility
                HStack(spacing: 6) {
                    Image(systemName: isAccessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(isAccessibilityGranted ? .green : .orange)
                        .font(.system(size: 11))
                    Text(localizationManager.tr(.accessibilityPermission))
                        .font(.system(size: 10.5))
                    if !isAccessibilityGranted {
                        Button(action: {
                            _ = PermissionManager.shared.requestAccessibility()
                            refreshPermissions()
                        }) {
                            Text(localizationManager.tr(.grantPermissionButton))
                                .font(.system(size: 9.5))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .pointingHandCursor()
                    }
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        )
    }

    // MARK: - Actions Section
    private var actionsSection: some View {
        HStack {
            Button(localizationManager.tr(.closeButton)) {
                onDismiss?()
            }
            .keyboardShortcut(.cancelAction)
            .buttonStyle(.plain)
            .pointingHandCursor()

            Spacer()

            Button(action: {
                onDismiss?()
            }) {
                Text(localizationManager.tr(.getStartedButton))
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .pointingHandCursor()
        }
        .padding(.top, 4)
    }

    private func refreshPermissions() {
        isScreenRecordingGranted = PermissionManager.shared.isScreenRecordingGranted
        isAccessibilityGranted = PermissionManager.shared.isAccessibilityGranted
    }
}

// MARK: - Welcome Window Controller
public final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    public static let shared = WelcomeWindowController()

    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = LocalizationManager.shared.tr(.welcomeTitle)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 520, height: 460))

        super.init(window: window)
        window.delegate = self
        setupContentView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupContentView() {
        guard let window = self.window else { return }
        let view = WelcomeView(onDismiss: { [weak self] in
            self?.dismiss()
        })
        window.contentView = NSHostingView(rootView: view)
    }

    public func showWelcomeWindow() {
        guard let window = self.window else { return }
        setupContentView()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func dismiss() {
        window?.close()
    }

    public func windowWillClose(_ notification: Notification) {
        // Cleanup if needed
    }
}
