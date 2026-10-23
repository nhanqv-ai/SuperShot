<p align="center">
  <img src="Assets/AppIcon.png" alt="SuperShot App Icon" width="128" height="128" />
</p>

<h1 align="center">SuperShot</h1>

<p align="center">
  <strong>Ultra-lightweight, Lightning-Fast Native macOS Screenshot &amp; In-Place Annotation Tool</strong><br>
  <em>Swift &bull; SwiftUI &bull; Lightshot-Style Overlay &bull; Vector Annotations &bull; Universal 2 &bull; Multi-language Support</em>
</p>

<p align="center">
  <a href="#english">English</a> &bull; <a href="#tiếng-việt">Tiếng Việt</a>
</p>

<p align="center">
  <a href="https://github.com/nhanqv-ai/SuperShot/releases"><img src="https://img.shields.io/github/v/release/nhanqv-ai/SuperShot?style=flat-square&color=blue" alt="Release"></a>
  <a href="https://github.com/nhanqv-ai/SuperShot/releases/tag/v1.0.16"><img src="https://img.shields.io/badge/version-v1.0.16-blue.svg?style=flat-square" alt="Version v1.0.16"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green.svg?style=flat-square" alt="License"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B%20%7C%20Sonoma%2014.6%2B-lightgrey.svg?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/architecture-Universal%202%20(arm64%20%2B%20x86__64)-blue.svg?style=flat-square" alt="Architecture">
  <img src="https://img.shields.io/badge/Swift-6.0-orange.svg?style=flat-square" alt="Swift">
</p>

---

<a name="english"></a>
## English

**SuperShot** is an ultra-lightweight, native macOS menu bar screenshot and annotation tool built with Swift, AppKit, and SwiftUI. Inspired by the speed of **Lightshot** and the menu bar workflow of **SuperClip**, it freezes your screen instantly on shortcut trigger (`Option + S`), lets you drag and resize a selection region, and provides floating toolbars right beside your selection for object-based shapes, text, arrows, freehand drawing, and pixelation blur before copying or saving.

### Highlights

- **Lightshot-Style In-Place Screen Overlay**: Pressing `Option + S` (customizable) immediately freezes the screen at full Retina (`2x`) resolution and dims the surrounding area. Drag to select any region, adjust using 8 resize handles, and see live `W x H px` dimensions.
- **Object-Based Vector Annotations (Select, Move, Edit & Undo/Redo)**:
  - **Shapes & Pointers**: Rectangle (`rectangle`), Ellipse/Circle (`circle`), Arrow (`arrow.up.right`), and Straight Line (`line.diagonal`).
  - **Freehand & Highlighter**: Smooth Pen (`pencil.tip`) and semi-transparent Highlighter Marker (`highlighter`).
  - **In-Place Editable Text**: Click anywhere inside the capture region to type text (`textformat`), double-click to edit existing text, drag to reposition, or change color and font size on the fly.
  - **Sensitive Region Blur / Pixelate**: Drag over passwords, tokens, or personal data (`checkerboard.rectangle`) to pixelate/blur them cleanly.
  - **Interactive Object Manipulation**: Select any drawn shape, arrow, or text box to move, resize, recolor, adjust stroke width, or delete (`Delete` / `Backspace`), backed by full `Cmd + Z` / `Cmd + Shift + Z` Undo/Redo stacks.
- **Smart Edge-Aware Toolbars**:
  - **Vertical Annotation Toolbar**: Anchored along the right edge of the selection box (auto-flips to the left or inside when near screen boundaries).
  - **Horizontal Action Toolbar**: Anchored along the bottom edge for 1-click **Copy** (`Cmd + C` / `Return`), **Save** (`Cmd + S`), **macOS Share Sheet**, and **Cancel** (`Esc`).
- **Scrolling Screenshot for Long Content (Webpages, Documents, Code)**:
  - Full-page capture extending beyond screen borders with automatic scroll wheel synthesis (`CGEvent`) or manual scrolling.
  - Stationary **Sticky Header & Footer Deduplication** so navigation headers are not repeated mid-stitch.
  - Automatic right-edge **Scrollbar Strip Exclusion** during overlap matching.
  - Real-time **Live Stitched Preview** with running dimensions and frame counts.
  - Multi-page **Scrollable Annotation Canvas** for full vector annotations on long captures before saving or copying.
- **Color Preset System (`ColorPreset` & `ColorPalettePopoverView`)**:
  - Preloaded with 8 standard high-contrast colors for instant 1-click swatch recoloring.
  - Custom HEX (`#RRGGBB`) color input and screen Eyedropper sampling tool.
  - Favorite presets shelf storing up to 16 custom colors with right-click deletion.
  - Automatic persistence of last-used color, stroke width, and font size across capture sessions.
- **Menu Bar Screenshot History & Direct Auto-Paste (SuperClip Style)**:
  - Left-clicking the menu bar icon opens the **Screenshot History Popover** with Pinned & Recent sections, instant search, hover zoom preview (`ThumbnailHoverPreviewPanel`), quick `1..9` keyboard selection, and Direct Auto-Paste (`Cmd + V` simulation).
  - Each history row provides quick actions to **Copy**, **Save to File**, **Pin/Unpin**, and **Delete**.
- **Flexible Save Modes**: Configure `Cmd + S` to either prompt with the native `NSSavePanel` or save instantaneously into a default folder (e.g. `~/Desktop` or `~/Pictures/SuperShot`) in `PNG` or `JPEG` format.
- **Universal 2 Architecture**: Compiled as a native fat Mach-O binary supporting both Apple Silicon (`arm64`: M1/M2/M3/M4) and Intel (`x86_64`: MacBook Pro 2020 and earlier) on macOS 13.0 (Ventura) and macOS 14.6+ (Sonoma).
- **Multi-Language Support**: Full dynamic runtime translation without restarting: English, Vietnamese (Tiếng Việt), Simplified Chinese (简体中文), Japanese (日本語), Korean (한국어), Spanish (Español), French (Français), German (Deutsch), and System Default.
- **Zero Emojis Invariant**: Crisp typography and native SF Symbols throughout the entire application.

### Keyboard Shortcuts

| Shortcut | Action | Scope |
| :--- | :--- | :--- |
| `Option + S` | Trigger instant screen capture overlay (customizable) | Global |
| `Option + Shift + S` | Trigger scrolling capture overlay for long content (customizable) | Global |
| `Command + C` or `Return` | Copy annotated screenshot to clipboard & save to history | Capture Overlay |
| `Command + S` | Save annotated screenshot to file (`PNG` / `JPEG`) | Capture Overlay |
| `Return` or `Space` | Finish scrolling capture and open annotation canvas | Scrolling Capture |
| `Command + Z` | Undo last annotation action | Capture Overlay |
| `Command + Shift + Z` | Redo annotation action | Capture Overlay |
| `Command + D` | Duplicate currently selected annotation object | Capture Overlay |
| `Shift` (Hold) | Constrain rectangle to square, ellipse to circle, line/arrow to 45 deg | Capture Overlay |
| `Delete / Backspace` | Delete currently selected annotation object | Capture Overlay |
| `Escape` | Cancel capture overlay or dismiss history popover | Overlay / Panel |
| `1` .. `9` or `Cmd + 1` .. `Cmd + 9` | Directly copy & auto-paste screenshot 1 to 9 | History Popover |
| `Up / Down Arrow` | Circular navigation across screenshot history | History Popover |
| `Command + ,` | Open Preferences window | History Popover / Menu |
| `Command + Q` | Quit SuperShot | History Popover / Menu |

