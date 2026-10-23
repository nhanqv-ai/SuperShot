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

    public var shortcutNumber: Int {
        switch self {
        case .general: return 1
        case .captureSave: return 2
        case .history: return 3
        case .about: return 4
        }
    }

    public var shortcutHint: String {
        "⌘\(shortcutNumber)"
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
        .frame(width: 520, height: 565)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: .settingsSelectTab)) { notification in
            if let tab = notification.object as? SettingsTab {
                selectedTab = tab
            } else if let index = notification.userInfo?["tabIndex"] as? Int, index >= 0 && index < SettingsTab.allCases.count {
                selectedTab = SettingsTab.allCases[index]
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsCycleTab)) { notification in
            let direction = notification.userInfo?["direction"] as? Int ?? 1
            let tabs = SettingsTab.allCases
            if let currentIndex = tabs.firstIndex(of: selectedTab) {
                let nextIndex = (currentIndex + direction + tabs.count) % tabs.count
                selectedTab = tabs[nextIndex]
            }
        }
    }

    // Top tab selector with full-bleed rectangular hit target and instant tab switching
    private var topTabBar: some View {
        HStack(spacing: 12) {
            ForEach(SettingsTab.allCases) { tab in
                SettingsTabButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    action: {
                        selectedTab = tab
                    }
                )
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
            Button(localizationManager.tr(.doneButton)) {
                onClose?()
            }
            .pointingHandCursor()
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

public struct SettingsTabButton: View {
    public let tab: SettingsTab
    public let isSelected: Bool
    public let action: () -> Void

    @State private var isHovered: Bool = false

    public init(tab: SettingsTab, isSelected: Bool, action: @escaping () -> Void) {
        self.tab = tab
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: tab.iconName)
                    .font(.system(size: 18, weight: isSelected ? .medium : .regular))
                    .frame(height: 22)
                Text(tab.localizedTitle)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundColor(isSelected ? .primary : (isHovered ? .primary.opacity(0.85) : .secondary))
            .frame(minWidth: 108, minHeight: 46)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.secondary.opacity(0.18)
                            : (isHovered ? Color.secondary.opacity(0.09) : Color.white.opacity(0.001))
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isSelected {
                        action()
                    }
                }
        )
        .onHover { hovering in
            if isHovered != hovering {
                isHovered = hovering
            }
        }
        .pointingHandCursor()
        .keyboardShortcut(KeyEquivalent(Character("\(tab.shortcutNumber)")), modifiers: .command)
        .help("\(tab.localizedTitle) (\(tab.shortcutHint))")
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

// Settings Tab Navigation Notification
extension NSNotification.Name {
    public static let settingsSelectTab = NSNotification.Name("SuperShotSettingsSelectTab")
    public static let settingsCycleTab = NSNotification.Name("SuperShotSettingsCycleTab")
}

