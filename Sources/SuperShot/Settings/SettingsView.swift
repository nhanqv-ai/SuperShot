import SwiftUI
import AppKit
import Carbon
import Combine
import SuperShotCore

public enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case captureSave = "Capture & Save"
    case history = "History"
    case about = "About"

    public var id: String { rawValue }

    public var localizedTitle: String {
        switch self {
        case .general: return LocalizationManager.shared.tr(.tabGeneral)
        case .captureSave: return LocalizationManager.shared.tr(.tabCaptureSave)
        case .history: return LocalizationManager.shared.tr(.tabHistory)
        case .about: return LocalizationManager.shared.tr(.tabAbout)
        }
    }

    public var iconName: String {
        switch self {
        case .general: return "gear"
        case .captureSave: return "camera.viewfinder"
        case .history: return "clock.arrow.circlepath"
        case .about: return "info.circle"
        }
    }
}

public struct SettingsView: View {
    @ObservedObject public var appSettings: AppSettings
    @ObservedObject public var storageManager: StorageManager
    @ObservedObject private var localizationManager = LocalizationManager.shared
    public var hotKeyManager: any HotKeyManaging
    public var launchAtLoginManager: any LaunchAtLoginManaging
    public var autoPasteService: any AutoPasteServicing
    public var permissionManager: any PermissionManaging
    public var onClose: (() -> Void)?

    @State private var selectedTab: SettingsTab = .general

    public init(
        appSettings: AppSettings,
        storageManager: StorageManager,
        hotKeyManager: any HotKeyManaging = HotKeyManager.shared,
        launchAtLoginManager: any LaunchAtLoginManaging = LaunchAtLoginManager.shared,
        autoPasteService: any AutoPasteServicing = AutoPasteService.shared,
        permissionManager: any PermissionManaging = PermissionManager.shared,
        initialTab: SettingsTab = .general,
        onClose: (() -> Void)? = nil
    ) {
        self.appSettings = appSettings
        self.storageManager = storageManager
        self.hotKeyManager = hotKeyManager
        self.launchAtLoginManager = launchAtLoginManager
        self.autoPasteService = autoPasteService
        self.permissionManager = permissionManager
        self._selectedTab = State(initialValue: initialTab)
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            topTabBar
            Divider()
            contentArea
            Divider()
            footerBar
        }
        .frame(width: 520, height: 530)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // Top tab selector with icon above label
    private var topTabBar: some View {
        HStack(spacing: 24) {
            ForEach(SettingsTab.allCases) { tab in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                }) {
                    VStack(spacing: 3) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 18, weight: .regular))
                            .frame(height: 22)
                        Text(tab.localizedTitle)
                            .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .regular))
                            .lineLimit(1)
                    }
                    .foregroundColor(selectedTab == tab ? .primary : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selectedTab == tab ? Color.secondary.opacity(0.15) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var contentArea: some View {
        ScrollView {
            VStack(spacing: 12) {
                switch selectedTab {
                case .general:
                    GeneralSettingsTab(
                        appSettings: appSettings,
                        hotKeyManager: hotKeyManager,
                        launchAtLoginManager: launchAtLoginManager,
                        autoPasteService: autoPasteService,
                        permissionManager: permissionManager
                    )
                case .captureSave:
                    CaptureSaveSettingsTab(
                        appSettings: appSettings
                    )
                case .history:
                    HistorySettingsTab(
                        appSettings: appSettings,
                        storageManager: storageManager
                    )
                case .about:
                    AboutSettingsTab(
                        appSettings: appSettings,
                        storageManager: storageManager,
                        hotKeyManager: hotKeyManager,
                        launchAtLoginManager: launchAtLoginManager
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var footerBar: some View {
        HStack {
            Spacer()
            Button("Done") {
                onClose?()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// Visual Card Modifier Helper
extension View {
    public func cardStyle() -> some View {
        self.background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 1)
                )
        )
    }
}
