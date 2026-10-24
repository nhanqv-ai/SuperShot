import SwiftUI
import AppKit
import SuperShotCore

public struct CaptureSaveSettingsTab: View {
    @ObservedObject public var appSettings: AppSettings
    @ObservedObject private var localizationManager = LocalizationManager.shared

    @State private var newPresetHex: String = ""
    @State private var showingHexError: Bool = false
    @State private var showingResetPresetsConfirmation: Bool = false

    public init(appSettings: AppSettings) {
        self.appSettings = appSettings
    }

    public var body: some View {
        VStack(spacing: 10) {
            saveModeCard
            scrollingCaptureCard
            colorPresetsCard
        }
    }

    // MARK: - Save Mode Card
    private var saveModeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizationManager.shared.tr(.saveMode))
                .font(.system(size: 12.5, weight: .semibold))

            Picker("", selection: $appSettings.autoSaveEnabled) {
                Text(LocalizationManager.shared.tr(.saveModePrompt)).tag(false)
                Text(LocalizationManager.shared.tr(.saveModeAuto)).tag(true)
            }
            .labelsHidden()
            .pickerStyle(.radioGroup)

            if appSettings.autoSaveEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(LocalizationManager.shared.tr(.saveDirectory))
                            .font(.system(size: 11.5))
                            .frame(width: 100, alignment: .leading)

                        Text(appSettings.autoSaveDirectory.path)
                            .font(.system(size: 10.5, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(4)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(4)

                        Button(LocalizationManager.shared.tr(.chooseDirectoryButton)) {
                            chooseDirectory()
                        }
                        .controlSize(.small)
                        .pointingHandCursor()

                        Button(action: {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: appSettings.autoSaveDirectory.path)
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "folder")
                                    .font(.system(size: 10))
                                Text(LocalizationManager.shared.tr(.openInFinder))
                                    .font(.system(size: 11))
                            }
                        }
                        .controlSize(.small)
                        .pointingHandCursor()
                        .help(LocalizationManager.shared.tr(.openInFinder))
                    }

                    HStack {
                        Text(LocalizationManager.shared.tr(.saveFormat))
                            .font(.system(size: 11.5))
                            .frame(width: 100, alignment: .leading)

                        Picker("", selection: $appSettings.saveFormat) {
                            Text(LocalizationManager.shared.tr(.formatPNG)).tag(ImageSaveFormat.png)
                            Text(LocalizationManager.shared.tr(.formatJPEG)).tag(ImageSaveFormat.jpeg)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 160)

                        if appSettings.saveFormat == .jpeg {
                            Text("\(Int(appSettings.jpegQuality * 100))%")
                                .font(.system(size: 11))
                            Slider(value: $appSettings.jpegQuality, in: 0.1...1.0)
                                .frame(width: 80)
                        }
                    }

                    HStack(spacing: 4) {
                        Text(localizationManager.tr(.filenamePreviewLabel))
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                        Text(sampleFilename())
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                    .padding(.top, 2)
                }
                .padding(.leading, 18)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = appSettings.autoSaveDirectory
        if panel.runModal() == .OK, let url = panel.url {
            appSettings.autoSaveDirectory = url
        }
    }

    private func sampleFilename() -> String {
        let ext = appSettings.saveFormat == .png ? "png" : "jpg"
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screenshot_\(df.string(from: Date())).\(ext)"
    }

    // MARK: - Scrolling Capture Settings Card
    private var scrollingCaptureCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizationManager.shared.tr(.scrollingCaptureSettings))
                .font(.system(size: 12.5, weight: .semibold))

            HStack {
                Text(LocalizationManager.shared.tr(.maxScrollHeight))
                    .font(.system(size: 11.5))
                    .frame(width: 140, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { Double(appSettings.maxScrollHeightPx) },
                        set: { appSettings.maxScrollHeightPx = Int($0) }
                    ),
                    in: 5000...30000,
                    step: 1000
                )

                Text("\(appSettings.maxScrollHeightPx) px")
                    .font(.system(size: 11.5, design: .monospaced))
                    .frame(width: 70, alignment: .trailing)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Color Presets Management Card
    private var colorPresetsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(LocalizationManager.shared.tr(.colorPresetsManagement))
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Text("\(appSettings.presets.count) / \(AppSettings.maxPresetsCount)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            // Swatch Grid
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 8), count: 8), spacing: 8) {
                ForEach(appSettings.presets) { preset in
                    Circle()
                        .fill(preset.toColor())
                        .frame(width: 26, height: 26)
                        .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1))
                        .overlay(
                            Circle()
                                .stroke(Color.accentColor, lineWidth: preset.hex.caseInsensitiveCompare(appSettings.activeColorHex) == .orderedSame ? 2.5 : 0)
                        )
                        .contentShape(Circle())
                        .contextMenu {
                            Button(LocalizationManager.shared.tr(.deletePreset)) {
                                appSettings.deletePreset(id: preset.id)
                            }
                            .disabled(appSettings.presets.count <= 1)
                        }
                        .help("\(preset.name) (\(preset.hex))")
                        .pointingHandCursor()
                        .onTapGesture {
                            appSettings.activeColorHex = preset.hex
                        }
                }
            }
            .padding(.vertical, 4)

            // Add Custom Preset Row
            HStack(spacing: 8) {
                // Live Color Preview Swatch
                RoundedRectangle(cornerRadius: 4)
                    .fill(ColorPreset.isValid(hex: newPresetHex) ? Color(hex: ColorPreset.normalize(hex: newPresetHex)) : Color.clear)
                    .frame(width: 24, height: 24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                    )

                TextField("#RRGGBB", text: $newPresetHex)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 95)

                // Eyedropper Button
                Button(action: activateEyedropper) {
                    Image(systemName: "eyedropper")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 24, height: 24)
                        .background(Color.primary.opacity(0.08))
                        .cornerRadius(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help(LocalizationManager.shared.tr(.eyedropperTooltip))

                Button(LocalizationManager.shared.tr(.addPreset)) {
                    if ColorPreset.isValid(hex: newPresetHex) {
                        let normalized = ColorPreset.normalize(hex: newPresetHex)
                        let newP = ColorPreset(name: LocalizationManager.shared.tr(.customColorPreset), hex: normalized)
                        if appSettings.addPreset(newP) {
                            newPresetHex = ""
                            showingHexError = false
                        }
                    } else {
                        showingHexError = true
                    }
                }
                .controlSize(.small)
                .pointingHandCursor()
                .disabled(appSettings.presets.count >= AppSettings.maxPresetsCount || newPresetHex.trimmingCharacters(in: .whitespaces).isEmpty)

                Spacer()

                Button(LocalizationManager.shared.tr(.resetPresetsButton)) {
                    showingResetPresetsConfirmation = true
                }
                .controlSize(.small)
                .pointingHandCursor()
                .confirmationDialog(
                    LocalizationManager.shared.tr(.resetPresets),
                    isPresented: $showingResetPresetsConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(LocalizationManager.shared.tr(.resetPresets), role: .destructive) {
                        appSettings.resetPresets()
                    }
                    Button(LocalizationManager.shared.tr(.actionCancel), role: .cancel) {}
                }
            }

            if showingHexError {
                Text(LocalizationManager.shared.tr(.invalidHexCode))
                    .font(.system(size: 10.5))
                    .foregroundColor(.red)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func activateEyedropper() {
        let sampler = NSColorSampler()
        sampler.show { selectedColor in
            guard let color = selectedColor,
                  let rgbColor = color.usingColorSpace(.sRGB) else { return }
            let r = Int(round(rgbColor.redComponent * 255.0))
            let g = Int(round(rgbColor.greenComponent * 255.0))
            let b = Int(round(rgbColor.blueComponent * 255.0))
            let hex = String(format: "#%02X%02X%02X", r, g, b)
            DispatchQueue.main.async {
                self.newPresetHex = hex
                self.showingHexError = false
            }
        }
    }
}
