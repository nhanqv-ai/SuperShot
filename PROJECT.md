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
- `make verify-app`: Runs 8-step bundle integrity and headless launch under native arm64 and Rosetta 2 x86_64, returns exit code 0.
- `make package`: Produces `SuperShot-v1.0.0.zip` cleanly.
