import SwiftUI
import AppKit
import Carbon
import SuperShotCore

public struct AboutSettingsTab: View {
    @ObservedObject public var appSettings: AppSettings
    public var storageManager: StorageManager
    public var hotKeyManager: any HotKeyManaging
    public var launchAtLoginManager: any LaunchAtLoginManaging

    @State private var showingResetAllConfirmation: Bool = false
    @State private var isCheckingForUpdates: Bool = false

    public init(
        appSettings: AppSettings,
        storageManager: StorageManager,
        hotKeyManager: any HotKeyManaging = HotKeyManager.shared,
        launchAtLoginManager: any LaunchAtLoginManaging = LaunchAtLoginManager.shared
    ) {
        self.appSettings = appSettings
        self.storageManager = storageManager
        self.hotKeyManager = hotKeyManager
        self.launchAtLoginManager = launchAtLoginManager
    }

    public var body: some View {
        VStack(spacing: 12) {
            // App Identity
            if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
               let icon = NSImage(contentsOf: iconURL), icon.isValid {
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

                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
                Text(LocalizationManager.shared.tr(.versionLabel(version)))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
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
                    Text("License:")
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
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)

            Divider()

            HStack {
                Button(action: {
                    isCheckingForUpdates = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        isCheckingForUpdates = false
                    }
                }) {
                    HStack(spacing: 4) {
                        if isCheckingForUpdates {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.6)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text(isCheckingForUpdates ? LocalizationManager.shared.tr(.checkingForUpdates) : LocalizationManager.shared.tr(.menuCheckUpdates))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button(action: { showingResetAllConfirmation = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                        Text(LocalizationManager.shared.tr(.resetAllDefaults))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
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
            }
            .padding(.horizontal, 14)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .cardStyle()
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
}
