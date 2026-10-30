# Project: SuperShot (com.supershot.SuperShot)

## Architecture

SuperShot is structured as a native macOS menu bar application (`LSUIElement = true`) adhering to macOS 13.0+ and Swift 5.9+. The codebase is partitioned cleanly into a shared core dynamic library (`SuperShotCore`) and a lightweight executable application target (`SuperShot`), unified by a Universal 2 (`arm64` + `x86_64`) build pipeline.

```
+---------------------------------------------------------------------------------------+
|                                    SuperShot.app                                      |
|                                                                                       |
|  +-----------------------+   +---------------------------+   +---------------------+  |
|  |   StatusItemManager   |   |    CaptureOverlayWindow   |   |   SettingsWindow    |  |
|  | (NSStatusItem Popover |   | (Lightshot Fullscreen     |   | (4-Tab Preferences  |  |
|  |  + Context Menu)      |   |  Selection & Toolbars)    |   |  + Permissions)     |  |
|  +-----------+-----------+   +-------------+-------------+   +----------+----------+  |
|              |                             |                            |             |
|              v                             v                            v             |
|  +-----------------------+   +---------------------------+   +---------------------+  |
|  |     MainShotView      |   | ScrollableAnnotationCanvas|   |  AutoPasteService   |  |
|  | (History List, Search,|   | (Tall Stitched Image      |   | (Synthetic CGEvent  |  |
|  |  Hover Zoom Preview)  |   |  Viewport & Vector Tools) |   |  Command+V Paste)   |  |
|  +-----------+-----------+   +-------------+-------------+   +----------+----------+  |
|              \                             |                           /              |
+---------------\----------------------------|--------------------------/---------------+
                 \                           |                         /
                  v                          v                        v
+---------------------------------------------------------------------------------------+
|                              libSuperShotCore.dylib                                   |
|                                                                                       |
|  +--------------------+  +--------------------+  +---------------------------------+  |
|  | ScreenCaptureEngine|  |  AnnotationEngine  |  |         ImageStitcher           |  |
|  | (CGDisplay Retina  |  | (8 Vector Tools,   |  | (Vertical Offset Matching,      |  |
|  |  2x Screen Freeze) |  |  Undo/Redo Stack)  |  |  Scrollbar Strip Exclusion,     |  |
|  +--------------------+  +--------------------+  |  Sticky Header/Footer Dedup)    |  |
|                                                  +---------------------------------+  |
|  +--------------------+  +--------------------+  +---------------------------------+  |
|  |   StorageManager   |  |    ColorPreset     |  |       LocalizationManager       |  |
|  | (Thread-safe Lock, |  | (8 Defaults to 16, |  | (9 Languages, Pure Swift        |  |
|  |  Async Disk Queue, |  |  Hex Picker,       |  |  Dynamic Localization,          |  |
|  |  NSCache & Sandbox)|  |  AppSettings Store)|  |  Zero Emojis)                    |  |
|  +--------------------+  +--------------------+  +---------------------------------+  |
+---------------------------------------------------------------------------------------+
```

## Code Layout

```
/Users/nhanquach/my-screenshot-app/
├── Makefile                                # Universal 2 build system, lint, test, package
├── Package.swift                           # SwiftPM manifest (0 external dependencies)
├── README.md                               # Bilingual product documentation
├── LICENSE                                 # MIT License
├── Assets/                                 # App icon PNG assets
├── Scripts/                                # Build, lint, and verification scripts
│   ├── generate_icon.swift                 # 10-resolution icon generator
│   ├── lint_emojis.py                      # Strict zero-emoji validator
│   ├── verify.sh                           # Headless test runner build & execution
│   ├── verify_app.sh                       # 8-step bundle layout & execution verification
│   ├── verify_bundle.sh                    # Bundle integrity check
│   └── run_adversarial.sh                  # Stress test runner
├── Sources/
│   ├── SuperShotCore/                      # Dynamic library target
│   │   ├── Models/
│   │   │   ├── ColorPreset.swift           # ColorPreset, hex conversion, defaults
│   │   │   ├── AnnotationModels.swift      # AnnotationTool, AnnotationObject, Action
│   │   │   ├── ShotItem.swift              # Screenshot record, metadata, dimensions
│   │   │   └── AppSettings.swift           # User preferences & preset storage
│   │   ├── Capture/
│   │   │   ├── ScreenCaptureManager.swift  # Retina 2x display freeze capture
│   │   │   └── ScrollingCaptureManager.swift # Auto-scroll CGEvent synthesis, loops
│   │   ├── Stitching/
│   │   │   └── ImageStitcher.swift         # Vertical overlap, scrollbar/sticky dedup
│   │   ├── Annotation/
│   │   │   ├── AnnotationEngine.swift      # Vector object management, hit test, undo/redo
│   │   │   └── ImageRenderer.swift         # Vector rendering & blur filter rasterization
│   │   ├── Storage/
│   │   │   └── StorageManager.swift        # Thread-safe disk persistence, NSCache
│   │   └── Services/
│   │       ├── HotKeyManager.swift         # Carbon global hotkeys (Option+S, etc.)
│   │       ├── AutoPasteService.swift      # Direct CGEvent Cmd+V paste & AX check
│   │       └── LocalizationManager.swift   # Pure-Swift multi-language translation
│   └── SuperShot/                          # App executable target
│       ├── App/
│       │   ├── AppDelegate.swift           # App lifecycle, NSStatusItem initialization
│       │   └── main.swift                  # Swift executable entry point
│       ├── UI/
│       │   ├── Overlay/
│       │   │   ├── CaptureOverlayWindow.swift # Fullscreen borderless overlay window
│       │   │   ├── SelectionBoxView.swift  # 8-handle selection box with dimension badge
│       │   │   ├── AnnotationCanvasView.swift # Interactive vector drawing canvas
│       │   │   ├── FloatingToolbarsView.swift # Vertical tool & horizontal action toolbars
│       │   │   └── ColorPalettePopover.swift # Swatches, hex input, eyedropper popover
│       │   ├── Scrolling/
│       │   │   ├── LiveStitchedPreviewView.swift # Live stitching thumbnail badge
│       │   │   └── ScrollableCanvasView.swift # Tall image scrollable canvas
│       │   ├── Popover/
│       │   │   ├── MainShotView.swift      # History popover (pinned, recent, search)
│       │   │   ├── ShotRowView.swift       # History item row with actions
│       │   │   └── ThumbnailHoverPreview.swift # Floating zoom preview panel
│       │   └── Settings/
│       │       ├── SettingsView.swift      # 4-tab preference view
│       │       └── SettingsWindowController.swift # Centered preference window
└── Tests/
    ├── Common/
    │   └── TestHarness.swift               # Zero-dependency ANSI test harness & sandbox
    ├── SuperShotCoreTests/                 # Core engine unit tests
    │   ├── ColorPresetTests.swift
    │   ├── AnnotationEngineTests.swift
    │   ├── ImageStitcherTests.swift
    │   ├── StorageManagerTests.swift
    │   ├── HotKeyManagerTests.swift
    │   └── LocalizationTests.swift
    ├── SuperShotUITests/                   # UI logic & auto-paste unit tests
    │   ├── AutoPasteServiceTests.swift
    │   ├── HistoryPopoverTests.swift
    │   └── SettingsViewTests.swift
    └── VerificationRunner/
        └── main.swift                      # Test runner aggregating all test suites
```

## Feature Inventory

| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Universal 2 Makefile | Dual-slice arm64 + x86_64 compilation using MacOSX15.4.sdk | M1 | ORIGINAL_REQUEST §R4 |
| 2 | Package.swift Manifest | Swift 5.9, macOS 13+, 0 external package dependencies | M1 | ORIGINAL_REQUEST §R4 |
| 3 | Zero-Emoji Linter | Strict python3 script scanning unicode ranges, 0 emojis allowed | M1 | ORIGINAL_REQUEST §R4 |
| 4 | TestHarness Framework | Zero-dependency unit test assertion engine with ANSI reporting | M1 | Reference SuperClip |
| 5 | ColorPreset Data Model | 8 high-contrast default presets, hex `#RRGGBB` parsing, RGBA conversion | M1 | ORIGINAL_REQUEST §R1 |
| 6 | ColorPreset Persistence | Up to 16 favorite presets, add, delete, reset to default | M1 | ORIGINAL_REQUEST §R1 |
| 7 | AppSettings Store | JSON-backed persistence for active color, stroke width, font size | M1 | ORIGINAL_REQUEST §R1 |
| 8 | ShotItem Data Model | Screenshot metadata, file path, dimensions, pinned state, timestamp | M1 | ORIGINAL_REQUEST §R3 |
| 9 | Thread-safe StorageManager | NSRecursiveLock, dedicated serial fileQueue, baseDirectory sandbox | M1 | Reference SuperClip |
| 10 | In-Memory NSCache | Synchronous thumbnail & image retrieval with size-based eviction | M1 | Reference SuperClip |
| 11 | Pinned Item Protection | Storage capacity enforcement that guarantees pinned items are kept | M1 | ORIGINAL_REQUEST §R3 |
| 12 | LocalizationManager | 9 languages (including EN & VI), dynamic runtime switching, 0 emojis | M1 | ORIGINAL_REQUEST §R3 |
| 13 | HotKeyManager | Carbon global hotkey registration for Option+S and Option+Shift+S | M1 | ORIGINAL_REQUEST §R1, R2 |
| 14 | AppIcon Asset Generator | 10-resolution icon generator via Scripts/generate_icon.swift | M1 | ORIGINAL_REQUEST §Verification |
| 15 | Retina 2x Screen Freeze | Full 2x resolution capture using CGDisplayCreateImage | M2 | ORIGINAL_REQUEST §R1 |
| 16 | Multi-Display Support | Active screen detection and coordinate mapping across displays | M2 | ORIGINAL_REQUEST §R1 |
| 17 | Outside Dimming Overlay | Borderless full-screen window dimming outside selection with black.opacity(0.45) | M2 | ORIGINAL_REQUEST §R1 |
| 18 | 8-Handle Selection Box | Resizable bounding box with 8 circular grab handles | M2 | ORIGINAL_REQUEST §R1 |
| 19 | Live Dimension Badge | Real-time `W x H px` resolution indicator anchored to selection | M2 | ORIGINAL_REQUEST §R1 |
| 20 | Edge-Aware Repositioning | Automatic flipping of toolbars near screen borders | M2 | ORIGINAL_REQUEST §R1 |
| 21 | Vector Tool: Select/Move | Hit-testing, dragging, and repositioning existing vector objects | M2 | ORIGINAL_REQUEST §R1 |
| 22 | Vector Tool: Rectangle | Sharp bordered bounding rectangles with variable stroke & color | M2 | ORIGINAL_REQUEST §R1 |
| 23 | Vector Tool: Ellipse/Circle | Vector oval and circle drawing | M2 | ORIGINAL_REQUEST §R1 |
| 24 | Vector Tool: Arrow | Vector directional arrows with crisp proportional arrowheads | M2 | ORIGINAL_REQUEST §R1 |
| 25 | Vector Tool: Line | Straight diagonal / orthogonal vector lines | M2 | ORIGINAL_REQUEST §R1 |
| 26 | Vector Tool: Freehand Pen | Smooth freeform path rendering with anti-aliasing | M2 | ORIGINAL_REQUEST §R1 |
| 27 | Vector Tool: Highlighter | Semi-transparent marker stroke preserving background text contrast | M2 | ORIGINAL_REQUEST §R1 |
| 28 | Vector Tool: Editable Text | In-place text input box, font size selector, color, keyboard focus | M2 | ORIGINAL_REQUEST §R1 |
| 29 | Vector Tool: Region Blur | Sensitive area pixelate / gaussian blur vector overlay | M2 | ORIGINAL_REQUEST §R1 |
| 30 | Undo / Redo Engine | Complete command pattern history supporting Cmd+Z and Cmd+Shift+Z | M2 | ORIGINAL_REQUEST §R1 |
| 31 | Color Swatch Bar | 1-click active color or selected object recoloring from 8 presets | M2 | ORIGINAL_REQUEST §R1 |
| 32 | Custom HEX Input Picker | Direct text input for `#RRGGBB` custom color selection | M2 | ORIGINAL_REQUEST §R1 |
| 33 | Screen Eyedropper Tool | Magnified screen color sampler using NSColorSampler / CGDisplay | M2 | ORIGINAL_REQUEST §R1 |
| 34 | Floating Action Toolbar | Horizontal toolbar with Copy, Save, Share, Scroll, and Cancel | M2 | ORIGINAL_REQUEST §R1 |
| 35 | High-Fidelity Rasterizer | Vector path & blur compositing onto underlying bitmap for final output | M2 | ORIGINAL_REQUEST §R1 |
| 36 | Scroll Event Synthesizer | Smooth downward CGEvent scroll wheel generation at viewport center | M3 | ORIGINAL_REQUEST §R2 |
| 37 | Manual Scroll Mode | User scroll input listening with real-time frame capturing | M3 | ORIGINAL_REQUEST §R2 |
| 38 | Live Stitched Preview | Floating miniature preview showing incremental stitched image & dims | M3 | ORIGINAL_REQUEST §R2 |
| 39 | Scrollbar Strip Exclusion | Automatic exclusion of rightmost 24px scrollbar from offset matching | M3 | ORIGINAL_REQUEST §R2 |
| 40 | Sticky Header Detection | Cross-frame stationary row correlation at top of frame to prevent dupes | M3 | ORIGINAL_REQUEST §R2 |
| 41 | Sticky Footer Detection | Cross-frame stationary row correlation at bottom of frame to prevent dupes | M3 | ORIGINAL_REQUEST §R2 |
| 42 | Vertical Overlap Matching | Pixel-difference offset estimation for seam-free image concatenation | M3 | ORIGINAL_REQUEST §R2 |
| 43 | Auto-Stop on End-of-Page | Zero-delta overlap detection signaling page bottom has been reached | M3 | ORIGINAL_REQUEST §R2 |
| 44 | maxScrollHeightPx Clamp | Configurable hard height ceiling (default 15,000 px, 5k-30k px) | M3 | ORIGINAL_REQUEST §R2 |
| 45 | User Done Stop Trigger | Manual termination via Return or Space key | M3 | ORIGINAL_REQUEST §R2 |
| 46 | Tall Image Scroll Canvas | NSScrollView viewport capable of displaying tall images up to 30,000 px | M3 | ORIGINAL_REQUEST §R2 |
| 47 | Tall Canvas Vector Annotations | Full vector annotation tools enabled on stitched tall screenshot | M3 | ORIGINAL_REQUEST §R2 |
| 48 | NSStatusItem Controller | Dual-click status bar item (left-click popover, right-click menu) | M4 | ORIGINAL_REQUEST §R3 |
| 49 | History Popover View | MainShotView featuring Pinned and Recent sections | M4 | ORIGINAL_REQUEST §R3 |
| 50 | Instant History Search | Substring and timestamp search filtering history items | M4 | ORIGINAL_REQUEST §R3 |
| 51 | Hover Zoom Preview | ThumbnailHoverPreviewPanel displaying high-res magnified preview | M4 | ORIGINAL_REQUEST §R3 |
| 52 | Circular Keyboard Nav | Up/Down arrow cycling through history items seamlessly | M4 | ORIGINAL_REQUEST §R3 |
| 53 | 1..9 Quick Select | Number keys 1-9 immediately selecting and copying corresponding item | M4 | ORIGINAL_REQUEST §R3 |
| 54 | Direct Auto-Paste Service | Synthetic Cmd+V keystroke injection into previous active app | M4 | ORIGINAL_REQUEST §R3 |
| 55 | Context Menu | Right-click NSMenu (Capture, Scroll, History, Preferences, Quit) | M4 | ORIGINAL_REQUEST §R3 |
| 56 | 4-Tab Settings Window | General, Capture & Save, History, About with permission checks | M4 | ORIGINAL_REQUEST §R3 |
| 57 | Flexible Save Modes | Prompt NSSavePanel vs direct auto-save to directory in PNG/JPEG | M4 | ORIGINAL_REQUEST §R3 |
| 58 | Launch at Login | SMAppService login item registration and state querying | M4 | ORIGINAL_REQUEST §R3 |
| 59 | Documentation Sync | Updated README.md documenting Scrolling Capture and Color Presets | M4 | ORIGINAL_REQUEST §R4 |
| 60 | E2E Regression Pass | 100% pass on all 4 tiers of E2E test suite and adversarial check | M5 | ORIGINAL_REQUEST §Acceptance |
| 61 | Live GUI Driver Execution | Compile and execute LiveGUIDriver.swift to render on-screen GUI and generate snapshots | M6 | ORIGINAL_REQUEST §R1 |
| 62 | In-Place Capture Overlay Verification | Test pre-selection instruction banner, 8 handles, W x H px badge, edge-aware positioning | M6 | ORIGINAL_REQUEST §R1.1 |
| 63 | Context-Aware Cursor UX Verification | Verify pointingHand on controls, crosshair/tool/resize cursors on canvas | M6 | ORIGINAL_REQUEST §R1.2 |
| 64 | Vector Engine & Mosaic Blur Verification | Test 9 tools, 1-click presets, hex/eyedropper, undo/redo | M6 | ORIGINAL_REQUEST §R1.3 |
| 65 | Scrolling Capture & Tall Canvas Verification | Auto/manual scroll, sticky dedup, preview panel, tall canvas annotation | M6 | ORIGINAL_REQUEST §R1.4 |
| 66 | Menu Bar Popover & Settings Verification | 380x560 popover, pinned/recent, hover preview, 4 settings tabs in EN and VI | M6 | ORIGINAL_REQUEST §R1.5 |
| 67 | Proactive UX & Feature Polish | Inspect live snapshots for visual rough edges, clipping, responsiveness; refine code (0 emojis) | M7 | ORIGINAL_REQUEST §R2 |
| 68 | Automated Release Pipeline | Bump patch version, branch, PR, merge, make verify/package, GitHub public release | M8 | ORIGINAL_REQUEST §R3 |
| 69 | Real UpdateManager Integration | Implement UpdateManager in SuperShotCore querying GitHub releases API, wire to AboutSettingsTab | M7.1 | Follow-up 2026-10-23 |
| 70 | In-App Update Banner & Notification | MainShotView update banner (.updateAvailable, .downloading, .readyToRestart, .error), Settings gear badge dot | M10 | Follow-up 2026-10-23 |
| 71 | Update Frequency Setting | Daily (1), Weekly (7), Monthly (30) interval options in General settings, persisted & clamped in AppSettings | M10 | Follow-up 2026-10-23 |
| 72 | Ergonomics Polish & Zero-Emoji L10n | Popover dynamic arrowEdge, scroll capture cleanup, pointingHandCursor on settings buttons, 9 languages | M10 | Follow-up 2026-10-23 |
| 73 | Full Download & Install Flow | Direct download of release asset zip and installation/updater launch matching SuperClip | M10 | ORIGINAL_REQUEST §R2 |
| 74 | Vector/Capture Ergonomics Polish | Any cursor, hover, or toolbar refinements identified during live GUI audit | M10 | ORIGINAL_REQUEST §R2 |
| 75 | Version Bump to v1.0.4 | Update Info.plist, AboutSettingsTab, Makefile, README.md | M11 | ORIGINAL_REQUEST §R3 |
| 76 | Automated Git PR & Merge | Feature branch, gh pr create, gh pr merge to main | M11 | ORIGINAL_REQUEST §R3 |
| 77 | Universal 2 Package & Release | make clean, lint, test, adversarial, app, verify-app, package, gh release create v1.0.4 | M11 | ORIGINAL_REQUEST §R3 |
| 78 | Public Repo Enforcement | Ensure nhanqv-ai/SuperShot visibility is PUBLIC | M11 | Follow-up 2026-10-23 |
| 79 | Annotation Object Duplication | Cmd+D shortcut and toolbar duplicate button to clone selected vector annotation with offset | M13 | ORIGINAL_REQUEST §R2 |
| 80 | Shift-Constrained Drawing | Shift-key modifier enforcing 1:1 square/circle aspect ratio and 45-degree line/arrow snapping | M13 | ORIGINAL_REQUEST §R2 |
| 81 | Canvas Quick Zoom HUD | Floating zoom controls (Fit, 100%, 200%, Cmd+/- shortcuts) and status HUD on ScrollableCanvasView | M13 | ORIGINAL_REQUEST §R2 |
| 82 | Canvas & Popover Ergonomics | Enhanced keyboard navigation, drag selection bounds clamping, and pointingHand feedback | M13 | ORIGINAL_REQUEST §R2 |
| 83 | Version Bump to v1.0.5 | Update Info.plist, AboutSettingsTab, Makefile, PROJECT.md, README.md | M14 | ORIGINAL_REQUEST §R3 |
| 84 | Automated Git PR & Merge | Feature branch feat/v1.0.5-ux-canvas-polish, gh pr create, gh pr merge to main | M14 | ORIGINAL_REQUEST §R3 |
| 85 | Universal 2 Package & Release | make clean, lint, test, adversarial, app, verify-app, package, gh release create v1.0.5 | M14 | ORIGINAL_REQUEST §R3 |
| 86 | Public Repo Enforcement | Ensure nhanqv-ai/SuperShot visibility remains PUBLIC with release tag v1.0.5 verified | M14 | ORIGINAL_REQUEST §R3 |
| 87 | Live GUI & On-Screen Audit v1.0.10 | Exercise 6 surfaces on screen, capture 24 Retina snapshots, inspect layout | M24 | ORIGINAL_REQUEST §R1 |
| 88 | About Settings Button Layout & Truncation Fix | Reorganize 3 action buttons into 2 rows to eliminate ellipsis clipping in EN & VI | M25 | ORIGINAL_REQUEST §R2 |
| 89 | Shift-Key Square Selection & Smart Aspect Ratio Badge | Constrain 1:1 selection box with Shift, detect standard aspect ratios with auto-sizing badge | M25 | ORIGINAL_REQUEST §R2 |
| 90 | Stroke Width Shortcuts & ScrollableCanvas HUD | Bracket keys [ and ] step stroke width with HUD pill, copy/save HUD confirmation | M25 | ORIGINAL_REQUEST §R2 |
| 91 | Localization & Settings Tab Cycling | Full 9-language localization for Welcome feature cards & zoom tooltips, Cmd+[/] tab cycling | M25 | ORIGINAL_REQUEST §R2 |
| 92 | Version Bump v1.0.10 & Automated Release | Bump 6 files + 1 test file, PR, merge, clean Universal 2 build, zip & dmg release, app relaunch | M26 | ORIGINAL_REQUEST §R3 |
| 93 | Selection Box & Object Keyboard Resizing | Option + Arrow (1px) and Option + Shift + Arrow (10px) in SelectionBoxView to resize width/height of selection box and selected vector objects | M30 | Explorers 1 & 2 Survey |
| 94 | Tall Canvas Annotation Keyboard Parity | Arrow key nudging (1px/10px) and Option + Arrow resizing (1px/10px) on selected annotations in ScrollableCanvasView | M30 | Explorer 2 Survey |
| 95 | Share / Export Keyboard Shortcut | Cmd+E shortcut for share/export in FloatingToolbarsView and ScrollableCanvasView | M30 | Explorer 2 Survey |
| 96 | 1-Click Clear All Annotations with Undo | Cmd+Shift+K batch clear all annotations with undo/redo integration in AnnotationEngine and HUD pill confirmation | M30 | Explorer 2 Survey |
| 97 | Search Bar Shortcut Hint Badge | Subtle [ / ] keyboard hint badge in SearchBarView when text.isEmpty | M30 | Explorers 1 & 2 Survey |
| 98 | LiveGUIDriver Modernization & Expansion | Update LiveGUIDriver.swift for v1.0.16: cover Cmd+A, arrow nudging, Option-Arrow resizing, / shortcut, Cmd+9, dual-language Welcome window | M30 | Explorer 1 Survey |
| 99 | Version Bump to 1.0.16 & Test Invariant Sync | Update all 7 version locations: Info.plist (1.0.16, build 16), AboutSettingsTab, WelcomeWindow, UpdateManager, Makefile, README.md, SettingsViewTests | M30 | Explorer 3 Survey |
| 100 | Option-Modifier Center-Out Selection Box Creation | calculateCenterRect in SelectionBoxGeometry and dynamic Option / Shift handling in SelectionBoxView mouseDragged & flagsChanged | M34 | DISPATCH §2 |
| 101 | Vector Layer Z-Index Reordering with Undo/Redo | Reorder action in AnnotationAction, bring/send front/back/forward/backward in AnnotationEngine, Cmd+[/], Cmd+Shift+[/] shortcuts & HUD | M34 | DISPATCH §3 |
| 102 | Tall Viewport Keyboard Navigation & Zoom HUD | scrollBy, pageUp/Down, scrollToTop/Bottom in ScrollableAnnotationScrollView, arrow/page/home/end/space keys in ScrollableAnnotationWindow, transient zoom HUD pill | M34 | DISPATCH §4 |
| 103 | History Popover Ergonomics (Cmd+F & Cmd+O) | Cmd+F to focus search field, Cmd+O & Cmd+Return to reveal item in macOS Finder via activateFileViewerSelecting, updated context menu hint | M34 | DISPATCH §5 |
| 104 | Dimension Badge Overlap & Edge Clamping Fix | Prevent dimension badge visual collision when horizontal action toolbar flips above selectionRect.maxY in bottom-screen captures | M34 | DISPATCH §6 |
| 105 | ScrollableAnnotationWindow Dark Styling Fix | NSAppearance .darkAqua and dark background color (white: 0.12) on ScrollableAnnotationWindow & ScrollableAnnotationScrollView | M34 | DISPATCH §7 |
| 106 | Instruction Banner & Auto-Paste Subtitle L10n | Update captureOverlayInstruction across 9 languages (⌘A fullscreen & Shift square) and refine auto-paste subtitle technical copy (0 emojis) | M34 | DISPATCH §8 |
| 107 | Canonical Version Bump to v1.0.17 | Synchronize v1.0.17 across Info.plist (build 17), AboutSettingsTab, WelcomeWindow, UpdateManager, Makefile, README.md, SettingsViewTests, PROJECT.md | M34 | DISPATCH §9 |
| 108 | Tool Single-Key Mnemonic Parity | 'M' for Mosaic Blur alongside 'B', 'E' for Ellipse alongside 'C', alternateMnemonicKey in AnnotationToolType | M38 | Explorer 2 Survey |
| 109 | IME Composition (hasMarkedText) Input Guard | Yield Up/Down arrow and Return to active IME in MainShotView search | M38 | Explorer 2 Survey |
| 110 | Real-Time Frame Counter on Live Preview | photo.stack badge in LiveStitchedPreviewPanel displaying localized framesCount | M38 | Explorer 2 Survey |
| 111 | History Item Deletion Toast HUD & Shortcut Hints | showDeletedToast HUD in MainShotView and (⌘C), (⌘S), (⌘P), (⌫) shortcut hints in ShotRowView contextMenu | M38 | Explorer 2 Survey |
| 112 | One-Click System Diagnostics & Version Copy | Interactive version pill with checkmark feedback in AboutSettingsTab copying system diagnostic string | M38 | Explorer 2 Survey |
| 113 | Standard macOS Control+Tab Settings Tab Cycling | Support Control+Tab and Control+Shift+Tab (keyCode 48) tab cycling in SettingsWindowController | M38 | Explorer 2 Survey |
| 114 | Capture Overlay Quick Copy Confirmation | In-place capture overlay showHUDNotification copiedToClipboard feedback pill | M38 | Explorer 2 Survey |
| 115 | Strict Zero-Emoji 9-Language Localization Completeness | framesCount, screenshotDeleted, copiedDiagnostics in LocalizationManager across 9 languages | M38 | Explorer 2 Survey |
| 116 | Canonical Version Bump to v1.0.18 | Synchronize v1.0.18 across Info.plist (build 18), AboutSettingsTab, WelcomeWindow, UpdateManager, Makefile, README.md, SettingsViewTests, PROJECT.md | M38 | Explorer 3 Survey |
| 117 | Settings Localization Parity (.rememberLabel, .updateAvailable) | Full 9-language translation for .rememberLabel and using .updateAvailable(tag) in Settings tabs | M42 | Explorer 2 Survey |
| 118 | Popover Differentiated Section Shortcuts | Option + 1..9 for Pinned items, 1..9 / Cmd + 1..9 for Recent items via ShortcutSection | M42 | Explorer 2 Survey |
| 119 | Popover Fast Navigation (Home, End, PageUp, PageDown, Cmd+Up, Cmd+Down) | Fast history list keyboard navigation in MainShotView localKeyMonitor | M42 | Explorer 2 Survey |
| 120 | Clear Unpinned History Shortcut & Toast (⌘⇧⌫) | Cmd+Shift+Delete shortcut and unpinnedHistoryCleared feedback toast in MainShotView | M42 | Explorer 2 Survey |
| 121 | Selection Handle Center-Out & 1:1 Aspect Resizing | Option key center-out and Option+Shift 1:1 aspect lock in SelectionBoxGeometry.calculateResizedRect | M42 | Explorer 1 Survey |
| 122 | Annotation Tool Alternate Mnemonic Tooltips | Display alternate mnemonics (3 / C, E and 9 / B, M) in FloatingToolbarsView shortcutDisplay | M42 | Explorer 1 & 2 Survey |
| 123 | Capture & Save Preferences Open in Finder Button | Add folder quick-action button next to Choose in CaptureSaveSettingsTab | M42 | Explorer 2 Survey |
| 124 | Welcome Window Escape Dismissal Parity | Subclass WelcomeWindow from NSWindow to handle Escape (53) and cancelOperation | M42 | Explorer 2 Survey |
| 125 | Dynamic Localized Status Item ToolTip | Update status item tooltip dynamically on language and hotkey changes in StatusItemManager | M42 | Explorer 2 Survey |
| 126 | Canonical Version Bump to v1.0.19 | Synchronize v1.0.19 across Info.plist (build 19), AboutSettingsTab, WelcomeWindow, UpdateManager, Makefile, README.md, SettingsViewTests, PROJECT.md | M42 | Explorer 3 Survey |
| 127 | Dynamic Shortcut Synchronization | Dynamic shortcut sync in StatusItemManager menuNeedsUpdate, MainShotView header tooltips, and GeneralSettingsTab typographic symbols | M46 | Cycle 13 Backlog |
| 128 | Quick Share / Export Action & Cmd+E in Popover | Popover row hover and context menu share action with NSSharingServicePicker and Cmd+E shortcut | M46 | Cycle 13 Backlog |
| 129 | Re-Annotate / Edit Past Screenshots | Open past screenshot in ScrollableAnnotationWindow vector editor from history row hover and context menu | M46 | Cycle 13 Backlog |
| 130 | WelcomeWindow & SettingsWindow Ergonomics | Transparent titlebar fix for WelcomeWindow and standard macOS Cmd+W window close across utility windows | M46 | Cycle 13 Backlog |
| 131 | In-Place Capture Copy HUD Feedback Delay | 180ms delay before overlay dismissal on copy so copiedToClipboard HUD pill is perceived | M46 | Cycle 13 Backlog |
| 132 | Popover Keyboard Shortcut Hint Footer Bar & Tooltip | Subtle footer hint bar using quickSelectHint and clearHistory tooltip with shortcut discovery | M46 | Cycle 13 Backlog |
| 133 | Native Eyedropper & Live Swatch Preview in Settings | 24x24 live preview swatch and NSColorSampler eyedropper in CaptureSaveSettingsTab | M46 | Cycle 13 Backlog |
| 134 | Localization Parity for Tall Canvas & Color Presets | 9-language localization parity for tall canvas window title, save dialog, and custom preset naming | M46 | Cycle 13 Backlog |
| 136 | Canonical Version Bump to v1.0.20 | Increment version to 1.0.20 (Build 20) across all 8 canonical project locations | M46 | Cycle 13 Backlog |
| 137 | Native Drag-and-Drop for History Rows | Support .onDrag with NSItemProvider fileURL and NSImage registration | M50 | Cycle 14 Backlog |
| 138 | Re-Annotate Keyboard Shortcut & Context Menu Parity | Cmd+Shift+A (⌘⇧A) in localKeyMonitor to open vector editor and (⌘⇧A) in context menu | M50 | Cycle 14 Backlog |
| 139 | Perceptible Keyboard Copy Confirmation Delay | 180ms delay before overlay dismissal on Return or Cmd+C so HUD pill is perceived | M50 | Cycle 14 Backlog |
| 140 | Vector Canvas Mutation HUD Pills | HUD pills on Undo (⌘Z), Redo (⌘⇧Z), and Duplicate (⌘D) in overlay and tall canvas | M50 | Cycle 14 Backlog |
| 141 | Adaptive Popover Footer Shortcut Hint | Dynamically adapt footer hint when pinned items exist (⌥1-9: Pinned · 1-9: Recent) with keyboard icon | M50 | Cycle 14 Backlog |
| 142 | Welcome Window Safe Area Bleed & Permission Deep Linking | .ignoresSafeArea() on WelcomeView and deep link to System Settings on permission grant | M50 | Cycle 14 Backlog |
| 143 | Hex Input Return-Key Preset Creation & Swatch Placeholder | .onSubmit preset creation and subtle paintpalette placeholder in swatch | M50 | Cycle 14 Backlog |
| 144 | VoiceOver Accessibility Role & Traits in Settings | .accessibilityRole(.tab) and .isSelected trait on SettingsTabButton | M50 | Cycle 14 Backlog |
| 145 | Localization Hygiene & Button Alignment | 9-language parity for presets and text tool, and flush-left Reset button alignment | M50 | Cycle 14 Backlog |
| 146 | Canonical Version Bump to v1.0.21 | Synchronize v1.0.21 (Build 21) across all canonical files, README, and test suites | M50 | Cycle 14 Backlog |
| 147 | UpdateManager DMG Support | Discover `.dmg` assets, mount via `hdiutil attach`, copy app bundle, unmount | M54 | Cycle 15 Backlog |
| 148 | Streaming Download Progress | `URLSessionDownloadDelegate` byte-level progress reporting from 0.0 to 1.0 | M54 | Cycle 15 Backlog |
| 149 | Dynamic Staging Destination | Resolve `Bundle.main.bundleURL` dynamically for non-admin user installs | M54 | Cycle 15 Backlog |
| 150 | Safe App Relaunch | Call terminationHandler inside `openApplication` completion callback with fallback timer | M54 | Cycle 15 Backlog |
| 151 | Clean Quarantine Removal | Strip `com.apple.quarantine` on staged bundle before relaunch via xattr | M54 | Cycle 15 Backlog |
| 152 | About Tab Status Text & Button Fix | Resolve duplicate label to `.updateReadyRestart` + `.restart` | M54 | Cycle 15 Backlog |
| 153 | About Tab Downloading Label & Checkmark | Add `.downloadingUpdate` context text and green checkmark icon to `.upToDate` state | M54 | Cycle 15 Backlog |
| 154 | Annotation Deletion HUD Pill | Add `.hudDelete` across all 9 languages with transient HUD pill on Delete/Backspace | M54 | Cycle 15 Backlog |
| 155 | Popover Context Menu SF Symbols | Native `Label(title, systemImage: icon)` with 0 emojis in `ShotRowView` | M54 | Cycle 15 Backlog |
| 156 | Keyboard Selection Cycling | `Tab` / `Shift+Tab` cycling across vector annotations via `AnnotationEngine.selectNextObject` | M54 | Cycle 15 Backlog |
| 157 | Popover Safe Download Fallback | Browser fallback when asset URL is nil in `MainShotView` | M54 | Cycle 15 Backlog |
| 158 | Canonical Version Bump to v1.0.22 | Increment version to 1.0.22 (Build 22) across all 8 canonical project locations | M54 | Cycle 15 Backlog |
| 159 | Update Download Cancellation & Abort Recovery | Retain activeDownloadTask, implement cancelDownload() in UpdateManager, add cancel button in About tab and MainShotView banner | M58 | Cycle 16 Backlog |
| 160 | Determinate Linear Progress Bar in About Tab | Replace indeterminate spinner with ProgressView(value:total:).progressViewStyle(.linear) alongside percentage | M58 | Cycle 16 Backlog |
| 161 | In-App Release Notes Viewer Sheet | Add in-app release notes viewer modal/sheet with formatted typography, fallback, and close action | M58 | Cycle 16 Backlog |
| 162 | Update Error Reporting with Inline Retry Action | Display warning icon, full error tooltip, and direct "Retry" button on check/download failures | M58 | Cycle 16 Backlog |
| 163 | Last Checked Timestamp Caption in About Tab | Display subtle "Last checked: ..." caption below Check for Updates button | M58 | Cycle 16 Backlog |
| 164 | Double-Click Selection to Quick-Copy & Dismiss | Double-clicking inside selectionRect (not hitting text object) triggers triggerCopy() with HUD pill and dismisses | M58 | Cycle 16 Backlog |
| 165 | Interactive Dimension Badge Click-to-Copy | Hit-test dimension badge frame on click; copy "W x H px" string to pasteboard with "Copied Dimensions" HUD pill | M58 | Cycle 16 Backlog |
| 166 | Positional Index & Total Count in Object Cycling HUD | Format Tab / Shift+Tab HUD as "\(tool) \(index + 1)/\(total) (\(key))" in both in-place overlay & scrollable canvas | M58 | Cycle 16 Backlog |
| 167 | History Context Menu: Copy File Path & Copy Dimensions | Add Copy File Path and Copy Dimensions to ShotRowView.contextMenu | M58 | Cycle 16 Backlog |
| 168 | Keyboard Nudge & Resize HUD Pill Feedback | Show transient HUD indicator on arrow key nudging ("Nudge (1pt)" / "Nudge (10pt)") and Option+Arrow object resizing ("W x H px") | M58 | Cycle 16 Backlog |
| 169 | Search Filter Empty State Quick Reset Button | Add prominent "Clear Search" button with xmark.circle icon in emptySearchView for 1-click query clearing | M58 | Cycle 16 Backlog |
| 170 | LiveGUIDriverV1023 On-Screen GUI Driver Updates | Update Live GUI Driver to V1023, run on-screen audit, capture 47+ Retina snapshots into scratch/v1023_audit_screenshots/ | M59 | Cycle 16 Backlog |
| 171 | Canonical Version Bump to v1.0.23 | Synchronize version 1.0.23 (Build 23) across all 8 canonical locations & downstream test assertions | M60 | Cycle 16 Backlog |
| 172 | Automated Release Pipeline (PR #23, Merge, Universal 2, GitHub Release, Public Repo, App Relaunch) | Git feature branch, PR #23 creation, squash/merge to main, Universal 2 zip/dmg build, GitHub Release v1.0.23, public repo verification, and live app relaunch | M60 | Cycle 16 Backlog |
| 173 | Quick Copy Action Pill on Dimension Badge | Clickable "Copy" pill adjacent to dimension badge with pointingHand cursor, hover highlight, and 1-click clipboard copy | M61 | Cycle 17 Backlog |
| 174 | Spacebar Repositioning (Space + Drag) | Holding Space during selection creation pans the active origin while preserving width/height | M61 | Cycle 17 Backlog |
| 175 | Font Size Stepping Shortcuts ([ / ]) & HUD Pill | Dedicated bracket shortcuts for text annotations stepping font size 10pt-72pt with transient HUD indicator | M61 | Cycle 17 Backlog |
| 176 | Fit to Window Button in Scrollable Canvas | Replace redundant zoom button with "Fit to Window" action (rectangle.inset.filled) calculating optimal document scale | M61 | Cycle 17 Backlog |
| 177 | Hover Highlight on Dimension Badge & Quick Copy Pill | Visual hover affordance and pointer feedback for dimension badge and quick copy pill | M61 | Cycle 17 Backlog |
| 178 | Direct Keyboard Shortcuts: Copy File Path & Dimensions | Dedicated Cmd+Shift+C (path) and Cmd+Option+C (dimensions) shortcuts with contextual toast feedback in MainShotView | M61 | Cycle 17 Backlog |
| 179 | Double-Click Quick Copy Parity on Stitched Canvas | Double-clicking empty canvas in ScrollableAnnotationWindow triggers instant copy to clipboard and window dismissal | M61 | Cycle 17 Backlog |
| 180 | Zero-Emoji Multilingual Localization (9 Languages) | Complete zero-emoji localized strings for quick copy, font size HUD, fit window tooltip, and copy notifications | M61 | Cycle 17 Backlog |
| 181 | Live On-Screen GUI Driver Updates (v1.0.24) | Update Live GUIDriver to V1024, execute 5 interactive surfaces, and verify Retina snapshots | M62 | Cycle 17 Backlog |
| 182 | Automated Release Pipeline (PR #24, Universal 2, GitHub Release v1.0.24) | Feature branch, PR #24, squash/merge, Universal 2 zip/dmg, GitHub Release v1.0.24, public verification, and app relaunch | M64 | Cycle 17 Backlog |
| 183 | Pixel-Exact Crop & Alignment in ImageRenderer | Resolve latent vertical rendering shift when cropRect != nil, ensuring exact alignment between background imagery and annotations | M65 | Cycle 18 Backlog |
| 184 | Multi-Display Coordinate Translation | Enhanced coordinate translation in ScrollingCoordinateMapper across non-standard, stacked, and negative-origin monitors | M65 | Cycle 18 Backlog |
| 185 | Typography Baseline & Layout Parity | CoreText line drawing parity across SelectionBoxView, ScrollableCanvasView, and ImageRenderer with dynamic bounds expansion | M65 | Cycle 18 Backlog |
| 186 | Blur Region Clamping & Anti-Bleed Guarantees | Strict CIImage extent clamping preventing transparent edge bleed and border sample artifacts during mosaic pixelation | M65 | Cycle 18 Backlog |
| 187 | Inverted Handle Resizing with Point Mirroring | Drag-across-anchor reflection for pen and highlighter strokes preserving vector geometry without squishing | M65 | Cycle 18 Backlog |
| 188 | Concurrency & Timer Lifecycle Hardening | Weak self capture and timer invalidation in UpdateManager deinit, rapid task cancellation in MainShotView | M65 | Cycle 18 Backlog |
| 189 | Pixel-Accurate Synthetic Image Regression Test Suite | Comprehensive synthetic image generator (4-quadrant, banded, checkerboard) verifying 0-pixel shift in Cycle18Tests.swift | M66 | Cycle 18 Backlog |
| 190 | Live On-Screen GUI Driver Updates (v1.0.25) | Implement and run LiveGUIDriverV1025.swift, verifying all interactive surfaces on screen | M67 | Cycle 18 Backlog |
| 191 | Canonical Version Bump & Automated Release Pipeline | Synchronize 8 canonical files to 1.0.25 / Build 25, update downstream tests, PR #25, Universal 2 build, and GitHub release v1.0.25 | M67/M68 | Cycle 18 Backlog |
| 192 | Latent Bug Fixes across Stitching, Canvas & Annotations | Low-entropy flat-MAD guard, sticky dedup resilience, frame tolerance, overlay Esc/Space tiering, edge crop clamping, handle minBy selection, metadata backup | M69 | Cycle 19 Backlog |
| 193 | Cycle 19 Regression Test Suite & Canonical Version Bump | Comprehensive Cycle19Tests.swift with non-uniform synthetic images, version bump to 1.0.26 / Build 26 across 8 files | M69/M70 | Cycle 19 Backlog |
| 194 | Cycle 20 Latent Bug Fixes & Concurrency Hardening | Short-vector arrow scaling, Escape text cancel, multi-display boundary clamping, StorageManager/ThumbnailImageCache lock-free notification, DMG force-detach, Cycle20Tests.swift, version bump to 1.0.27 / Build 27 | M71/M72 | Cycle 20 Backlog |

## Milestones

| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Core Foundation & Build System | Package.swift, Makefile (Universal 2, lint, test, app, verify, package), Scripts, SuperShotCore models (ColorPreset, ShotItem, AppSettings, StorageManager, LocalizationManager, HotKeyManager), TestHarness | none | DONE |
| M2 | In-Place Capture & Vector Overlay | ScreenCaptureManager (2x Retina freeze), Overlay Window & 8-handle selection box, 8 vector tools, ColorPreset picker/eyedropper/palette, Undo/Redo, floating toolbars, ImageRenderer | M1 | DONE |
| M3 | Scrolling Capture & Stitching | ScrollingCaptureManager (auto/manual scroll CGEvent wheel), ImageStitcher (scrollbar exclusion, sticky header/footer dedup, overlap matching, auto-stop), ScrollableAnnotationCanvas | M1, M2 | DONE |
| M4 | Popover History, Settings & App Target | SuperShot app target (main, AppDelegate), StatusItemManager, MainShotView (pinned, recent, search, hover zoom, 1..9), AutoPasteService, 4-tab SettingsView, README.md update | M1, M2, M3 | DONE |
| M5 | Final E2E Pass & Hardening | Wait for TEST_READY.md, pass 100% of E2E test tiers 1-4, Phase 2 adversarial hardening (Tier 5), verify-app, verify-bundle, and make package | M1, M2, M3, M4, E2E Track | DONE |
| M6 | Live On-Screen GUI & Interactive UX Testing | Execute LiveGUIDriver, verify 5 interactive surfaces (Features 61-66), validate snapshots | M1-M5 | DONE |
| M7 | Proactive UX & Feature Polish | Implement UX refinements in Sources/SuperShot and SuperShotCore (0 emojis), PR #3 | M6 | DONE |
| M7.1 | Real UpdateManager Integration | Implement UpdateManager, SemanticVersion, wire into AboutSettingsTab & AppDelegate, unit tests, enforce PUBLIC repo visibility | M7 | DONE |
| M8 | Automated Release Pipeline | Merge PR #3 to main, package Universal 2, publish public GH release v1.0.3 | M7.1 | DONE |
| M10 | In-App Update Banner & Frequency Polish | UpdateManager async wrappers, MainShotView update banner with gear badge, update check frequency picker in GeneralSettingsTab, ergonomics polish (popover dynamic edge, scrollable canvas, pointingHandCursor), comprehensive unit tests (0 emojis) | M8, M7.1 | DONE |
| M11 | Automated Release Pipeline v1.0.4 | Version bump to v1.0.4, branch, PR, merge, clean build/verify, GitHub release v1.0.4, verify PUBLIC | M10 | DONE |
| M12 | Live GUI Testing & UX Audit | Run LiveGUIDriver across 5 surfaces, capture snapshots, evaluate interactive UX & ergonomics | none | DONE |
| M13 | Proactive UX & Feature Polish | Implement Cmd+D duplication, Shift-constrained shapes/lines, zoom HUD controls, ergonomics, tests | M12 | DONE |
| M14 | Automated Release Pipeline v1.0.5 | Bump to v1.0.5, PR, merge, clean Universal 2 build, package, GitHub release, public repo verification | M13 | DONE |
| M15 | Synchronized Hover Preview (v1.0.6) | ThumbnailHoverPreviewViewModel, synchronous resolution, forItemId guard, PR #6 | M14 | DONE |
| M16 | Region-First Manual Scrolling (v1.0.7) | Region-first selection box, manual scroll capture, global Esc/Enter hotkeys, PR #7 | M15 | DONE |
| M17 | Live GUI Audit & Snapshot Verification | Full GUI driver verification across 5 surfaces | M16 | DONE |
| M18 | Explorer UX & Pipeline Audit | Detailed UX proposals (M18.2) and Makefile dmg recipe & health (M18.3) | M17 | DONE |
| M19 | Proactive UX & Feature Polish | Instant copy feedback, Settings 565pt & Cmd+1..4, mnemonic shortcuts, row button hover, make dmg | M18 | DONE |
| M21 | Explorer UX & Release Readiness Audit | Live on-screen audit, 5 concrete UX/feature proposals, pipeline readiness (v1.0.9) | M19 | DONE |
| M22 | UX Polish, 4-Tier Escape, Welcome Window & v1.0.9 | Search/empty state polish, 4-tier escape & tool HUD, zoom centering, WelcomeWindow, L10n hygiene, v1.0.9 bump | M21 | DONE |
| M24 | Survey, Live GUI Audit & Pipeline Audit (v1.0.10) | Live GUI Driver execution, snapshot analysis, UX polish identification, release readiness | M22 | DONE |
| M25 | UX Polish, Sizing Helper, Bracket Shortcuts & v1.0.10 Bump | Implement 6 proactive UX refinements, 9-language l10n, bump 6+1 version files to 1.0.10, tests | M24 | DONE |
| M26 | Automated Release Pipeline v1.0.10 & Live App Relaunch | Git branch, PR create/merge, clean build, Universal 2 zip & dmg release, app relaunch | M25 | DONE |
| M28 | Proactive UX Polish, Hit-Target Refinement & Version Bump to v1.0.15 | Settings tab truncation fix, explicit contentShape across buttons/pills, Cmd+A / Arrow nudge / '/' shortcuts, version bump to v1.0.15 | M26 | DONE |
| M29 | Survey & Live GUI Driver Audit | Explorers 1, 2, 3 survey codebase, live GUI driver, build/test, version locations | none | DONE |
| M30 | Implementation of UX Polish & Version Bump | Implement Features 93-99 in Sources/SuperShot, Sources/SuperShotCore, Tests/, Makefile, README.md, PROJECT.md | M29 | DONE |
| M31 | Review, Adversarial Challenge & Forensic Audit | Independent review (x2), adversarial stress tests (x2), and forensic audit | M30 | DONE |
| M32 | Live GUI Verification & Release Pipeline | Run LiveGUIDriver, execute make package/dmg, git branch/PR/merge, publish GitHub release v1.0.16, verify PUBLIC | M31 | DONE |
| M33 | Survey & Live GUI Driver Audit | Run LiveGUIDriver, inspect on-screen GUI snapshots, investigate UX/feature opportunities, verify release invariants | none | DONE |
| M34 | Implementation of Proactive UX Polish & Version Bump | Implement Features 100-107, 0 emojis, bump 8 locations to 1.0.17, make lint, make test, make adversarial, make app, verify_bundle | M33 | DONE |
| M35 | Multi-Angle Review, Adversarial Challenge & Forensic Audit | 2 Reviewers, 2 Challengers, 1 Forensic Auditor (binary veto) | M34 | DONE |
| M36 | Live GUI Verification, Automated Release Pipeline & App Relaunch | Git branch -> PR -> merge -> Universal 2 build -> GitHub release v1.0.17 -> public repo check -> app relaunch | M35 | DONE |
| M37 | Survey & Live GUI Driver Audit | Run LiveGUIDriver, inspect on-screen GUI snapshots, investigate UX/feature opportunities, verify release invariants (v1.0.18) | none | DONE |
| M38 | Implementation of Proactive UX Polish & Version Bump | Implement Features 108-116, 0 emojis, bump 8 locations to 1.0.18, make lint, make test, make adversarial, make app, verify_bundle | M37 | DONE |
| M39 | Multi-Angle Review, Adversarial Challenge & Forensic Audit | 2 Reviewers, 2 Challengers, 1 Forensic Auditor (binary veto) | M38 | DONE |
| M40 | Live GUI Verification, Automated Release Pipeline & App Relaunch | Git branch -> PR -> merge -> Universal 2 build -> GitHub release v1.0.18 -> public repo check -> app relaunch | M39 | DONE |
| M41 | Survey & Live GUI Driver Audit | Run LiveGUIDriver, inspect on-screen GUI snapshots, investigate UX/feature opportunities, verify release invariants (v1.0.19) | none | DONE |
| M42 | Implementation of Proactive UX Polish & Version Bump | Implement Features 117-126, 0 emojis, bump 8 locations to 1.0.19, make lint, make test, make adversarial, make app, verify_bundle | M41 | DONE |
| M43 | Multi-Angle Review, Adversarial Challenge & Forensic Audit | 2 Reviewers, 2 Challengers, 1 Forensic Auditor (binary veto) | M42 | DONE |
| M44 | Live GUI Verification, Automated Release Pipeline & App Relaunch | Git branch -> PR -> merge -> Universal 2 build -> GitHub release v1.0.19 -> public repo check -> app relaunch | M43 | DONE |
| M45 | Survey & Live GUI Driver Audit | Run LiveGUIDriver, inspect on-screen GUI snapshots, investigate UX/feature opportunities, verify release invariants (v1.0.20) | none | DONE |
| M46 | Implementation of Proactive UX Polish & Version Bump | Implement Features 127-136, 0 emojis, bump 8 locations to 1.0.20, make lint, make test, make adversarial, make app, verify_bundle | M45 | DONE |
| M47 | Multi-Angle Review, Adversarial Challenge & Forensic Audit | 2 Reviewers, 2 Challengers, 1 Forensic Auditor (binary veto) | M46 | DONE |
| M48 | Live GUI Verification, Automated Release Pipeline & App Relaunch | Git branch -> PR -> merge -> Universal 2 build -> GitHub release v1.0.20 -> public repo check -> app relaunch | M47 | DONE |
| M49 | Survey & Live GUI Driver Audit | Run LiveGUIDriver, inspect on-screen GUI snapshots, investigate UX/feature opportunities, verify release invariants (v1.0.21) | none | DONE |
| M50 | Implementation of Proactive UX Polish & Version Bump | Implement Features 137-146, 0 emojis, bump 8 locations to 1.0.21, make lint, make test, make adversarial, make app, verify_bundle | M49 | DONE |
| M51 | Multi-Angle Review, Adversarial Challenge & Forensic Audit | 2 Reviewers, 2 Challengers, 1 Forensic Auditor (binary veto) | M50 | DONE |
| M52 | Live GUI Verification, Automated Release Pipeline & App Relaunch | Git branch -> PR -> merge -> Universal 2 build -> GitHub release v1.0.21 -> public repo check -> app relaunch | M51 | DONE |
| M53 | Survey & Live GUI Driver Audit (v1.0.22) | Run LiveGUIDriver, inspect on-screen GUI snapshots, investigate UpdateManager and UX opportunities (v1.0.22) | none | DONE |
| M54 | UpdateManager & UX Implementation | Implement Features 147-158, 0 emojis, bump 8 locations to 1.0.22, make lint, make test, make adversarial | M53 | DONE |
| M55 | Live GUI & Automated Verification | Execute LiveGUIDriverV1022 with 47 snapshots, pass all test suites | M54 | DONE |
| M56 | Automated Release Pipeline v1.0.22 & Live App Relaunch | Git branch -> PR #22 -> merge -> Universal 2 build -> GitHub release v1.0.22 -> public repo check -> app relaunch | M55 | DONE |
| M57 | Survey & Live GUI Driver Audit (v1.0.23) | Explorers 1, 2, 3 survey codebase, Live GUI driver, git/release baseline | none | DONE |
| M58 | Proactive UX & Feature Polish | Implement F1–F11, 0 emojis, add Cycle16Tests.swift, unit test pass | M57 | DONE |
| M60 | Canonical Version Bump, PR #23, Release & App Relaunch | Synchronize 8 canonical files to 1.0.23 / Build 23, update downstream tests, create PR #23, merge into main, Universal 2 release, public repo check, relaunch SuperShot.app | M59 | DONE |
| M61 | UX & Feature Polish Implementation | Implement Features 173–180, 0 emojis, add Cycle17Tests.swift, unit test pass | M60 | DONE |
| M62 | Live On-Screen GUI Execution & Verification | Implement & run LiveGUIDriverV1024.swift, verify 56+ Retina snapshots, run make lint, make test, make adversarial | M61 | DONE |
| M63 | Multi-Angle Review, Adversarial Challenge & Forensic Audit | 2 Reviewers, 2 Challengers, 1 Forensic Auditor (binary veto) | M62 | DONE |
| M64 | Canonical Version Bump, PR #24, Release & App Relaunch | Synchronize 8 canonical files to 1.0.24 / Build 24, update downstream tests, create PR #24, merge into main, Universal 2 release, public repo check, relaunch SuperShot.app | M63 | DONE |
| M65 | Latent Bug Hunt & Coordinate Alignment Fixes | Fix ImageRenderer crop vertical shift, multi-display mapper, typography parity, blur clamping, and inverted handle resizing | M64 | DONE |
| M66 | Pixel-Accurate Regression Test Suite | Implement Cycle18Tests.swift with synthetic image tests (4-quadrant, banded, checkerboard) and lifecycle checks | M65 | DONE |
| M67 | Canonical Version Bump & Live GUI Verification | Synchronize 8 canonical files to 1.0.25 / Build 25, run LiveGUIDriverV1025, verify 0 emojis, make lint, make test | M66 | DONE |
| M68 | Multi-Angle Review, PR #25 & Release Pipeline | Independent review, adversarial challenge, PR #25 merge, Universal 2 package, GitHub release v1.0.25, live app relaunch | M67 | DONE |
| M69 | Latent Bug Fixes & Cycle 19 Regression Tests | Low-entropy flat-MAD guard, sticky dedup resilience, frame tolerance, overlay Esc/Space tiering, edge crop clamping, handle minBy selection, metadata backup, add Cycle19Tests.swift | M68 | DONE |
| M70 | Canonical Version Bump to 1.0.26 / Build 26 | Synchronize 8 canonical files to 1.0.26 / Build 26, update downstream tests, 0 emojis, make lint, make test | M69 | DONE |
| M71 | Cycle 20 Latent Bug Fixes & Regression Suite | Implement multi-display clamping, short-vector arrow geometry, lock-free storage notifications, DMG cleanup, and Cycle20Tests.swift | M70 | DONE |
| M72 | Canonical Version Bump to 1.0.27 / Build 27 & Release | Synchronize 8 canonical files to 1.0.27 / Build 27, update downstream tests, PR #27, Universal 2 release v1.0.27 | M71 | DONE |
| M73 | Fix UpdateDownloadDelegate 100% Completion & Release v1.0.28 | Retain completion callbacks across URLSession invalidation, auto-restart on user-initiated update install, PR #28, Universal 2 release v1.0.28 | M72 | DONE |

## Interface Contracts

### SuperShotCore ↔ App UI
- `ColorPreset`: Struct conforming to `Codable`, `Equatable`, `Identifiable`.
  - Initializers: `init(id: UUID = UUID(), name: String, hex: String)`
  - Methods: `toNSColor() -> NSColor`, `toColor() -> SwiftUI.Color`, `static let defaults: [ColorPreset]` (8 high-contrast colors).
- `AppSettings`: Observable class persisting user options via JSON.
  - Properties: `activeColorHex: String`, `activeStrokeWidth: CGFloat`, `activeFontSize: CGFloat`, `presets: [ColorPreset]`, `autoSaveEnabled: Bool`, `autoSaveDirectory: URL`, `saveFormat: ImageFormat`, `maxScrollHeightPx: Int`.
- `StorageManager`: Actor / Thread-safe class conforming to `StorageManaging`.
  - Methods: `save(image: CGImage, metadata: ShotItem) async throws -> URL`, `load(id: UUID) async -> CGImage?`, `delete(id: UUID) async throws`, `togglePin(id: UUID) async throws`, `search(query: String) -> [ShotItem]`.
- `AnnotationEngine`: State controller for vector drawing.
  - Properties: `activeTool: AnnotationTool`, `objects: [AnnotationObject]`, `canUndo: Bool`, `canRedo: Bool`.
  - Methods: `addObject(_ object: AnnotationObject)`, `selectObject(at point: CGPoint) -> AnnotationObject?`, `updateSelectedObject(_ transform: (inout AnnotationObject) -> Void)`, `undo()`, `redo()`.
- `ImageStitcher`: Pure engine for image analysis and vertical stitching.
  - Struct: `StitchOptions(scrollbarStripWidth: CGFloat = 24, headerDedupHeight: CGFloat = 80, footerDedupHeight: CGFloat = 80, maxScrollHeightPx: CGFloat = 15000)`.
  - Methods: `stitch(frames: [CGImage], options: StitchOptions) throws -> StitchResult(image: CGImage, totalHeight: CGFloat, frameOffsets: [CGFloat])`.
- `AutoPasteService`: Accessibility and pasteboard injector.
  - Properties: `isAccessibilityTrusted: Bool`.
  - Methods: `pasteImageDirectly(_ image: CGImage) async throws`.

### E2E Test Suite ↔ Product
- `make lint`: Scans entire repository with `Scripts/lint_emojis.py`, returns exit code 0.
- `make test`: Compiles and runs all test suites via headless runner, returns exit code 0.
- `make app`: Produces `SuperShot.app` in workspace root with Universal 2 binaries.
- `make verify-app`: Runs 8-step bundle integrity, lipo Universal 2 check, static otool x86_64 linkage check, and headless launch under native arm64, returns exit code 0.
- `make package`: Produces `SuperShot-v1.0.0.zip` cleanly.
