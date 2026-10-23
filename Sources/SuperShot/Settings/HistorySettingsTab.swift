import SwiftUI
import AppKit
import SuperShotCore

public struct HistorySettingsTab: View {
    @ObservedObject public var appSettings: AppSettings
    @ObservedObject public var storageManager: StorageManager
    @ObservedObject private var localizationManager = LocalizationManager.shared

    @State private var showingClearConfirmation: Bool = false

    public init(appSettings: AppSettings, storageManager: StorageManager) {
        self.appSettings = appSettings
        self.storageManager = storageManager
    }

    public var body: some View {
        VStack(spacing: 10) {
            capacityCard
            pinProtectionCard
            storageStatsCard
        }
    }

    private var capacityCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizationManager.shared.tr(.historyCapacity))
                .font(.system(size: 12.5, weight: .semibold))

            HStack {
                Text(localizationManager.effectiveLanguage == .vietnamese ? "Lưu trữ:" : "Remember:")
                    .font(.system(size: 11.5))
                    .frame(width: 80, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { Double(appSettings.capacity) },
                        set: {
                            appSettings.capacity = Int($0)
                            storageManager.capacity = Int($0)
                        }
                    ),
                    in: 10...500,
                    step: 10
                )

                Text("\(appSettings.capacity) \(LocalizationManager.shared.tr(.historyCapacityUnit))")
                    .font(.system(size: 11.5, design: .monospaced))
                    .lineLimit(1)
                    .frame(width: 118, alignment: .trailing)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var pinProtectionCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "pin.fill")
                .font(.system(size: 18))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizationManager.shared.tr(.pinProtectionTitle))
                    .font(.system(size: 12, weight: .semibold))
                Text(LocalizationManager.shared.tr(.pinProtectionDesc))
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var storageStatsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizationManager.shared.tr(.storageStatistics))
                .font(.system(size: 12.5, weight: .semibold))

            VStack(spacing: 4) {
                metricRow(label: LocalizationManager.shared.tr(.totalScreenshots), value: "\(storageManager.items.count)")
                metricRow(label: LocalizationManager.shared.tr(.pinnedScreenshots), value: "\(storageManager.pinnedItems.count)")
                metricRow(label: LocalizationManager.shared.tr(.unpinnedScreenshots), value: "\(storageManager.recentItems.count)")
                metricRow(label: LocalizationManager.shared.tr(.diskUsage), value: calculateDiskUsageFormatted())
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .cornerRadius(6)

            HStack(spacing: 12) {
                Button(action: { showingClearConfirmation = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text(LocalizationManager.shared.tr(.clearHistory))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .confirmationDialog(
                    LocalizationManager.shared.tr(.clearUnpinnedConfirmTitle),
                    isPresented: $showingClearConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(LocalizationManager.shared.tr(.clearConfirmButton), role: .destructive) {
                        storageManager.clearUnpinnedHistory()
                    }
                    Button(LocalizationManager.shared.tr(.actionCancel), role: .cancel) {}
                } message: {
                    Text(LocalizationManager.shared.tr(.clearUnpinnedConfirmMessage))
                }

                Button(action: {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: storageManager.baseDirectory.path)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                        Text(LocalizationManager.shared.tr(.openInFinder))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.top, 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func metricRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
        }
    }

    private func calculateDiskUsageFormatted() -> String {
        let url = storageManager.baseDirectory
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return "0 KB"
        }
        var totalBytes: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let vals = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
               vals.isRegularFile == true,
               let sz = vals.fileSize {
                totalBytes += Int64(sz)
            }
        }
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        bcf.countStyle = .file
        return bcf.string(fromByteCount: totalBytes)
    }
}
