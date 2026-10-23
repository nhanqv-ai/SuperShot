import AppKit
import SwiftUI
import Combine
import SuperShotCore

// MARK: - Annotation Tool Definition

public enum AnnotationToolType: Int, CaseIterable, Identifiable, Sendable {
    case select = 1
    case rectangle = 2
    case ellipse = 3
    case arrow = 4
    case line = 5
    case pen = 6
    case highlighter = 7
    case text = 8
    case blur = 9

    public var id: Int { rawValue }

    public var sfSymbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .text: return "textformat"
        case .blur: return "checkerboard.rectangle"
        }
    }

    public var localizedName: String {
        switch self {
        case .select: return LocalizationManager.shared.tr(.toolSelect)
        case .rectangle: return LocalizationManager.shared.tr(.toolRectangle)
        case .ellipse: return LocalizationManager.shared.tr(.toolEllipse)
        case .arrow: return LocalizationManager.shared.tr(.toolArrow)
        case .line: return LocalizationManager.shared.tr(.toolLine)
        case .pen: return LocalizationManager.shared.tr(.toolPen)
        case .highlighter: return LocalizationManager.shared.tr(.toolHighlighter)
        case .text: return LocalizationManager.shared.tr(.toolText)
        case .blur: return LocalizationManager.shared.tr(.toolBlur)
        }
    }

    public var shortcutKey: String {
        "\(rawValue)"
    }
}

// MARK: - Edge-Aware Layout Math Engine

public struct ToolbarLayoutCalculator {
    public static let verticalToolbarSize = CGSize(width: 44, height: 388)
    public static let horizontalToolbarSize = CGSize(width: 236, height: 42)
    public static let defaultMargin: CGFloat = 8.0
    public static let screenEdgePadding: CGFloat = 8.0

    public static func computeLayout(
        selectionRect: CGRect,
        screenRect: CGRect,
        margin: CGFloat = defaultMargin,
        padding: CGFloat = screenEdgePadding
    ) -> (verticalFrame: CGRect, horizontalFrame: CGRect) {
        let vSize = verticalToolbarSize
        let hSize = horizontalToolbarSize

        // 1. Vertical Toolbar Positioning
        var vX = selectionRect.maxX + margin
        if vX + vSize.width > screenRect.maxX - padding {
            vX = selectionRect.minX - margin - vSize.width
            if vX < screenRect.minX + padding {
                vX = max(screenRect.minX + padding, min(selectionRect.maxX - vSize.width - margin, screenRect.maxX - vSize.width - padding))
            }
        }

        var vY = selectionRect.minY
        if vY + vSize.height > screenRect.maxY - padding {
            vY = screenRect.maxY - padding - vSize.height
        }
        if vY < screenRect.minY + padding {
            vY = screenRect.minY + padding
        }
        let vFrame = CGRect(x: vX, y: vY, width: vSize.width, height: vSize.height)

        // 2. Horizontal Action Toolbar Positioning
        var hY = selectionRect.maxY + margin
        if hY + hSize.height > screenRect.maxY - padding {
            hY = selectionRect.minY - margin - hSize.height
            if hY < screenRect.minY + padding {
                hY = max(screenRect.minY + padding, min(selectionRect.maxY - hSize.height - margin, screenRect.maxY - hSize.height - padding))
            }
        }

        var hX = selectionRect.maxX - hSize.width
        if hX + hSize.width > screenRect.maxX - padding {
            hX = screenRect.maxX - padding - hSize.width
        }
        if hX < screenRect.minX + padding {
            hX = screenRect.minX + padding
        }
        var hFrame = CGRect(x: hX, y: hY, width: hSize.width, height: hSize.height)

        // 3. Collision & Overlap Prevention
        if vFrame.intersects(hFrame) {
            let shiftedLeftX = vFrame.minX - margin - hSize.width
            if shiftedLeftX >= screenRect.minX + padding {
                hFrame.origin.x = shiftedLeftX
            } else if vFrame.maxX + margin + hSize.width <= screenRect.maxX - padding {
                hFrame.origin.x = vFrame.maxX + margin
            } else if vFrame.minY - margin - hSize.height >= screenRect.minY + padding {
                hFrame.origin.y = vFrame.minY - margin - hSize.height
            } else if vFrame.maxY + margin + hSize.height <= screenRect.maxY - padding {
                hFrame.origin.y = vFrame.maxY + margin
            }
        }

        return (vFrame, hFrame)
    }
}

