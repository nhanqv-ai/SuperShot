import Foundation
import Combine

/// Supported application languages in SuperShot.
public enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case system = "system"
    case english = "en"
    case vietnamese = "vi"
    case german = "de"
    case french = "fr"
    case spanish = "es"
    case japanese = "ja"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case korean = "ko"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "System Default"
        case .english: return "English"
        case .vietnamese: return "Tiếng Việt"
        case .german: return "Deutsch"
        case .french: return "Français"
        case .spanish: return "Español"
        case .japanese: return "日本語"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .korean: return "한국어"
        }
    }

    public var localeIdentifier: String {
        switch self {
        case .system: return Locale.current.identifier
        case .english: return "en"
        case .vietnamese: return "vi"
        case .german: return "de"
        case .french: return "fr"
        case .spanish: return "es"
        case .japanese: return "ja"
        case .simplifiedChinese: return "zh-Hans"
        case .traditionalChinese: return "zh-Hant"
        case .korean: return "ko"
        }
    }
}

/// Centralized localization manager providing dynamic runtime translation across 9 languages.
public final class LocalizationManager: ObservableObject, @unchecked Sendable {
    public static let shared = LocalizationManager()
    public static let languageDidChangeNotification = Notification.Name("SuperShotLanguageDidChangeNotification")

    private let lock = NSLock()

    @Published public private(set) var currentLanguage: AppLanguage = .system {
        didSet {
            effectiveLanguage = resolveEffectiveLanguage(currentLanguage)
        }
    }

    @Published public private(set) var effectiveLanguage: AppLanguage = .english

    public init() {
        self.effectiveLanguage = resolveEffectiveLanguage(.system)
    }

    public func setLanguage(_ language: AppLanguage) {
        lock.lock()
        self.currentLanguage = language
        self.effectiveLanguage = resolveEffectiveLanguage(language)
        lock.unlock()
        NotificationCenter.default.post(name: LocalizationManager.languageDidChangeNotification, object: self)
    }

    public func setLanguage(code: String) {
        let lang = AppLanguage(rawValue: code) ?? .system
        setLanguage(lang)
    }

    public func resolveEffectiveLanguage(_ lang: AppLanguage) -> AppLanguage {
        if lang != .system {
            return lang
        }
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        if preferred.hasPrefix("vi") { return .vietnamese }
        if preferred.hasPrefix("zh-hant") || preferred.hasPrefix("zh-tw") || preferred.hasPrefix("zh-hk") {
            return .traditionalChinese
        }
        if preferred.hasPrefix("zh") { return .simplifiedChinese }
        if preferred.hasPrefix("ja") { return .japanese }
        if preferred.hasPrefix("ko") { return .korean }
        if preferred.hasPrefix("es") { return .spanish }
        if preferred.hasPrefix("fr") { return .french }
        if preferred.hasPrefix("de") { return .german }
        return .english
    }

    public func tr(_ key: L10nKey) -> String {
        lock.lock()
        let lang = effectiveLanguage
        lock.unlock()
        return key.localized(for: lang)
    }
}

/// Strongly-typed localization keys covering all user-facing strings across SuperShot.
public enum L10nKey: Sendable {
    // General App & Controls
    case appTitle
    case searchPlaceholder
    case preferencesTooltip
    case dismissTooltip
    case quitTooltip
    case doneButton
    case cancelButton
    case saveButton
    case copyButton
    case deleteButton
    case pinButton
    case unpinButton
    case shareButton
    case okButton
    case closeButton

    // Overlay Capture & Selection Box
    case captureOverlayInstruction
    case dimensionBadge(Int, Int)
    case fullscreenCapture
    case windowCapture

    // Vertical Annotation Toolbar Tools
    case toolSelect
    case toolRectangle
    case toolEllipse
    case toolArrow
    case toolLine
    case toolPen
    case toolHighlighter
    case toolText
    case toolBlur
    case strokeWidth
    case fontSize
    case undoTooltip
    case redoTooltip

    // Color Palette & Presets
    case colorPalette
    case hexInputPlaceholder
    case eyedropperTooltip
    case addPreset
    case deletePreset
    case resetPresets
    case maxPresetsReached
    case invalidHexCode
    case presetRed
    case presetOrange
    case presetYellow
    case presetGreen
    case presetBlue
    case presetIndigo
    case presetPurple
    case presetBlack

    // Horizontal Action Toolbar
    case actionScrollCapture
    case actionCopy
    case actionSave
    case actionShare
    case actionCancel
    case copiedToClipboard
    case savedToFile

    // Scrolling Capture Engine & Canvas
    case scrollCapturing
    case scrollAutoMode
    case scrollManualMode
    case scrollDoneInstruction
    case scrollMaxHeightReached
    case scrollBottomReached
    case liveStitchedPreview
    case stitchedHeight(Int)

    // History Popover & MainShotView
    case pinnedSection
    case recentSection
    case emptyHistoryTitle
    case emptyHistorySubtitle
    case noMatchingResults
    case refineSearch
    case clearHistory
    case itemCount(Int, Int)
    case dimensionTag(Int, Int)
    case directAutoPaste
    case quickSelectHint
    case openInFinder

    // Status Item Context Menu
    case menuCapture
    case menuScrollingCapture
    case menuShowHistory
    case menuPreferences
    case menuClearHistory
    case menuCheckUpdates
    case menuQuit

    // Settings Window & Tabs
    case tabGeneral
    case tabCaptureSave
    case tabHistory
    case tabAbout

    // Settings Tab 1: General
    case launchAtLogin
    case globalHotkeys
    case inPlaceCaptureShortcut
    case scrollingCaptureShortcut
    case recordShortcut
    case pressShortcutHint
    case pressShortcutCancelHint
    case languageLabel
    case screenRecordingPermission
    case accessibilityPermission
    case permissionGranted
    case permissionRequired
    case grantPermissionButton
    case recheckPermissionButton
    case screenRecordingGuide
    case accessibilityGuide
    case autoPasteOnSelection

    // Settings Tab 2: Capture & Save
    case saveMode
    case saveModePrompt
    case saveModeAuto
    case saveDirectory
    case chooseDirectoryButton
    case saveFormat
    case formatPNG
    case formatJPEG
    case scrollingCaptureSettings
    case maxScrollHeight
    case maxScrollHeightUnit
    case autoScrollSpeed
    case colorPresetsManagement
    case resetPresetsButton

    // Settings Tab 3: History Management
    case historyCapacity
    case historyCapacityUnit
    case rememberLabel
    case pinProtectionTitle
    case pinProtectionDesc
    case storageStatistics
    case totalScreenshots
    case pinnedScreenshots
    case unpinnedScreenshots
    case diskUsage
    case clearUnpinnedConfirmTitle
    case clearUnpinnedConfirmMessage
    case clearConfirmButton

    // Settings Tab 4: About
    case versionLabel(String)
    case buildLabel(String)
    case appDescription
    case licenseLabel
    case authorLabel
    case resetAllDefaults
    case resetAllConfirmTitle
    case resetAllConfirmMessage

    // Updates & System Alerts
    case checkingForUpdates
    case updateAvailable(String)
    case upToDate
    case downloadUpdate
    case installAndRestart
    case automaticallyCheckForUpdates
    case updateCheckIntervalLabel
    case intervalDaily
    case intervalWeekly
    case intervalMonthly
    case updateNow
    case later
    case releaseNotes
    case updateReadyRestart
    case restart
    case downloadingUpdate

    // Polish & Onboarding (v1.0.9)
    case permissionsSectionTitle
    case filenamePreviewLabel
    case clearSearchTooltip
    case clearSearchButton
    case quickCaptureRegion
    case quickCaptureScroll
    case welcomeTitle
    case welcomeSubtitle
    case getStartedButton
    case welcomeGuideButton

    // Feature Cards & UI Polish (v1.0.10)
    case welcomeFeature1Title
    case welcomeFeature1Desc
    case welcomeFeature2Title
    case welcomeFeature2Desc
    case welcomeFeature3Title
    case welcomeFeature3Desc
    case zoomOutTooltip
    case zoomActualSizeTooltip
    case zoomInTooltip
    case zoomFitWidthTooltip
    case strokeWidthHUD(Int)
    case resetShortcutTooltip(String)
    case previewCancelTooltip
    case previewDoneTooltip
    case actionShareTooltip
    case annotationsCleared

    // Layer Z-Index & Zoom HUD (v1.0.17)
    case layerBringToFront
    case layerSendToBack
    case layerBringForward
    case layerSendBackward
    case zoomHUD(Int)

    // Live Progress, Deletion Feedback & Diagnostics (v1.0.18)
    case framesCount(Int)
    case screenshotDeleted
    case unpinnedHistoryCleared
    case copiedDiagnostics

