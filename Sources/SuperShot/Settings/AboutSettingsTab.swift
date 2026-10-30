import SwiftUI
import AppKit
import Carbon
import SuperShotCore

public struct AboutSettingsTab: View {
    @ObservedObject public var appSettings: AppSettings
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @ObservedObject public var updateManager: UpdateManager
    public var storageManager: StorageManager
    public var hotKeyManager: any HotKeyManaging
    public var launchAtLoginManager: any LaunchAtLoginManaging

    @State private var showingResetAllConfirmation: Bool = false
    @State private var isHoveringVersion: Bool = false
    @State private var isDiagnosticsCopied: Bool = false
    @State private var showingReleaseNotesSheet: Bool = false
    @State private var copyTask: Task<Void, Never>? = nil


    private static let cachedAppIcon: NSImage? = {
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: iconURL),
              icon.isValid else {
            return nil
        }
        return icon
    }()

    public init(
        appSettings: AppSettings,
        storageManager: StorageManager,
        hotKeyManager: any HotKeyManaging = HotKeyManager.shared,
        launchAtLoginManager: any LaunchAtLoginManaging = LaunchAtLoginManager.shared,
        updateManager: UpdateManager = UpdateManager.shared
    ) {
        self.appSettings = appSettings
        self.storageManager = storageManager
        self.hotKeyManager = hotKeyManager
        self.launchAtLoginManager = launchAtLoginManager
        self.updateManager = updateManager
    }

    public var body: some View {
        VStack(spacing: 12) {
            // App Identity
            if let icon = Self.cachedAppIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 56, height: 56)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.04, green: 0.52, blue: 1.0), Color(red: 0.37, green: 0.36, blue: 0.90)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                        .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 2)

                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.white)
                }
            }

            VStack(spacing: 2) {
                Text(LocalizationManager.shared.tr(.appTitle))
                    .font(.system(size: 16, weight: .bold))

                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.31"
                Button(action: { copyDiagnosticsToClipboard(version: version) }) {
                    HStack(spacing: 4) {
                        Text(LocalizationManager.shared.tr(.versionLabel(version)))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Image(systemName: isDiagnosticsCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9))
                            .foregroundColor(isDiagnosticsCopied ? .green : .secondary.opacity(0.7))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color(nsColor: .separatorColor).opacity(isHoveringVersion ? 0.25 : 0.10))
                    )
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .onHover { isHoveringVersion = $0 }
                .help(LocalizationManager.shared.tr(.copiedDiagnostics))
            }

            Text(LocalizationManager.shared.tr(.appDescription))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Divider()

            VStack(spacing: 6) {
                HStack {
                    Text(LocalizationManager.shared.tr(.authorLabel))
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Nhan Quach (@nhanqv-ai)")
                        .font(.system(size: 11.5, weight: .medium))
                }

                HStack {
                    Text(localizationManager.tr(.licenseLabel))
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("MIT License")
                        .font(.system(size: 11.5, weight: .medium))
                }

                HStack {
                    Text("GitHub:")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: {
                        if let url = URL(string: "https://github.com/nhanqv-ai/SuperShot") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text("nhanqv-ai/SuperShot")
                                .font(.system(size: 11.5, weight: .medium))
                            Image(systemName: "arrow.up.forward.square")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.accentColor)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
            }
            .padding(.horizontal, 14)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Button(action: {
                            updateManager.checkForUpdates(userInitiated: true)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text(LocalizationManager.shared.tr(.menuCheckUpdates))
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(updateManager.isBusy)
                        .pointingHandCursor()

                        if let lastDate = appSettings.lastUpdateCheckDate {
                            Text(LocalizationManager.shared.tr(.lastCheckedLabel(RelativeTimeFormatter.format(lastDate))))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                    }

                    Button(action: { showingResetAllConfirmation = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                            Text(LocalizationManager.shared.tr(.resetAllDefaults))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .pointingHandCursor()
                    .confirmationDialog(
                        LocalizationManager.shared.tr(.resetAllConfirmTitle),
                        isPresented: $showingResetAllConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button(LocalizationManager.shared.tr(.resetAllDefaults), role: .destructive) {
                            resetAllDefaults()
                        }
                        Button(LocalizationManager.shared.tr(.actionCancel), role: .cancel) {}
                    } message: {
                        Text(LocalizationManager.shared.tr(.resetAllConfirmMessage))
                    }

                    Spacer()
                }

                if case .idle = updateManager.status {
                    // Idle state needs no extra status row
                } else {
                    HStack(spacing: 6) {
                        updateStatusView
                        Spacer()
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .cardStyle()
        .sheet(isPresented: $showingReleaseNotesSheet) {
            if let release = updateManager.latestRelease {
                ReleaseNotesSheetView(release: release) {
                    showingReleaseNotesSheet = false
                }
            }
        }
    }


    public static func diagnosticString(version: String) -> String {
        #if arch(arm64)
        let arch = "arm64"
        #elseif arch(x86_64)
        let arch = "x86_64"
        #else
        let arch = "unknown"
        #endif
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "31"
        return "SuperShot v\(version) (\(arch)) • macOS \(os) • Build \(build)"
    }

    private func copyDiagnosticsToClipboard(version: String) {
        let text = Self.diagnosticString(version: version)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        copyTask?.cancel()
        withAnimation(.easeInOut(duration: 0.15)) {
            isDiagnosticsCopied = true
        }
        copyTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.isDiagnosticsCopied = false
                }
            }
        }
    }

    private func resetAllDefaults() {
        let def = AppSettingsSnapshot.default
        appSettings.activeColorHex = def.activeColorHex
        appSettings.activeStrokeWidth = def.activeStrokeWidth
        appSettings.activeFontSize = def.activeFontSize
        appSettings.resetPresets()
        appSettings.autoSaveEnabled = def.autoSaveEnabled
        appSettings.autoSaveDirectory = URL(fileURLWithPath: def.autoSaveDirectoryPath, isDirectory: true)
        appSettings.saveFormat = def.saveFormat
        appSettings.jpegQuality = def.jpegQuality
        appSettings.maxScrollHeightPx = def.maxScrollHeightPx
        appSettings.capacity = def.capacity
        storageManager.capacity = def.capacity
        appSettings.launchAtLogin = def.launchAtLogin
        appSettings.language = def.language
        appSettings.autoPasteOnSelection = def.autoPasteOnSelection
        appSettings.regionHotKeyKeyCode = def.regionHotKeyKeyCode
        appSettings.regionHotKeyModifiers = def.regionHotKeyModifiers
        appSettings.scrollHotKeyKeyCode = def.scrollHotKeyKeyCode
        appSettings.scrollHotKeyModifiers = def.scrollHotKeyModifiers

        launchAtLoginManager.setEnabled(false)
        LocalizationManager.shared.setLanguage(code: "system")
        hotKeyManager.registerDefaults()
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch updateManager.status {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                Text(LocalizationManager.shared.tr(.checkingForUpdates))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        case .upToDate:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 11))
                Text(LocalizationManager.shared.tr(.upToDate))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.green)
            }
        case .updateAvailable(let release):
            HStack(spacing: 6) {
                Text(localizationManager.tr(.updateAvailable(release.tagName)))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.accentColor)

                Button(action: {
                    if release.preferredAssetURL != nil {
                        updateManager.startDownloadAndInstall(release: release, autoRestart: true)
                    } else {
                        NSWorkspace.shared.open(release.htmlURL)
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 10))
                        Text(LocalizationManager.shared.tr(.downloadUpdate))
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .pointingHandCursor()

                Button(action: {
                    showingReleaseNotesSheet = true
                }) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 11))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .pointingHandCursor()
                .help(LocalizationManager.shared.tr(.viewReleaseNotes))

                Button(action: {
                    NSWorkspace.shared.open(release.htmlURL)
                }) {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 10))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .pointingHandCursor()
            }
        case .downloading(let progress):
            HStack(spacing: 6) {
                ProgressView(value: max(0.0, min(1.0, progress)), total: 1.0)
                    .progressViewStyle(.linear)
                    .frame(width: 90)
                Text(String(format: "%.0f%%", progress * 100))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                Button(action: {
                    updateManager.cancelDownload()
                }) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help(LocalizationManager.shared.tr(.cancelDownload))
            }
        case .readyToRestart:
            HStack(spacing: 6) {
                Text(LocalizationManager.shared.tr(.updateReadyRestart))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.accentColor)
                Button(action: {
                    updateManager.restartApp()
                }) {
                    Text(LocalizationManager.shared.tr(.restart))
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .pointingHandCursor()
            }
        case .error(let msg):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 11))
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .lineLimit(1)
                    .help(msg)
                Button(action: {
                    if let rel = updateManager.latestRelease {
                        updateManager.startDownloadAndInstall(release: rel, autoRestart: true)
                    } else {
                        updateManager.checkForUpdates(userInitiated: true)
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                        Text(LocalizationManager.shared.tr(.retryButton))
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .pointingHandCursor()
            }
        }
    }
}

