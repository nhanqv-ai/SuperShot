import SwiftUI
import Carbon
import AppKit
import SuperShotCore

public struct GeneralSettingsTab: View {
    @ObservedObject public var appSettings: AppSettings
    @ObservedObject private var localizationManager = LocalizationManager.shared
    public var hotKeyManager: any HotKeyManaging
    public var launchAtLoginManager: any LaunchAtLoginManaging
    public var autoPasteService: any AutoPasteServicing
    public var permissionManager: any PermissionManaging

    @State private var isScreenRecordingGranted: Bool = false
    @State private var isAccessibilityGranted: Bool = false
    @State private var recordingAction: HotKeyAction? = nil
    @State private var localKeyMonitor: Any? = nil

    private let statusTimer = Timer.publish(every: 2.5, on: .main, in: .common).autoconnect()

    public init(
        appSettings: AppSettings,
        hotKeyManager: any HotKeyManaging = HotKeyManager.shared,
        launchAtLoginManager: any LaunchAtLoginManaging = LaunchAtLoginManager.shared,
        autoPasteService: any AutoPasteServicing = AutoPasteService.shared,
        permissionManager: any PermissionManaging = PermissionManager.shared
    ) {
        self.appSettings = appSettings
        self.hotKeyManager = hotKeyManager
        self.launchAtLoginManager = launchAtLoginManager
        self.autoPasteService = autoPasteService
        self.permissionManager = permissionManager
    }

    public var body: some View {
        VStack(spacing: 8) {
            systemStartupCard
            permissionsCard
            globalShortcutsCard
            autoPasteCard
        }
        .onAppear { refreshPermissions() }
        .onReceive(statusTimer) { _ in refreshPermissions() }
        .onDisappear { stopRecording() }
    }

    private func refreshPermissions() {
        let screenGranted = permissionManager.checkScreenRecording()
        if isScreenRecordingGranted != screenGranted {
            isScreenRecordingGranted = screenGranted
        }
        let accessGranted = permissionManager.checkAccessibility()
        if isAccessibilityGranted != accessGranted {
            isAccessibilityGranted = accessGranted
        }
    }

    // MARK: - Startup & Language
    private var systemStartupCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(LocalizationManager.shared.tr(.launchAtLogin), isOn: Binding(
                get: { appSettings.launchAtLogin },
                set: { newVal in
                    appSettings.launchAtLogin = newVal
                    launchAtLoginManager.setEnabled(newVal)
                }
            ))
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
            .pointingHandCursor()

            Toggle(LocalizationManager.shared.tr(.automaticallyCheckForUpdates), isOn: $appSettings.automaticallyCheckForUpdates)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .pointingHandCursor()