### User Guide: Scrolling Screenshot for Long Content

SuperShot seamlessly captures content that extends beyond the visible screen, such as long web pages, PDF documents, source code listings, terminal scrollbacks, or chat transcripts:

1. **Trigger Scrolling Capture**:
   - Press the global shortcut `Option + Shift + S` (or click **Scrolling Screenshot** in the menu bar context menu or the scroll icon on the selection toolbar).
   - Drag to select the target scrollable window or content area.
2. **Auto-Scroll vs Manual Scroll**:
   - **Auto-Scroll**: Click the **Start Scrolling** button. SuperShot automatically synthesizes smooth downward scroll wheel events (`CGEvent`), dynamically adapting scroll speed and frame intervals.
   - **Manual Scroll**: Toggle to manual mode if you prefer to scroll at your own pace using your mouse wheel, trackpad, or keyboard arrow keys.
3. **Intelligent Stitching Engine**:
   - **Sticky Header & Footer Deduplication**: Automatically detects fixed navigation bars, sticky headers, and floating footers, preserving them cleanly at the edges without duplicating them mid-stitch.
   - **Scrollbar Strip Exclusion**: Excludes the right-side vertical scrollbar strip during overlap matching to prevent stitching seams and artifacts.
   - **Live Stitched Preview**: Displays a real-time thumbnail preview and running pixel dimensions (`W x H px`) next to the capture region as new segments are stitched.
   - **Auto-Stop Detection**: Intelligently halts when the bottom of the page is detected, when `maxScrollHeightPx` is reached (configurable from `5,000 px` to `30,000 px` in Settings, default `15,000 px`), or when you press `Return`, `Space`, or click **Finish**.
4. **Scrollable Vector Annotation Canvas**:
   - Upon completion, the tall stitched image opens in the full-height scrollable canvas.
   - Pan and scroll smoothly through the tall canvas while adding any vector annotations (rectangles, circles, arrows, lines, text, highlighters, pen strokes, and sensitive blur/pixelation).
   - Click **Copy** (`Cmd + C`) or **Save** (`Cmd + S`) to finalize.

### User Guide: Color Presets & Palette System

SuperShot provides a fast, flexible color management system for all vector annotation tools:

1. **Toolbar Color Swatch**:
   - The active drawing color is displayed in the circular swatch on the vertical annotation toolbar.
   - Clicking the swatch opens the `ColorPalettePopoverView`.
2. **8 High-Contrast Default Swatches**:
   - Pre-loaded with 8 carefully tuned, high-contrast colors: Red (`#FF3B30`), Orange (`#FF9500`), Yellow (`#FFCC00`), Green (`#34C759`), Mint (`#00C7BE`), Blue (`#007AFF`), Purple (`#AF52DE`), and Dark Slate (`#1C1C1E`).
   - Clicking any swatch instantly changes the active tool's color or updates the selected object on the canvas.
3. **Custom Hex Input & Screen Eyedropper**:
   - **HEX Code Input**: Enter any custom 6-digit hex color code (`#RRGGBB`) directly into the text field.
   - **Screen Eyedropper**: Click the eyedropper icon to sample any pixel color directly from your macOS screen.
4. **Save Up to 16 Favorite Presets**:
   - Click the `+` button in the palette popover to save your current custom color into your personal presets (up to 16 presets stored).
   - Manage presets directly: right-click to delete a preset, or reset presets to factory defaults in **Preferences** -> **Capture & Save**.
5. **Session State Persistence**:
   - SuperShot automatically persists your selected color, stroke width, and font size across captures, so your preferred styling is ready every time you press `Option + S`.

### What's New in v1.0.16

- **Selection Box & Object Keyboard Resizing (`Option + Arrow`)**: Power users can now adjust the width and height of the selection region and selected vector annotations directly from the keyboard with 1-pixel precision (`Option + Arrow`) or 10-pixel steps (`Option + Shift + Arrow`).
- **Tall Canvas Annotation Keyboard Parity**: Full keyboard parity on stitched tall screenshots (`ScrollableAnnotationWindow`)—nudge selected annotations using Arrow keys (with Shift for 10pt) and resize with `Option + Arrow`.
- **Keyboard Shortcut for Share / Export (`Cmd + E`)**: Trigger macOS native Share Sheet / export picker instantly using standard `Cmd + E` (`⌘E`) in both capture overlay and tall scrolling canvases.
- **1-Click Clear All Annotations with Undo (`Cmd + Shift + K`)**: Instantly clear all annotations on the canvas using `Cmd + Shift + K` (`⌘⇧K`) with on-screen HUD confirmation pill and full multi-level Undo/Redo integration.
- **Search Bar Shortcut Hint Badge `[ / ]`**: Added an elegant, subtle `[ / ]` shortcut hint badge on the trailing edge of the history search bar when empty, making the `/` search shortcut immediately discoverable.
- **Universal 2 (`arm64` + `x86_64`) Binary Packaging**: Full Universal 2 build verified statically via `lipo` and `otool` without Rosetta 2 execution.

### What's New in v1.0.15

- **Settings Tab Bar Truncation Fix Across All Languages**: Eliminated tab label clipping across all 9 languages with `.minimumScaleFactor(0.78)` and standard concise titles (`History` in English, `Historial` in Spanish, and `Capture & Sauvegarde` in French).
- **Explicit ContentShape Hit-Testing Across All Custom Buttons & Pills**: Added full-bleed `.contentShape(Rectangle())` and `.contentShape(Circle())` across Floating Toolbars (`ActionButton`, `ActionShareButton`, stroke & color triggers, stroke width circles, font size buttons), Color Palette popover swatches and buttons, Scrollable Canvas zoom HUD buttons, Live Stitched Preview Panel buttons, History Popover header, empty state, and row buttons, Welcome Window actions, and Settings tabs so clicks in padding never miss.
- **Ergonomic Keyboard Shortcuts (`Cmd+A`, Arrow Nudge & `/`)**: Press `Cmd+A` during in-place capture to immediately select the entire display bounds, use Arrow keys (with optional Shift for 10px) to nudge selection with pixel precision, and press `/` in the history popover to focus the search field instantly.
- **Universal 2 (`arm64` + `x86_64`) Binary Packaging**: Full Universal 2 build verified statically via `lipo` and `otool` without Rosetta 2 execution.

### What's New in v1.0.14

