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
| `Command + C` or `Return` | Copy annotated screenshot to clipboard & save to history | Capture Overlay |
| `Command + S` | Save annotated screenshot to file (`PNG` / `JPEG`) | Capture Overlay |
| `Command + Z` | Undo last annotation action | Capture Overlay |
| `Command + Shift + Z` | Redo annotation action | Capture Overlay |
| `Delete / Backspace` | Delete currently selected annotation object | Capture Overlay |
| `Escape` | Cancel capture overlay or dismiss history popover | Overlay / Panel |
| `1` .. `9` or `Cmd + 1` .. `Cmd + 9` | Directly copy & auto-paste screenshot 1 to 9 | History Popover |
| `Up / Down Arrow` | Circular navigation across screenshot history | History Popover |
| `Command + ,` | Open Preferences window | History Popover / Menu |
| `Command + Q` | Quit SuperShot | History Popover / Menu |

### System Requirements

- macOS 13.0 (Ventura), macOS 14.6+ (Sonoma), or newer
- Apple Silicon Mac (`arm64`) or Intel Mac (`x86_64`, e.g. MacBook Pro 2020)

### Installation

#### Pre-built Release
1. Download the latest `SuperShot-v1.0.0.zip` from [Releases](https://github.com/nhanqv-ai/SuperShot/releases).
2. Unzip and drag `SuperShot.app` into your `/Applications` folder.
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
- **Popover Lịch sử Ảnh chụp & Tự động dán (Phong cách SuperClip)**:
  - Click chuột trái vào icon trên Menu Bar để mở **Popover Lịch sử ảnh chụp** với 2 nhóm Đã ghim (Pinned) và Gần đây (Recent), tìm kiếm tức thì, xem phóng to khi rê chuột (`ThumbnailHoverPreviewPanel`), bấm phím `1..9` để chọn nhanh và hỗ trợ Tự động dán (`Auto-Paste`).
  - Trên từng dòng lịch sử có đầy đủ nút **Sao chép**, **Lưu ra file**, **Ghim (Pin)** và **Xóa**.
- **Chế độ lưu file linh hoạt**: Tùy chỉnh trong Cài đặt để khi bấm Save (`Cmd + S`) sẽ mở hộp thoại chọn nơi lưu (`NSSavePanel`) hoặc tự động lưu thẳng vào thư mục mặc định (như `~/Desktop` hoặc `~/Pictures/SuperShot`) dưới định dạng `PNG` hoặc `JPEG`.
- **Kiến trúc Universal 2**: Biên dịch dưới dạng Mach-O fat binary hỗ trợ gốc cả chip Apple Silicon (`arm64`: M1/M2/M3/M4) và chip Intel (`x86_64`: MacBook Pro 2020 và các đời Intel) trên macOS 13.0 (Ventura) và macOS 14.6+ (Sonoma).
- **Hỗ trợ đa ngôn ngữ**: Thay đổi ngôn ngữ tức thì trong cài đặt: Tiếng Việt, Tiếng Anh, Tiếng Trung, Tiếng Nhật, Tiếng Hàn, Tiếng Tây Ban Nha, Tiếng Pháp, Tiếng Đức và Mặc định hệ thống.
- **Quy chuẩn 0 Emojis**: Sử dụng hoàn toàn biểu tượng SF Symbols hiện đại, tinh gọn và chuyên nghiệp.

### Bảng phím tắt thông dụng

| Phím tắt | Thao tác | Phạm vi |
| :--- | :--- | :--- |
| `Option + S` | Kích hoạt chụp màn hình nhanh (tùy chỉnh được) | Toàn hệ thống |
| `Command + C` hoặc `Return` | Sao chép ảnh đã chú thích vào Clipboard & lưu vào lịch sử | Màn hình chụp |
| `Command + S` | Lưu ảnh đã chú thích thành file (`PNG` / `JPEG`) | Màn hình chụp |
| `Command + Z` | Hoàn tác bước vẽ trước đó (Undo) | Màn hình chụp |
| `Command + Shift + Z` | Làm lại bước vẽ (Redo) | Màn hình chụp |
| `Delete / Backspace` | Xóa đối tượng hình vẽ/chữ đang chọn | Màn hình chụp |
| `Escape` | Hủy chụp màn hình hoặc đóng cửa sổ lịch sử | Màn hình chụp / Popover |
| `1` .. `9` hoặc `Cmd + 1` .. `Cmd + 9` | Chọn và sao chép/dán nhanh ảnh thứ 1 đến 9 | Popover lịch sử |
| `Mũi tên Lên / Xuống` | Điều hướng xoay vòng danh sách ảnh chụp | Popover lịch sử |
| `Command + ,` | Mở cửa sổ Cài đặt (Preferences) | Popover / Menu |
| `Command + Q` | Thoát ứng dụng SuperShot | Popover / Menu |

### Yêu cầu hệ thống

- macOS 13.0 (Ventura), macOS 14.6+ (Sonoma) trở lên
- Hỗ trợ tốt trên chip Apple Silicon (`arm64`) và chip Intel (`x86_64`, ví dụ MacBook Pro 2020)

### Hướng dẫn cài đặt

#### Tải bản đóng gói sẵn
1. Tải bản phát hành mới nhất `SuperShot-v1.0.0.zip` tại mục [Releases](https://github.com/nhanqv-ai/SuperShot/releases).
2. Giải nén và kéo file `SuperShot.app` vào thư mục `/Applications` (Ứng dụng).
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