            if appSettings.automaticallyCheckForUpdates {
                HStack(spacing: 8) {
                    Text(LocalizationManager.shared.tr(.updateCheckIntervalLabel))
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)

                    Picker("", selection: $appSettings.updateCheckIntervalDays) {
                        Text(LocalizationManager.shared.tr(.intervalDaily)).tag(1)
                        Text(LocalizationManager.shared.tr(.intervalWeekly)).tag(7)
                        Text(LocalizationManager.shared.tr(.intervalMonthly)).tag(30)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 140)
                    .pointingHandCursor()
                }
            }

            HStack(spacing: 8) {
                Text(LocalizationManager.shared.tr(.languageLabel))
                    .font(.system(size: 12))
                    .frame(width: 120, alignment: .leading)

                Picker("", selection: Binding(
                    get: { appSettings.language },
                    set: { newCode in
                        appSettings.language = newCode
                        LocalizationManager.shared.setLanguage(code: newCode)
                    }
                )) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 180)
                .pointingHandCursor()
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Permissions
    private var permissionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localizationManager.tr(.permissionsSectionTitle))
                .font(.system(size: 12.5, weight: .semibold))

            // Screen Recording Row
            HStack(spacing: 8) {
                Image(systemName: isScreenRecordingGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(isScreenRecordingGranted ? .green : .orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizationManager.shared.tr(.screenRecordingPermission))
                        .font(.system(size: 11.5, weight: .medium))
                    Text(isScreenRecordingGranted ? LocalizationManager.shared.tr(.permissionGranted) : LocalizationManager.shared.tr(.screenRecordingGuide))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !isScreenRecordingGranted {
                    Button(LocalizationManager.shared.tr(.grantPermissionButton)) {
                        _ = permissionManager.requestScreenRecording()
                        permissionManager.openScreenRecordingSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .pointingHandCursor()
                } else {
                    Text(localizationManager.tr(.permissionGranted))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Accessibility Row
            HStack(spacing: 8) {
                Image(systemName: isAccessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(isAccessibilityGranted ? .green : .orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizationManager.shared.tr(.accessibilityPermission))
                        .font(.system(size: 11.5, weight: .medium))
                    Text(isAccessibilityGranted ? LocalizationManager.shared.tr(.permissionGranted) : LocalizationManager.shared.tr(.accessibilityGuide))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !isAccessibilityGranted {
                    Button(LocalizationManager.shared.tr(.grantPermissionButton)) {
                        _ = autoPasteService.resetAndRequestAccessibilityPermission()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .pointingHandCursor()
                } else {
                    Text(localizationManager.tr(.permissionGranted))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Global Shortcuts
    private var globalShortcutsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizationManager.shared.tr(.globalHotkeys))
                .font(.system(size: 12.5, weight: .semibold))

            // Region Capture Shortcut
            HStack {
                Text(LocalizationManager.shared.tr(.inPlaceCaptureShortcut))
                    .font(.system(size: 11.5))
                    .frame(width: 160, alignment: .leading)

                shortcutButton(
                    action: .inPlaceCapture,
                    keyCode: appSettings.regionHotKeyKeyCode,
                    modifiers: appSettings.regionHotKeyModifiers
                )

                Button(action: {
                    resetHotKey(.inPlaceCapture)
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .pointingHandCursor()
                .help(LocalizationManager.shared.tr(.resetShortcutTooltip("⌥S")))
            }

            // Scrolling Capture Shortcut
            HStack {
                Text(LocalizationManager.shared.tr(.scrollingCaptureShortcut))
                    .font(.system(size: 11.5))
                    .frame(width: 160, alignment: .leading)

                shortcutButton(
                    action: .scrollingCapture,
                    keyCode: appSettings.scrollHotKeyKeyCode,
                    modifiers: appSettings.scrollHotKeyModifiers
                )

                Button(action: {
                    resetHotKey(.scrollingCapture)
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .pointingHandCursor()
                .help(LocalizationManager.shared.tr(.resetShortcutTooltip("⌥⇧S")))
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Auto-Paste
    private var autoPasteCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(LocalizationManager.shared.tr(.autoPasteOnSelection), isOn: $appSettings.autoPasteOnSelection)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))

            Text(LocalizationManager.shared.tr(.directAutoPaste))
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .padding(.leading, 20)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // Hotkey sub-methods
    private func shortcutButton(action: HotKeyAction, keyCode: UInt32, modifiers: UInt32) -> some View {
        let isRecording = (recordingAction == action)
        return Button(action: {
            if isRecording {
                stopRecording()
            } else {
                startRecording(action: action)
            }
        }) {
            HStack(spacing: 4) {
                if isRecording {
                    Image(systemName: "record.circle")
                        .foregroundColor(.accentColor)
                    Text(LocalizationManager.shared.tr(.pressShortcutHint))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.accentColor)
                } else {
                    let shortcut = HotKeyShortcut(keyCode: keyCode, carbonModifiers: modifiers)
                    Text(shortcut.displayString)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isRecording ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private func startRecording(action: HotKeyAction) {
        stopRecording()
        recordingAction = action

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc
                stopRecording()
                return nil
            }
            var carbonMods: UInt32 = 0
            if event.modifierFlags.contains(.command) { carbonMods |= UInt32(cmdKey) }
            if event.modifierFlags.contains(.option) { carbonMods |= UInt32(optionKey) }
            if event.modifierFlags.contains(.control) { carbonMods |= UInt32(controlKey) }
            if event.modifierFlags.contains(.shift) { carbonMods |= UInt32(shiftKey) }

            // Require at least Option, Command, or Control
            if (carbonMods & (UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey))) != 0 {
                let code = UInt32(event.keyCode)
                applyHotKey(action: action, keyCode: code, modifiers: carbonMods)
                stopRecording()
                return nil
            }
            return nil
        }
    }

    private func stopRecording() {
        if let mon = localKeyMonitor {
            NSEvent.removeMonitor(mon)
            localKeyMonitor = nil
        }
        recordingAction = nil
    }

    private func applyHotKey(action: HotKeyAction, keyCode: UInt32, modifiers: UInt32) {
        if action == .inPlaceCapture {
            appSettings.regionHotKeyKeyCode = keyCode
            appSettings.regionHotKeyModifiers = modifiers
        } else {
            appSettings.scrollHotKeyKeyCode = keyCode
            appSettings.scrollHotKeyModifiers = modifiers
        }
        _ = hotKeyManager.register(action: action, keyCode: keyCode, modifiers: modifiers)
    }

    private func resetHotKey(_ action: HotKeyAction) {
        if action == .inPlaceCapture {
            applyHotKey(action: .inPlaceCapture, keyCode: 1, modifiers: UInt32(optionKey))
        } else {
            applyHotKey(action: .scrollingCapture, keyCode: 1, modifiers: UInt32(optionKey | shiftKey))
        }
    }
}