// MARK: - Floating Toolbars State Coordinator

public final class FloatingToolbarsViewModel: ObservableObject {
    @Published public var activeTool: AnnotationToolType = .select
    @Published public var canUndo: Bool = false
    @Published public var canRedo: Bool = false
    @Published public var isColorPalettePresented: Bool = false
    @Published public var isStrokeWidthPresented: Bool = false
    @Published public var selectionRect: CGRect = .zero

    public let appSettings: AppSettings
    public var onCopyRequested: (() -> Void)?
    public var onSaveRequested: (() -> Void)?
    public var onShareRequested: ((NSView) -> Void)?
    public var onScrollCaptureRequested: (() -> Void)?
    public var onCancelRequested: (() -> Void)?
    public var onUndoRequested: (() -> Void)?
    public var onRedoRequested: (() -> Void)?
    public var onToolChanged: ((AnnotationToolType) -> Void)?

    public init(appSettings: AppSettings = .init()) {
        self.appSettings = appSettings
    }

    public func selectTool(_ tool: AnnotationToolType) {
        activeTool = tool
        onToolChanged?(tool)
    }

    public func triggerCopy() { onCopyRequested?() }
    public func triggerSave() { onSaveRequested?() }
    public func triggerShare(from view: NSView) { onShareRequested?(view) }
    public func triggerScrollCapture() { onScrollCaptureRequested?() }
    public func triggerCancel() { onCancelRequested?() }
    public func triggerUndo() { if canUndo { onUndoRequested?() } }
    public func triggerRedo() { if canRedo { onRedoRequested?() } }
}

// MARK: - Vertical Annotation Toolbar View

public struct VerticalAnnotationToolbarView: View {
    @ObservedObject public var viewModel: FloatingToolbarsViewModel
    @ObservedObject public var appSettings: AppSettings

    public init(viewModel: FloatingToolbarsViewModel, appSettings: AppSettings) {
        self.viewModel = viewModel
        self.appSettings = appSettings
    }

