import AppKit
import SwiftUI
import SuperShotCore

// MARK: - Color Palette Popover View

public struct ColorPalettePopoverView: View {
    @ObservedObject public var appSettings: AppSettings
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @State private var hexInputText: String = ""
    @State private var isHexValid: Bool = true
    @State private var feedbackMessage: String?
    public var onColorChanged: ((String) -> Void)?

    public init(appSettings: AppSettings, onColorChanged: ((String) -> Void)? = nil) {
        self.appSettings = appSettings
        self.onColorChanged = onColorChanged
        _hexInputText = State(initialValue: appSettings.activeColorHex)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(LocalizationManager.shared.tr(.colorPalette))
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Text("\(appSettings.presets.count)/\(AppSettings.maxPresetsCount)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }

            // Swatch Grid (Up to 16 presets in 2 rows of 8)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 6), count: 8), spacing: 6) {
                ForEach(appSettings.presets) { preset in
                    PresetSwatchButton(
                        preset: preset,
                        isSelected: preset.hex.caseInsensitiveCompare(appSettings.activeColorHex) == .orderedSame,
                        onSelect: { selectPreset(preset) },
                        onDelete: { deletePreset(preset) },
                        onReset: { resetPresets() }
                    )
                }
            }

            Divider()

            // Custom HEX Input & Eyedropper Row
            HStack(spacing: 8) {
                // Color Preview
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: appSettings.activeColorHex))
                    .frame(width: 26, height: 26)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )

                // Hex Text Field
                HStack(spacing: 2) {
                    Text("#")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    TextField("RRGGBB", text: $hexInputText)
                        .font(.system(size: 12, design: .monospaced))
                        .textFieldStyle(PlainTextFieldStyle())
                        .frame(width: 60)
                        .onChange(of: hexInputText) { newValue in
                            handleHexInputChange(newValue)
                        }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isHexValid ? Color.clear : Color.red, lineWidth: 1)
                )

                // Native macOS Eyedropper Tool
                Button(action: activateEyedropper) {
                    Image(systemName: "eyedropper")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 26, height: 26)
                        .background(Color.primary.opacity(0.08))
                        .cornerRadius(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .pointingHandCursor()
                .help(LocalizationManager.shared.tr(.eyedropperTooltip))

                // Save Preset Button (+)
                Button(action: saveCurrentColorAsPreset) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(canAddPreset ? .primary : .secondary.opacity(0.4))
                        .frame(width: 26, height: 26)
                        .background(Color.primary.opacity(canAddPreset ? 0.08 : 0.03))
                        .cornerRadius(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!canAddPreset)
                .pointingHandCursor(isEnabled: canAddPreset)
                .help(canAddPreset ? LocalizationManager.shared.tr(.addPreset) : LocalizationManager.shared.tr(.maxPresetsReached))
            }

            // Quick Status / Feedback Line
            if let msg = feedbackMessage {
                Text(msg)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(width: 280)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            hexInputText = appSettings.activeColorHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        }
    }

    private var canAddPreset: Bool {
        appSettings.presets.count < AppSettings.maxPresetsCount
    }

    private func selectPreset(_ preset: ColorPreset) {
        appSettings.activeColorHex = preset.hex
        hexInputText = preset.hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        isHexValid = true
        feedbackMessage = nil
        onColorChanged?(preset.hex)
    }

    private func handleHexInputChange(_ input: String) {
        let clean = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if ColorPreset.isValid(hex: clean) {
            isHexValid = true
            let normalized = ColorPreset.normalize(hex: clean)
            appSettings.activeColorHex = normalized
            feedbackMessage = nil
            onColorChanged?(normalized)
        } else {
            isHexValid = clean.isEmpty || clean.count < 6
            if clean.count == 6 && !ColorPreset.isValid(hex: clean) {
                feedbackMessage = LocalizationManager.shared.tr(.invalidHexCode)
            }
        }
    }

    private func activateEyedropper() {
        let sampler = NSColorSampler()
        sampler.show { selectedColor in
            guard let color = selectedColor else { return }
            guard let rgbColor = color.usingColorSpace(.sRGB) else { return }
            let r = Int(round(rgbColor.redComponent * 255.0))
            let g = Int(round(rgbColor.greenComponent * 255.0))
            let b = Int(round(rgbColor.blueComponent * 255.0))
            let hex = String(format: "#%02X%02X%02X", r, g, b)

            DispatchQueue.main.async {
                self.appSettings.activeColorHex = hex
                self.hexInputText = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                self.isHexValid = true
                self.feedbackMessage = nil
                self.onColorChanged?(hex)
            }
        }
    }

    private func saveCurrentColorAsPreset() {
        guard canAddPreset else {
            feedbackMessage = LocalizationManager.shared.tr(.maxPresetsReached)
            return
        }
        let hex = ColorPreset.normalize(hex: appSettings.activeColorHex)
        let preset = ColorPreset(name: "Preset \(appSettings.presets.count + 1)", hex: hex)
        let added = appSettings.addPreset(preset)
        if !added {
            feedbackMessage = LocalizationManager.shared.tr(.maxPresetsReached)
        }
    }

    private func deletePreset(_ preset: ColorPreset) {
        appSettings.deletePreset(id: preset.id)
    }

    private func resetPresets() {
        appSettings.resetPresets()
    }
}

// MARK: - Individual Swatch Button with Context Menu

public struct PresetSwatchButton: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    public let preset: ColorPreset
    public let isSelected: Bool
    public let onSelect: () -> Void
    public let onDelete: () -> Void
    public let onReset: () -> Void

    public init(preset: ColorPreset, isSelected: Bool, onSelect: @escaping () -> Void, onDelete: @escaping () -> Void, onReset: @escaping () -> Void) {
        self.preset = preset
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onDelete = onDelete
        self.onReset = onReset
    }

    public var body: some View {
        Button(action: onSelect) {
            ZStack {
                Circle()
                    .fill(preset.toColor())
                    .frame(width: 22, height: 22)

                if isSelected {
                    Circle()
                        .stroke(Color.accentColor, lineWidth: 2)
                        .frame(width: 26, height: 26)
                } else {
                    Circle()
                        .stroke(Color.primary.opacity(0.2), lineWidth: 0.5)
                        .frame(width: 22, height: 22)
                }
            }
            .frame(width: 26, height: 26)
            .contentShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
        .pointingHandCursor()
        .help("\(preset.name) (\(preset.hex))")
        .contextMenu {
            Button(LocalizationManager.shared.tr(.deletePreset)) {
                onDelete()
            }
            Divider()
            Button(LocalizationManager.shared.tr(.resetPresets)) {
                onReset()
            }
        }
    }
}

// MARK: - AppKit Popover Controller Bridge

public final class ColorPalettePopoverController: NSViewController {
    public let appSettings: AppSettings
    public var onColorChanged: ((String) -> Void)?

    public init(appSettings: AppSettings, onColorChanged: ((String) -> Void)? = nil) {
        self.appSettings = appSettings
        self.onColorChanged = onColorChanged
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        let rootView = ColorPalettePopoverView(appSettings: appSettings, onColorChanged: onColorChanged)
        self.view = NSHostingView(rootView: rootView)
    }
}