    public func localized(for lang: AppLanguage) -> String {
        switch self {
        case .appTitle:
            return "SuperShot"

        case .searchPlaceholder:
            switch lang {
            case .vietnamese: return "Tìm kiếm ảnh chụp..."
            case .german: return "Aufnahmen suchen..."
            case .french: return "Rechercher des captures..."
            case .spanish: return "Buscar capturas..."
            case .japanese: return "スクリーンショットを検索..."
            case .simplifiedChinese: return "搜索截屏..."
            case .traditionalChinese: return "搜尋截圖..."
            case .korean: return "스크린샷 검색..."
            default: return "Search screenshots..."
            }

        case .preferencesTooltip:
            switch lang {
            case .vietnamese: return "Cài đặt (Cmd+,)"
            case .german: return "Einstellungen (Cmd+,)"
            case .french: return "Préférences (Cmd+,)"
            case .spanish: return "Preferencias (Cmd+,)"
            case .japanese: return "環境設定 (Cmd+,)"
            case .simplifiedChinese: return "偏好设置 (Cmd+,)"
            case .traditionalChinese: return "偏好設定 (Cmd+,)"
            case .korean: return "환경설정 (Cmd+,)"
            default: return "Preferences (Cmd+,)"
            }

        case .dismissTooltip:
            switch lang {
            case .vietnamese: return "Đóng (Escape)"
            case .german: return "Schließen (Escape)"
            case .french: return "Fermer (Escape)"
            case .spanish: return "Cerrar (Escape)"
            case .japanese: return "閉じる (Escape)"
            case .simplifiedChinese: return "关闭 (Escape)"
            case .traditionalChinese: return "關閉 (Escape)"
            case .korean: return "닫기 (Escape)"
            default: return "Dismiss (Escape)"
            }

        case .quitTooltip:
            switch lang {
            case .vietnamese: return "Thoát (Cmd+Q)"
            case .german: return "Beenden (Cmd+Q)"
            case .french: return "Quitter (Cmd+Q)"
            case .spanish: return "Salir (Cmd+Q)"
            case .japanese: return "終了 (Cmd+Q)"
            case .simplifiedChinese: return "退出 (Cmd+Q)"
            case .traditionalChinese: return "結束 (Cmd+Q)"
            case .korean: return "종료 (Cmd+Q)"
            default: return "Quit (Cmd+Q)"
            }

        case .doneButton:
            switch lang {
            case .vietnamese: return "Xong"
            case .german: return "Fertig"
            case .french: return "Terminé"
            case .spanish: return "Listo"
            case .japanese: return "完了"
            case .simplifiedChinese: return "完成"
            case .traditionalChinese: return "完成"
            case .korean: return "완료"
            default: return "Done"
            }

        case .cancelButton:
            switch lang {
            case .vietnamese: return "Hủy"
            case .german: return "Abbrechen"
            case .french: return "Annuler"
            case .spanish: return "Cancelar"
            case .japanese: return "キャンセル"
            case .simplifiedChinese: return "取消"
            case .traditionalChinese: return "取消"
            case .korean: return "취소"
            default: return "Cancel"
            }

        case .saveButton:
            switch lang {
            case .vietnamese: return "Lưu"
            case .german: return "Speichern"
            case .french: return "Enregistrer"
            case .spanish: return "Guardar"
            case .japanese: return "保存"
            case .simplifiedChinese: return "保存"
            case .traditionalChinese: return "儲存"
            case .korean: return "저장"
            default: return "Save"
            }

        case .copyButton:
            switch lang {
            case .vietnamese: return "Sao chép"
            case .german: return "Kopieren"
            case .french: return "Copier"
            case .spanish: return "Copiar"
            case .japanese: return "コピー"
            case .simplifiedChinese: return "复制"
            case .traditionalChinese: return "複製"
            case .korean: return "복사"
            default: return "Copy"
            }

        case .deleteButton:
            switch lang {
            case .vietnamese: return "Xóa"
            case .german: return "Löschen"
            case .french: return "Supprimer"
            case .spanish: return "Eliminar"
            case .japanese: return "削除"
            case .simplifiedChinese: return "删除"
            case .traditionalChinese: return "刪除"
            case .korean: return "삭제"
            default: return "Delete"
            }

        case .pinButton:
            switch lang {
            case .vietnamese: return "Ghim"
            case .german: return "Anheften"
            case .french: return "Épingler"
            case .spanish: return "Fijar"
            case .japanese: return "ピン留め"
            case .simplifiedChinese: return "置顶"
            case .traditionalChinese: return "置頂"
            case .korean: return "고정"
            default: return "Pin"
            }

        case .unpinButton:
            switch lang {
            case .vietnamese: return "Bỏ ghim"
            case .german: return "Lösen"
            case .french: return "Désépingler"
            case .spanish: return "Desfijar"
            case .japanese: return "ピン留め解除"
            case .simplifiedChinese: return "取消置顶"
            case .traditionalChinese: return "取消置頂"
            case .korean: return "고정 해제"
            default: return "Unpin"
            }

        case .shareButton:
            switch lang {
            case .vietnamese: return "Chia sẻ"
            case .german: return "Teilen"
            case .french: return "Partager"
            case .spanish: return "Compartir"
            case .japanese: return "共有"
            case .simplifiedChinese: return "分享"
            case .traditionalChinese: return "分享"
            case .korean: return "공유"
            default: return "Share"
            }

        case .okButton:
            switch lang {
            case .vietnamese: return "Đồng ý"
            case .german: return "OK"
            case .french: return "OK"
            case .spanish: return "Aceptar"
            case .japanese: return "OK"
            case .simplifiedChinese: return "确定"
            case .traditionalChinese: return "確定"
            case .korean: return "확인"
            default: return "OK"
            }

        case .closeButton:
            switch lang {
            case .vietnamese: return "Đóng"
            case .german: return "Schließen"
            case .french: return "Fermer"
            case .spanish: return "Cerrar"
            case .japanese: return "閉じる"
            case .simplifiedChinese: return "关闭"
            case .traditionalChinese: return "關閉"
            case .korean: return "닫기"
            default: return "Close"
            }

        case .captureOverlayInstruction:
            switch lang {
            case .vietnamese: return "Kéo để chọn · ⌘A toàn màn hình · Shift hình vuông · Esc hủy"
            case .german: return "Bereich ziehen · ⌘A Vollbild · Shift Quadrat · Esc Abbrechen"
            case .french: return "Glisser pour sélectionner · ⌘A plein écran · Shift carré · Échap annuler"
            case .spanish: return "Arrastrar para seleccionar · ⌘A pantalla completa · Shift cuadrado · Esc cancelar"
            case .japanese: return "ドラッグで選択 · ⌘A 全画面 · Shift 正方形 · Esc キャンセル"
            case .simplifiedChinese: return "拖动选择 · ⌘A 全屏 · Shift 正方形 · Esc 取消"
            case .traditionalChinese: return "拖曳選取 · ⌘A 全螢幕 · Shift 正方形 · Esc 取消"
            case .korean: return "드래그하여 선택 · ⌘A 전체 화면 · Shift 정사각형 · Esc 취소"
            default: return "Drag to select · ⌘A full screen · Shift square · Esc cancel"
            }

        case .dimensionBadge(let w, let h):
            return "\(w) x \(h) px"

        case .fullscreenCapture:
            switch lang {
            case .vietnamese: return "Toàn màn hình"
            case .german: return "Vollbild"
            case .french: return "Plein écran"
            case .spanish: return "Pantalla completa"
            case .japanese: return "全画面"
            case .simplifiedChinese: return "全屏"
            case .traditionalChinese: return "全螢幕"
            case .korean: return "전체 화면"
            default: return "Full Screen"
            }

        case .windowCapture:
            switch lang {
            case .vietnamese: return "Cửa sổ"
            case .german: return "Fenster"
            case .french: return "Fenêtre"
            case .spanish: return "Ventana"
            case .japanese: return "ウィンドウ"
            case .simplifiedChinese: return "窗口"
            case .traditionalChinese: return "視窗"
            case .korean: return "창"
            default: return "Window"
            }

        case .toolSelect:
            switch lang {
            case .vietnamese: return "Chọn / Di chuyển"
            case .german: return "Auswählen / Bewegen"
            case .french: return "Sélectionner / Déplacer"
            case .spanish: return "Seleccionar / Mover"
            case .japanese: return "選択 / 移動"
            case .simplifiedChinese: return "选择 / 移动"
            case .traditionalChinese: return "選取 / 移動"
            case .korean: return "선택 / 이동"
            default: return "Select / Move"
            }

        case .toolRectangle:
            switch lang {
            case .vietnamese: return "Hình chữ nhật"
            case .german: return "Rechteck"
            case .french: return "Rectangle"
            case .spanish: return "Rectángulo"
            case .japanese: return "四角形"
            case .simplifiedChinese: return "矩形"
            case .traditionalChinese: return "矩形"
            case .korean: return "직사각형"
            default: return "Rectangle"
            }

        case .toolEllipse:
            switch lang {
            case .vietnamese: return "Hình elip"
            case .german: return "Ellipse"
            case .french: return "Ellipse"
            case .spanish: return "Elipse"
            case .japanese: return "楕円"
            case .simplifiedChinese: return "椭圆"
            case .traditionalChinese: return "橢圓"
            case .korean: return "타원"
            default: return "Ellipse"
            }

        case .toolArrow:
            switch lang {
            case .vietnamese: return "Mũi tên"
            case .german: return "Pfeil"
            case .french: return "Flèche"
            case .spanish: return "Flecha"
            case .japanese: return "矢印"
            case .simplifiedChinese: return "箭头"
            case .traditionalChinese: return "箭頭"
            case .korean: return "화살표"
            default: return "Arrow"
            }

        case .toolLine:
            switch lang {
            case .vietnamese: return "Đường thẳng"
            case .german: return "Linie"
            case .french: return "Ligne"
            case .spanish: return "Línea"
            case .japanese: return "直線"
            case .simplifiedChinese: return "直线"
            case .traditionalChinese: return "直線"
            case .korean: return "직선"
            default: return "Line"
            }

        case .toolPen:
            switch lang {
            case .vietnamese: return "Bút vẽ"
            case .german: return "Freihandstift"
            case .french: return "Stylo"
            case .spanish: return "Lápiz"
            case .japanese: return "ペン"
            case .simplifiedChinese: return "画笔"
            case .traditionalChinese: return "畫筆"
            case .korean: return "펜"
            default: return "Pen"
            }

        case .toolHighlighter:
            switch lang {
            case .vietnamese: return "Bút dạ quang"
            case .german: return "Textmarker"
            case .french: return "Surligneur"
            case .spanish: return "Resaltador"
            case .japanese: return "蛍光ペン"
            case .simplifiedChinese: return "荧光笔"
            case .traditionalChinese: return "螢光筆"
            case .korean: return "형광펜"
            default: return "Highlighter"
            }

        case .toolText:
            switch lang {
            case .vietnamese: return "Văn bản"
            case .german: return "Text"
            case .french: return "Texte"
            case .spanish: return "Texto"
            case .japanese: return "テキスト"
            case .simplifiedChinese: return "文本"
            case .traditionalChinese: return "文字"
            case .korean: return "텍스트"
            default: return "Text"
            }

        case .toolBlur:
            switch lang {
            case .vietnamese: return "Làm mờ / Điểm ảnh"
            case .german: return "Weichzeichnen / Verpixeln"
            case .french: return "Flouter / Pixelliser"
            case .spanish: return "Desenfocar / Pixelar"
            case .japanese: return "ぼかし / モザイク"
            case .simplifiedChinese: return "模糊 / 马赛克"
            case .traditionalChinese: return "模糊 / 馬賽克"
            case .korean: return "블러 / 모자이크"
            default: return "Blur / Pixelate"
            }

        case .strokeWidth:
            switch lang {
            case .vietnamese: return "Độ dày nét"
            case .german: return "Strichstärke"
            case .french: return "Épaisseur du trait"
            case .spanish: return "Grosor del trazo"
            case .japanese: return "線の太さ"
            case .simplifiedChinese: return "线条粗细"
            case .traditionalChinese: return "線條粗細"
            case .korean: return "선 굵기"
            default: return "Stroke Width"
            }

        case .fontSize:
            switch lang {
            case .vietnamese: return "Cỡ chữ"
            case .german: return "Schriftgröße"
            case .french: return "Taille de police"
            case .spanish: return "Tamaño de fuente"
            case .japanese: return "フォントサイズ"
            case .simplifiedChinese: return "字体大小"
            case .traditionalChinese: return "字型大小"
            case .korean: return "글꼴 크기"
            default: return "Font Size"
            }

        case .undoTooltip:
            switch lang {
            case .vietnamese: return "Hoàn tác (Cmd+Z)"
            case .german: return "Widerrufen (Cmd+Z)"
            case .french: return "Annuler (Cmd+Z)"
            case .spanish: return "Deshacer (Cmd+Z)"
            case .japanese: return "取り消し (Cmd+Z)"
            case .simplifiedChinese: return "撤销 (Cmd+Z)"
            case .traditionalChinese: return "復原 (Cmd+Z)"
            case .korean: return "실행 취소 (Cmd+Z)"
            default: return "Undo (Cmd+Z)"
            }

        case .redoTooltip:
            switch lang {
            case .vietnamese: return "Làm lại (Cmd+Shift+Z)"
            case .german: return "Wiederholen (Cmd+Shift+Z)"
            case .french: return "Rétablir (Cmd+Shift+Z)"
            case .spanish: return "Rehacer (Cmd+Shift+Z)"
            case .japanese: return "やり直し (Cmd+Shift+Z)"
            case .simplifiedChinese: return "重做 (Cmd+Shift+Z)"
            case .traditionalChinese: return "重做 (Cmd+Shift+Z)"
            case .korean: return "다시 실행 (Cmd+Shift+Z)"
            default: return "Redo (Cmd+Shift+Z)"
            }

        case .colorPalette:
            switch lang {
            case .vietnamese: return "Bảng màu"
            case .german: return "Farbpalette"
            case .french: return "Palette de couleurs"
            case .spanish: return "Paleta de colores"
            case .japanese: return "カラーパレット"
            case .simplifiedChinese: return "调色板"
            case .traditionalChinese: return "調色盤"
            case .korean: return "색상 팔레트"
            default: return "Color Palette"
            }

        case .hexInputPlaceholder:
            return "#RRGGBB"

        case .eyedropperTooltip:
            switch lang {
            case .vietnamese: return "Lấy màu màn hình"
            case .german: return "Farbe vom Bildschirm wählen"
            case .french: return "Prélever une couleur à l'écran"
            case .spanish: return "Cuentagotas de pantalla"
            case .japanese: return "画面から色を取得"
            case .simplifiedChinese: return "屏幕吸管取色"
            case .traditionalChinese: return "螢幕滴管取色"
            case .korean: return "화면 색상 추출"
            default: return "Pick Screen Color"
            }

        case .addPreset:
            switch lang {
            case .vietnamese: return "Thêm màu mẫu"
            case .german: return "Farbe speichern"
            case .french: return "Ajouter la couleur"
            case .spanish: return "Añadir preajuste"
            case .japanese: return "プリセットに追加"
            case .simplifiedChinese: return "添加预设颜色"
            case .traditionalChinese: return "新增預設顏色"
            case .korean: return "프리셋 추가"
            default: return "Add Color Preset"
            }

        case .deletePreset:
            switch lang {
            case .vietnamese: return "Xóa màu mẫu"
            case .german: return "Farbe löschen"
            case .french: return "Supprimer la couleur"
            case .spanish: return "Eliminar preajuste"
            case .japanese: return "プリセットを削除"
            case .simplifiedChinese: return "删除预设颜色"
            case .traditionalChinese: return "刪除預設顏色"
            case .korean: return "프리셋 삭제"
            default: return "Delete Color Preset"
            }

        case .resetPresets:
            switch lang {
            case .vietnamese: return "Đặt lại bảng màu mặc định"
            case .german: return "Farben zurücksetzen"
            case .french: return "Réinitialiser les couleurs"
            case .spanish: return "Restablecer colores"
            case .japanese: return "初期色に戻す"
            case .simplifiedChinese: return "重置默认颜色"
            case .traditionalChinese: return "重設預設顏色"
            case .korean: return "기본 색상으로 재설정"
            default: return "Reset Colors to Default"
            }

        case .maxPresetsReached:
            switch lang {
            case .vietnamese: return "Đã đạt giới hạn tối đa 16 màu mẫu"
            case .german: return "Maximal 16 Farbvoreinstellungen erreicht"
            case .french: return "Limite de 16 présélections atteinte"
            case .spanish: return "Límite máximo de 16 colores alcanzado"
            case .japanese: return "プリセットの上限16色に達しました"
            case .simplifiedChinese: return "已达到 16 种颜色预设上限"
            case .traditionalChinese: return "已達到 16 種顏色預設上限"
            case .korean: return "최대 16개 색상 프리셋에 도달했습니다"
            default: return "Maximum 16 presets reached"
            }

        case .invalidHexCode:
            switch lang {
            case .vietnamese: return "Mã màu HEX không hợp lệ"
            case .german: return "Ungültiges HEX-Farbformat"
            case .french: return "Format HEX invalide"
            case .spanish: return "Formato HEX no válido"
            case .japanese: return "無効なHEXカラーコードです"
            case .simplifiedChinese: return "无效的 HEX 颜色代码"
            case .traditionalChinese: return "無效的 HEX 顏色代碼"
            case .korean: return "유효하지 않은 HEX 색상 코드"
            default: return "Invalid HEX color format"
            }

        case .presetRed:
            switch lang {
            case .vietnamese: return "Đỏ"
            case .german: return "Rot"
            case .french: return "Rouge"
            case .spanish: return "Rojo"
            case .japanese: return "赤"
            case .simplifiedChinese: return "红色"
            case .traditionalChinese: return "紅色"
            case .korean: return "빨강"
            default: return "Red"
            }

        case .presetOrange:
            switch lang {
            case .vietnamese: return "Cam"
            case .german: return "Orange"
            case .french: return "Orange"
            case .spanish: return "Naranja"
            case .japanese: return "オレンジ"
            case .simplifiedChinese: return "橙色"
            case .traditionalChinese: return "橙色"
            case .korean: return "주황"
            default: return "Orange"
            }

        case .presetYellow:
            switch lang {
            case .vietnamese: return "Vàng"
            case .german: return "Gelb"
            case .french: return "Jaune"
            case .spanish: return "Amarillo"
            case .japanese: return "黄"
            case .simplifiedChinese: return "黄色"
            case .traditionalChinese: return "黃色"
            case .korean: return "노랑"
            default: return "Yellow"
            }

        case .presetGreen:
            switch lang {
            case .vietnamese: return "Xanh lá"
            case .german: return "Grün"
            case .french: return "Vert"
            case .spanish: return "Verde"
            case .japanese: return "緑"
            case .simplifiedChinese: return "绿色"
            case .traditionalChinese: return "綠色"
            case .korean: return "초록"
            default: return "Green"
            }

        case .presetBlue:
            switch lang {
            case .vietnamese: return "Xanh dương"
            case .german: return "Blau"
            case .french: return "Bleu"
            case .spanish: return "Azul"
            case .japanese: return "青"
            case .simplifiedChinese: return "蓝色"
            case .traditionalChinese: return "藍色"
            case .korean: return "파랑"
            default: return "Blue"
            }

        case .presetIndigo:
            switch lang {
            case .vietnamese: return "Chàm"
            case .german: return "Indigo"
            case .french: return "Indigo"
            case .spanish: return "Índigo"
            case .japanese: return "藍色"
            case .simplifiedChinese: return "靛蓝"
            case .traditionalChinese: return "靛藍"
            case .korean: return "남색"
            default: return "Indigo"
            }

        case .presetPurple:
            switch lang {
            case .vietnamese: return "Tím"
            case .german: return "Lila"
            case .french: return "Violet"
            case .spanish: return "Púrpura"
            case .japanese: return "紫"
            case .simplifiedChinese: return "紫色"
            case .traditionalChinese: return "紫色"
            case .korean: return "보라"
            default: return "Purple"
            }

        case .presetBlack:
            switch lang {
            case .vietnamese: return "Đen"
            case .german: return "Schwarz"
            case .french: return "Noir"
            case .spanish: return "Negro"
            case .japanese: return "黒"
            case .simplifiedChinese: return "黑色"
            case .traditionalChinese: return "黑色"
            case .korean: return "검정"
            default: return "Black"
            }

        case .actionScrollCapture:
            switch lang {
            case .vietnamese: return "Chụp cuộn trang"
            case .german: return "Scroll-Aufnahme"
            case .french: return "Capture défilante"
            case .spanish: return "Captura con desplazamiento"
            case .japanese: return "スクロール撮影"
            case .simplifiedChinese: return "滚动截图"
            case .traditionalChinese: return "滾動截圖"
            case .korean: return "스크롤 캡처"
            default: return "Scrolling Capture"
            }

        case .actionCopy:
            switch lang {
            case .vietnamese: return "Sao chép (Cmd+C / Return)"
            case .german: return "Kopieren (Cmd+C / Eingabe)"
            case .french: return "Copier (Cmd+C / Entrée)"
            case .spanish: return "Copiar (Cmd+C / Retorno)"
            case .japanese: return "コピー (Cmd+C / Return)"
            case .simplifiedChinese: return "复制 (Cmd+C / 回车)"
            case .traditionalChinese: return "複製 (Cmd+C / Enter)"
            case .korean: return "복사 (Cmd+C / Return)"
            default: return "Copy (Cmd+C / Return)"
            }

        case .actionSave:
            switch lang {
            case .vietnamese: return "Lưu (Cmd+S)"
            case .german: return "Speichern (Cmd+S)"
            case .french: return "Enregistrer (Cmd+S)"
            case .spanish: return "Guardar (Cmd+S)"
            case .japanese: return "保存 (Cmd+S)"
            case .simplifiedChinese: return "保存 (Cmd+S)"
            case .traditionalChinese: return "儲存 (Cmd+S)"
            case .korean: return "저장 (Cmd+S)"
            default: return "Save (Cmd+S)"
            }

        case .actionShare:
            switch lang {
            case .vietnamese: return "Chia sẻ (Cmd+E)"
            case .german: return "Teilen (Cmd+E)"
            case .french: return "Partager (Cmd+E)"
            case .spanish: return "Compartir (Cmd+E)"
            case .japanese: return "共有 (Cmd+E)"
            case .simplifiedChinese: return "分享 (Cmd+E)"
            case .traditionalChinese: return "分享 (Cmd+E)"
            case .korean: return "공유 (Cmd+E)"
            default: return "Share (Cmd+E)"
            }

        case .actionCancel:
            switch lang {
            case .vietnamese: return "Hủy (Esc)"
            case .german: return "Abbrechen (Esc)"
            case .french: return "Annuler (Échap)"
            case .spanish: return "Cancelar (Esc)"
            case .japanese: return "キャンセル (Esc)"
            case .simplifiedChinese: return "取消 (Esc)"
            case .traditionalChinese: return "取消 (Esc)"
            case .korean: return "취소 (Esc)"
            default: return "Cancel (Esc)"
            }

        case .copiedToClipboard:
            switch lang {
            case .vietnamese: return "Đã sao chép vào bộ nhớ tạm"
            case .german: return "In Zwischenablage kopiert"
            case .french: return "Copié dans le presse-papiers"
            case .spanish: return "Copiado al portapapeles"
            case .japanese: return "クリップボードにコピーしました"
            case .simplifiedChinese: return "已复制到剪贴板"
            case .traditionalChinese: return "已複製到剪貼簿"
            case .korean: return "클립보드에 복사됨"
            default: return "Copied to Clipboard"
            }

        case .savedToFile:
            switch lang {
            case .vietnamese: return "Đã lưu tệp thành công"
            case .german: return "Datei erfolgreich gespeichert"
            case .french: return "Fichier enregistré avec succès"
            case .spanish: return "Archivo guardado con éxito"
            case .japanese: return "ファイルを保存しました"
            case .simplifiedChinese: return "已成功保存到文件"
            case .traditionalChinese: return "已成功儲存至檔案"
            case .korean: return "파일이 저장되었습니다"
            default: return "Saved to File"
            }

        case .scrollCapturing:
            switch lang {
            case .vietnamese: return "Đang chụp cuộn trang..."
            case .german: return "Erfasse Scroll-Inhalt..."
            case .french: return "Capture du défilement en cours..."
            case .spanish: return "Capturando contenido con desplazamiento..."
            case .japanese: return "スクロール内容を撮影中..."
            case .simplifiedChinese: return "正在截取滚动内容..."
            case .traditionalChinese: return "正在擷取滾動內容..."
            case .korean: return "스크롤 내용 캡처 중..."
            default: return "Capturing scroll content..."
            }

        case .scrollAutoMode:
            switch lang {
            case .vietnamese: return "Cuộn tự động"
            case .german: return "Automatischer Bildlauf"
            case .french: return "Défilement automatique"
            case .spanish: return "Desplazamiento automático"
            case .japanese: return "自動スクロール"
            case .simplifiedChinese: return "自动滚动"
            case .traditionalChinese: return "自動滾動"
            case .korean: return "자동 스크롤"
            default: return "Auto-Scroll"
            }

        case .scrollManualMode:
            switch lang {
            case .vietnamese: return "Cuộn thủ công"
            case .german: return "Manueller Bildlauf"
            case .french: return "Défilement manuel"
            case .spanish: return "Desplazamiento manual"
            case .japanese: return "手動スクロール"
            case .simplifiedChinese: return "手动滚动"
            case .traditionalChinese: return "手動滾動"
            case .korean: return "수동 스크롤"
            default: return "Manual Scroll"
            }

        case .scrollDoneInstruction:
            switch lang {
            case .vietnamese: return "Nhấn Xong hoặc Return để hoàn tất"
            case .german: return "Fertig oder Eingabetaste zum Beenden"
            case .french: return "Appuyez sur Terminé ou Entrée pour finir"
            case .spanish: return "Presione Listo o Retorno para finalizar"
            case .japanese: return "完了またはReturnキーで終了"
            case .simplifiedChinese: return "按“完成”或回车键结束"
            case .traditionalChinese: return "按「完成」或 Enter 鍵結束"
            case .korean: return "완료 또는 Return 키를 눌러 종료"
            default: return "Press Done or Return to finish"
            }

        case .scrollMaxHeightReached:
            switch lang {
            case .vietnamese: return "Đã đạt giới hạn chiều cao tối đa"
            case .german: return "Maximale Höhe erreicht"
            case .french: return "Hauteur maximale atteinte"
            case .spanish: return "Altura máxima alcanzada"
            case .japanese: return "最大高さ制限に達しました"
            case .simplifiedChinese: return "已达到最大高度限制"
            case .traditionalChinese: return "已達到最大高度限制"
            case .korean: return "최대 높이 제한에 도달했습니다"
            default: return "Reached maximum height limit"
            }

        case .scrollBottomReached:
            switch lang {
            case .vietnamese: return "Đã đến cuối trang"
            case .german: return "Seitenende erreicht"
            case .french: return "Bas de page atteint"
            case .spanish: return "Fin de página alcanzado"
            case .japanese: return "ページの終端に達しました"
            case .simplifiedChinese: return "已到达页面底部"
            case .traditionalChinese: return "已到達頁面底部"
            case .korean: return "페이지 끝에 도달했습니다"
            default: return "Bottom of page reached"
            }

        case .liveStitchedPreview:
            switch lang {
            case .vietnamese: return "Xem trước ghép nối trực tiếp"
            case .german: return "Live-Zusammensetzungsvorschau"
            case .french: return "Aperçu de composition en direct"
            case .spanish: return "Vista previa de unión en directo"
            case .japanese: return "リアルタイム結合プレビュー"
            case .simplifiedChinese: return "实时拼接预览"
            case .traditionalChinese: return "即時拼接預覽"
            case .korean: return "실시간 결합 미리보기"
            default: return "Live Stitched Preview"
            }

        case .stitchedHeight(let h):
            switch lang {
            case .vietnamese: return "Chiều cao: \(h) px"
            case .german: return "Höhe: \(h) px"
            case .french: return "Hauteur : \(h) px"
            case .spanish: return "Altura: \(h) px"
            case .japanese: return "全体の高さ: \(h) px"
            case .simplifiedChinese: return "总高度: \(h) px"
            case .traditionalChinese: return "總高度: \(h) px"
            case .korean: return "총 높이: \(h) px"
            default: return "Total Height: \(h) px"
            }

        case .pinnedSection:
            switch lang {
            case .vietnamese: return "ĐÃ GHIM"
            case .german: return "ANGEHEFTET"
            case .french: return "ÉPINGLÉS"
            case .spanish: return "FIJADOS"
            case .japanese: return "ピン留め"
            case .simplifiedChinese: return "已置顶"
            case .traditionalChinese: return "已置頂"
            case .korean: return "고정됨"
            default: return "PINNED"
            }

        case .recentSection:
            switch lang {
            case .vietnamese: return "ẢNH CHỤP GẦN ĐÂY"
            case .german: return "NEUESTE AUFNAHMEN"
            case .french: return "CAPTURES RÉCENTES"
            case .spanish: return "CAPTURAS RECIENTES"
            case .japanese: return "最近のスクリーンショット"
            case .simplifiedChinese: return "最近截屏"
            case .traditionalChinese: return "最近截圖"
            case .korean: return "최근 스크린샷"
            default: return "RECENT SCREENSHOTS"
            }

        case .emptyHistoryTitle:
            switch lang {
            case .vietnamese: return "Chưa có ảnh chụp nào"
            case .german: return "Noch keine Aufnahmen"
            case .french: return "Aucune capture pour le moment"
            case .spanish: return "Aún no hay capturas"
            case .japanese: return "スクリーンショットはまだありません"
            case .simplifiedChinese: return "暂无截屏记录"
            case .traditionalChinese: return "尚無截圖記錄"
            case .korean: return "아직 스크린샷이 없습니다"
            default: return "No Screenshots Yet"
            }

        case .emptyHistorySubtitle:
            switch lang {
            case .vietnamese: return "Nhấn Option+S để chụp màn hình"
            case .german: return "Drücken Sie Option+S zum Erfassen"
            case .french: return "Appuyez sur Option+S pour capturer"
            case .spanish: return "Pulsa Opción+S para capturar"
            case .japanese: return "Option+S を押して画面をキャプチャ"
            case .simplifiedChinese: return "按下 Option+S 开始截屏"
            case .traditionalChinese: return "按下 Option+S 開始截圖"
            case .korean: return "Option+S를 눌러 화면을 캡처하세요"
            default: return "Press Option+S to capture your screen"
            }

        case .noMatchingResults:
            switch lang {
            case .vietnamese: return "Không tìm thấy ảnh chụp phù hợp"
            case .german: return "Keine passenden Aufnahmen gefunden"
            case .french: return "Aucune capture correspondante trouvée"
            case .spanish: return "No se encontraron capturas coincidentes"
            case .japanese: return "一致するスクリーンショットがありません"
            case .simplifiedChinese: return "未找到匹配的截屏"
            case .traditionalChinese: return "未找到符合的截圖"
            case .korean: return "일치하는 스크린샷을 찾을 수 없습니다"
            default: return "No matching screenshots found"
            }

        case .refineSearch:
            switch lang {
            case .vietnamese: return "Thử tìm kiếm với từ khóa khác"
            case .german: return "Versuchen Sie eine andere Suchanfrage"
            case .french: return "Essayez un autre mot-clé"
            case .spanish: return "Prueba con otra búsqueda"
            case .japanese: return "別のキーワードで検索してください"
            case .simplifiedChinese: return "尝试更换搜索关键字"
            case .traditionalChinese: return "嘗試更換搜尋關鍵字"
            case .korean: return "다른 검색어로 시도해 보세요"
            default: return "Try a different search query"
            }

        case .clearHistory:
            switch lang {
            case .vietnamese: return "Xóa lịch sử chưa ghim"
            case .german: return "Nicht angehefteten Verlauf löschen"
            case .french: return "Effacer l'historique non épinglé"
            case .spanish: return "Borrar historial no fijado"
            case .japanese: return "ピン留め以外の履歴を消去"
            case .simplifiedChinese: return "清除非置顶历史"
            case .traditionalChinese: return "清除非置頂記錄"
            case .korean: return "고정되지 않은 기록 지우기"
            default: return "Clear Unpinned History"
            }

        case .itemCount(let visible, let total):
            switch lang {
            case .vietnamese: return "\(visible) / \(total)"
            case .german: return "\(visible) von \(total)"
            case .french: return "\(visible) sur \(total)"
            case .spanish: return "\(visible) de \(total)"
            case .japanese: return "\(visible) / \(total)"
            case .simplifiedChinese: return "\(visible) / \(total)"
            case .traditionalChinese: return "\(visible) / \(total)"
            case .korean: return "\(visible) / \(total)"
            default: return "\(visible) of \(total)"
            }

        case .dimensionTag(let w, let h):
            return "\(w) x \(h) px"

        case .directAutoPaste:
            switch lang {
            case .vietnamese: return "Mô phỏng ⌘V ngay sau khi sao chép ảnh chụp vào bộ nhớ tạm"
            case .german: return "Simuliert ⌘V sofort nach dem Kopieren der Aufnahme in die Zwischenablage"
            case .french: return "Simule ⌘V immédiatement après la copie de la capture dans le presse-papiers"
            case .spanish: return "Simula ⌘V inmediatamente después de copiar la captura al portapapeles"
            case .japanese: return "スクリーンショットをクリップボードにコピーした直後に ⌘V を送信します"
            case .simplifiedChinese: return "将截图复制到剪贴板后立即模拟 ⌘V 粘贴"
            case .traditionalChinese: return "將截圖複製到剪貼簿後立即模擬 ⌘V 貼上"
            case .korean: return "스크린샷을 클립보드에 복사한 즉시 ⌘V 키를 시뮬레이션합니다"
            default: return "Simulates ⌘V immediately after copying screenshot to clipboard"
            }

        case .quickSelectHint:
            switch lang {
            case .vietnamese: return "Nhấn 1-9 để sao chép nhanh"
            case .german: return "1-9 drücken zum schnellen Kopieren"
            case .french: return "Appuyez sur 1-9 pour copier rapidement"
            case .spanish: return "Pulsa 1-9 para copia rápida"
            case .japanese: return "1-9キーで素早くコピー"
            case .simplifiedChinese: return "按 1-9 键快速复制"
            case .traditionalChinese: return "按 1-9 鍵快速複製"
            case .korean: return "1-9를 눌러 빠른 복사"
            default: return "Press 1-9 to quick copy"
            }

        case .openInFinder:
            switch lang {
            case .vietnamese: return "Hiện trong Finder"
            case .german: return "Im Finder anzeigen"
            case .french: return "Afficher dans le Finder"
            case .spanish: return "Mostrar en Finder"
            case .japanese: return "Finder で表示"
            case .simplifiedChinese: return "在访达中显示"
            case .traditionalChinese: return "在 Finder 中顯示"
            case .korean: return "Finder에서 보기"
            default: return "Reveal in Finder"
            }

        case .menuCapture:
            switch lang {
            case .vietnamese: return "Chụp màn hình"
            case .german: return "Bildschirm erfassen"
            case .french: return "Capturer l'écran"
            case .spanish: return "Capturar pantalla"
            case .japanese: return "画面をキャプチャ"
            case .simplifiedChinese: return "截取屏幕"
            case .traditionalChinese: return "截取螢幕"
            case .korean: return "화면 캡처"
            default: return "Capture Screen"
            }

        case .menuScrollingCapture:
            switch lang {
            case .vietnamese: return "Chụp cuộn trang"
            case .german: return "Scrollende Aufnahme"
            case .french: return "Capture avec défilement"
            case .spanish: return "Captura con desplazamiento"
            case .japanese: return "スクロールキャプチャ"
            case .simplifiedChinese: return "滚动截屏"
            case .traditionalChinese: return "滾動截圖"
            case .korean: return "스크롤 캡처"
            default: return "Scrolling Screenshot"
            }

        case .menuShowHistory:
            switch lang {
            case .vietnamese: return "Hiện lịch sử"
            case .german: return "Verlauf anzeigen"
            case .french: return "Afficher l'historique"
            case .spanish: return "Mostrar historial"
            case .japanese: return "履歴を表示"
            case .simplifiedChinese: return "显示历史"
            case .traditionalChinese: return "顯示記錄"
            case .korean: return "기록 표시"
            default: return "Show History"
            }

        case .menuPreferences:
            switch lang {
            case .vietnamese: return "Cài đặt..."
            case .german: return "Einstellungen..."
            case .french: return "Préférences..."
            case .spanish: return "Preferencias..."
            case .japanese: return "環境設定..."
            case .simplifiedChinese: return "偏好设置..."
            case .traditionalChinese: return "偏好設定..."
            case .korean: return "환경설정..."
            default: return "Preferences..."
            }

        case .menuClearHistory:
            switch lang {
            case .vietnamese: return "Xóa lịch sử chưa ghim"
            case .german: return "Nicht angeheftete Aufnahmen löschen"
            case .french: return "Effacer l'historique non épinglé"
            case .spanish: return "Borrar historial no fijado"
            case .japanese: return "ピン留め以外の履歴を消去"
            case .simplifiedChinese: return "清除非置顶历史"
            case .traditionalChinese: return "清除非置頂記錄"
            case .korean: return "고정되지 않은 기록 삭제"
            default: return "Clear Unpinned History"
            }

        case .menuCheckUpdates:
            switch lang {
            case .vietnamese: return "Kiểm tra bản cập nhật..."
            case .german: return "Nach Updates suchen..."
            case .french: return "Rechercher des mises à jour..."
            case .spanish: return "Buscar actualizaciones..."
            case .japanese: return "アップデートを確認..."
            case .simplifiedChinese: return "检查更新..."
            case .traditionalChinese: return "檢查更新..."
            case .korean: return "업데이트 확인..."
            default: return "Check for Updates..."
            }

        case .menuQuit:
            switch lang {
            case .vietnamese: return "Thoát SuperShot"
            case .german: return "SuperShot beenden"
            case .french: return "Quitter SuperShot"
            case .spanish: return "Salir de SuperShot"
            case .japanese: return "SuperShot を終了"
            case .simplifiedChinese: return "退出 SuperShot"
            case .traditionalChinese: return "結束 SuperShot"
            case .korean: return "SuperShot 종료"
            default: return "Quit SuperShot"
            }

        case .tabGeneral:
            switch lang {
            case .vietnamese: return "Cài đặt chung"
            case .german: return "Allgemein"
            case .french: return "Général"
            case .spanish: return "General"
            case .japanese: return "一般"
            case .simplifiedChinese: return "通用"
            case .traditionalChinese: return "一般"
            case .korean: return "일반"
            default: return "General"
            }

        case .tabCaptureSave:
            switch lang {
            case .vietnamese: return "Chụp & Lưu"
            case .german: return "Aufnahme & Speichern"
            case .french: return "Capture & Sauvegarde"
            case .spanish: return "Captura y guardado"
            case .japanese: return "撮影と保存"
            case .simplifiedChinese: return "截屏与保存"
            case .traditionalChinese: return "截圖與儲存"
            case .korean: return "캡처 및 저장"
            default: return "Capture & Save"
            }

        case .tabHistory:
            switch lang {
            case .vietnamese: return "Quản lý dữ liệu"
            case .german: return "Verlauf"
            case .french: return "Historique"
            case .spanish: return "Historial"
            case .japanese: return "履歴管理"
            case .simplifiedChinese: return "历史管理"
            case .traditionalChinese: return "記錄管理"
            case .korean: return "기록 관리"
            default: return "History"
            }

        case .tabAbout:
            switch lang {
            case .vietnamese: return "Giới thiệu"
            case .german: return "Über"
            case .french: return "À propos"
            case .spanish: return "Acerca de"
            case .japanese: return "情報"
            case .simplifiedChinese: return "关于"
            case .traditionalChinese: return "關於"
            case .korean: return "정보"
            default: return "About"
            }

        case .launchAtLogin:
            switch lang {
            case .vietnamese: return "Khởi động cùng hệ thống"
            case .german: return "SuperShot beim Systemstart ausführen"
            case .french: return "Lancer SuperShot au démarrage du système"
            case .spanish: return "Iniciar SuperShot al arrancar el sistema"
            case .japanese: return "システム起動時に SuperShot を起動"
            case .simplifiedChinese: return "开机自动启动 SuperShot"
            case .traditionalChinese: return "開機自動啟動 SuperShot"
            case .korean: return "시스템 시작 시 SuperShot 실행"
            default: return "Start SuperShot at system startup"
            }

        case .globalHotkeys:
            switch lang {
            case .vietnamese: return "Phím tắt toàn cầu"
            case .german: return "Globale Tastenkürzel"
            case .french: return "Raccourcis globaux"
            case .spanish: return "Atajos globales"
            case .japanese: return "グローバルショートカット"
            case .simplifiedChinese: return "全局快捷键"
            case .traditionalChinese: return "全域快速鍵"
            case .korean: return "글로벌 단축키"
            default: return "Global Shortcuts"
            }

        case .inPlaceCaptureShortcut:
            switch lang {
            case .vietnamese: return "Chụp màn hình tại chỗ:"
            case .german: return "Direkte Aufnahme:"
            case .french: return "Capture directe :"
            case .spanish: return "Captura en pantalla:"
            case .japanese: return "インプレース撮影:"
            case .simplifiedChinese: return "区域截屏快捷键:"
            case .traditionalChinese: return "區域截圖快速鍵:"
            case .korean: return "화면 캡처 단축키:"
            default: return "In-Place Capture:"
            }

        case .scrollingCaptureShortcut:
            switch lang {
            case .vietnamese: return "Chụp cuộn trang:"
            case .german: return "Scroll-Aufnahme:"
            case .french: return "Capture défilante :"
            case .spanish: return "Captura con desplazamiento:"
            case .japanese: return "スクロール撮影:"
            case .simplifiedChinese: return "滚动截屏快捷键:"
            case .traditionalChinese: return "滾動截圖快速鍵:"
            case .korean: return "스크롤 캡처 단축키:"
            default: return "Scrolling Capture:"
            }

        case .recordShortcut:
            switch lang {
            case .vietnamese: return "Ghi phím tắt"
            case .german: return "Tastenkürzel aufnehmen"
            case .french: return "Enregistrer le raccourci"
            case .spanish: return "Grabar atajo"
            case .japanese: return "ショートカットを記録"
            case .simplifiedChinese: return "录制快捷键"
            case .traditionalChinese: return "錄製快速鍵"
            case .korean: return "단축키 녹음"
            default: return "Record Shortcut"
            }

        case .pressShortcutHint:
            switch lang {
            case .vietnamese: return "Nhấn tổ hợp phím mong muốn..."
            case .german: return "Gewünschte Tastenkombination drücken..."
            case .french: return "Appuyez sur la combinaison de touches souhaitée..."
            case .spanish: return "Pulsa la combinación deseada..."
            case .japanese: return "希望のショートカットキーを押してください..."
            case .simplifiedChinese: return "按下所需快捷键组合..."
            case .traditionalChinese: return "按下所需快速鍵組合..."
            case .korean: return "원하는 단축키 조합을 누르세요..."
            default: return "Press desired key combination..."
            }

        case .pressShortcutCancelHint:
            switch lang {
            case .vietnamese: return "Nhấn phím hoặc Esc để hủy"
            case .german: return "Tasten drücken oder Esc zum Abbrechen"
            case .french: return "Appuyez sur les touches ou Échap pour annuler"
            case .spanish: return "Pulsa teclas o Esc para cancelar"
            case .japanese: return "キーを押すかEscでキャンセル"
            case .simplifiedChinese: return "按下按键或按 Esc 取消"
            case .traditionalChinese: return "按下按鍵或按 Esc 取消"
            case .korean: return "키를 누르거나 Esc로 취소"
            default: return "Press keys or Esc to cancel"
            }

        case .languageLabel:
            switch lang {
            case .vietnamese: return "Ngôn ngữ:"
            case .german: return "Sprache:"
            case .french: return "Langue :"
            case .spanish: return "Idioma:"
            case .japanese: return "言語:"
            case .simplifiedChinese: return "语言:"
            case .traditionalChinese: return "語言:"
            case .korean: return "언어:"
            default: return "Language:"
            }

        case .screenRecordingPermission:
            switch lang {
            case .vietnamese: return "Quyền Ghi màn hình"
            case .german: return "Bildschirmaufnahme-Berechtigung"
            case .french: return "Autorisation d'enregistrement d'écran"
            case .spanish: return "Permiso de grabación de pantalla"
            case .japanese: return "画面収録の権限"
            case .simplifiedChinese: return "屏幕录制权限"
            case .traditionalChinese: return "螢幕錄製權限"
            case .korean: return "화면 기록 권한"
            default: return "Screen Recording Permission"
            }

        case .accessibilityPermission:
            switch lang {
            case .vietnamese: return "Quyền Trợ năng"
            case .german: return "Bedienungshilfen-Berechtigung"
            case .french: return "Autorisation d'accessibilité"
            case .spanish: return "Permiso de accesibilidad"
            case .japanese: return "アクセシビリティ権限"
            case .simplifiedChinese: return "辅助功能权限"
            case .traditionalChinese: return "輔助功能權限"
            case .korean: return "손쉬운 사용 권한"
            default: return "Accessibility Permission"
            }

        case .permissionGranted:
            switch lang {
            case .vietnamese: return "Đã cấp quyền"
            case .german: return "Erteilt"
            case .french: return "Accordée"
            case .spanish: return "Concedido"
            case .japanese: return "許可済み"
            case .simplifiedChinese: return "已授权"
            case .traditionalChinese: return "已授權"
            case .korean: return "허용됨"
            default: return "Granted"
            }

        case .permissionRequired:
            switch lang {
            case .vietnamese: return "Cần cấp quyền"
            case .german: return "Berechtigung erforderlich"
            case .french: return "Autorisation requise"
            case .spanish: return "Permiso requerido"
            case .japanese: return "権限が必要です"
            case .simplifiedChinese: return "需要授权"
            case .traditionalChinese: return "需要授權"
            case .korean: return "권한 필요"
            default: return "Permission Required"
            }

        case .grantPermissionButton:
            switch lang {
            case .vietnamese: return "Cấp quyền..."
            case .german: return "Berechtigung erteilen..."
            case .french: return "Accorder l'autorisation..."
            case .spanish: return "Conceder permiso..."
            case .japanese: return "権限を付与..."
            case .simplifiedChinese: return "授予权限..."
            case .traditionalChinese: return "授予權限..."
            case .korean: return "권한 허용..."
            default: return "Grant Permission..."
            }

        case .recheckPermissionButton:
            switch lang {
            case .vietnamese: return "Kiểm tra lại"
            case .german: return "Erneut prüfen"
            case .french: return "Vérifier à nouveau"
            case .spanish: return "Comprobar de nuevo"
            case .japanese: return "再確認"
            case .simplifiedChinese: return "重新检查"
            case .traditionalChinese: return "重新檢查"
            case .korean: return "다시 확인"
            default: return "Check Again"
            }

        case .screenRecordingGuide:
            switch lang {
            case .vietnamese: return "Cần quyền Ghi màn hình để chụp hình ảnh từ màn hình."
            case .german: return "Bildschirmaufnahme-Berechtigung ist erforderlich, um den Bildschirm zu erfassen."
            case .french: return "L'autorisation d'enregistrement d'écran est nécessaire pour capturer l'écran."
            case .spanish: return "Se requiere permiso de grabación de pantalla para capturar pantallas."
            case .japanese: return "画面をキャプチャするには画面収録の権限が必要です。"
            case .simplifiedChinese: return "截取屏幕需要屏幕录制权限。"
            case .traditionalChinese: return "截取螢幕需要螢幕錄製權限。"
            case .korean: return "화면을 캡처하려면 화면 기록 권한이 필요합니다."
            default: return "Screen recording permission is required to capture screens."
            }

        case .accessibilityGuide:
            switch lang {
            case .vietnamese: return "Cần quyền Trợ năng để cuộn tự động và dán trực tiếp."
            case .german: return "Bedienungshilfen-Berechtigung ist für automatisches Scrollen und Einfügen erforderlich."
            case .french: return "L'autorisation d'accessibilité est nécessaire pour le défilement automatique et le collage direct."
            case .spanish: return "Se requiere permiso de accesibilidad para desplazamiento y pegado automático."
            case .japanese: return "自動スクロールと自動貼り付けにはアクセシビリティ権限が必要です。"
            case .simplifiedChinese: return "自动滚动和直接粘贴需要辅助功能权限。"
            case .traditionalChinese: return "自動滾動和直接貼上需要輔助功能權限。"
            case .korean: return "자동 스크롤 및 직접 붙여넣기를 사용하려면 손쉬운 사용 권한이 필요합니다."
            default: return "Accessibility permission is required for auto-scroll and direct paste."
            }

        case .autoPasteOnSelection:
            switch lang {
            case .vietnamese: return "Tự động dán vào ứng dụng trước khi chọn ảnh"
            case .german: return "Automatisch beim Auswählen in vorherige Anwendung einfügen"
            case .french: return "Coller automatiquement dans l'application précédente lors de la sélection"
            case .spanish: return "Pegar automáticamente en la aplicación anterior al seleccionar"
            case .japanese: return "選択時に直前のアプリケーションへ自動貼り付け"
            case .simplifiedChinese: return "选择截屏后自动粘贴至前台应用"
            case .traditionalChinese: return "選取截圖後自動貼上至前台應用程式"
            case .korean: return "선택 시 이전 애플리케이션으로 자동 붙여넣기"
            default: return "Auto-paste into previous application upon selection"
            }

        case .saveMode:
            switch lang {
            case .vietnamese: return "Chế độ lưu"
            case .german: return "Speichermodus"
            case .french: return "Mode d'enregistrement"
            case .spanish: return "Modo de guardado"
            case .japanese: return "保存モード"
            case .simplifiedChinese: return "保存模式"
            case .traditionalChinese: return "儲存模式"
            case .korean: return "저장 모드"
            default: return "Save Mode"
            }

        case .saveModePrompt:
            switch lang {
            case .vietnamese: return "Luôn hỏi vị trí lưu (NSSavePanel)"
            case .german: return "Immer nach Speicherort fragen (NSSavePanel)"
            case .french: return "Toujours demander où enregistrer (NSSavePanel)"
            case .spanish: return "Preguntar siempre dónde guardar (NSSavePanel)"
            case .japanese: return "保存先を常に確認 (NSSavePanel)"
            case .simplifiedChinese: return "每次提示保存位置 (NSSavePanel)"
            case .traditionalChinese: return "每次提示儲存位置 (NSSavePanel)"
            case .korean: return "저장 위치 항상 묻기 (NSSavePanel)"
            default: return "Always ask where to save (NSSavePanel)"
            }

        case .saveModeAuto:
            switch lang {
            case .vietnamese: return "Tự động lưu vào thư mục mặc định"
            case .german: return "Automatisch im Standardordner speichern"
            case .french: return "Enregistrer automatiquement dans le dossier par défaut"
            case .spanish: return "Guardar automáticamente en la carpeta predeterminada"
            case .japanese: return "デフォルトフォルダへ自動保存"
            case .simplifiedChinese: return "自动保存到默认文件夹"
            case .traditionalChinese: return "自動儲存至預設資料夾"
            case .korean: return "기본 폴더로 자동 저장"
            default: return "Automatically save to default folder"
            }

        case .saveDirectory:
            switch lang {
            case .vietnamese: return "Thư mục lưu:"
            case .german: return "Speicherordner:"
            case .french: return "Dossier d'enregistrement :"
            case .spanish: return "Carpeta de guardado:"
            case .japanese: return "保存先フォルダ:"
            case .simplifiedChinese: return "保存目录:"
            case .traditionalChinese: return "儲存資料夾:"
            case .korean: return "저장 디렉토리:"
            default: return "Save Directory:"
            }

        case .chooseDirectoryButton:
            switch lang {
            case .vietnamese: return "Chọn..."
            case .german: return "Auswählen..."
            case .french: return "Choisir..."
            case .spanish: return "Seleccionar..."
            case .japanese: return "選択..."
            case .simplifiedChinese: return "选择..."
            case .traditionalChinese: return "選取..."
            case .korean: return "선택..."
            default: return "Choose..."
            }

        case .saveFormat:
            switch lang {
            case .vietnamese: return "Định dạng hình ảnh:"
            case .german: return "Bildformat:"
            case .french: return "Format d'image :"
            case .spanish: return "Formato de imagen:"
            case .japanese: return "画像形式:"
            case .simplifiedChinese: return "图像格式:"
            case .traditionalChinese: return "圖像格式:"
            case .korean: return "이미지 형식:"
            default: return "Image Format:"
            }

        case .formatPNG:
            return "PNG (Lossless)"

        case .formatJPEG:
            return "JPEG (Compressed)"

        case .scrollingCaptureSettings:
            switch lang {
            case .vietnamese: return "Tùy chọn chụp cuộn trang"
            case .german: return "Optionen für Scroll-Aufnahme"
            case .french: return "Options de capture défilante"
            case .spanish: return "Opciones de captura con desplazamiento"
            case .japanese: return "スクロール撮影設定"
            case .simplifiedChinese: return "滚动截屏设置"
            case .traditionalChinese: return "滾動截圖設定"
            case .korean: return "스크롤 캡처 설정"
            default: return "Scrolling Capture Options"
            }

        case .maxScrollHeight:
            switch lang {
            case .vietnamese: return "Chiều cao cuộn tối đa:"
            case .german: return "Maximale Scroll-Höhe:"
            case .french: return "Hauteur maximale de défilement :"
            case .spanish: return "Altura máxima de desplazamiento:"
            case .japanese: return "最大スクロール高さ:"
            case .simplifiedChinese: return "最大滚动高度:"
            case .traditionalChinese: return "最大滾動高度:"
            case .korean: return "최대 스크롤 높이:"
            default: return "Maximum Scroll Height:"
            }

        case .maxScrollHeightUnit:
            switch lang {
            case .vietnamese: return "điểm ảnh"
            case .german: return "Pixel"
            case .french: return "pixels"
            case .spanish: return "píxeles"
            case .japanese: return "ピクセル"
            case .simplifiedChinese: return "像素"
            case .traditionalChinese: return "像素"
            case .korean: return "픽셀"
            default: return "pixels"
            }

        case .autoScrollSpeed:
            switch lang {
            case .vietnamese: return "Tốc độ cuộn tự động"
            case .german: return "Scroll-Geschwindigkeit"
            case .french: return "Vitesse de défilement automatique"
            case .spanish: return "Velocidad de desplazamiento"
            case .japanese: return "スクロール速度"
            case .simplifiedChinese: return "自动滚动速度"
            case .traditionalChinese: return "自動滾動速度"
            case .korean: return "자동 스크롤 속도"
            default: return "Auto-Scroll Speed"
            }

        case .colorPresetsManagement:
            switch lang {
            case .vietnamese: return "Quản lý màu mẫu"
            case .german: return "Farbvoreinstellungen verwalten"
            case .french: return "Gestion des présélections de couleur"
            case .spanish: return "Gestión de colores preestablecidos"
            case .japanese: return "カラープリセット管理"
            case .simplifiedChinese: return "颜色预设管理"
            case .traditionalChinese: return "顏色預設管理"
            case .korean: return "색상 프리셋 관리"
            default: return "Color Presets"
            }

        case .resetPresetsButton:
            switch lang {
            case .vietnamese: return "Đặt lại bảng màu gốc"
            case .german: return "Standardfarben wiederherstellen"
            case .french: return "Réinitialiser les couleurs d'origine"
            case .spanish: return "Restablecer colores predeterminados"
            case .japanese: return "デフォルト色にリセット"
            case .simplifiedChinese: return "重置默认预设颜色"
            case .traditionalChinese: return "重設預設顏色"
            case .korean: return "기본 프리셋으로 초기화"
            default: return "Reset Presets to Default"
            }

        case .historyCapacity:
            switch lang {
            case .vietnamese: return "Giới hạn lịch sử:"
            case .german: return "Verlaufskapazität:"
            case .french: return "Capacité de l'historique :"
            case .spanish: return "Capacidad del historial:"
            case .japanese: return "履歴の上限:"
            case .simplifiedChinese: return "历史容量:"
            case .traditionalChinese: return "記錄容量:"
            case .korean: return "기록 보관 용량:"
            default: return "History Capacity:"
            }

        case .historyCapacityUnit:
            switch lang {
            case .vietnamese: return "ảnh chụp"
            case .german: return "Aufnahmen"
            case .french: return "captures"
            case .spanish: return "capturas"
            case .japanese: return "枚"
            case .simplifiedChinese: return "张"
            case .traditionalChinese: return "張"
            case .korean: return "개"
            default: return "screenshots"
            }

        case .rememberLabel:
            switch lang {
            case .vietnamese: return "Lưu trữ:"
            case .german: return "Merken:"
            case .french: return "Mémoriser :"
            case .spanish: return "Recordar:"
            case .japanese: return "記憶数:"
            case .simplifiedChinese: return "保存数量:"
            case .traditionalChinese: return "保存數量:"
            case .korean: return "보관 수:"
            default: return "Remember:"
            }

        case .pinProtectionTitle:
            switch lang {
            case .vietnamese: return "Bảo vệ ảnh chụp đã ghim"
            case .german: return "Schutz für angeheftete Aufnahmen"
            case .french: return "Garantie de protection des épinglés"
            case .spanish: return "Garantía de protección de fijados"
            case .japanese: return "ピン留め保護機能"
            case .simplifiedChinese: return "置顶项保护机制"
            case .traditionalChinese: return "置頂項保護機制"
            case .korean: return "고정 항목 영구 보관"
            default: return "Pin Protection Guarantee"
            }

        case .pinProtectionDesc:
            switch lang {
            case .vietnamese: return "Ảnh chụp đã ghim được bảo vệ vĩnh viễn và không bị xóa khi đầy dung lượng."
            case .german: return "Angeheftete Aufnahmen sind dauerhaft geschützt und werden nicht automatisch gelöscht."
            case .french: return "Les captures épinglées sont protégées de façon permanente et ne sont jamais supprimées."
            case .spanish: return "Las capturas fijadas están protegidas permanentemente y nunca se eliminan automáticamente."
            case .japanese: return "ピン留めされたスクリーンショットは永久に保護され、上限により削除されることはありません。"
            case .simplifiedChinese: return "已置顶的截屏受到永久保护，不会因容量超限被清理。"
            case .traditionalChinese: return "已置頂的截圖受到永久保護，不會因容量超限而被清理。"
            case .korean: return "고정된 스크린샷은 영구적으로 보호되며 용량 초과로 삭제되지 않습니다."
            default: return "Pinned screenshots are permanently preserved and never evicted by capacity limits."
            }

        case .storageStatistics:
            switch lang {
            case .vietnamese: return "Thống kê lưu trữ"
            case .german: return "Speicherstatistiken"
            case .french: return "Statistiques de stockage"
            case .spanish: return "Estadísticas de almacenamiento"
            case .japanese: return "ストレージ統計"
            case .simplifiedChinese: return "存储统计"
            case .traditionalChinese: return "儲存統計"
            case .korean: return "저장소 통계"
            default: return "Storage Statistics"
            }

        case .totalScreenshots:
            switch lang {
            case .vietnamese: return "Tổng số ảnh:"
            case .german: return "Gesamte Aufnahmen:"
            case .french: return "Total des captures :"
            case .spanish: return "Total de capturas:"
            case .japanese: return "総撮影数:"
            case .simplifiedChinese: return "总截屏数:"
            case .traditionalChinese: return "總截圖數:"
            case .korean: return "총 스크린샷 수:"
            default: return "Total Screenshots:"
            }

        case .pinnedScreenshots:
            switch lang {
            case .vietnamese: return "Ảnh đã ghim:"
            case .german: return "Angeheftet:"
            case .french: return "Captures épinglées :"
            case .spanish: return "Capturas fijadas:"
            case .japanese: return "ピン留め数:"
            case .simplifiedChinese: return "已置顶数:"
            case .traditionalChinese: return "已置頂數:"
            case .korean: return "고정된 항목:"
            default: return "Pinned Screenshots:"
            }

        case .unpinnedScreenshots:
            switch lang {
            case .vietnamese: return "Ảnh chưa ghim:"
            case .german: return "Nicht angeheftet:"
            case .french: return "Non épinglées :"
            case .spanish: return "No fijadas:"
            case .japanese: return "未ピン留め数:"
            case .simplifiedChinese: return "未置顶数:"
            case .traditionalChinese: return "未置頂數:"
            case .korean: return "고정되지 않은 항목:"
            default: return "Unpinned Screenshots:"
            }

        case .diskUsage:
            switch lang {
            case .vietnamese: return "Dung lượng đĩa:"
            case .german: return "Festplattenbelegung:"
            case .french: return "Espace disque utilisé :"
            case .spanish: return "Espacio en disco utilizado:"
            case .japanese: return "ディスク使用量:"
            case .simplifiedChinese: return "占用磁盘空间:"
            case .traditionalChinese: return "磁碟佔用空間:"
            case .korean: return "디스크 사용량:"
            default: return "Disk Space Used:"
            }

        case .clearUnpinnedConfirmTitle:
            switch lang {
            case .vietnamese: return "Xóa tất cả ảnh chụp chưa ghim?"
            case .german: return "Alle nicht angehefteten Aufnahmen löschen?"
            case .french: return "Supprimer toutes les captures non épinglées ?"
            case .spanish: return "¿Eliminar todas las capturas no fijadas?"
            case .japanese: return "ピン留めされていないスクリーンショットをすべて消去しますか？"
            case .simplifiedChinese: return "清除所有未置顶截屏？"
            case .traditionalChinese: return "清除所有未置頂截圖？"
            case .korean: return "고정되지 않은 모든 스크린샷을 삭제하시겠습니까?"
            default: return "Clear All Unpinned Screenshots?"
            }

        case .clearUnpinnedConfirmMessage:
            switch lang {
            case .vietnamese: return "Thao tác này không thể hoàn tác. Các ảnh chụp đã ghim sẽ vẫn được giữ lại."
            case .german: return "Dieser Vorgang kann nicht widerrufen werden. Angeheftete Aufnahmen bleiben erhalten."
            case .french: return "Cette action est irréversible. Les captures épinglées seront conservées."
            case .spanish: return "Esta acción no se puede deshacer. Las capturas fijadas se conservarán."
            case .japanese: return "この操作は取り消せません。ピン留めされた項目は保護されます。"
            case .simplifiedChinese: return "此操作无法撤销。已置顶的截屏将被保留。"
            case .traditionalChinese: return "此操作無法復原。已置頂的截圖將會保留。"
            case .korean: return "이 작업은 되돌릴 수 없습니다. 고정된 스크린샷은 유지됩니다."
            default: return "This action cannot be undone. All unpinned screenshots will be deleted."
            }

        case .clearConfirmButton:
            switch lang {
            case .vietnamese: return "Xóa lịch sử"
            case .german: return "Verlauf löschen"
            case .french: return "Effacer l'historique"
            case .spanish: return "Borrar historial"
            case .japanese: return "履歴を消去"
            case .simplifiedChinese: return "清除历史"
            case .traditionalChinese: return "清除記錄"
            case .korean: return "기록 삭제"
            default: return "Clear History"
            }

        case .versionLabel(let v):
            switch lang {
            case .vietnamese: return "Phiên bản \(v)"
            case .german: return "Version \(v)"
            case .french: return "Version \(v)"
            case .spanish: return "Versión \(v)"
            case .japanese: return "バージョン \(v)"
            case .simplifiedChinese: return "版本 \(v)"
            case .traditionalChinese: return "版本 \(v)"
            case .korean: return "버전 \(v)"
            default: return "Version \(v)"
            }

        case .buildLabel(let b):
            switch lang {
            case .vietnamese: return "Bản dựng \(b)"
            case .german: return "Build \(b)"
            case .french: return "Build \(b)"
            case .spanish: return "Compilación \(b)"
            case .japanese: return "ビルド \(b)"
            case .simplifiedChinese: return "构建号 \(b)"
            case .traditionalChinese: return "組建 \(b)"
            case .korean: return "빌드 \(b)"
            default: return "Build \(b)"
            }

        case .appDescription:
            switch lang {
            case .vietnamese: return "Ứng dụng chụp màn hình, chụp cuộn và chú thích vector nguyên bản cho macOS."
            case .german: return "Native macOS Bildschirmaufnahme, Scroll-Screenshot und Vektor-Annotation."
            case .french: return "Utilitaire natif macOS de capture d'écran, capture défilante et annotation vectorielle."
            case .spanish: return "Utilidad nativa de macOS para captura de pantalla, desplazamiento y anotación vectorial."
            case .japanese: return "macOSネイティブのスクリーンショット・スクロール撮影・ベクター注釈ユーティリティ。"
            case .simplifiedChinese: return "原生 macOS 菜单栏截屏、长截图及矢量标注工具。"
            case .traditionalChinese: return "原生 macOS 選單列截圖、長截圖及向量標註工具。"
            case .korean: return "네이티브 macOS 메뉴 바 스크린샷, 스크롤 캡처 및 벡터 주석 유틸리티."
            default: return "Native macOS menu bar screenshot & scrolling capture utility."
            }

        case .licenseLabel:
            switch lang {
            case .vietnamese: return "Giấy phép:"
            case .german: return "Lizenz:"
            case .french: return "Licence :"
            case .spanish: return "Licencia:"
            case .japanese: return "ライセンス:"
            case .simplifiedChinese: return "许可证:"
            case .traditionalChinese: return "授權:"
            case .korean: return "라이선스:"
            default: return "License:"
            }

        case .authorLabel:
            return "SuperShot Contributors"

        case .resetAllDefaults:
            switch lang {
            case .vietnamese: return "Đặt lại toàn bộ cài đặt"
            case .german: return "Alle Einstellungen zurücksetzen"
            case .french: return "Réinitialiser tous les réglages"
            case .spanish: return "Restablecer todos los ajustes"
            case .japanese: return "すべての設定をリセット"
            case .simplifiedChinese: return "恢复所有默认设置"
            case .traditionalChinese: return "恢復所有預設設定"
            case .korean: return "모든 설정 초기화"
            default: return "Reset All Settings"
            }

        case .resetAllConfirmTitle:
            switch lang {
            case .vietnamese: return "Đặt lại tất cả cài đặt về mặc định?"
            case .german: return "Alle Einstellungen auf Standardwerte zurücksetzen?"
            case .french: return "Réinitialiser toutes les préférences par défaut ?"
            case .spanish: return "¿Restablecer todos los ajustes a los valores iniciales?"
            case .japanese: return "すべての環境設定を初期設定に戻しますか？"
            case .simplifiedChinese: return "确定恢复所有偏好设置为默认值吗？"
            case .traditionalChinese: return "確定將所有偏好設定恢復為預設值嗎？"
            case .korean: return "모든 설정을 기본값으로 초기화하시겠습니까?"
            default: return "Reset All Preferences to Defaults?"
            }

        case .resetAllConfirmMessage:
            switch lang {
            case .vietnamese: return "Mọi cài đặt phím tắt, lưu trữ và màu sắc sẽ được đưa về giá trị gốc."
            case .german: return "Alle Tastenkürzel, Speicheroptionen und Farbpaletten werden zurückgesetzt."
            case .french: return "Tous les raccourcis, options d'enregistrement et couleurs seront réinitialisés."
            case .spanish: return "Se restablecerán todos los atajos, opciones de guardado y paletas de color."
            case .japanese: return "すべてのショートカット、保存設定、カラーパレットが初期化されます。"
            case .simplifiedChinese: return "所有快捷键、保存选项及颜色调色板将被重置。"
            case .traditionalChinese: return "所有快速鍵、儲存選項及色彩調色盤將被重設。"
            case .korean: return "모든 단축키, 저장 옵션 및 색상 팔레트가 기본값으로 복원됩니다."
            default: return "All settings including shortcuts, save preferences, and colors will be reset."
            }

        case .checkingForUpdates:
            switch lang {
            case .vietnamese: return "Đang kiểm tra bản cập nhật..."
            case .german: return "Suche nach Updates..."
            case .french: return "Recherche de mises à jour..."
            case .spanish: return "Buscando actualizaciones..."
            case .japanese: return "アップデートを確認中..."
            case .simplifiedChinese: return "正在检查更新..."
            case .traditionalChinese: return "正在檢查更新..."
            case .korean: return "업데이트 확인 중..."
            default: return "Checking for updates..."
            }

        case .updateAvailable(let v):
            switch lang {
            case .vietnamese: return "Đã có phiên bản \(v)"
            case .german: return "Version \(v) ist verfügbar"
            case .french: return "La version \(v) est disponible"
            case .spanish: return "Versión \(v) disponible"
            case .japanese: return "バージョン \(v) が利用可能です"
            case .simplifiedChinese: return "发现新版本 \(v)"
            case .traditionalChinese: return "發現新版本 \(v)"
            case .korean: return "버전 \(v) 사용 가능"
            default: return "Version \(v) is available"
            }

        case .upToDate:
            switch lang {
            case .vietnamese: return "SuperShot đang ở phiên bản mới nhất"
            case .german: return "SuperShot ist auf dem neuesten Stand"
            case .french: return "SuperShot est à jour"
            case .spanish: return "SuperShot está actualizado"
            case .japanese: return "SuperShot は最新の状態です"
            case .simplifiedChinese: return "SuperShot 已是最新版本"
            case .traditionalChinese: return "SuperShot 已是最新版本"
            case .korean: return "SuperShot이 최신 상태입니다"
            default: return "SuperShot is up to date"
            }

        case .downloadUpdate:
            switch lang {
            case .vietnamese: return "Tải bản cập nhật"
            case .german: return "Update laden"
            case .french: return "Télécharger la mise à jour"
            case .spanish: return "Descargar actualización"
            case .japanese: return "アップデートをダウンロード"
            case .simplifiedChinese: return "下载更新"
            case .traditionalChinese: return "下載更新"
            case .korean: return "업데이트 다운로드"
            default: return "Download Update"
            }

        case .installAndRestart:
            switch lang {
            case .vietnamese: return "Cài đặt và Khởi động lại"
            case .german: return "Installieren und Neustarten"
            case .french: return "Installer et redémarrer"
            case .spanish: return "Instalar y reiniciar"
            case .japanese: return "インストールして再起動"
            case .simplifiedChinese: return "安装并重启"
            case .traditionalChinese: return "安裝並重啟"
            case .korean: return "설치 후 재시작"
            default: return "Install and Restart"
            }

        case .automaticallyCheckForUpdates:
            switch lang {
            case .vietnamese: return "Tự động kiểm tra bản cập nhật"
            case .german: return "Automatisch nach Updates suchen"
            case .french: return "Rechercher automatiquement les mises à jour"
            case .spanish: return "Buscar actualizaciones automáticamente"
            case .japanese: return "アップデートを自動的に確認"
            case .simplifiedChinese: return "自动检查更新"
            case .traditionalChinese: return "自動檢查更新"
            case .korean: return "자동으로 업데이트 확인"
            default: return "Automatically check for updates"
            }

        case .updateCheckIntervalLabel:
            switch lang {
            case .vietnamese: return "Tần suất kiểm tra:"
            case .german: return "Prüfintervall:"
            case .french: return "Fréquence de vérification :"
            case .spanish: return "Frecuencia de comprobación:"
            case .japanese: return "確認頻度:"
            case .simplifiedChinese: return "检查频率："
            case .traditionalChinese: return "檢查頻率："
            case .korean: return "확인 주기:"
            default: return "Check frequency:"
            }

        case .intervalDaily:
            switch lang {
            case .vietnamese: return "Hàng ngày"
            case .german: return "Täglich"
            case .french: return "Quotidien"
            case .spanish: return "Diario"
            case .japanese: return "毎日"
            case .simplifiedChinese: return "每天"
            case .traditionalChinese: return "每天"
            case .korean: return "매일"
            default: return "Daily"
            }

        case .intervalWeekly:
            switch lang {
            case .vietnamese: return "Hàng tuần"
            case .german: return "Wöchentlich"
            case .french: return "Hebdomadaire"
            case .spanish: return "Semanal"
            case .japanese: return "毎週"
            case .simplifiedChinese: return "每周"
            case .traditionalChinese: return "每週"
            case .korean: return "매주"
            default: return "Weekly"
            }

        case .intervalMonthly:
            switch lang {
            case .vietnamese: return "Hàng tháng"
            case .german: return "Monatlich"
            case .french: return "Mensuel"
            case .spanish: return "Mensual"
            case .japanese: return "毎月"
            case .simplifiedChinese: return "每月"
            case .traditionalChinese: return "每月"
            case .korean: return "매월"
            default: return "Monthly"
            }

        case .updateNow:
            switch lang {
            case .vietnamese: return "Cập nhật ngay"
            case .german: return "Jetzt aktualisieren"
            case .french: return "Mettre à jour"
            case .spanish: return "Actualizar ahora"
            case .japanese: return "今すぐアップデート"
            case .simplifiedChinese: return "立即更新"
            case .traditionalChinese: return "立即更新"
            case .korean: return "지금 업데이트"
            default: return "Update Now"
            }

        case .later:
            switch lang {
            case .vietnamese: return "Để sau"
            case .german: return "Später"
            case .french: return "Plus tard"
            case .spanish: return "Más tarde"
            case .japanese: return "後で"
            case .simplifiedChinese: return "稍后"
            case .traditionalChinese: return "稍後"
            case .korean: return "나중에"
            default: return "Later"
            }

        case .releaseNotes:
            switch lang {
            case .vietnamese: return "Chi tiết phát hành"
            case .german: return "Versionshinweise"
            case .french: return "Notes de version"
            case .spanish: return "Notas de la versión"
            case .japanese: return "リリースノート"
            case .simplifiedChinese: return "发行说明"
            case .traditionalChinese: return "版本說明"
            case .korean: return "릴리즈 노트"
            default: return "Release Notes"
            }

        case .updateReadyRestart:
            switch lang {
            case .vietnamese: return "Bản cập nhật đã sẵn sàng, khởi động lại ngay"
            case .german: return "Update bereit, jetzt neu starten"
            case .french: return "Mise à jour prête, redémarrer maintenant"
            case .spanish: return "Actualización lista, reiniciar ahora"
            case .japanese: return "アップデートの準備が完了しました。今すぐ再起動"
            case .simplifiedChinese: return "更新已就绪，立即重启"
            case .traditionalChinese: return "更新已就緒，立即重啟"
            case .korean: return "업데이트 준비 완료, 지금 재시작"
            default: return "Update ready, restart now"
            }

        case .restart:
            switch lang {
            case .vietnamese: return "Khởi động lại"
            case .german: return "Neu starten"
            case .french: return "Redémarrer"
            case .spanish: return "Reiniciar"
            case .japanese: return "再起動"
            case .simplifiedChinese: return "重启"
            case .traditionalChinese: return "重啟"
            case .korean: return "재시작"
            default: return "Restart"
            }

        case .downloadingUpdate:
            switch lang {
            case .vietnamese: return "Đang tải bản cập nhật..."
            case .german: return "Update wird geladen..."
            case .french: return "Téléchargement de la mise à jour..."
            case .spanish: return "Descargando actualización..."
            case .japanese: return "アップデートをダウンロード中..."
            case .simplifiedChinese: return "正在下载更新..."
            case .traditionalChinese: return "正在下載更新..."
            case .korean: return "업데이트 다운로드 중..."
            default: return "Downloading update..."
            }

        case .permissionsSectionTitle:
            switch lang {
            case .vietnamese: return "Quyền truy cập hệ thống"
            case .german: return "Berechtigungen"
            case .french: return "Autorisations"
            case .spanish: return "Permisos"
            case .japanese: return "システムアクセス許可"
            case .simplifiedChinese: return "系统权限"
            case .traditionalChinese: return "系統權限"
            case .korean: return "시스템 권한"
            default: return "Permissions"
            }

        case .filenamePreviewLabel:
            switch lang {
            case .vietnamese: return "Xem trước tên tệp:"
            case .german: return "Dateinamen-Vorschau:"
            case .french: return "Aperçu du nom de fichier :"
            case .spanish: return "Vista previa del nombre:"
            case .japanese: return "ファイル名のプレビュー:"
            case .simplifiedChinese: return "文件名预览:"
            case .traditionalChinese: return "檔名預覽:"
            case .korean: return "파일명 미리보기:"
            default: return "Filename Preview:"
            }

        case .clearSearchTooltip:
            switch lang {
            case .vietnamese: return "Xóa truy vấn tìm kiếm"
            case .german: return "Suchbegriff löschen"
            case .french: return "Effacer la recherche"
            case .spanish: return "Borrar búsqueda"
            case .japanese: return "検索クエリを消去"
            case .simplifiedChinese: return "清除搜索内容"
            case .traditionalChinese: return "清除搜尋內容"
            case .korean: return "검색어 지우기"
            default: return "Clear search query"
            }

        case .clearSearchButton:
            switch lang {
            case .vietnamese: return "Xóa tìm kiếm"
            case .german: return "Suche löschen"
            case .french: return "Effacer la recherche"
            case .spanish: return "Borrar búsqueda"
            case .japanese: return "検索をクリア"
            case .simplifiedChinese: return "清除搜索"
            case .traditionalChinese: return "清除搜尋"
            case .korean: return "검색 초기화"
            default: return "Clear Search"
            }

        case .quickCaptureRegion:
            switch lang {
            case .vietnamese: return "Chụp vùng màn hình (⌥S)"
            case .german: return "Bereich aufnehmen (⌥S)"
            case .french: return "Capture de zone (⌥S)"
            case .spanish: return "Captura de área (⌥S)"
            case .japanese: return "範囲キャプチャ (⌥S)"
            case .simplifiedChinese: return "区域截图 (⌥S)"
            case .traditionalChinese: return "區域截圖 (⌥S)"
            case .korean: return "영역 캡처 (⌥S)"
            default: return "Area Capture (⌥S)"
            }

        case .quickCaptureScroll:
            switch lang {
            case .vietnamese: return "Chụp cuộn trang (⌥⇧S)"
            case .german: return "Scrollende Aufnahme (⌥⇧S)"
            case .french: return "Capture avec défilement (⌥⇧S)"
            case .spanish: return "Captura con desplazamiento (⌥⇧S)"
            case .japanese: return "スクロールキャプチャ (⌥⇧S)"
            case .simplifiedChinese: return "滚动长截图 (⌥⇧S)"
            case .traditionalChinese: return "滾動長截圖 (⌥⇧S)"
            case .korean: return "스크롤 캡처 (⌥⇧S)"
            default: return "Scrolling Capture (⌥⇧S)"
            }

        case .welcomeTitle:
            switch lang {
            case .vietnamese: return "Chào mừng đến với SuperShot"
            case .german: return "Willkommen bei SuperShot"
            case .french: return "Bienvenue dans SuperShot"
            case .spanish: return "Bienvenido a SuperShot"
            case .japanese: return "SuperShot へようこそ"
            case .simplifiedChinese: return "欢迎使用 SuperShot"
            case .traditionalChinese: return "歡迎使用 SuperShot"
            case .korean: return "SuperShot에 오신 것을 환영합니다"
            default: return "Welcome to SuperShot"
            }

        case .welcomeSubtitle:
            switch lang {
            case .vietnamese: return "Chụp màn hình chuyên nghiệp, chụp cuộn trang và chú thích vector trực quan."
            case .german: return "Professionelle Bildschirmaufnahmen, Scroll-Stitching und Vektor-Anmerkungen."
            case .french: return "Capture d'écran professionnelle, assemblage par défilement et annotations vectorielles."
            case .spanish: return "Captura de pantalla profesional, unión por desplazamiento y anotaciones vectoriales."
            case .japanese: return "プロフェッショナルな画面キャプチャ、スクロール結合、ベクター注釈ツール。"
            case .simplifiedChinese: return "专业的屏幕截图、滚动拼接长截图与即时矢量标注工具。"
            case .traditionalChinese: return "專業的螢幕截圖、滾動拼接長截圖與即時向量標註工具。"
            case .korean: return "전문적인 화면 캡처, 스크롤 결합 및 실시간 벡터 주석 도구."
            default: return "Professional screen capture, scrolling stitching, and in-place vector annotation."
            }

        case .getStartedButton:
            switch lang {
            case .vietnamese: return "Bắt đầu"
            case .german: return "Loslegen"
            case .french: return "Commencer"
            case .spanish: return "Empezar"
            case .japanese: return "始める"
            case .simplifiedChinese: return "开始使用"
            case .traditionalChinese: return "開始使用"
            case .korean: return "시작하기"
            default: return "Get Started"
            }

        case .welcomeGuideButton:
            switch lang {
            case .vietnamese: return "Chào mừng & Hướng dẫn nhanh"
            case .german: return "Willkommen & Schnellanleitung"
            case .french: return "Bienvenue et guide rapide"
            case .spanish: return "Bienvenida y guía rápida"
            case .japanese: return "ようこそ＆クイックガイド"
            case .simplifiedChinese: return "欢迎与快速指南"
            case .traditionalChinese: return "歡迎與快速指南"
            case .korean: return "환영 및 빠른 가이드"
            default: return "Welcome & Quick Guide"
            }

        case .welcomeFeature1Title:
            switch lang {
            case .vietnamese: return "Chụp vùng & Chú thích tại chỗ (Option+S)"
            case .german: return "Direkte Aufnahme & Anmerkung (Option+S)"
            case .french: return "Capture et annotation sur place (Option+S)"
            case .spanish: return "Captura y anotación en el lugar (Option+S)"
            case .japanese: return "その場でキャプチャ＆注釈 (Option+S)"
            case .simplifiedChinese: return "即时区域截屏与标注 (Option+S)"
            case .traditionalChinese: return "即時區域截圖與標註 (Option+S)"
            case .korean: return "실시간 영역 캡처 및 주석 (Option+S)"
            default: return "In-Place Capture & Annotation (Option+S)"
            }

        case .welcomeFeature1Desc:
            switch lang {
            case .vietnamese: return "Đóng băng màn hình Retina với 9 công cụ vector, làm mờ mosaic 12px, bảng màu và sao chép/lưu tức thì."
            case .german: return "Retina-Display einfrieren mit 9 Vektorwerkzeugen, 12px Mosaikunschärfe, Farbpaletten und sofortigem Kopieren/Speichern."
            case .french: return "Figez l'écran Retina avec 9 outils vectoriels, flou mosaïque 12px, préréglages de couleurs et copie/sauvegarde instantanée."
            case .spanish: return "Congele la pantalla Retina con 9 herramientas vectoriales, desenfoque mosaico de 12px, ajustes de color y copia/guardado instantáneo."
            case .japanese: return "9種類のベクターツール、12pxモザイクぼかし、カラープリセット、即時コピー/保存でRetina画面を静止。"
            case .simplifiedChinese: return "冻结Retina屏幕，提供9种矢量工具、12px马赛克模糊、颜色预设及即时复制/保存。"
            case .traditionalChinese: return "凍結Retina螢幕，提供9種向量工具、12px馬賽克模糊、顏色預設及即時複製/儲存。"
            case .korean: return "9가지 벡터 도구, 12px 모자이크 블러, 색상 프리셋, 즉시 복사/저장으로 Retina 화면을 정지합니다."
            default: return "Freeze Retina display with 9 vector tools, 12px mosaic blur, color presets, and instant copy/save."
            }

        case .welcomeFeature2Title:
            switch lang {
            case .vietnamese: return "Chụp cuộn trang (Option+Shift+S)"
            case .german: return "Scroll-Aufnahme (Option+Shift+S)"
            case .french: return "Capture par défilement (Option+Shift+S)"
            case .spanish: return "Captura con desplazamiento (Option+Shift+S)"
            case .japanese: return "スクロールキャプチャ (Option+Shift+S)"
            case .simplifiedChinese: return "滚动长截屏 (Option+Shift+S)"
            case .traditionalChinese: return "滾動長截圖 (Option+Shift+S)"
            case .korean: return "스크롤 캡처 (Option+Shift+S)"
            default: return "Scrolling Capture (Option+Shift+S)"
            }

        case .welcomeFeature2Desc:
            switch lang {
            case .vietnamese: return "Chụp cuộn thủ công theo vùng chọn, xem trước ảnh ghép trực tiếp, khử lặp thanh tiêu đề cố định và khung vẽ dài."
            case .german: return "Bereichsbasiertes manuelles Scrollen mit Live-Vorschau, Header-Deduplizierung und hoher Leinwand."
            case .french: return "Défilement manuel par région avec aperçu assemblé en direct, déduplication des en-têtes fixes et toile haute."
            case .spanish: return "Desplazamiento manual por región con vista previa ensamblada en vivo, deduplicación de encabezados fijos y lienzo largo."
            case .japanese: return "領域指定の手動スクロール、リアルタイム結合プレビュー、固定ヘッダー重複除外、縦長キャンバス。"
            case .simplifiedChinese: return "区域优先手动滚动截屏，实时长图拼接预览，固定导航栏去重与长画布编辑。"
            case .traditionalChinese: return "區域優先手動滾動截圖，即時長圖拼接預覽，固定導覽列去重與長畫布編輯。"
            case .korean: return "영역 우선 수동 스크롤, 실시간 결합 미리보기, 고정 헤더 중복 제거 및 세로형 캔버스 지원."
            default: return "Region-first manual scrolling with live stitched preview, sticky header deduplication, and tall canvas."
            }

        case .welcomeFeature3Title:
            switch lang {
            case .vietnamese: return "Lịch sử Popover & Tự động dán"
            case .german: return "Verlauf-Popover & Automatisches Einfügen"
            case .french: return "Popover d'historique et collage auto"
            case .spanish: return "Popover de historial y pegado automático"
            case .japanese: return "履歴ポップオーバー＆自動貼り付け"
            case .simplifiedChinese: return "历史记录浮窗与自动粘贴"
            case .traditionalChinese: return "歷史記錄浮窗與自動貼上"
            case .korean: return "히스토리 팝오버 및 자동 붙여넣기"
            default: return "History Popover & Auto-Paste"
            }

        case .welcomeFeature3Desc:
            switch lang {
            case .vietnamese: return "Lịch sử thanh menu với xem trước phóng to khi rê chuột, tìm kiếm toàn văn, phím tắt và tự động dán trực tiếp."
            case .german: return "Menüleisten-Verlauf mit Hover-Zoom-Vorschau, Volltextsuche, Tastaturkürzeln und direktem Auto-Einfügen."
            case .french: return "Historique de la barre des menus avec aperçu zoom au survol, recherche textuelle, raccourcis et collage direct."
            case .spanish: return "Historial en la barre de menú con vista previa de zoom al pasar el cursor, búsqueda de texto completo, atajos y pegado directo."
            case .japanese: return "ホバー拡大プレビュー、全文検索、キーボードショートカット、直接自動貼り付けを備えたメニューバー履歴。"
            case .simplifiedChinese: return "菜单栏截屏历史，支持悬停放大预览、全文检索、快捷键与直接自动粘贴。"
            case .traditionalChinese: return "選單列截圖歷史，支援懸停放大預覽、全文檢索、快捷鍵與直接自動貼上。"
            case .korean: return "호버 확대 미리보기, 전체 텍스트 검색, 단축키 및 직접 자동 붙여넣기를 지원하는 메뉴 막대 히스토리."
            default: return "Menu bar history with hover zoom preview, full-text search, keyboard shortcuts, and direct auto-paste."
            }

        case .zoomOutTooltip:
            switch lang {
            case .vietnamese: return "Thu nhỏ (⌘-)"
            case .german: return "Verkleinern (⌘-)"
            case .french: return "Zoom arrière (⌘-)"
            case .spanish: return "Alejar (⌘-)"
            case .japanese: return "縮小 (⌘-)"
            case .simplifiedChinese: return "缩小 (⌘-)"
            case .traditionalChinese: return "縮小 (⌘-)"
            case .korean: return "축소 (⌘-)"
            default: return "Zoom Out (⌘-)"
            }

        case .zoomActualSizeTooltip:
            switch lang {
            case .vietnamese: return "Kích thước thật 100% (⌘0)"
            case .german: return "Tatsächliche Größe 100% (⌘0)"
            case .french: return "Taille réelle 100 % (⌘0)"
            case .spanish: return "Tamaño real 100% (⌘0)"
            case .japanese: return "実際のサイズ 100% (⌘0)"
            case .simplifiedChinese: return "实际大小 100% (⌘0)"
            case .traditionalChinese: return "實際大小 100% (⌘0)"
            case .korean: return "실제 크기 100% (⌘0)"
            default: return "Actual Size 100% (⌘0)"
            }

        case .zoomInTooltip:
            switch lang {
            case .vietnamese: return "Phóng to (⌘+)"
            case .german: return "Vergrößern (⌘+)"
            case .french: return "Zoom avant (⌘+)"
            case .spanish: return "Acercar (⌘+)"
            case .japanese: return "拡大 (⌘+)"
            case .simplifiedChinese: return "放大 (⌘+)"
            case .traditionalChinese: return "放大 (⌘+)"
            case .korean: return "확대 (⌘+)"
            default: return "Zoom In (⌘+)"
            }

        case .zoomFitWidthTooltip:
            switch lang {
            case .vietnamese: return "Vừa chiều rộng (⌘9)"
            case .german: return "An Breite anpassen (⌘9)"
            case .french: return "Ajuster à la largeur (⌘9)"
            case .spanish: return "Ajustar al ancho (⌘9)"
            case .japanese: return "幅に合わせる (⌘9)"
            case .simplifiedChinese: return "适应宽度 (⌘9)"
            case .traditionalChinese: return "符合寬度 (⌘9)"
            case .korean: return "너비에 맞추기 (⌘9)"
            default: return "Fit to Width (⌘9)"
            }

        case .strokeWidthHUD(let width):
            switch lang {
            case .vietnamese: return "Độ dày nét: \(width) pt"
            case .german: return "Strichbreite: \(width) pt"
            case .french: return "Épaisseur du trait : \(width) pt"
            case .spanish: return "Grosor de trazo: \(width) pt"
            case .japanese: return "線の太さ: \(width) pt"
            case .simplifiedChinese: return "描边粗细: \(width) pt"
            case .traditionalChinese: return "筆畫粗細: \(width) pt"
            case .korean: return "선 두께: \(width) pt"
            default: return "Stroke Width: \(width) pt"
            }

        case .resetShortcutTooltip(let shortcut):
            switch lang {
            case .vietnamese: return "Đặt lại về \(shortcut)"
            case .german: return "Auf \(shortcut) zurücksetzen"
            case .french: return "Réinitialiser à \(shortcut)"
            case .spanish: return "Restablecer a \(shortcut)"
            case .japanese: return "\(shortcut) にリセット"
            case .simplifiedChinese: return "重置为 \(shortcut)"
            case .traditionalChinese: return "重設為 \(shortcut)"
            case .korean: return "\(shortcut)(으)로 초기화"
            default: return "Reset to \(shortcut)"
            }

        case .previewCancelTooltip:
            switch lang {
            case .vietnamese: return "Hủy (Esc)"
            case .german: return "Abbrechen (Esc)"
            case .french: return "Annuler (Esc)"
            case .spanish: return "Cancelar (Esc)"
            case .japanese: return "キャンセル (Esc)"
            case .simplifiedChinese: return "取消 (Esc)"
            case .traditionalChinese: return "取消 (Esc)"
            case .korean: return "취소 (Esc)"
            default: return "Cancel (Esc)"
            }

        case .previewDoneTooltip:
            switch lang {
            case .vietnamese: return "Hoàn thành (Return / Enter)"
            case .german: return "Fertig (Eingabetaste)"
            case .french: return "Terminé (Retour / Entrée)"
            case .spanish: return "Listo (Retorno / Intro)"
            case .japanese: return "完了 (Return / Enter)"
            case .simplifiedChinese: return "完成 (Return / Enter)"
            case .traditionalChinese: return "完成 (Return / Enter)"
            case .korean: return "완료 (Return / Enter)"
            default: return "Done (Return / Enter)"
            }

        case .actionShareTooltip:
            switch lang {
            case .vietnamese: return "Chia sẻ (⌘E)"
            case .german: return "Teilen (⌘E)"
            case .french: return "Partager (⌘E)"
            case .spanish: return "Compartir (⌘E)"
            case .japanese: return "共有 (⌘E)"
            case .simplifiedChinese: return "分享 (⌘E)"
            case .traditionalChinese: return "分享 (⌘E)"
            case .korean: return "공유 (⌘E)"
            default: return "Share (⌘E)"
            }

        case .annotationsCleared:
            switch lang {
            case .vietnamese: return "Đã xóa toàn bộ chú thích (⌘⇧K)"
            case .german: return "Alle Anmerkungen gelöscht (⌘⇧K)"
            case .french: return "Toutes les annotations effacées (⌘⇧K)"
            case .spanish: return "Todas las anotaciones eliminadas (⌘⇧K)"
            case .japanese: return "すべての注釈を消去しました (⌘⇧K)"
            case .simplifiedChinese: return "已清除所有注释 (⌘⇧K)"
            case .traditionalChinese: return "已清除所有註釋 (⌘⇧K)"
            case .korean: return "모든 주석 삭제됨 (⌘⇧K)"
            default: return "Annotations Cleared (⌘⇧K)"
            }

        case .layerBringToFront:
            switch lang {
            case .vietnamese: return "Chuyển lên trên cùng (⌘⇧])"
            case .german: return "Ganz nach vorne bringen (⌘⇧])"
            case .french: return "Placer au premier plan (⌘⇧])"
            case .spanish: return "Traer al frente (⌘⇧])"
            case .japanese: return "最前面へ移動 (⌘⇧])"
            case .simplifiedChinese: return "置于顶层 (⌘⇧])"
            case .traditionalChinese: return "移至最上層 (⌘⇧])"
            case .korean: return "맨 앞으로 가져오기 (⌘⇧])"
            default: return "Bring to Front (⌘⇧])"
            }

        case .layerSendToBack:
            switch lang {
            case .vietnamese: return "Chuyển xuống dưới cùng (⌘⇧[)"
            case .german: return "Ganz nach hinten senden (⌘⇧[)"
            case .french: return "Placer à l'arrière-plan (⌘⇧[)"
            case .spanish: return "Enviar al fondo (⌘⇧[)"
            case .japanese: return "最背面へ移動 (⌘⇧[)"
            case .simplifiedChinese: return "置于底层 (⌘⇧[)"
            case .traditionalChinese: return "移至最下層 (⌘⇧[)"
            case .korean: return "맨 뒤로 보내기 (⌘⇧[)"
            default: return "Send to Back (⌘⇧[)"
            }

        case .layerBringForward:
            switch lang {
            case .vietnamese: return "Tiến lên một lớp (⌘])"
            case .german: return "Schritt nach vorne (⌘])"
            case .french: return "Avancer d'un plan (⌘])"
            case .spanish: return "Traer adelante (⌘])"
            case .japanese: return "前面へ移動 (⌘])"
            case .simplifiedChinese: return "上移一层 (⌘])"
            case .traditionalChinese: return "上移一層 (⌘])"
            case .korean: return "앞으로 가져오기 (⌘])"
            default: return "Bring Forward (⌘])"
            }

        case .layerSendBackward:
            switch lang {
            case .vietnamese: return "Lùi lại một lớp (⌘[)"
            case .german: return "Schritt nach hinten (⌘[)"
            case .french: return "Reculer d'un plan (⌘[)"
            case .spanish: return "Enviar atrás (⌘[)"
            case .japanese: return "背面へ移動 (⌘[)"
            case .simplifiedChinese: return "下移一层 (⌘[)"
            case .traditionalChinese: return "下移一層 (⌘[)"
            case .korean: return "뒤로 보내기 (⌘[)"
            default: return "Send Backward (⌘[)"
            }

        case .zoomHUD(let pct):
            switch lang {
            case .vietnamese: return "Thu phóng: \(pct)%"
            case .german: return "Zoom: \(pct)%"
            case .french: return "Zoom : \(pct)%"
            case .spanish: return "Zoom: \(pct)%"
            case .japanese: return "ズーム: \(pct)%"
            case .simplifiedChinese: return "缩放: \(pct)%"
            case .traditionalChinese: return "縮放: \(pct)%"
            case .korean: return "확대/축소: \(pct)%"
            default: return "Zoom: \(pct)%"
            }

        case .framesCount(let n):
            switch lang {
            case .vietnamese: return "\(n) khung hình"
            case .german: return "\(n) Bilder"
            case .french: return "\(n) images"
            case .spanish: return "\(n) fotogramas"
            case .japanese: return "\(n) フレーム"
            case .simplifiedChinese: return "\(n) 帧"
            case .traditionalChinese: return "\(n) 幀"
            case .korean: return "\(n) 프레임"
            default: return "\(n) frames"
            }

        case .screenshotDeleted:
            switch lang {
            case .vietnamese: return "Đã xóa ảnh chụp"
            case .german: return "Screenshot gelöscht"
            case .french: return "Capture supprimée"
            case .spanish: return "Captura eliminada"
            case .japanese: return "スクリーンショットを削除しました"
            case .simplifiedChinese: return "已删除屏幕截图"
            case .traditionalChinese: return "已刪除螢幕截圖"
            case .korean: return "스크린샷 삭제됨"
            default: return "Screenshot Deleted"
            }

        case .unpinnedHistoryCleared:
            switch lang {
            case .vietnamese: return "Đã xóa lịch sử chưa ghim"
            case .german: return "Nicht angehefteter Verlauf gelöscht"
            case .french: return "Historique non épinglé effacé"
            case .spanish: return "Historial no fijado borrado"
            case .japanese: return "固定解除した履歴を消去しました"
            case .simplifiedChinese: return "已清除未固定历史"
            case .traditionalChinese: return "已清除未固定歷史"
            case .korean: return "고정되지 않은 기록 삭제됨"
            default: return "Unpinned history cleared"
            }

        case .copiedDiagnostics:
            switch lang {
            case .vietnamese: return "Đã sao chép thông tin chẩn đoán"
            case .german: return "Diagnosedaten kopiert"
            case .french: return "Infos de diagnostic copiées"
            case .spanish: return "Información de diagnóstico copiada"
            case .japanese: return "診断情報をコピーしました"
            case .simplifiedChinese: return "已复制诊断信息"
            case .traditionalChinese: return "已複製診斷資訊"
            case .korean: return "진단 정보 복사됨"
            default: return "Diagnostic Info Copied"
            }
        }
    }
}