    public var body: some View {
        VStack(spacing: 4) {
            ForEach(AnnotationToolType.allCases) { tool in
                ToolIconButton(
                    icon: tool.sfSymbol,
                    tooltip: "\(tool.localizedName) (\(tool.shortcutKey))",
                    isSelected: viewModel.activeTool == tool
                ) {
                    viewModel.selectTool(tool)
                }
            }

            ToolbarDivider()

            Button(action: { viewModel.isStrokeWidthPresented.toggle() }) {
                ZStack {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                }
                .frame(width: 32, height: 32)
                .background(viewModel.isStrokeWidthPresented ? Color.white.opacity(0.2) : Color.clear)
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            .help("\(LocalizationManager.shared.tr(.strokeWidth)): \(Int(appSettings.activeStrokeWidth))pt / \(LocalizationManager.shared.tr(.fontSize)): \(Int(appSettings.activeFontSize))pt")
            .popover(isPresented: $viewModel.isStrokeWidthPresented, arrowEdge: .leading) {
                StrokeWidthPopoverView(appSettings: appSettings)
            }

            Button(action: { viewModel.isColorPalettePresented.toggle() }) {
                ZStack {
                    Circle()
                        .fill(Color(hex: appSettings.activeColorHex))
                        .frame(width: 20, height: 20)
                    Circle()
                        .stroke(Color.white, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                }
                .frame(width: 32, height: 32)
                .background(viewModel.isColorPalettePresented ? Color.white.opacity(0.2) : Color.clear)
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            .help(LocalizationManager.shared.tr(.colorPalette))
            .popover(isPresented: $viewModel.isColorPalettePresented, arrowEdge: .leading) {
                ColorPalettePopoverView(appSettings: appSettings)
            }

            ToolbarDivider()

            ToolIconButton(
                icon: "arrow.uturn.backward",
                tooltip: "\(LocalizationManager.shared.tr(.undoTooltip)) (Cmd+Z)",
                isEnabled: viewModel.canUndo
            ) {
                viewModel.triggerUndo()
            }

            ToolIconButton(
                icon: "arrow.uturn.forward",
                tooltip: "\(LocalizationManager.shared.tr(.redoTooltip)) (Cmd+Shift+Z)",
                isEnabled: viewModel.canRedo
            ) {
                viewModel.triggerRedo()
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: NSColor.windowBackgroundColor).opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 3)
        )
        .frame(width: ToolbarLayoutCalculator.verticalToolbarSize.width)
    }
}

// MARK: - Horizontal Action Toolbar View

public struct HorizontalActionToolbarView: View {
    @ObservedObject public var viewModel: FloatingToolbarsViewModel

    public init(viewModel: FloatingToolbarsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 6) {
            ActionButton(
                icon: "arrow.up.and.down.text.horizontal",
                tooltip: "\(LocalizationManager.shared.tr(.actionScrollCapture)) (Space)",
                tint: .blue
            ) {
                viewModel.triggerScrollCapture()
            }

            ToolbarVerticalDivider()

            ActionButton(
                icon: "doc.on.doc",
                tooltip: "\(LocalizationManager.shared.tr(.actionCopy)) (Cmd+C / Return)",
                tint: .green
            ) {
                viewModel.triggerCopy()
            }

            ActionButton(
                icon: "square.and.arrow.down",
                tooltip: "\(LocalizationManager.shared.tr(.actionSave)) (Cmd+S)",
                tint: .primary
            ) {
                viewModel.triggerSave()
            }

            ActionShareButton(viewModel: viewModel)

            ToolbarVerticalDivider()

            ActionButton(
                icon: "xmark",
                tooltip: "\(LocalizationManager.shared.tr(.actionCancel)) (Esc)",
                tint: .red
            ) {
                viewModel.triggerCancel()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: NSColor.windowBackgroundColor).opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 3)
        )
        .frame(height: ToolbarLayoutCalculator.horizontalToolbarSize.height)
    }
}

// MARK: - Stroke Width & Font Size Popover View

public struct StrokeWidthPopoverView: View {
    @ObservedObject public var appSettings: AppSettings
    public let strokeWidthOptions: [Double] = [1.0, 2.0, 3.0, 5.0, 8.0, 12.0]
    public let fontSizeOptions: [Double] = [12.0, 14.0, 18.0, 24.0, 36.0, 48.0]

    public init(appSettings: AppSettings) {
        self.appSettings = appSettings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LocalizationManager.shared.tr(.strokeWidth))
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)

            HStack(spacing: 6) {
                ForEach(strokeWidthOptions, id: \.self) { width in
                    Button(action: { appSettings.activeStrokeWidth = width }) {
                        ZStack {
                            Circle()
                                .fill(appSettings.activeStrokeWidth == width ? Color.accentColor : Color.primary.opacity(0.15))
                                .frame(width: 24, height: 24)
                            Circle()
                                .fill(appSettings.activeStrokeWidth == width ? Color.white : Color.primary)
                                .frame(width: CGFloat(width), height: CGFloat(width))
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("\(Int(width)) px")
                }
            }

            Divider()

            Text(LocalizationManager.shared.tr(.fontSize))
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)

            HStack(spacing: 6) {
                ForEach(fontSizeOptions, id: \.self) { size in
                    Button(action: { appSettings.activeFontSize = size }) {
                        Text("\(Int(size))")
                            .font(.system(size: 11, weight: appSettings.activeFontSize == size ? .bold : .regular))
                            .foregroundColor(appSettings.activeFontSize == size ? .white : .primary)
                            .frame(width: 26, height: 22)
                            .background(appSettings.activeFontSize == size ? Color.accentColor : Color.primary.opacity(0.1))
                            .cornerRadius(4)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("\(Int(size)) pt")
                }
            }
        }
        .padding(10)
        .frame(width: 210)
    }
}

// MARK: - Reusable Buttons & Helpers

public struct ToolIconButton: View {
    public let icon: String
    public let tooltip: String
    public var isSelected: Bool = false
    public var isEnabled: Bool = true
    public let action: () -> Void