- **Instant & Responsive Settings Tabs**: Extracted `SettingsTabButton` with full-bleed `.contentShape(Rectangle())` hit targets (`108x46pt`), non-transparent hit-testing surface, hover highlight, and zero-latency mouse-down response (`DragGesture(minimumDistance: 0)`). Eliminated synchronous disk enumeration in `HistorySettingsTab.body`, cached `AppIcon.icns` in `AboutSettingsTab`, and guarded `CursorTrackingRepresentable.updateNSView` against redundant cursor-rect invalidations.
- **Context Menu Deduplication Fix**: Fixed an index-shift bug in `StatusItemManager.menuNeedsUpdate` by matching `item.action` selectors instead of hardcoded array indices.
- **Universal 2 (`arm64` + `x86_64`) Support without Rosetta 2 Alert**: Full Universal 2 fat binary support for both Apple Silicon (`arm64`) and Intel (`x86_64`) Macs while verifying the `x86_64` slice statically (`lipo -info` + `otool -arch x86_64 -L`).

### What's New in v1.0.10

- **Shift-Key Aspect Ratio Lock & Smart Dimension Badge**: Holding Shift while dragging or corner-resizing selection boxes now locks the region to a 1:1 square. The live dimension badge intelligently recognizes standard aspect ratios (`1:1`, `16:9`, `4:3`, `16:10`, `3:2`, `21:9`, `9:16`, `3:4`, `2:3`) with dynamic width sizing to prevent badge truncation.
- **Bracket Key Shortcuts & Stroke Width HUD**: Adjust stroke width on the fly using bracket keys `[` (decrease) and `]` (increase) between 1pt and 16pt, accompanied by an instant on-screen HUD pill notification in both overlay and tall scrolling canvases.
- **Copy & Save HUD Confirmation in Scrollable Canvas**: Copying (`Cmd+C` / toolbar) or Saving (`Cmd+S` / toolbar) on tall scrolling canvases now displays non-intrusive on-screen HUD feedback ("Copied to Clipboard" / "Saved to File").
- **About Settings Tab 2-Row Action Buttons**: Action buttons are reorganized into 2 balanced rows (Row 1: Welcome & Quick Guide + Check for Updates; Row 2: Reset All Settings centered), eliminating ellipsis truncation in both English and Vietnamese.
- **Settings Window Tab Cycling (`Cmd+[` / `Cmd+]`)**: Seamlessly cycle between Settings tabs using standard macOS shortcuts `Cmd+[` / `Cmd+Shift+[` (previous tab) and `Cmd+]` / `Cmd+Shift+]` (next tab).
- **Full 9-Language Localization (0 Emojis)**: Comprehensive translations for WelcomeWindow feature cards, zoom controls tooltips, stroke width HUD, and shortcut reset tooltips across English, Vietnamese, German, French, Spanish, Japanese, Simplified Chinese, Traditional Chinese, and Korean.

### What's New in v1.0.9

- **Search Field & Empty State Actionability**: Search clear button now features `pointingHand` cursor with localized tooltip. Empty search results display an instant "Clear Search" button, and empty history includes quick capture action buttons ("Area Capture (⌥S)" and "Scrolling Capture (⌥⇧S)").
- **4-Tier Hierarchical Escape Key & Tool Selection Feedback HUD**: Escape key now gracefully dismisses in layers (Tier 1: commits active inline text; Tier 2: deselects active vector object; Tier 3: resets active drawing tool to `.select`; Tier 4: cancels capture session only when idle). Switching tools via shortcuts instantly synchronizes the canvas cursor and displays a brief non-intrusive HUD feedback pill indicator.
- **Quick Zoom HUD Native Glyphs & Viewport Centering**: Zoom controls feature native macOS modifier glyphs (`⌘-`, `⌘0`, `⌘+`, `⌘9`), and "Actual Size (100%)" maintains the visible viewport center when scaling long scrolling captures.
- **First-Class Welcome & Onboarding Window**: Beautiful 520x460pt onboarding window (`WelcomeWindow.swift`) with material background, feature cards, live Screen Recording and Accessibility permission checks, accessible anytime from the About tab and menu bar context menu.
- **Strict Settings Localization Hygiene**: Eliminated hardcoded strings and ternary expressions across all 4 settings tabs, providing typed `L10nKey` translations across all 9 supported languages with 100% SF Symbols and zero emojis.

### What's New in v1.0.8

- **Instant "Copied to Clipboard" Visual Feedback**: Copying an item from the history popover (via copy button, `1..9` quick keys, or `Cmd+C`) now triggers an instant 1.2-second green checkmark animation on the row button and popover HUD using localized text (`LocalizationManager.shared.tr(.copiedToClipboard)`).
- **Settings Window Layout & Sizing Polish**: Adjusted window height from 530 to 565 pt and tuned card spacing in `GeneralSettingsTab`, ensuring all 4 cards (including `autoPasteCard`) render completely unclipped without micro-scrolling in English and Vietnamese.
- **Native Settings Tab Keyboard Navigation (`Cmd+1`..`Cmd+4`)**: Switch between General, Capture & Save, History, and About tabs effortlessly using native `Cmd+1`..`Cmd+4` keyboard shortcuts and discoverable tab tooltips.
- **Mnemonic Letter Shortcuts & Native macOS Modifier Glyphs**: Vector annotation tools now support mnemonic single-letter shortcuts (`V`, `R`, `C`, `A`, `L`, `P`, `H`, `T`, `B`) displayed cleanly in tooltips (`1 / V`, `2 / R`), and action toolbars feature native macOS modifier glyphs (`⌘C / ↵`, `⌘S`, `⎋`, `␣`, `⌘Z`, `⇧⌘Z`).
- **Interactive Action Button Hover Micro-Interactions**: History row action buttons (Copy, Save, Pin, Delete) now use interactive hover luminance feedback (`0.10` to `0.18` opacity), spring animation, and `pointingHand` cursor.
- **Native Makefile DMG Target**: Added `make dmg` producing `SuperShot-v1.0.8.dmg` using `hdiutil` with an `/Applications` symlink for frictionless drag-and-drop installation.

### What's New in v1.0.7

- **Region-First Manual Scrolling Capture & Global `Esc`/`Enter` Controls**: Triggering scrolling capture (`Option + Shift + S` or Menu/Popover button) now opens the interactive region selector first, starts directly in user-controlled **Manual Scroll** mode (never hijacking cursor movement), and installs global Carbon/NSEvent `Esc` (Cancel) and `Enter` (Finish) listeners so stopping capture works reliably from any active window.
- **Synchronized Hover Preview & Row Thumbnail**: Replaced stale `@State` image loading with reactive `ThumbnailHoverPreviewViewModel` and synchronous `resolveImage` / `resolveThumbnail` lookup, eliminating preview/hover image mismatches and out-of-order row exit races.
- **Vector Object Duplication (`Cmd + D`)**: Instant cloning of any selected annotation object with smart diagonal offset via keyboard shortcut or toolbar duplicate button.
- **Proportional & Angle Constraints (`Shift`)**: Hold Shift while drawing to constrain rectangles to 1:1 squares, ellipses to perfect circles, and straight lines/arrows to 45-degree angle increments.
- **Tall Canvas Quick Zoom HUD**: Floating zoom controls with Fit, 100%, and 200% presets, plus interactive status display and `Cmd +` / `Cmd -` / `Cmd 0` shortcuts on `ScrollableCanvasView`.
- **100% Zero-Emoji Compliance**: Pure SF Symbols iconography and native macOS typography across all 9 supported languages.