    public init(icon: String, tooltip: String, isSelected: Bool = false, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.icon = icon
        self.tooltip = tooltip
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button(action: { if isEnabled { action() } }) {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor)
                }
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? .white : (isEnabled ? .primary : .secondary.opacity(0.4)))
            }
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isEnabled)
        .help(tooltip)
    }
}

public struct ActionButton: View {
    public let icon: String
    public let tooltip: String
    public var tint: Color = .primary
    public let action: () -> Void

    public init(icon: String, tooltip: String, tint: Color = .primary, action: @escaping () -> Void) {
        self.icon = icon
        self.tooltip = tooltip
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(tint)
                .frame(width: 32, height: 32)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
        .help(tooltip)
    }
}

public struct ActionShareButton: View {
    @ObservedObject public var viewModel: FloatingToolbarsViewModel
    @State private var hostingViewRef: NSView?

    public init(viewModel: FloatingToolbarsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Button(action: {
            if let view = hostingViewRef {
                viewModel.triggerShare(from: view)
            }
        }) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: 32, height: 32)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
        .help("\(LocalizationManager.shared.tr(.shareButton))")
        .background(ViewAccessor(viewRef: $hostingViewRef))
    }
}

public struct ToolbarDivider: View {
    public init() {}
    public var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(width: 24, height: 1)
            .padding(.vertical, 2)
    }
}

public struct ToolbarVerticalDivider: View {
    public init() {}
    public var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 2)
    }
}

public struct ViewAccessor: NSViewRepresentable {
    @Binding public var viewRef: NSView?

    public init(viewRef: Binding<NSView?>) {
        self._viewRef = viewRef
    }

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.viewRef = view
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Keyboard Shortcut Handler

public struct ToolbarKeyShortcutHandler {
    public static func handleKeyEvent(
        event: NSEvent,
        viewModel: FloatingToolbarsViewModel
    ) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = event.keyCode

        // 1. Escape (Cancel / Dismiss)
        if keyCode == 53 {
            viewModel.triggerCancel()
            return true
        }

        // 2. Return (Copy & Dismiss)
        if keyCode == 36 && flags.isEmpty {
            viewModel.triggerCopy()
            return true
        }

        // 3. Space (Scroll Capture / Pause)
        if keyCode == 49 && flags.isEmpty {
            viewModel.triggerScrollCapture()
            return true
        }

        // 4. Command + C (Copy)
        if flags == .command && keyCode == 8 {
            viewModel.triggerCopy()
            return true
        }

        // 5. Command + S (Save)
        if flags == .command && keyCode == 1 {
            viewModel.triggerSave()
            return true
        }

        // 6. Command + Shift + Z (Redo)
        if flags == [.command, .shift] && keyCode == 6 {
            viewModel.triggerRedo()
            return true
        }

        // 7. Command + Z (Undo)
        if flags == .command && keyCode == 6 {
            viewModel.triggerUndo()
            return true
        }

        // 8. Number shortcuts 1..9 (Tool Selection)
        if flags.isEmpty {
            switch keyCode {
            case 18: viewModel.selectTool(.select); return true
            case 19: viewModel.selectTool(.rectangle); return true
            case 20: viewModel.selectTool(.ellipse); return true
            case 21: viewModel.selectTool(.arrow); return true
            case 23: viewModel.selectTool(.line); return true
            case 22: viewModel.selectTool(.pen); return true
            case 26: viewModel.selectTool(.highlighter); return true
            case 28: viewModel.selectTool(.text); return true
            case 25: viewModel.selectTool(.blur); return true
            default: break
            }
        }

        return false
    }
}

// MARK: - Color Extension for Hex Construction

extension Color {
    public init(hex: String) {
        let normalized = ColorPreset.normalize(hex: hex)
        var clean = normalized
        if clean.hasPrefix("#") { clean.removeFirst() }
        let scanner = Scanner(string: clean)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        let r = Double((rgbValue >> 16) & 0xFF) / 255.0
        let g = Double((rgbValue >> 8) & 0xFF) / 255.0
        let b = Double(rgbValue & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}