### System Requirements

- macOS 13.0 (Ventura), macOS 14.6+ (Sonoma), or newer
- Apple Silicon Mac (`arm64`: M1/M2/M3/M4) or Intel Mac (`x86_64`, e.g. MacBook Pro 2020)

### Installation

#### Pre-built Release
1. Download the latest `SuperShot-v1.0.16.dmg` (or `.zip`) from [Releases](https://github.com/nhanqv-ai/SuperShot/releases).
2. Open the DMG and drag `SuperShot.app` into your `/Applications` folder.
3. Open `SuperShot.app`. A viewfinder icon will appear on your macOS menu bar.

> [!NOTE]
> **First-Time Launch (macOS Gatekeeper)**:
> Since SuperShot is an independent open-source project without Apple Developer ID notarization, macOS may show a verification dialog (*"SuperShot" Not Opened*). You can allow it via any of these methods:
> - **Terminal (Recommended)**: Run `xattr -cr /Applications/SuperShot.app` (or on the unzipped path).
> - **System Settings**: Go to **System Settings** -> **Privacy & Security** -> click **Open Anyway**.
> - **Finder**: Right-click `SuperShot.app` -> choose **Open** -> click **Open**.

> [!TIP]
> **Screen Recording & Accessibility Permissions**:
> - **Screen Recording**: Required by macOS to capture windows on your screen. In SuperShot **Preferences** -> **General**, click **Grant Permission...** next to Screen Recording, or enable `SuperShot` under **System Settings** -> **Privacy & Security** -> **Screen & System Audio Recording**.
> - **Accessibility (Optional for Direct Auto-Paste)**: Enables automatic `Cmd + V` pasting when selecting an item from the history popover. You can reset stale TCC cache anytime via `tccutil reset ScreenCapture com.supershot.SuperShot` or `tccutil reset Accessibility com.supershot.SuperShot`.

#### Build from Source
```bash
git clone https://github.com/nhanqv-ai/SuperShot.git
cd SuperShot
make app
open SuperShot.app
```

### Development & Testing

```bash
# Compile and run automated test suite
make test

# Verify standalone Universal 2 app bundle integrity
make verify-app

# Check strict 0-emoji invariant
make lint

# Package distributable Universal 2 zip archive
make package

# Clean build artifacts
make clean
```

### License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

<a name="tiếng-việt"></a>
## Tiếng Việt

**SuperShot** là ứng dụng chụp màn hình và chú thích trực tiếp siêu nhẹ, native cho macOS được xây dựng bằng Swift, AppKit và SwiftUI. Kết hợp tốc độ chụp vùng chọn trực quan của **Lightshot** cùng giao diện quản lý lịch sử Menu Bar của **SuperClip**, ứng dụng đóng băng màn hình tức thì khi nhấn phím tắt (`Option + S`), cho phép kéo chọn vùng, khoanh hình, vẽ mũi tên, viết chữ, làm mờ thông tin nhạy cảm ngay trên màn hình trước khi sao chép hoặc lưu thành file.

### Tính năng nổi bật

- **Chụp và chỉnh sửa trực tiếp trên màn hình (Kiểu Lightshot)**: Nhấn `Option + S` (có thể tùy chỉnh) để đóng băng màn hình ngay lập tức ở độ phân giải Retina (`2x`) sắc nét. Kéo chuột để chọn vùng cần chụp, tinh chỉnh kích thước qua 8 điểm neo kèm thông số `Rộng x Cao px` trực quan.
- **Bộ công cụ chú thích dạng đối tượng Vector (Chọn, Di chuyển, Sửa & Undo/Redo)**:
  - **Khoanh vùng & Chỉ điểm**: Khung chữ nhật (`rectangle`), Hình tròn/Elip (`circle`), Mũi tên (`arrow.up.right`), Đường thẳng (`line.diagonal`).
  - **Bút vẽ & Tô sáng**: Bút vẽ tự do mượt mà (`pencil.tip`) và Bút dạ quang bán trong suốt (`highlighter`).
  - **Viết chữ trực tiếp (Editable Text)**: Click vào vùng chụp để gõ chữ ngay tại chỗ (`textformat`), click đúp để sửa lại nội dung chữ, kéo để đổi vị trí, đổi màu sắc hoặc cỡ chữ linh hoạt.
  - **Làm mờ thông tin nhạy cảm (Blur / Pixelate)**: Kéo chọn vùng chứa mật khẩu, token hoặc thông tin cá nhân (`checkerboard.rectangle`) để làm mờ tức thì.
  - **Chỉnh sửa lại đối tượng đã vẽ**: Có thể click chọn bất kỳ hình khoanh, mũi tên hay dòng chữ nào đã tạo để di chuyển, co giãn, đổi màu, đổi độ dày nét hoặc xóa (`Delete` / `Backspace`), hỗ trợ đầy đủ Hoàn tác / Làm lại (`Cmd + Z` / `Cmd + Shift + Z`).
- **Thanh công cụ bám cạnh thông minh**:
  - **Thanh công cụ vẽ dọc**: Bám sát cạnh phải khung chọn (tự động lật sang trái hoặc vào trong khi chạm mép màn hình).
  - **Thanh hành động ngang**: Bám sát cạnh dưới khung chọn giúp **Copy nhanh** (`Cmd + C` / `Return`), **Lưu file** (`Cmd + S`), **Chia sẻ qua macOS Share Sheet**, hoặc **Hủy** (`Esc`).
- **Chụp cuộn trang dài (Scrolling Screenshot cho Web, Tài liệu, Mã nguồn)**:
  - Chụp toàn bộ nội dung dài vượt quá màn hình với cơ chế tự động cuộn lăn chuột (`CGEvent`) hoặc cuộn thủ công.
  - Tự động **Khử trùng lặp Header & Footer cố định** (sticky bar) giúp thanh điều hướng không bị lặp lại ở giữa ảnh.
  - Tự động **Bỏ qua dải thanh cuộn (Scrollbar)** ở mép phải khi khớp điểm ảnh dọc.
  - Xem trước kết quả ghép theo thời gian thực (**Live Stitched Preview**) kèm kích thước pixel và số khung hình.
  - **Khung vẽ chú thích cuộn chiều dọc**: Cho phép cuộn dọc toàn bộ ảnh ghép siêu dài để chèn chú thích vector trước khi sao chép hoặc lưu.
- **Hệ thống bảng màu & Màu mẫu (`ColorPreset` & `ColorPalettePopoverView`)**:
  - Tích hợp sẵn 8 mã màu chuẩn tương phản cao, click 1 chạm để đổi ngay màu vẽ hoặc đổi màu đối tượng đang chọn.
  - Nhập trực tiếp mã màu HEX (`#RRGGBB`) và công cụ Bút chấm màu màn hình (Eyedropper).
  - Khay lưu tối đa 16 màu yêu thích cá nhân với tính năng nhấp chuột phải để xóa hoặc khôi phục gốc.
  - Tự động ghi nhớ màu sắc, độ dày nét vẽ và cỡ chữ đã dùng gần nhất giữa các phiên chụp.
- **Popover Lịch sử Ảnh chụp & Tự động dán (Phong cách SuperClip)**:
  - Click chuột trái vào icon trên Menu Bar để mở **Popover Lịch sử ảnh chụp** với 2 nhóm Đã ghim (Pinned) và Gần đây (Recent), tìm kiếm tức thì, xem phóng to khi rê chuột (`ThumbnailHoverPreviewPanel`), bấm phím `1..9` để chọn nhanh và hỗ trợ Tự động dán (`Auto-Paste`).
  - Trên từng dòng lịch sử có đầy đủ nút **Sao chép**, **Lưu ra file**, **Ghim (Pin)** và **Xóa**.
- **Chế độ lưu file linh hoạt**: Tùy chỉnh trong Cài đặt để khi bấm Save (`Cmd + S`) sẽ mở hộp thoại chọn nơi lưu (`NSSavePanel`) hoặc tự động lưu thẳng vào thư mục mặc định (như `~/Desktop` hoặc `~/Pictures/SuperShot`) dưới định dạng `PNG` hoặc `JPEG`.
- **Kiến trúc Universal 2**: Biên dịch dưới dạng Mach-O fat binary hỗ trợ gốc cả chip Apple Silicon (`arm64`: M1/M2/M3/M4) và chip Intel (`x86_64`: MacBook Pro 2020 và các đời Intel) on macOS 13.0 (Ventura) và macOS 14.6+ (Sonoma).
- **Hỗ trợ đa ngôn ngữ**: Thay đổi ngôn ngữ tức thì trong cài đặt: Tiếng Việt, Tiếng Anh, Tiếng Trung, Tiếng Nhật, Tiếng Hàn, Tiếng Tây Ban Nha, Tiếng Pháp, Tiếng Đức và Mặc định hệ thống.
- **Quy chuẩn 0 Emojis**: Sử dụng hoàn toàn biểu tượng SF Symbols hiện đại, tinh gọn và chuyên nghiệp.

### Bảng phím tắt thông dụng

| Phím tắt | Thao tác | Phạm vi |
| :--- | :--- | :--- |
| `Option + S` | Kích hoạt chụp màn hình nhanh (tùy chỉnh được) | Toàn hệ thống |
| `Option + Shift + S` | Kích hoạt chụp cuộn trang dài (tùy chỉnh được) | Toàn hệ thống |
| `Command + C` hoặc `Return` | Sao chép ảnh đã chú thích vào Clipboard & lưu vào lịch sử | Màn hình chụp |
| `Command + S` | Lưu ảnh đã chú thích thành file (`PNG` / `JPEG`) | Màn hình chụp |
| `Return` hoặc `Space` | Hoàn tất cuộn và mở khung chú thích | Màn hình chụp cuộn |
| `Command + Z` | Hoàn tác bước vẽ trước đó (Undo) | Màn hình chụp |
| `Command + Shift + Z` | Làm lại bước vẽ (Redo) | Màn hình chụp |
| `Command + D` | Nhân bản (duplicate) đối tượng chú thích đang chọn | Màn hình chụp |
| `Shift` (Giữ phím) | Khóa tỉ lệ vuông/tròn (1:1) hoặc góc 45 độ cho đường thẳng/mũi tên | Màn hình chụp |
| `Delete / Backspace` | Xóa đối tượng hình vẽ/chữ đang chọn | Màn hình chụp |
| `Escape` | Hủy chụp màn hình hoặc đóng cửa sổ lịch sử | Màn hình chụp / Popover |
| `1` .. `9` hoặc `Cmd + 1` .. `Cmd + 9` | Chọn và sao chép/dán nhanh ảnh thứ 1 đến 9 | Popover lịch sử |
| `Mũi tên Lên / Xuống` | Điều hướng xoay vòng danh sách ảnh chụp | Popover lịch sử |
| `Command + ,` | Mở cửa sổ Cài đặt (Preferences) | Popover / Menu |
| `Command + Q` | Thoát ứng dụng SuperShot | Popover / Menu |

### Hướng dẫn sử dụng: Chụp cuộn trang dài (Scrolling Screenshot)

SuperShot hỗ trợ chụp mượt mà các nội dung dài vượt quá khung nhìn màn hình, chẳng hạn như trang web, tài liệu PDF, file mã nguồn dài, log terminal hoặc cuộc trò chuyện chat:

1. **Kích hoạt chụp cuộn**:
   - Nhấn phím tắt toàn hệ thống `Option + Shift + S` (hoặc chọn **Chụp cuộn màn hình** trong menu chuột phải trên Menu Bar hoặc biểu tượng cuộn trên thanh công cụ vùng chọn).
   - Kéo chuột chọn vùng cửa sổ hoặc nội dung cần cuộn chụp.
2. **Cuộn tự động và Cuộn thủ công**:
   - **Tự động cuộn (Auto-Scroll)**: Nhấn nút **Bắt đầu cuộn**. SuperShot tự động gửi tín hiệu lăn chuột mượt mà (`CGEvent`), tự điều chỉnh tốc độ và chu kỳ lấy mẫu khung hình.
   - **Cuộn thủ công (Manual Scroll)**: Chuyển sang chế độ thủ công nếu bạn muốn tự lăn chuột, vuốt trackpad hoặc dùng phím mũi tên theo nhịp riêng.
3. **Bộ xử lý ghép ảnh thông minh (Image Stitcher)**:
   - **Khử trùng lặp Header & Footer cố định**: Tự động nhận diện thanh điều hướng, menu bám đỉnh (sticky header) hoặc chân trang nổi (sticky footer), giữ nguyên ở đầu/cuối và không bị lặp lại ở giữa ảnh.
   - **Bỏ qua thanh cuộn (Scrollbar)**: Loại trừ dải thanh cuộn ở mép phải khi khớp điểm ảnh dọc, tránh vệt lỗi hoặc đường ghép đứt đoạn.
   - **Xem trước ghép ảnh trực tiếp (Live Stitched Preview)**: Hiển thị hình thu nhỏ kết quả ghép theo thời gian thực kèm số đo kích thước `Rộng x Cao px` ngay bên cạnh vùng chụp.
   - **Tự động dừng chuẩn xác**: Tự động kết thúc khi cuộn chạm đáy nội dung, khi đạt giới hạn chiều cao tối đa (`5.000 px` đến `30.000 px` trong Cài đặt, mặc định `15.000 px`), hoặc khi bạn bấm `Return`, `Space` hoặc nút **Hoàn thành**.
4. **Khung vẽ chú thích cuộn chiều dọc**:
   - Sau khi hoàn thành, ảnh ghép chiều cao lớn sẽ hiển thị trong khung vẽ cuộn mượt mà.
   - Dễ dàng cuộn dọc toàn bộ bức ảnh và sử dụng đầy đủ các công cụ chú thích vector (khung chữ nhật, hình tròn, mũi tên, dòng chữ, bút vẽ, bút dạ quang, làm mờ thông tin).
   - Bấm **Sao chép** (`Cmd + C`) hoặc **Lưu file** (`Cmd + S`) như ảnh chụp thông thường.

### Hướng dẫn sử dụng: Hệ thống bảng màu & Màu mẫu (Color Presets)

SuperShot mang đến khả năng chọn và lưu màu sắc trực quan, linh hoạt cho mọi công cụ chú thích:

1. **Biểu tượng màu trên thanh công cụ**:
   - Màu vẽ hiện tại được biểu thị bằng nút tròn màu trên thanh công cụ vẽ dọc.
   - Bấm vào nút tròn màu để mở bảng chọn `ColorPalettePopoverView`.
2. **8 màu sắc mặc định tương phản cao**:
   - Cung cấp sẵn 8 mã màu chuẩn, độ tương phản sắc nét trên mọi nền ảnh: Đỏ (`#FF3B30`), Cam (`#FF9500`), Vàng (`#FFCC00`), Xanh lá (`#34C759`), Xanh ngọc (`#00C7BE`), Xanh dương (`#007AFF`), Tím (`#AF52DE`) và Xám đậm (`#1C1C1E`).
   - Click chọn màu bất kỳ để đổi ngay màu vẽ hoặc đổi màu của đối tượng đang được chọn trên màn hình.
3. **Nhập mã HEX tùy chọn & Bút chấm màu (Eyedropper)**:
   - **Nhập mã màu HEX**: Gõ trực tiếp mã màu 6 ký tự (`#RRGGBB`) vào ô văn bản.
   - **Bút chấm màu màn hình**: Bấm biểu tượng ống hút màu để lấy mẫu bất kỳ điểm ảnh nào đang hiển thị trên màn hình máy Mac.
4. **Lưu tối đa 16 màu yêu thích**:
   - Bấm nút `+` trong popover bảng màu để lưu màu hiện tại vào danh sách yêu thích (tối đa 16 màu).
   - Quản lý nhanh: Nhấp chuột phải để xóa màu preset, hoặc khôi phục 8 màu ban đầu trong **Cài đặt** -> **Chụp & Lưu**.
5. **Ghi nhớ thông số giữa các phiên chụp**:
   - SuperShot tự động lưu lại mã màu, độ dày nét vẽ và cỡ chữ đã dùng gần nhất, sẵn sàng cho các lần chụp tiếp theo mà không cần chỉnh lại.

### Điểm mới trong v1.0.16

- **Thay đổi kích thước khung chọn & hình vẽ bằng bàn phím (`Option + Mũi tên`)**: Hỗ trợ tăng giảm chiều rộng và chiều cao của khung chọn cũng như hình chú thích đang chọn trực tiếp từ bàn phím với độ chính xác 1px (`Option + Mũi tên`) hoặc 10px (`Option + Shift + Mũi tên`).
- **Đồng bộ thao tác bàn phím trên khung vẽ cuộn dài**: Đầy đủ tính năng di chuyển (nudge) và thay đổi kích thước hình chú thích trên ảnh cuộn dài qua phím Mũi tên và `Option + Mũi tên`.
- **Phím tắt Chia sẻ / Xuất ảnh nhanh (`Cmd + E`)**: Mở bảng chia sẻ macOS (Share Sheet) tức thì bằng tổ hợp phím `Cmd + E` (`⌘E`) trên cả màn hình chụp lớp phủ lẫn khung vẽ cuộn.
- **Xóa toàn bộ chú thích 1 chạm kèm Hoàn tác (`Cmd + Shift + K`)**: Xóa sạch toàn bộ hình vẽ trên màn hình bằng `Cmd + Shift + K` (`⌘⇧K`) kèm huy hiệu thông báo HUD và hỗ trợ hoàn tác đầy đủ với `Cmd + Z`.
- **Huy hiệu gợi ý phím tắt `[ / ]` trên ô tìm kiếm**: Bổ sung huy hiệu `[ / ]` tinh tế ở góc phải ô tìm kiếm khi chưa nhập chữ giúp người dùng dễ dàng nhận biết phím tắt tìm kiếm nhanh.
- **Đóng gói Universal 2 (`arm64` + `x86_64`) chuẩn xác**: Bản phân phối nhị phân Universal 2 chạy gốc mượt mà trên cả chip Apple Silicon lẫn Intel.

### Điểm mới trong v1.0.15

- **Khắc phục triệt để tràn chữ trên thanh Tab Cài đặt (Preferences)**: Tự động co giãn chữ thông minh `.minimumScaleFactor(0.78)` và chuẩn hóa tiêu đề gọn gàng trên mọi ngôn ngữ (`History` trong tiếng Anh, `Historial` trong tiếng Tây Ban Nha và `Capture & Sauvegarde` trong tiếng Pháp), loại bỏ hoàn toàn dấu ba chấm cắt chữ.
- **Vùng nhận diện click toàn phần (Full-Bleed ContentShape) trên mọi nút bấm**: Bổ sung `.contentShape(Rectangle())` và `.contentShape(Circle())` cho toàn bộ các nút tùy biến trên thanh công cụ nổi (Action buttons, bảng màu, chọn nét vẽ, cỡ chữ), cụm nút Zoom HUD ảnh cuộn dài, bảng điều khiển ghép ảnh trực tiếp, các nút trên hàng lịch sử và thanh tiêu đề popover, cửa sổ Chào mừng và các tab Cài đặt giúp click chuột luôn chính xác 100% dù bấm vào phần viền padding.
- **Phím tắt tiện dụng mới (`Cmd+A`, phím mũi tên & `/`)**: Nhấn `Cmd+A` khi đang mở lớp phủ chụp để chọn ngay toàn bộ màn hình, dùng 4 phím Mũi tên (kết hợp Shift để nhảy 10px) để vi chỉnh khung chọn pixel-perfect, và nhấn phím `/` trong popover lịch sử để chuyển ngay tiêu điểm vào ô tìm kiếm.
- **Đóng gói Universal 2 (`arm64` + `x86_64`) chuẩn xác**: Bản phân phối nhị phân Universal 2 chạy gốc mượt mà trên cả chip Apple Silicon lẫn Intel.

### Điểm mới trong v1.0.14

- **Phản hồi tức thì khi bấm chuyển Tab trong Cài đặt (Preferences)**: Bổ sung `SettingsTabButton` với vùng nhận click toàn phần `.contentShape(Rectangle())` (`108x46pt`), phản hồi tức thì ngay khi nhấn chuột xuống (`DragGesture(minimumDistance: 0)`), chuyển tính toán dung lượng ổ đĩa trong tab Lịch sử sang bất đồng bộ và lưu đệm biểu tượng ứng dụng trong tab Giới thiệu giúp chuyển tab mượt mà 0ms độ trễ.
- **Khắc phục lỗi trùng lặp menu Check for Updates**: Sửa lỗi lệch chỉ số mảng trong `StatusItemManager.menuNeedsUpdate` bằng cách đối chiếu theo `action` selector.
- **Hỗ trợ đầy đủ Universal 2 (`arm64` + `x86_64`) không gây cảnh báo Rosetta 2**: Giữ nguyên kiến trúc Universal 2 chạy gốc trên cả MacBook chip Apple Silicon (`arm64`) lẫn MacBook chip Intel (`x86_64`).

### Điểm mới trong v1.0.10

- **Khóa tỉ lệ vuông bằng phím Shift & Huy hiệu kích thước thông minh**: Giữ phím Shift khi kéo tạo vùng chọn hoặc kéo góc để khóa cố định khung hình vuông 1:1. Huy hiệu kích thước trực tiếp tự động nhận diện các tỉ lệ chuẩn (`1:1`, `16:9`, `4:3`, `16:10`, `3:2`, `21:9`, `9:16`, `3:4`, `2:3`) với độ rộng co giãn thông minh không bị cắt chữ.
- **Phím tắt phím ngoặc & Bảng HUD độ dày nét**: Tăng giảm nhanh độ dày nét vẽ từ 1pt đến 16pt bằng các phím ngoặc `[` (giảm) và `]` (tăng), kết hợp huy hiệu HUD xác nhận tức thì trên cả màn hình chụp lẫn khung vẽ cuộn dài.
- **Phản hồi HUD khi Sao chép & Lưu trên khung vẽ cuộn**: Thao tác Sao chép (`Cmd+C` / nút thanh công cụ) hoặc Lưu file (`Cmd+S` / nút thanh công cụ) trên ảnh cuộn dài hiển thị thông báo HUD trực quan ("Đã sao chép vào bộ nhớ tạm" / "Đã lưu tệp thành công").
- **Bố cục 2 hàng nút tab Giới thiệu chống tràn chữ**: Tái cấu trúc cụm nút hành động thành 2 hàng cân đối (Hàng 1: Chào mừng & Hướng dẫn + Kiểm tra bản cập nhật; Hàng 2: Đặt lại toàn bộ cài đặt căn giữa), loại bỏ hoàn toàn hiện tượng cắt chữ ba chấm trên cả tiếng Anh và tiếng Việt.
- **Chuyển tab Cài đặt bằng phím tắt (`Cmd+[` / `Cmd+]`)**: Chuyển đổi linh hoạt giữa các tab Cài đặt bằng tổ hợp phím chuẩn macOS `Cmd+[` / `Cmd+Shift+[` (tab trước) và `Cmd+]` / `Cmd+Shift+]` (tab sau).
- **Bản địa hóa 9 ngôn ngữ toàn diện (100% 0 emoji)**: Dịch chuẩn xác các thẻ tính năng cửa sổ Chào mừng, tooltip công cụ zoom, HUD độ dày nét và gợi ý đặt lại phím tắt trên toàn bộ 9 ngôn ngữ hỗ trợ.

### Điểm mới trong v1.0.9

- **Nâng cấp ô tìm kiếm & trạng thái trống**: Nút xóa tìm kiếm trang bị con trỏ `pointingHand` và tooltip bản địa hóa. Màn hình không tìm thấy kết quả hỗ trợ nút bấm "Xóa tìm kiếm", và màn hình lịch sử trống cung cấp các nút thao tác nhanh ("Chụp vùng màn hình (⌥S)" và "Chụp cuộn trang (⌥⇧S)").
- **Phím Escape phân cấp 4 tầng & Bảng HUD phản hồi chọn công cụ**: Phím Escape hoạt động thông minh và không phá hủy công việc đang vẽ (Tầng 1: xác nhận chữ đang nhập; Tầng 2: bỏ chọn đối tượng hình vẽ đang chọn; Tầng 3: đưa công cụ vẽ về chế độ Chọn `.select`; Tầng 4: chỉ thoát màn hình chụp khi đang ở công cụ chọn và không có đối tượng nào được chọn). Chuyển đổi công cụ bằng phím tắt lập tức đồng bộ con trỏ chuột và hiển thị huy hiệu HUD xác nhận công cụ trực quan.
- **Ký tự modifier chuẩn macOS & Căn giữa khung nhìn khi Zoom**: Cụm nút Quick Zoom HUD sử dụng ký tự phím tắt chuẩn macOS (`⌘-`, `⌘0`, `⌘+`, `⌘9`), đồng thời chế độ "Kích thước thật (100%)" tự động giữ nguyên tâm điểm vùng nhìn của ảnh cuộn dài.
- **Cửa sổ Chào mừng & Hướng dẫn sử dụng chuẩn macOS**: Bổ sung cửa sổ chào mừng 520x460pt (`WelcomeWindow.swift`) với nền kính mờ, các thẻ tính năng nổi bật, kiểm tra trạng thái quyền Ghi màn hình và Trợ năng trực tiếp, mở nhanh từ tab Giới thiệu hoặc menu chuột phải thanh menu.
- **Bản địa hóa cài đặt toàn diện & Chuẩn xác 0-emoji**: Thay thế hoàn toàn các chuỗi ký tự cố định bằng bộ khóa `L10nKey` dịch chuẩn xác trên cả 9 ngôn ngữ, tuân thủ tuyệt đối quy tắc không emoji (100% SF Symbols).

### Điểm mới trong v1.0.8

- **Phản hồi sao chép trực quan tức thì**: Khi sao chép một ảnh từ popover lịch sử (bằng nút sao chép, phím số `1..9` hoặc `Cmd+C`), ứng dụng hiển thị hiệu ứng dấu tích xanh lá kéo dài 1.2 giây trên nút hàng và biểu ngữ HUD popover với chuỗi ký tự bản địa hóa ("Đã sao chép vào bộ nhớ tạm").
- **Tối ưu kích thước & bố cục cửa sổ Cài đặt**: Tăng chiều cao khung cửa sổ từ 530 lên 565 pt và tinh chỉnh khoảng cách các thẻ trong `GeneralSettingsTab`, đảm bảo cả 4 thẻ (bao gồm thẻ Tự động dán) hiển thị đầy đủ, không bị cắt mép dưới và không cần cuộn chuột trên cả tiếng Anh và tiếng Việt.
- **Điều hướng tab Cài đặt bằng phím tắt chuẩn macOS (`Cmd+1`..`Cmd+4`)**: Chuyển đổi linh hoạt giữa các tab Cài đặt chung, Chụp & Lưu, Lịch sử và Thông tin bằng tổ hợp phím `Cmd+1`..`Cmd+4` kèm gợi ý phím tắt trên tooltip.
- **Phím tắt chữ cái gợi nhớ & ký tự modifier macOS chuẩn**: Các công cụ chú thích véc-tơ hỗ trợ phím tắt chữ cái gợi nhớ (`V`, `R`, `C`, `A`, `L`, `P`, `H`, `T`, `B`) hiển thị trực quan trong tooltip (`1 / V`, `2 / R`), đồng thời thanh công cụ thao tác sử dụng ký tự modifier chuẩn macOS (`⌘C / ↵`, `⌘S`, `⎋`, `␣`, `⌘Z`, `⇧⌘Z`).
- **Hiệu ứng rê chuột tương tác mượt mà trên nút thao tác**: Các nút chức năng trên hàng lịch sử (Sao chép, Lưu, Ghim, Xóa) được nâng cấp với độ sáng nền tương tác (tăng từ `0.10` lên `0.18` khi rê chuột), chuyển động lò xo mềm mại và con trỏ `pointingHand`.
- **Mục tiêu Makefile DMG chuẩn macOS**: Thêm lệnh `make dmg` tạo file ảnh đĩa `SuperShot-v1.0.8.dmg` qua `hdiutil` với liên kết `/Applications` giúp kéo thả cài đặt nhanh chóng.

### Điểm mới trong v1.0.7

- **Chụp cuộn chủ động (Manual Scroll) & Chọn vùng trước kèm phím `Esc`/`Enter` toàn cục**: Khi bấm `Option + Shift + S` (hoặc nút Chụp cuộn), ứng dụng mở màn hình kéo chọn vùng chụp trước, sau đó chuyển sang chế độ **Manual Scroll** (loại bỏ hoàn toàn Auto Scroll gây khóa trỏ chuột) và đăng ký phím `Esc` (Hủy) / `Enter` (Hoàn thành) toàn cục để dừng cuộn tức thì dù đang ở bất kỳ ứng dụng nào.
- **Đồng bộ tuyệt đối ảnh Preview và ảnh Hover**: Sử dụng `ThumbnailHoverPreviewViewModel` kết hợp giải mã đồng bộ `resolveImage` / `resolveThumbnail` và khử xung đột sự kiện `onHover` giữa các hàng, đảm bảo ảnh phóng to luôn khớp 100% với ảnh đang trỏ chuột.
- **Nhân bản đối tượng chú thích (`Cmd + D`)**: Sao chép nhanh đối tượng hình vẽ, chữ hoặc vùng làm mờ đang chọn với độ lệch vị trí thông minh qua phím tắt hoặc nút nhân bản trên thanh công cụ.
- **Khóa tỉ lệ chuẩn & góc nghiêng (`Shift`)**: Giữ phím Shift khi vẽ để khóa khung chữ nhật thành hình vuông (1:1), elip thành hình tròn tuyệt đối, và đường thẳng/mũi tên khớp các góc 45 độ.
- **Bảng điều khiển phóng to/thu nhỏ nhanh (Zoom HUD)**: Thêm cụm nút zoom nổi trên khung vẽ cuộn `ScrollableCanvasView` với các chế độ Fit (vừa màn hình), 100%, 200% và phím tắt `Cmd +` / `Cmd -` / `Cmd 0`.
- **Chuẩn xác 0-emoji tuyệt đối**: 100% biểu tượng SF Symbols và bố cục giao diện chuẩn macOS trên tất cả các ngôn ngữ hỗ trợ.

### Yêu cầu hệ thống

- macOS 13.0 (Ventura), macOS 14.6+ (Sonoma) trở lên
- Hỗ trợ tốt trên cả chip Apple Silicon (`arm64`: M1/M2/M3/M4) và chip Intel (`x86_64`, ví dụ MacBook Pro 2020)

### Hướng dẫn cài đặt

#### Tải bản đóng gói sẵn
1. Tải bản phát hành mới nhất `SuperShot-v1.0.16.dmg` (hoặc `.zip`) tại mục [Releases](https://github.com/nhanqv-ai/SuperShot/releases).
2. Mở file DMG và kéo `SuperShot.app` vào thư mục `/Applications` (Ứng dụng).
3. Mở `SuperShot.app`. Biểu tượng khung chụp sẽ xuất hiện trên thanh menu macOS.

> [!NOTE]
> **Mở ứng dụng lần đầu (macOS Gatekeeper)**:
> Do SuperShot là phần mềm mã nguồn mở độc lập (chưa đăng ký chứng chỉ Apple Developer có phí), macOS có thể hiển thị thông báo bảo vệ (*"SuperShot" Not Opened*). Bạn có thể mở ứng dụng dễ dàng bằng một trong các cách:
> - **Dùng Terminal (Nhanh nhất)**: Chạy lệnh `xattr -cr /Applications/SuperShot.app` (hoặc đường dẫn file vừa giải nén).
> - **Dùng Cài đặt hệ thống**: Vào **System Settings** -> **Privacy & Security** -> cuộn xuống mục **Security** -> chọn **Open Anyway** (Vẫn mở).
> - **Dùng chuột phải**: Nhấp chuột phải (hoặc giữ phím `Control` + click) vào `SuperShot.app` -> chọn **Open** (Mở) -> chọn **Open**.

> [!TIP]
> **Cấp quyền Ghi màn hình (Screen Recording) & Trợ năng (Accessibility)**:
> - **Ghi màn hình (Screen Recording)**: Cần thiết để macOS cho phép chụp nội dung các cửa sổ trên màn hình. Vào SuperShot **Cài đặt** -> tab **Chung** -> bấm **Cấp quyền...** tại mục Ghi màn hình, hoặc bật `SuperShot` trong **System Settings** -> **Privacy & Security** -> **Screen & System Audio Recording**.
> - **Trợ năng (Accessibility - Tùy chọn cho Tự động dán)**: Giúp tự động dán ảnh (`Cmd + V`) khi chọn từ lịch sử Popover. Nếu cập nhật bản mới bị kẹt cache quyền trên macOS, có thể chạy `tccutil reset ScreenCapture com.supershot.SuperShot` hoặc bấm nút cấp quyền trong Cài đặt.

#### Biên dịch từ mã nguồn
```bash
git clone https://github.com/nhanqv-ai/SuperShot.git
cd SuperShot
make app
open SuperShot.app
```

### Lệnh phát triển & Kiểm thử

```bash
# Biên dịch và chạy bộ kiểm thử tự động
make test

# Xác thực tính toàn vẹn của bundle ứng dụng Universal 2
make verify-app

# Kiểm tra quy chuẩn nghiêm ngặt 0-emoji
make lint

# Đóng gói file nén zip phân phối Universal 2
make package

# Dọn dẹp file build
make clean
```

### Giấy phép (License)

Dự án được phân phối dưới giấy phép [MIT License](LICENSE).
