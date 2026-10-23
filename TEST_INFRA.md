# SuperShot Test Infrastructure & 4-Tier E2E Testing Specification

## 1. Overview & Test Infrastructure Architecture

This document establishes the comprehensive end-to-end (E2E) testing architecture, methodology, and verification specification for **SuperShot** (`com.supershot.SuperShot`), the production-ready native macOS menu bar screenshot, scrolling capture, and in-place vector annotation application. The testing infrastructure is designed to validate all 60 system features across functional, boundary, combinatorial, and real-world workload dimensions while maintaining complete isolation from the host environment.

### 1.1 Core Testing Principles
1. **Opaque-Box Requirement-Driven Derivation**: Every test case directly derives its expected input/output behavior from `ORIGINAL_REQUEST.md` and `PROJECT.md` contracts rather than internal implementation details.
2. **Deterministic Sandboxing Isolation**: Tests execute in ephemeral sandbox directories created under `NSTemporaryDirectory()`. No test shall read, write, modify, or pollute the real host directory `~/Library/Application Support/SuperShot/`.
3. **Strict Zero-Emoji Enforcement**: Absolute zero-tolerance invariant on emoji characters across all source code, test code, assertion messages, test fixtures, comments, logs, and console outputs. Validated via static code analysis.
4. **Toolchain Resilience & Standard SDK**: All test executions target standard Command Line Tools SDKs (`MacOSX15.4.sdk` with automatic fallback to `MacOSX.sdk` or `xcrun --show-sdk-path`) to guarantee flawless compilation without Xcode IDE dependencies.
5. **Headless Execution Capability**: The test suite executes in headless CLI environments, programmatically exercising AppKit, CoreGraphics, ImageIO, and Carbon constructs without requiring interactive user mouse clicks or window display server attachment.
6. **Zero External Package Dependencies**: Pure Swift implementation leveraging native Apple frameworks (`AppKit`, `CoreGraphics`, `ImageIO`, `Carbon`, `UniformTypeIdentifiers`, `ServiceManagement`, `Combine`, `SwiftUI`) without external third-party package dependencies.

---

## 2. Sandboxing & Test Runner Architecture

### 2.1 Ephemeral Sandbox Lifecycle
For every test execution run:
- A unique sandbox directory `SuperShot_Sandbox_<UUID>` is provisioned in `NSTemporaryDirectory()`.
- Isolated subdirectories and stores are provisioned:
  - `metadata.json`: Serialized `ShotItem` records and history store.
  - `settings.json`: User preferences, active color, stroke width, and custom color presets.
  - `shots/`: Stored full-resolution screenshot image assets (`<UUID>.png` or `<UUID>.jpg`).
  - `thumbnails/`: Stored downscaled thumbnail preview images (`<UUID>_thumb.png`).
- On suite completion, all sandbox artifacts are atomically purged, leaving zero disk residues.

### 2.2 Dual-Execution Strategy
1. **Automated Verification Runner (`Tests/VerificationRunner/main.swift`)**:
   - Compiles into a standalone native binary `SuperShotVerifier`.
   - Links against `libSuperShotCore.dylib` and directly executes programmatic assertions across all core subsystems: `ColorPreset`, `AppSettings`, `StorageManager`, `AnnotationEngine`, `ImageRenderer`, `ImageStitcher`, `HotKeyManager`, and `LocalizationManager`.
   - Emits structured ANSI reports detailing individual suite pass/fail counts, execution timing, and zero-emoji compliance.
2. **Build and Verification Shell Harness (`Scripts/verify.sh` & `Makefile`)**:
   - Validates the environment SDKROOT.
   - Runs `Scripts/lint_emojis.py` static scanner across the entire repository.
   - Ensures `libSuperShotCore.dylib` and modules are compiled.
   - Compiles and executes the test suites with exit code 0 indicating 100% pass rate.

---

## 3. Tier 1: Feature Coverage (>=5 Test Cases per Feature for all 60 Features)

Total Tier 1 Test Cases: **300 test cases** (60 features x 5 test cases).

### Feature 1: Universal 2 Makefile
- **T1-F01-01 (SDK Probing)**: Probes `/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk` and successfully falls back to system SDK when specific version is absent.
- **T1-F01-02 (Dual Architecture Compilation)**: Compiles separate `arm64` and `x86_64` Mach-O slices for both `SuperShot` and `libSuperShotCore.dylib`.
- **T1-F01-03 (Lipo Universal 2 Assembly)**: Merges distinct architecture slices using `lipo -create` and validates `arm64 x86_64` via `lipo -archs`.
- **T1-F01-04 (Inside-Out Codesigning)**: Signs embedded dynamic library first, followed by main executable with designated requirement, and finally the bundle.
- **T1-F01-05 (All Makefile Targets)**: Makefile exposes functioning targets: `build`, `release`, `icon`, `app`, `bundle`, `package`, `verify-app`, `lint`, `test`, `adversarial`, `clean`.

### Feature 2: Package.swift Manifest
- **T1-F02-01 (Swift Tools Version)**: Manifest specifies `// swift-tools-version: 5.9`.
- **T1-F02-02 (Platform Target)**: Platform target declares macOS 13.0 minimum (`.macOS(.v13)`).
- **T1-F02-03 (Zero Dependencies Array)**: Package dependencies array `dependencies: []` is strictly empty.
- **T1-F02-04 (Library Product Export)**: Exports library product `SuperShotCore` targeting `Sources/SuperShotCore`.
- **T1-F02-05 (Executable Target Binding)**: Executable target `SuperShot` depends directly on `SuperShotCore`.

### Feature 3: Zero-Emoji Linter
- **T1-F03-01 (Clean Repo Pass)**: Scans valid repository without emojis and exits cleanly with code 0.
- **T1-F03-02 (Swift File Emoji Detection)**: Synthetic file containing U+1F4F8 (camera) triggers exit code 1 with line number.
- **T1-F03-03 (Makefile Comment Emoji Detection)**: Emoji in Makefile comment triggers linter failure.
- **T1-F03-04 (Markdown Emoji Detection)**: Emoji in README.md triggers linter failure.
- **T1-F03-05 (Multi-Directory Traversal)**: Traverses `Sources/`, `Tests/`, `Scripts/`, and root configuration files recursively.

### Feature 4: TestHarness Framework
- **T1-F04-01 (Pass Assertion Tracking)**: Calling `assertTrue(true)` increments `passedTests` and `totalTests`.
- **T1-F04-02 (Fail Assertion Tracking)**: Calling `assertTrue(false)` increments `failedTests` and records failure reason.
- **T1-F04-03 (Equal Assertion Equatable)**: `assertEqual` compares primitive values, strings, and custom Equatable structs.
- **T1-F04-04 (Sandbox Lifecycle)**: `createSandbox()` creates directory in `NSTemporaryDirectory()`; `cleanupSandbox()` deletes it completely.
- **T1-F04-05 (ANSI Reporting Zero Emojis)**: Summary banner emits standard ANSI escapes without any emoji unicode characters.

### Feature 5: ColorPreset Data Model
- **T1-F05-01 (Default 8 High-Contrast Presets)**: `ColorPreset.defaults` contains exactly 8 presets: Red, Orange, Yellow, Green, Blue, Indigo, Purple, Black.
- **T1-F05-02 (Hex Parsing #RRGGBB)**: Instantiating with `"#FF3B30"` yields correct red (1.0), green (0.231), blue (0.188) components.
- **T1-F05-03 (Hex Parsing Case Insensitivity)**: Parses both lowercase `"#007aff"` and uppercase `"#007AFF"` to identical RGB values.
- **T1-F05-04 (NSColor and SwiftUI Color Conversion)**: `toNSColor()` and `toColor()` produce valid color representations.
- **T1-F05-05 (Codable Serialization)**: Encodes to and decodes from JSON without data loss.

### Feature 6: ColorPreset Persistence
- **T1-F06-01 (Add Custom Preset)**: Adding a custom preset increases total presets list.
- **T1-F06-02 (Maximum 16 Favorite Presets Constraint)**: Attempting to add a 17th preset is rejected or ignored.
- **T1-F06-03 (Delete Custom Preset)**: Deleting a preset by ID removes it from store.
- **T1-F06-04 (Reset to Defaults)**: Invoking reset restores exactly the 8 standard default presets.
- **T1-F06-05 (Disk Persistence Across Sessions)**: Saved presets reload identically upon re-instantiating `AppSettings`.

### Feature 7: AppSettings Store
- **T1-F07-01 (Default Active Values)**: Initial settings default `activeStrokeWidth = 3.0` and `activeFontSize = 18.0`.
- **T1-F07-02 (Active Color Persistence)**: Changing `activeColorHex` updates property and persists to `settings.json`.
- **T1-F07-03 (Auto-Save Configuration)**: Toggling `autoSaveEnabled` and setting `autoSaveDirectory` persists to disk.
- **T1-F07-04 (Save Format Selection)**: Supports `.png` and `.jpeg` image formats and persists choice.
- **T1-F07-05 (Max Scroll Height Persistence)**: Configurable `maxScrollHeightPx` clamps within 5,000 to 30,000 px and persists.

### Feature 8: ShotItem Data Model
- **T1-F08-01 (Model Properties)**: Stores `id`, `timestamp`, `filePath`, `thumbnailPath`, `width`, `height`, `isPinned`, and `sourceApp`.
- **T1-F08-02 (Dimension Extraction)**: Accurately reflects captured pixel width and height.
- **T1-F08-03 (JSON Serialization)**: Conforms to `Codable` and serializes deterministically to `metadata.json`.
- **T1-F08-04 (Pin Flag State)**: `isPinned` initializes to `false` and reflects toggle state.
- **T1-F08-05 (Display Title Formatting)**: Formats timestamp or dimension metadata into readable title string without emojis.

### Feature 9: Thread-Safe StorageManager
- **T1-F09-01 (NSRecursiveLock Protection)**: Read and write access to internal arrays is protected by lock.
- **T1-F09-02 (Dedicated Serial File Queue)**: Disk operations execute on serial background dispatch queue (`com.supershot.storage.fileio`).
- **T1-F09-03 (Add Shot Record)**: Adding a shot updates in-memory array and schedules disk persistence.
- **T1-F09-04 (Delete Shot Record)**: Deleting by ID removes metadata and deletes image and thumbnail files from disk.
- **T1-F09-05 (Isolated Sandbox Path Initialization)**: Custom `baseDirectory` initializes storage safely inside temporary directory.

### Feature 10: In-Memory NSCache
- **T1-F10-01 (Cache Insertion)**: Saving or loading an image caches decoded `CGImage` / `NSData` in `NSCache`.
- **T1-F10-02 (Cache Hit Fast Retrieval)**: Subsequent retrieval of existing shot returns image directly from cache without disk I/O.
- **T1-F10-03 (Cache Eviction Tolerance)**: Purging cache forces transparent reload from disk asset.
- **T1-F10-04 (Thumbnail Memory Cache)**: Downscaled thumbnails cached separately for instant history rendering.
- **T1-F10-05 (Thread-Safe Cache Access)**: Concurrent cache reads from multiple threads execute without race conditions.

### Feature 11: Pinned Item Protection
- **T1-F11-01 (Capacity Trim Immunity)**: When total items exceed capacity, pinned items are never evicted.
- **T1-F11-02 (Clear Unpinned History Preservation)**: Calling `clearUnpinnedHistory()` preserves 100% of pinned items.
- **T1-F11-03 (Toggle Pin State)**: Calling `togglePin(id:)` flips `isPinned` and persists new state.
- **T1-F11-04 (Pinned Asset Retention on Disk)**: Original image and thumbnail files of pinned items remain on disk during maintenance pruning.
- **T1-F11-05 (All-Pinned Storage Overflow)**: If capacity is 20 and all 20 are pinned, adding a 21st item retains all 20 pinned items.

### Feature 12: LocalizationManager
- **T1-F12-01 (9 Supported Languages)**: Supports English (en), Vietnamese (vi), German (de), French (fr), Spanish (es), Japanese (ja), Simplified Chinese (zh-Hans), Traditional Chinese (zh-Hant), Korean (ko).
- **T1-F12-02 (Dynamic Language Switching)**: Changing active language immediately updates localized string lookups.
- **T1-F12-03 (Vietnamese Translations)**: Validates complete Vietnamese dictionary for overlay buttons, tools, history, settings.
- **T1-F12-04 (English Fallback)**: Missing key falls back gracefully to English string.
- **T1-F12-05 (Zero Emojis in Translations)**: All 9 language dictionaries contain zero emoji characters.

### Feature 13: HotKeyManager
- **T1-F13-01 (Carbon Event Handler Setup)**: Installs Carbon event handler for `kEventClassKeyboard` / `kEventHotKeyPressed`.
- **T1-F13-02 (Option+S In-Place Shortcut)**: Registers default `Option + S` shortcut (`kVK_ANSI_S`, `optionKey`).
- **T1-F13-03 (Option+Shift+S Scrolling Shortcut)**: Registers default `Option + Shift + S` shortcut (`kVK_ANSI_S`, `optionKey | shiftKey`).
- **T1-F13-04 (Dynamic Re-Registration)**: Unregisters previous hotkey and registers new hotkey dynamically.
- **T1-F13-05 (Zero Accessibility Dependency)**: Global Carbon hotkeys fire without requiring macOS Accessibility permissions.

### Feature 14: AppIcon Asset Generator
- **T1-F14-01 (Script Execution)**: `swift Scripts/generate_icon.swift` compiles and runs cleanly.
- **T1-F14-02 (10 Standard Resolutions)**: Generates 16x16, 32x32, 64x64, 128x128, 256x256, 512x512, 1024x1024 with @1x and @2x scales.
- **T1-F14-03 (Iconset Generation)**: Produces valid `.iconset` directory structure under build artifacts.
- **T1-F14-04 (ICNS Compilation)**: Invokes `iconutil -c icns` to produce valid `AppIcon.icns`.
- **T1-F14-05 (PNG Magic Bytes)**: Output files match PNG header signature `0x89 0x50 0x4E 0x47`.

### Feature 15: Retina 2x Screen Freeze
- **T1-F15-01 (Full Resolution Freeze)**: `CGDisplayCreateImage` captures active display at native pixel resolution.
- **T1-F15-02 (Retina 2.0 Backing Scale)**: Preserves 2x pixel density on Retina displays.
- **T1-F15-03 (Instantaneous Capture Timing)**: Screen capture executes in under 50ms without visible screen flicker.
- **T1-F15-04 (Color Space Preservation)**: Captured image maintains display color space (`CGColorSpaceCreateDeviceRGB` or Display P3).
- **T1-F15-05 (Valid CGImage Reference)**: Returns non-nil `CGImage` with non-zero width and height.

### Feature 16: Multi-Display Support
- **T1-F16-01 (Active Screen Detection)**: Identifies display currently containing mouse cursor via `NSEvent.mouseLocation`.
- **T1-F16-02 (Secondary Display Capture)**: Freezes secondary display when cursor is located on secondary monitor.
- **T1-F16-03 (Global Coordinate Translation)**: Converts Cocoa screen coordinates (origin bottom-left) to CoreGraphics coordinates (origin top-left).
- **T1-F16-04 (Display Bounds Mapping)**: Handles displays with differing resolutions and backing scales.
- **T1-F16-05 (Display Disconnect Resilience)**: Handles display topology changes gracefully without crashing.

### Feature 17: Outside Dimming Overlay
- **T1-F17-01 (Borderless Fullscreen Window)**: Overlay window covers entire target display with `.borderless` style mask.
- **T1-F17-02 (Window Level Screen Saver)**: Window level set to `.screenSaver` or `.statusBar` to float above regular windows.
- **T1-F17-03 (Dimming Opacity 0.45)**: Outside non-selected region rendered with `NSColor.black.withAlphaComponent(0.45)`.
- **T1-F17-04 (Clear Cutout for Selection)**: Selection box interior is completely clear (`NSColor.clear` / `CGBlendMode.clear`).
- **T1-F17-05 (Cursor Customization)**: Crosshair cursor displayed over unselected region; grab cursors over selection handles.

### Feature 18: 8-Handle Selection Box
- **T1-F18-01 (8 Control Handles)**: Selection box exposes Top-Left, Top-Center, Top-Right, Middle-Left, Middle-Right, Bottom-Left, Bottom-Center, Bottom-Right handles.
- **T1-F18-02 (Drag to Resize Handle)**: Dragging any handle recalculates selection rectangle smoothly.
- **T1-F18-03 (Drag Interior to Move)**: Dragging inside selection box translates rectangle position without changing dimensions.
- **T1-F18-04 (Negative Dimension Inversion)**: Dragging handle past opposite edge flips coordinates cleanly without inverted boxes.
- **T1-F18-05 (Hit-Testing Handle Precision)**: Handle grab regions detect mouse down within 8pt radius.

### Feature 19: Live Dimension Badge
- **T1-F19-01 (Dimension Format)**: Badge displays live dimensions in format `"<W> x <H> px"`.
- **T1-F19-02 (Anchor Position)**: Badge anchors above top-left of selection box by default.
- **T1-F19-03 (Top Edge Boundary Flipping)**: When selection is near screen top, badge flips inside or below selection box.
- **T1-F19-04 (Real-Time Drag Updates)**: Badge text updates synchronously with mouse drag events.
- **T1-F19-05 (Retina Pixel Accuracy)**: Badge values accurately report physical device pixels (scaled by 2x on Retina).

### Feature 20: Edge-Aware Repositioning
- **T1-F20-01 (Vertical Toolbar Flipping)**: Vertical annotation toolbar positioned to right of selection flips to left if right screen edge is near.
- **T1-F20-02 (Horizontal Toolbar Flipping)**: Horizontal action toolbar positioned below selection flips above if bottom screen edge is near.
- **T1-F20-03 (Corner Clamping)**: Selection touching corner keeps toolbars visible inside screen viewport.
- **T1-F20-04 (Minimum Margin Enforcement)**: Toolbars maintain minimum 8pt padding from display edges.
- **T1-F20-05 (Dynamic Recalculation on Resize)**: Toolbars reposition dynamically as selection box is resized.

### Feature 21: Vector Tool: Select/Move
- **T1-F21-01 (Tool Activation)**: Selecting Select/Move tool sets `activeTool = .select`.
- **T1-F21-02 (Hit-Testing Existing Object)**: Clicking on existing rectangle or line selects that object.
- **T1-F21-03 (Drag to Reposition)**: Dragging selected object translates its origin coordinates.
- **T1-F21-04 (Selection Bounding Box)**: Selected object displays bounding highlight or resize handles.
- **T1-F21-05 (Deselect on Empty Click)**: Clicking empty canvas area deselects active object.

### Feature 22: Vector Tool: Rectangle
- **T1-F22-01 (Rectangle Creation)**: Dragging with Rectangle tool creates `AnnotationObject` with `.rectangle` shape.
- **T1-F22-02 (Stroke Width Binding)**: Uses `activeStrokeWidth` from settings for border thickness.
- **T1-F22-03 (Stroke Color Binding)**: Uses `activeColorHex` for border color.
- **T1-F22-04 (Shift Key Square Constraint)**: Holding Shift constrains rectangle to 1:1 square aspect ratio.
- **T1-F22-05 (Hit Test Outline)**: Clicking on or near rectangle border registers hit test selection.

### Feature 23: Vector Tool: Ellipse/Circle
- **T1-F23-01 (Ellipse Creation)**: Dragging creates `AnnotationObject` with `.ellipse` shape.
- **T1-F23-02 (Shift Key Circle Constraint)**: Holding Shift constrains ellipse to perfect circular shape.
- **T1-F23-03 (Perimeter Hit Testing)**: Hit testing checks proximity to mathematical ellipse perimeter.
- **T1-F23-04 (Vector Rasterization Fidelity)**: Compositing ellipse uses antialiased vector path.
- **T1-F23-05 (Color & Stroke Variation)**: Modifying stroke width or color updates ellipse geometry.

### Feature 24: Vector Tool: Arrow
- **T1-F24-01 (Arrow Creation)**: Dragging defines start point (origin) and end point (arrowhead tip).
- **T1-F24-02 (Proportional Arrowhead)**: Arrowhead wings scale proportionally with stroke width.
- **T1-F24-03 (Angle Calculation)**: Arrowhead calculates orientation using `atan2(deltaY, deltaX)`.
- **T1-F24-04 (Hit Test Segment)**: Clicking along arrow shaft or head selects the arrow.
- **T1-F24-05 (Shift Key Snap)**: Holding Shift snaps arrow angle to 0, 45, 90, 135, 180 degrees.

### Feature 25: Vector Tool: Line
- **T1-F25-01 (Straight Line Creation)**: Dragging creates straight 2-point line object.
- **T1-F25-02 (Shift Key Orthogonal Constraint)**: Holding Shift snaps line to horizontal, vertical, or 45-degree angle.
- **T1-F25-03 (Line Cap Rounding)**: Line endpoints use `.round` line cap style for smooth appearance.
- **T1-F25-04 (Hit-Test Distance)**: Point-to-segment distance within `max(strokeWidth / 2 + 4, 8)` points selects line.
- **T1-F25-05 (Live Preview Drag)**: Live line updates continuously during mouse drag.

### Feature 26: Vector Tool: Freehand Pen
- **T1-F26-01 (Pen Path Creation)**: Continuous mouse drag records sequence of `CGPoint` coordinates.
- **T1-F26-02 (Path Smoothing)**: Interpolates points via Bezier curve smoothing for fluid freehand rendering.
- **T1-F26-03 (Polyline Hit Testing)**: Clicking within proximity threshold of any path segment selects the pen drawing.
- **T1-F26-04 (Opaque Stroke Rendering)**: Freehand pen renders with 100% opacity using active color.
- **T1-F26-05 (Rapid Movement Capture)**: High-frequency mouse movements capture dense point sequences without straight gaps.

### Feature 27: Vector Tool: Highlighter
- **T1-F27-01 (Highlighter Path Creation)**: Dragging creates semi-transparent marker stroke.
- **T1-F27-02 (Alpha Transparency 0.35)**: Renders with approximately 35% opacity allowing underlying text to remain legible.
- **T1-F27-03 (Broad Stroke Width)**: Highlighter default stroke width is scaled 4x larger than regular pen stroke.
- **T1-F27-04 (Multiply Blend Mode)**: Blends with background using multiply or normal blend preserving contrast.
- **T1-F27-05 (Consecutive Highlighter Overlap)**: Overlapping highlighter strokes composite cleanly.

### Feature 28: Vector Tool: Editable Text
- **T1-F28-01 (Text Object Creation)**: Clicking with Text tool creates in-place text box and summons keyboard focus.
- **T1-F28-02 (Font Size Selection)**: Renders text using configured `activeFontSize` (default 18pt).
- **T1-F28-03 (Live Text Editing)**: Typing updates text content string in real time.
- **T1-F28-04 (Text Box Bounds Auto-Expansion)**: Text bounding box expands horizontally and vertically as typing continues.
- **T1-F28-05 (Commit on Outside Click)**: Clicking outside text box commits text and switches to select mode.

### Feature 29: Vector Tool: Region Blur
- **T1-F29-01 (Blur Object Creation)**: Dragging creates rectangular region blur vector object.
- **T1-F29-02 (Pixelate / Gaussian Filter)**: Underlying image within blur bounds is filtered via CoreImage or pixelate shader.
- **T1-F29-03 (Sensitive Data Obfuscation)**: Text or credentials under blur region are rendered completely unreadable.
- **T1-F29-04 (Resizable Blur Box)**: Blur box can be moved or resized using selection handles.
- **T1-F29-05 (Multiple Blur Regions)**: Multiple distinct blur regions can be placed on a single screenshot.

### Feature 30: Undo / Redo Engine
- **T1-F30-01 (Command Pattern Undo)**: Adding an annotation and pressing Cmd+Z removes it and sets `canUndo = false`, `canRedo = true`.
- **T1-F30-02 (Command Pattern Redo)**: Pressing Cmd+Shift+Z re-adds the undone object and restores `canUndo = true`.
- **T1-F30-03 (Multi-Level Stack)**: Supports at least 50 sequential undo and redo operations.
- **T1-F30-04 (Undo Mutation)**: Undoing an object property change (color, position, text) reverts to previous state.
- **T1-F30-05 (Redo Stack Invalidation)**: Adding a new object after undo clears the redo stack.

### Feature 31: Color Swatch Bar
- **T1-F31-01 (8 Visible Swatches)**: Displays 8 color swatches matching default presets in vertical toolbar.
- **T1-F31-02 (1-Click Color Selection)**: Clicking a swatch immediately updates `activeColorHex`.
- **T1-F31-03 (Selected Object Recolor)**: Clicking a swatch with an object selected immediately recolors the object.
- **T1-F31-04 (Active Swatch Ring Highlight)**: Currently active color swatch displays selection ring indicator.
- **T1-F31-05 (Persistent Choice)**: Selected swatch persists across capture sessions.

### Feature 32: Custom HEX Input Picker
- **T1-F32-01 (Hex Input Popover)**: Clicking custom color button opens `ColorPalettePopoverView`.
- **T1-F32-02 (Direct Hex Typing)**: Typing `"#00FF00"` sets color to vibrant green.
- **T1-F32-03 (Hex Validation)**: Invalid strings (e.g. `"hello"`, `"#GGGGGG"`) are rejected or reverted.
- **T1-F32-04 (Add to Presets Button)**: Clicking `+` button adds current hex to user's saved presets.
- **T1-F32-05 (Preset Limit Enforcement)**: `+` button is disabled or alerts when 16 presets limit is reached.

### Feature 33: Screen Eyedropper Tool
- **T1-F33-01 (Eyedropper Summons)**: Clicking eyedropper button activates screen color sampling mode.
- **T1-F33-02 (Magnified Loupe Preview)**: Displays magnified pixel grid under mouse cursor.
- **T1-F33-03 (Sample Pixel Color)**: Clicking a screen pixel samples exact RGB value.
- **T1-F33-04 (Hex Update on Sample)**: Updates active hex text and active drawing color to sampled color.
- **T1-F33-05 (Cancel Sampling)**: Pressing Escape exits eyedropper mode without modifying color.

### Feature 34: Floating Action Toolbar
- **T1-F34-01 (Action Buttons Layout)**: Contains Scroll Capture, Copy to Clipboard, Save to File, Share Sheet, and Cancel buttons.
- **T1-F34-02 (Copy Action Cmd+C / Return)**: Pressing Copy button or Return key composites screenshot and copies to clipboard.
- **T1-F34-03 (Save Action Cmd+S)**: Pressing Save button prompts `NSSavePanel` or auto-saves to configured folder.
- **T1-F34-04 (Share Action)**: Pressing Share button opens `NSSharingServicePicker` anchored to button.
- **T1-F34-05 (Cancel Action Esc)**: Pressing Cancel button or Escape key dismisses overlay without saving.

### Feature 35: High-Fidelity Rasterizer
- **T1-F35-01 (Bitmap Context Creation)**: Creates CoreGraphics bitmap context at exact target pixel dimensions.
- **T1-F35-02 (Base Image Rendering)**: Renders base cropped screenshot at full 2x Retina resolution.
- **T1-F35-03 (Vector Path Compositing)**: Renders all vector shapes with subpixel antialiasing in correct z-index order.
- **T1-F35-04 (Blur Area Filtering)**: Composites pixelated/blurred regions cleanly over base pixels.
- **T1-F35-05 (Output Image Generation)**: Produces final pristine `CGImage` ready for clipboard, disk, or share sheet.

### Feature 36: Scroll Event Synthesizer
- **T1-F36-01 (Auto-Scroll Start)**: Activating auto-scroll begins periodic scroll event synthesis.
- **T1-F36-02 (CGEvent Scroll Wheel)**: Synthesizes `CGEventCreateScrollWheelEvent2` with smooth downward deltas.
- **T1-F36-03 (Viewport Center Target)**: Directs scroll events at center point of capture selection box.
- **T1-F36-04 (Configurable Scroll Speed)**: Scroll step delta is configurable (e.g. 10 to 30 units per step).
- **T1-F36-05 (Clean Stop on Cancellation)**: Stopping auto-scroll immediately terminates scroll timer.

### Feature 37: Manual Scroll Mode
- **T1-F37-01 (Manual Mode Toggle)**: Toggle button switches between Auto-Scroll and Manual Scroll.
- **T1-F37-02 (User Scroll Listening)**: Captures frames as user manually scrolls through document or webpage.
- **T1-F37-03 (Frame Ingestion on Movement)**: Detects content displacement and submits new frame to stitcher.
- **T1-F37-04 (Idle Frame Debouncing)**: Consecutive frames with zero movement are debounced.
- **T1-F37-05 (Done Button Termination)**: User completes manual capture by clicking Done or pressing Return.

### Feature 38: Live Stitched Preview
- **T1-F38-01 (Preview Window Presentation)**: Floating miniature preview window anchors adjacent to capture region during scrolling.
- **T1-F38-02 (Real-Time Thumbnail Update)**: Displays progressively stitched tall image scaled down to preview thumbnail.
- **T1-F38-03 (Dimension Badge Update)**: Live badge displays accumulated stitched height (e.g. `1280 x 4820 px`).
- **T1-F38-04 (Frame Counter)**: Shows count of captured frames (e.g. `"12 frames"`).
- **T1-F38-05 (Dismissal on Finish)**: Preview window cleanly dismisses when scrolling finishes.

### Feature 39: Scrollbar Strip Exclusion
- **T1-F39-01 (24px Right Strip Masking)**: Excludes rightmost 24px of captured frame from vertical overlap feature matching.
- **T1-F39-02 (Dynamic Scrollbar Movement Invariance)**: Moving scrollbar thumb does not corrupt vertical offset calculation.
- **T1-F39-03 (Configurable Strip Width)**: `StitchOptions.scrollbarStripWidth` can be adjusted (e.g. 0 to 40px).
- **T1-F39-04 (Final Output Retention)**: Full image (including content) is retained in output; exclusion applies to correlation matcher.
- **T1-F39-05 (Zero-Scrollbar Handling)**: Pages without visible scrollbars match successfully.

### Feature 40: Sticky Header Detection
- **T1-F40-01 (Stationary Header Correlation)**: Correlates top rows across consecutive frames to detect fixed navigation bars.
- **T1-F40-02 (Duplicate Header Stripping)**: Prevents fixed headers from being repeated in stitched output mid-image.
- **T1-F40-03 (Header Height Bound)**: Evaluates header deduplication within top `headerDedupHeight` (default 80px).
- **T1-F40-04 (Non-Sticky Header Invariance)**: If page has no sticky header, top content is preserved normally.
- **T1-F40-05 (Single Topmost Presentation)**: Sticky header is rendered exactly once at very top of stitched image.

### Feature 41: Sticky Footer Detection
- **T1-F41-01 (Stationary Footer Correlation)**: Correlates bottom rows across consecutive frames to detect fixed footers or cookie banners.
- **T1-F41-02 (Duplicate Footer Stripping)**: Prevents stationary footer bars from appearing repeatedly throughout the stitched body.
- **T1-F41-03 (Footer Height Bound)**: Evaluates footer deduplication within bottom `footerDedupHeight` (default 80px).
- **T1-F41-04 (Non-Sticky Footer Invariance)**: If page has no sticky footer, bottom content matches normally.
- **T1-F41-05 (Single Bottom Presentation)**: Sticky footer is rendered exactly once at bottom of final stitched image.

### Feature 42: Vertical Overlap Matching
- **T1-F42-01 (Pixel-Difference Correlation)**: Estimates vertical offset delta between successive frames using row correlation.
- **T1-F42-02 (Sub-Pixel Seam-Free Blending)**: Concatenates frames at exact offset matching seam without duplicate lines.
- **T1-F42-03 (Variable Scroll Speed Tolerance)**: Accurately matches offsets ranging from 10px to 500px per step.
- **T1-F42-04 (Textureless Region Robustness)**: Handles solid color blocks or whitespace without false offset locks.
- **T1-F42-05 (Multi-Frame Accumulation)**: Stitches at least 50 frames into seamless tall image.

### Feature 43: Auto-Stop on End-of-Page
- **T1-F43-01 (Zero-Delta Detection)**: Detects when 3 consecutive frames yield zero vertical offset displacement.
- **T1-F43-02 (Automatic Scrolling Termination)**: Stops scroll event synthesis automatically upon detecting end-of-page.
- **T1-F43-03 (Canvas Transition)**: Automatically transitions to Scrollable Annotation Canvas upon stop.
- **T1-F43-04 (No Duplicate Bottom Tail)**: Ensures final frame does not append duplicate content at end.
- **T1-F43-05 (Audible or Visual Completion Signal)**: Provides clean completion state transition.

### Feature 44: maxScrollHeightPx Clamp
- **T1-F44-01 (Default 15,000 px Ceiling)**: Clamps stitched total height to `maxScrollHeightPx` (default 15,000 px).
- **T1-F44-02 (Configurable Range 5k-30k px)**: Accepts configuration between 5,000 and 30,000 px.
- **T1-F44-03 (Automatic Termination on Clamp)**: Scrolling halts immediately upon reaching configured ceiling.
- **T1-F44-04 (Memory Overflow Protection)**: Prevents out-of-memory crashes on infinite-scrolling social media feeds.
- **T1-F44-05 (Image Truncation Clean Seam)**: Stitched image is clipped cleanly at maximum height without corruption.

### Feature 45: User Done Stop Trigger
- **T1-F45-01 (Return Key Trigger)**: Pressing Return key immediately halts scrolling capture.
- **T1-F45-02 (Spacebar Trigger)**: Pressing Space key halts scrolling capture.
- **T1-F45-03 (Done Button Click)**: Clicking floating Done button halts capture.
- **T1-F45-04 (Escape Abort)**: Pressing Escape halts and cancels capture without saving partial image.
- **T1-F45-05 (Partial Capture Preservation)**: Completing via Done preserves all frames stitched up to that moment.

### Feature 46: Tall Image Scroll Canvas
- **T1-F46-01 (NSScrollView Integration)**: Loads tall stitched image into high-performance `NSScrollView`.
- **T1-F46-02 (Vertical Scrolling Navigation)**: Smooth trackpad and mouse wheel scrolling through 15,000+ px image.
- **T1-F46-03 (Zoom Controls)**: Supports zooming in/out (Fit Width, 100%, 200%) on tall image.
- **T1-F46-04 (Tiled Layer Rendering)**: Utilizes `CATiledLayer` or segmented rendering to maintain 60fps on massive textures.
- **T1-F46-05 (Centered Viewport Layout)**: Centers tall image canvas horizontally within display window.

### Feature 47: Tall Canvas Vector Annotations
- **T1-F47-01 (All 8 Vector Tools Enabled)**: Select, Rectangle, Ellipse, Arrow, Line, Pen, Highlighter, Text, and Blur available on tall canvas.
- **T1-F47-02 (Global Coordinate Mapping)**: Annotations placed at scroll offset 12,000px maintain correct absolute positions.
- **T1-F47-03 (Full-Length Hit Testing)**: Hit testing operates accurately throughout the entire scrollable height.
- **T1-F47-04 (Tall Canvas Undo/Redo)**: Undo/Redo functions identically across tall canvas annotations.
- **T1-F47-05 (Tall Rasterization Export)**: Rasterizes full tall image with all vector annotations composited at native resolution.

### Feature 48: NSStatusItem Controller
- **T1-F48-01 (Dual-Click Behavior)**: Left-clicking status item opens `MainShotView` popover; right-clicking opens context menu.
- **T1-F48-02 (Status Item Positioning)**: Anchors status item in macOS system menu bar.
- **T1-F48-03 (SF Symbol Camera Icon)**: Sets status button image to SF Symbol `camera` or `viewfinder`.
- **T1-F48-04 (Popover Toggle)**: Left-clicking when popover is open closes popover cleanly.
- **T1-F48-05 (Menu Item Synchronization)**: Context menu items update dynamic state (e.g. unpinned count).

### Feature 49: History Popover View
- **T1-F49-01 (MainShotView Presentation)**: Popover presents Pinned section and Recent History section.
- **T1-F49-02 (Header Action Buttons)**: Header contains 1-click buttons for Region Capture and Scroll Capture.
- **T1-F49-03 (Thumbnail Previews)**: Each row displays crisp downscaled thumbnail of screenshot.
- **T1-F49-04 (Dimension & Time Badges)**: Displays resolution (e.g. `"1920x1080"`) and relative time (e.g. `"2m ago"`).
- **T1-F49-05 (Per-Row Actions)**: Each row exposes Copy, Save, Pin/Unpin, and Delete buttons.

### Feature 50: Instant History Search
- **T1-F50-01 (Auto-Focused Search Field)**: Opening popover focuses search input immediately.
- **T1-F50-02 (Real-Time Substring Filtering)**: Typing filters history items by timestamp, dimension, or source app.
- **T1-F50-03 (Instant Clear Button)**: Clicking clear ("x") restores full history list immediately.
- **T1-F50-04 (Zero Matches State)**: Displays clean "No screenshots found" notice when query yields 0 results.
- **T1-F50-05 (Section Preservation in Search)**: Filtered results maintain Pinned and Recent section grouping.

### Feature 51: Hover Zoom Preview
- **T1-F51-01 (ThumbnailHoverPreviewPanel Presentation)**: Hovering over history row displays floating magnified preview panel.
- **T1-F51-02 (Screen Clamping Positioning)**: Hover panel clamps cleanly within screen bounds adjacent to popover.
- **T1-F51-03 (Full Resolution Thumbnail)**: Displays high-resolution preview without pixelation blur.
- **T1-F51-04 (Dismissal on Mouse Exit)**: Moving cursor away dismisses hover preview panel immediately.
- **T1-F51-05 (Zero Hover Delay)**: Panel summons with smooth 100ms fade-in avoiding jarring flickers.

### Feature 52: Circular Keyboard Nav
- **T1-F52-01 (Down Arrow Navigation)**: Pressing Down arrow moves selection down the history list.
- **T1-F52-02 (Up Arrow Navigation)**: Pressing Up arrow moves selection up the list.
- **T1-F52-03 (Circular Wrap-Around Bottom to Top)**: Pressing Down arrow at last item wraps selection to first item.
- **T1-F52-04 (Circular Wrap-Around Top to Bottom)**: Pressing Up arrow at first item wraps selection to last item.
- **T1-F52-05 (Return Key Selection)**: Pressing Return selects active item, copies to clipboard, and closes popover.

### Feature 53: 1..9 Quick Select
- **T1-F53-01 (Number Key 1)**: Pressing `1` immediately selects and copies 1st visible screenshot.
- **T1-F53-02 (Number Key 9)**: Pressing `9` selects and copies 9th visible screenshot.
- **T1-F53-03 (Filtered List Mapping)**: During search, keys 1..9 map directly to visible filtered rows.
- **T1-F53-04 (Out-of-Bounds Rejection)**: Pressing `5` when only 2 items are visible does nothing safely.
- **T1-F53-05 (Quick Select Badge)**: Visible rows display number badge indicators (1 through 9).

### Feature 54: Direct Auto-Paste Service
- **T1-F54-01 (AX Permission Query)**: `isAccessibilityTrusted` queries `AXIsProcessTrusted()`.
- **T1-F54-02 (Synthetic Cmd+V Keystroke)**: If AX is granted, injects synthetic `CGEvent` Command+V keystroke into previous active app.
- **T1-F54-03 (Safe Fallback to Copy-Only)**: If AX is denied, writes screenshot to pasteboard without crashing or hanging.
- **T1-F54-04 (Previous App Focus Tracking)**: Records bundle ID of previous active app before opening popover.
- **T1-F54-05 (App Reactivation)**: Reactivates previous application before injecting paste keystroke.

### Feature 55: Context Menu
- **T1-F55-01 (Right-Click Menu Opening)**: Right-clicking status item opens `NSMenu`.
- **T1-F55-02 (Menu Items Structure)**: Contains Take Screenshot, Scrolling Screenshot, Show History, Preferences `Cmd+,`, Clear Unpinned History, Check for Updates, Quit `Cmd+Q`.
- **T1-F55-03 (Action Binding)**: Selecting Take Screenshot activates capture overlay immediately.
- **T1-F55-04 (Preferences Summons)**: Selecting Preferences opens centered `SettingsWindowController`.
- **T1-F55-05 (Quit Clean Termination)**: Selecting Quit terminates application cleanly.

### Feature 56: 4-Tab Settings Window
- **T1-F56-01 (4 Tabs Layout)**: Settings presents General, Capture & Save, History Management, About tabs.
- **T1-F56-02 (Permission Status Badges)**: General tab displays Screen Recording & Accessibility permission status and grant buttons.
- **T1-F56-03 (Centered Window Presentation)**: Settings window opens centered on active screen.
- **T1-F56-04 (Model Binding)**: UI controls bind two-way with `AppSettings` store.
- **T1-F56-05 (Zero Emojis in Settings UI)**: All settings labels, tabs, and notices contain zero emojis.

### Feature 57: Flexible Save Modes
- **T1-F57-01 (NSSavePanel Prompt Mode)**: When auto-save is disabled, saving prompts `NSSavePanel`.
- **T1-F57-02 (Direct Auto-Save Mode)**: When enabled, saving writes directly to configured folder.
- **T1-F57-03 (PNG Format Export)**: Saves high-resolution lossless PNG file.
- **T1-F57-04 (JPEG Format Export)**: Saves compressed JPEG file with configurable quality.
- **T1-F57-05 (Default Filename Format)**: Generates timestamped filename (e.g. `SuperShot_2026-10-22_163000.png`).

### Feature 58: Launch at Login
- **T1-F58-01 (SMAppService Registration)**: Registers login item via `SMAppService.mainApp.register()`.
- **T1-F58-02 (Status Querying)**: Accurately reports whether app is configured to launch at login.
- **T1-F58-03 (Unregistration)**: Unregisters login item via `SMAppService.mainApp.unregister()`.
- **T1-F58-04 (Settings Toggle Binding)**: Toggling switch in General tab updates login item status.
- **T1-F58-05 (Error Handling)**: Handles system registration errors cleanly without crashing.

### Feature 59: Documentation Sync
- **T1-F59-01 (README.md Architecture Documentation)**: Documents Scrolling Screenshot, Color Presets, and architecture.
- **T1-F59-02 (Bilingual Support)**: Provides English and Vietnamese product descriptions.
- **T1-F59-03 (Zero Emojis in Documentation)**: README.md complies strictly with zero emoji rule.
- **T1-F59-04 (Hotkeys Table)**: Documents Option+S, Option+Shift+S, Cmd+Z, Cmd+C, Cmd+S shortcuts.
- **T1-F59-05 (Build Instructions Accuracy)**: Documents exact `make build`, `make app`, `make test`, `make package` commands.

### Feature 60: E2E Regression Pass
- **T1-F60-01 (100% Pass Rate)**: Full automated test suite passes with 0 failures across all suites.
- **T1-F60-02 (Execution Timing Metric)**: Entire test run completes within acceptable headless execution window.
- **T1-F60-03 (Exit Code 0 Verification)**: Test runner process exits with status code 0.
- **T1-F60-04 (Clean Console Output)**: Output contains structured ANSI reporting with zero emoji characters.
- **T1-F60-05 (No Sandbox Leaks)**: Zero temporary files or directories left behind after execution.

---

## 4. Tier 2: Boundary & Corner Cases (>=5 Test Cases per Feature for all 60 Features)

Total Tier 2 Test Cases: **300 test cases** (60 features x 5 boundary test cases).

### Feature 1: Universal 2 Makefile Boundaries
- **T2-F01-01 (Missing SDK Fallback)**: Builds successfully when SDK path `/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk` is missing by probing `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk` or `xcrun`.
- **T2-F01-02 (Single Architecture Force)**: Makefile tolerates `HOST_ARCH` override for developer fast iteration without breaking Universal 2 release target.
- **T2-F01-03 (Space in Project Path)**: Build commands handle directory paths containing spaces cleanly.
- **T2-F01-04 (Parallel Make Jobs `make -j8`)**: Makefile dependencies prevent race conditions during concurrent slice compilation.
- **T2-F01-05 (Idempotent Re-build)**: Running `make build` consecutively executes cleanly without re-linking errors.

### Feature 2: Package.swift Manifest Boundaries
- **T2-F02-01 (Swift Version Compatibility)**: Manifest compiles cleanly under Swift 5.9 through Swift 6.x toolchains.
- **T2-F02-02 (macOS Minimum Version Enforcement)**: Fails build if target is configured below macOS 13.0.
- **T2-F02-03 (Module Visibility)**: Internal types in `SuperShotCore` are appropriately protected from unintended public exposure.
- **T2-F02-04 (Path Sanitization)**: Paths in `Package.swift` resolve cleanly across symbolic links.
- **T2-F02-05 (Zero Dependency Enforcement)**: Adding any third-party URL to dependencies array triggers verification failure.

### Feature 3: Zero-Emoji Linter Boundaries
- **T2-F03-01 (Emoji Inside Multi-Line Comment)**: Detects emoji inside `/* ... */` comment block.
- **T2-F03-02 (Emoji Inside Unicode Escape)**: Detects emoji written as `\u{1F600}` in Swift string literals.
- **T2-F03-03 (Technical Symbols Exemption)**: Permits valid keyboard symbols (`Cmd`, `Option`, `Shift`, `Return`) while strictly blocking all pictographs and dingbats.
- **T2-F03-04 (Variation Selectors)**: Detects and blocks variation selector codepoints (`0xFE0E`, `0xFE0F`).
- **T2-F03-05 (Binary Files Traversal)**: Safely ignores binary files (e.g. `.png`, `.icns`) without false positives or decode errors.

### Feature 4: TestHarness Framework Boundaries
- **T2-F04-01 (Zero Tests Executed)**: TestHarness reports failure if test suite exits without executing any assertions.
- **T2-F04-02 (10,000 Rapid Assertions)**: Executes 10,000 consecutive assertions in < 100ms without memory bloat.
- **T2-F04-03 (Sandbox Directory Collision)**: Generating 1,000 sandboxes concurrently generates 1,000 unique URLs.
- **T2-F04-04 (Sandbox Cleanup on Non-Existent Path)**: Calling `cleanupSandbox` on missing URL causes no exception.
- **T2-F04-05 (Nil String Assertion)**: `assertNil` handles optional strings and pointers cleanly.

### Feature 5: ColorPreset Data Model Boundaries
- **T2-F05-01 (Invalid Hex Length)**: Parsing `"#FF"`, `"#FFFF"`, or `"#FFFFFFF"` fails gracefully and falls back to default.
- **T2-F05-02 (Missing Hex Hash Prefix)**: Parsing `"FF3B30"` (without `#`) parses valid color or sanitizes cleanly.
- **T2-F05-03 (Non-Hex Characters)**: Parsing `"#ZZZZZZ"` or `"#12G45H"` rejects invalid hex.
- **T2-F05-04 (Pure White and Pure Black)**: `"#FFFFFF"` and `"#000000"` parse with exact boundary RGB values 1.0 and 0.0.
- **T2-F05-05 (Alpha Channel Invariance)**: 6-character hex parsing guarantees 100% alpha (1.0).

### Feature 6: ColorPreset Persistence Boundaries
- **T2-F06-01 (Adding 100 Presets Consecutively)**: Strictly clamps to 16 maximum presets; presets 17..100 are ignored.
- **T2-F06-02 (Deleting Non-Existent UUID)**: Deleting preset with random UUID causes no error or side effects.
- **T2-F06-03 (Reset When Already Default)**: Calling reset when store is already in default state executes idempotently.
- **T2-F06-04 (Deleting All Presets)**: Deleting all presets maintains safe state and allows restoration.
- **T2-F06-05 (Corrupted Presets JSON)**: Malformed presets array in `settings.json` falls back to default 8 presets.

### Feature 7: AppSettings Store Boundaries
- **T2-F07-01 (Stroke Width Clamping)**: Stroke width clamps to minimum 1.0pt and maximum 50.0pt.
- **T2-F07-02 (Font Size Clamping)**: Font size clamps to minimum 9.0pt and maximum 144.0pt.
- **T2-F07-03 (Max Scroll Height Clamping)**: Value below 5,000px clamps to 5,000px; value above 30,000px clamps to 30,000px.
- **T2-F07-04 (Non-Existent Auto-Save Directory)**: If auto-save folder was deleted on disk, falls back to Pictures/Screenshots.
- **T2-F07-05 (Read-Only Settings Directory)**: Disk write failure on read-only permissions handled cleanly without crashing.

### Feature 8: ShotItem Data Model Boundaries
- **T2-F08-01 (Micro Dimensions 1x1)**: Handles 1x1 pixel screenshot item without division-by-zero.
- **T2-F08-02 (Gigantic Dimensions 30,000x30,000)**: Accurately stores massive pixel dimensions without integer overflow.
- **T2-F08-03 (Missing Source App)**: `sourceApp = nil` handles cleanly in serialization and display.
- **T2-F08-04 (Future Timestamp)**: Item with future timestamp renders safely without breaking chronological sort.
- **T2-F08-05 (Empty Tags Array)**: Operates cleanly with empty or populated tags list.

### Feature 9: Thread-Safe StorageManager Boundaries
- **T2-F09-01 (Concurrent 50-Thread Add)**: 50 threads simultaneously saving screenshots complete with zero race conditions.
- **T2-F09-02 (Deleting While Reading)**: Deleting item while background thread is reading items array executes safely.
- **T2-F09-03 (Zero-Byte File Handling)**: Zero-byte image file on disk handles gracefully on load without crash.
- **T2-F09-04 (Disk Full Emulation)**: Image save error due to disk quota throws handled error without corrupting metadata.
- **T2-F09-05 (Special Characters in Path)**: Sandbox paths containing spaces and non-Latin characters function identically.

### Feature 10: In-Memory NSCache Boundaries
- **T2-F10-01 (Memory Pressure Eviction)**: System memory pressure triggers automatic cache purge without data loss.
- **T2-F10-02 (Zero-Cost Cache Limit)**: Operates reliably under strict total cost limits.
- **T2-F10-03 (Rapid Reload Burst)**: Requesting same image 1,000 times hits cache with zero disk reads.
- **T2-F10-04 (Corrupt Cached Object)**: Handles unexpected cache payload types safely.
- **T2-F10-05 (Cache Clear on Logout)**: Manual cache flush frees memory immediately.

### Feature 11: Pinned Item Protection Boundaries
- **T2-F11-01 (100% Pinned Store Overflow)**: Adding unpinned item to store where 100% of items are pinned keeps all pinned items.
- **T2-F11-02 (Rapid 20x Pin Toggling)**: Rapidly toggling pin flag on same item leaves state consistent.
- **T2-F11-03 (Unpinning Evicts If Beyond Capacity)**: Unpinning an item older than the capacity window triggers immediate eviction.
- **T2-F11-04 (Pinning Non-Existent ID)**: Toggling pin on missing UUID causes no error.
- **T2-F11-05 (Clear Unpinned on All-Pinned Store)**: Leaves 100% of items intact.

### Feature 12: LocalizationManager Boundaries
- **T2-F12-01 (Empty Key Query)**: Querying empty string `""` returns empty string safely without crash.
- **T2-F12-02 (Unknown Language Code)**: Setting language to `"xx_YY"` falls back safely to English.
- **T2-F12-03 (Rapid Language Cycling)**: Cycling through all 9 languages 100 times executes without memory leaks.
- **T2-F12-04 (Special Formatting Tokens)**: Localized strings with format arguments (`%d`, `%@`) format accurately.
- **T2-F12-05 (Right-to-Left Layout Independence)**: Language selection maintains correct LTR text rendering.

### Feature 13: HotKeyManager Boundaries
- **T2-F13-01 (Re-Registering Same Keycode)**: Re-registering existing keycode updates handler without duplicate event registrations.
- **T2-F13-02 (Unregistering When Empty)**: Calling unregister when no hotkeys are registered causes no error.
- **T2-F13-03 (Conflicting System Shortcuts)**: Handles collision with system shortcuts cleanly.
- **T2-F13-04 (All Modifiers Pressed)**: Handles combinations with Command+Option+Shift+Control.
- **T2-F13-05 (Function Keys)**: Supports F1..F12 key codes if configured.

### Feature 14: AppIcon Asset Generator Boundaries
- **T2-F14-01 (Existing Output Directory)**: Re-running script overwrites existing assets cleanly.
- **T2-F14-02 (Zero-Size Icon Generation)**: Rejects negative or zero pixel dimensions safely.
- **T2-F14-03 (Corrupt Canvas Handling)**: Handles CoreGraphics bitmap context creation failures gracefully.
- **T2-F14-04 (File Permission Denied)**: Emits actionable error if output folder is write-protected.
- **T2-F14-05 (Strict Square Aspect Ratio)**: All generated PNG assets maintain exactly 1:1 aspect ratio.

### Feature 15: Retina 2x Screen Freeze Boundaries
- **T2-F15-01 (1x Non-Retina Display)**: Freezes standard 1x displays at native 1x resolution without upsampling blur.
- **T2-F15-02 (Multi-Monitor Mixed DPI)**: Freezes 2x Retina screen and 1x external monitor with respective native scales.
- **T2-F15-03 (Display Sleep Transition)**: Handles display sleeping or waking state safely.
- **T2-F15-04 (HDR / Wide Color P3)**: Captures wide gamut color displays without color banding.
- **T2-F15-05 (Zero-Dimension Display Fallback)**: Rejects invalid display bounds safely.

### Feature 16: Multi-Display Support Boundaries
- **T2-F16-01 (Negative Coordinate Screens)**: Handles secondary displays positioned to the left or above primary display (negative origins).
- **T2-F16-02 (Cursor on Display Seam)**: Cursor at exact boundary between two screens selects predictable primary screen.
- **T2-F16-03 (Display Disconnected Mid-Capture)**: Disconnecting external monitor during freeze aborts capture cleanly without crash.
- **T2-F16-04 (3+ Connected Displays)**: Correctly identifies cursor across 3 or more displays.
- **T2-F16-05 (Virtual / AirPlay Displays)**: Operates cleanly on Sidecar or AirPlay virtual displays.

### Feature 17: Outside Dimming Overlay Boundaries
- **T2-F17-01 (Zero Selection Area)**: When selection is 0x0, entire screen is dimmed 0.45.
- **T2-F17-02 (Full Screen Selection Area)**: When selection matches display size, dimming is 0.0 (completely clear).
- **T2-F17-03 (Notched Display Clamping)**: Dimming overlay extends under MacBook display notch.
- **T2-F17-04 (Rapid Selection Drags)**: Dragging rapidly updates clear cutout region smoothly at 60fps.
- **T2-F17-05 (Window Level Precedence)**: Dimming overlay floats above full-screen apps and Menu Bar.

### Feature 18: 8-Handle Selection Box Boundaries
- **T2-F18-01 (1x1 Minimum Box Size)**: Prevents resizing selection below 1x1 pixel.
- **T2-F18-02 (Dragging Off-Screen)**: Clamps selection box edges to active screen display bounds.
- **T2-F18-03 (Cross-Handle Drag Inversion)**: Dragging right handle past left handle switches handle identities cleanly.
- **T2-F18-04 (Rapid Handle Switching)**: Clicking handles rapidly causes no stuck drag states.
- **T2-F18-05 (Touchpad Gestures)**: Handles mouse, trackpad, and stylus drag events identically.

### Feature 19: Live Dimension Badge Boundaries
- **T2-F19-01 (1x1 Dimension Formatting)**: Formats `"1 x 1 px"` cleanly.
- **T2-F19-02 (Huge Resolution 7680x4320)**: Formats 8K dimensions without text truncation.
- **T2-F19-03 (Badge Collision with Screen Edge)**: Flips badge position when near any screen boundary.
- **T2-F19-04 (Zero Latency on Drag)**: Badge redraws synchronously with cursor movement.
- **T2-F19-05 (Retina Pixel Scaling Accuracy)**: Badge values accurately multiply points by backing scale factor.

### Feature 20: Edge-Aware Repositioning Boundaries
- **T2-F20-01 (Four Screen Corners)**: Repositions toolbars cleanly when selection is placed in any of the 4 screen corners.
- **T2-F20-02 (Very Small Selection Box 20x20)**: Toolbars reposition outside tiny selection without overlapping each other.
- **T2-F20-03 (Display with Left Dock)**: Accounts for Dock thickness when Dock is on left screen edge.
- **T2-F20-04 (Display with Bottom Dock)**: Accounts for Dock thickness when Dock is on bottom screen edge.
- **T2-F20-05 (Menu Bar Overlap Prevention)**: Toolbars clamp below Menu Bar height.

### Feature 21: Vector Tool: Select/Move Boundaries
- **T2-F21-01 (Hit-Testing 1pt Thin Line)**: Expands hit-test target area to minimum 8pt so thin lines can be selected easily.
- **T2-F21-02 (Selecting Overlapping Objects)**: Selects topmost object in z-order when multiple objects overlap.
- **T2-F21-03 (Moving Object Partially Off-Screen)**: Allows objects to extend partially outside selection without crash.
- **T2-F21-04 (Drag Object with Zero Movement)**: Mouse down and up at same coordinate preserves object position.
- **T2-F21-05 (Empty Selection Drag)**: Dragging on empty space does not move unselected objects.

### Feature 22: Vector Tool: Rectangle Boundaries
- **T2-F22-01 (1x1 Micro Rectangle)**: Renders 1x1 rectangle without negative path errors.
- **T2-F22-02 (Huge Stroke Width 50pt)**: Renders wide stroke width with clean corner joins.
- **T2-F22-03 (Shift Key Toggle Mid-Drag)**: Pressing and releasing Shift during drag toggles square aspect ratio dynamically.
- **T2-F22-04 (Negative Coordinate Drag)**: Dragging up and left creates valid positive width and height rectangle.
- **T2-F22-05 (Zero-Opacity Background)**: Rectangle interior is completely transparent, only border is stroked.

### Feature 23: Vector Tool: Ellipse/Circle Boundaries
- **T2-F23-01 (1x1 Micro Circle)**: Renders 1x1 dot safely without division-by-zero.
- **T2-F23-02 (Extreme Aspect Ratio 1000x5)**: Renders flattened oval path cleanly.
- **T2-F23-03 (Interior Hit-Testing Exemption)**: Clicking inside unfilled ellipse does not trigger hit test; only perimeter hits.
- **T2-F23-04 (Shift Key Circle Constraint)**: Perfect circle maintains equal width and height.
- **T2-F23-05 (Antialiased Edge Blending)**: Circle edges blend smoothly without pixel stair-stepping.

### Feature 24: Vector Tool: Arrow Boundaries
- **T2-F24-01 (Zero-Length Arrow)**: Dragging 0 distance creates no arrow or cleans up safely.
- **T2-F24-02 (Very Short Arrow 5pt)**: Arrowhead scales down to avoid inverted wings.
- **T2-F24-03 (Vertical Straight Arrow)**: Angle 90 degrees renders vertical arrow with symmetrical head.
- **T2-F24-04 (Horizontal Straight Arrow)**: Angle 0 degrees renders horizontal arrow with symmetrical head.
- **T2-F24-05 (Thick Stroke Arrow 20pt)**: Arrowhead wings remain proportional and sharply joined.

### Feature 25: Vector Tool: Line Boundaries
- **T2-F25-01 (Zero-Length Line)**: Dragging 0 distance handles safely without NaN coordinates.
- **T2-F25-02 (Single-Pixel Line)**: 1px line aligns to pixel grid to avoid unintended blur.
- **T2-F25-03 (45-Degree Snap Snap Angle)**: Shift key snaps line precisely to 45.0 degrees.
- **T2-F25-04 (Reverse Drag Direction)**: Dragging right-to-left produces identical line to left-to-right.
- **T2-F25-05 (Off-Screen Line Endpoint)**: Line extending past selection edge clips cleanly to selection bounds.

### Feature 26: Vector Tool: Freehand Pen Boundaries
- **T2-F26-01 (Single-Click Dot)**: Clicking without dragging creates small round dot.
- **T2-F26-02 (10,000 Points Pen Stroke)**: Long continuous scribbling records 10,000 points without memory degradation.
- **T2-F26-03 (Zero-Distance Point Filtering)**: Consecutive identical points are filtered to optimize path complexity.
- **T2-F26-04 (Rapid Zig-Zag Motion)**: Sharp turns preserve crisp corners with round joins.
- **T2-F26-05 (Pen Path Clipping)**: Freehand strokes outside selection box clip at selection boundary.

### Feature 27: Vector Tool: Highlighter Boundaries
- **T2-F27-01 (Highlighter on Black Background)**: Highlights over dark content without producing white haze.
- **T2-F27-02 (Highlighter on White Background)**: Highlights over light content with clear vibrant tint.
- **T2-F27-03 (Triple-Layer Overlap)**: Multiple highlighter passes over same word composite without turning completely opaque.
- **T2-F27-04 (Highlighter Stroke Width Clamping)**: Minimum stroke width clamped to readable marker thickness (12pt).
- **T2-F27-05 (Highlighter Antialiasing)**: Semi-transparent edges render smoothly without fringe artifacts.

### Feature 28: Vector Tool: Editable Text Boundaries
- **T2-F28-01 (Empty Text Dismissal)**: Clicking text tool and clicking away without typing creates no empty text object.
- **T2-F28-02 (1,000-Word Multiline Text)**: Pasting large text block wraps and renders without crashing.
- **T2-F28-03 (Non-Latin & CJK Text)**: Typing Japanese, Chinese, Vietnamese, and Arabic text renders with correct fonts.
- **T2-F28-04 (Text Box Drag Boundary)**: Moving text box near selection edge keeps text within visible bounds.
- **T2-F28-05 (Font Size 144pt)**: Giant text renders sharp vectors without clipping glyph ascenders/descenders.

### Feature 29: Vector Tool: Region Blur Boundaries
- **T2-F29-01 (1x1 Micro Blur)**: Renders 1x1 blur region without filter shader crash.
- **T2-F29-02 (Full Selection Blur)**: Blurring 100% of selection area executes without slowdown.
- **T2-F29-03 (Overlapping Blur Boxes)**: Two overlapping blur regions composite cleanly without double-blur inversion artifacts.
- **T2-F29-04 (Blur Radius Strength)**: Blur strength is sufficient to obscure 10pt passwords and credit card numbers.
- **T2-F29-05 (Blur Region Edge Bleed)**: Blur filter clamps to region boundary without bleeding unblurred pixels.

### Feature 30: Undo / Redo Engine Boundaries
- **T2-F30-01 (Undo on Empty Stack)**: Pressing Cmd+Z when stack is empty causes no error.
- **T2-F30-02 (Redo on Empty Stack)**: Pressing Cmd+Shift+Z when redo stack is empty causes no error.
- **T2-F30-03 (Undo 100 Times in Rapid Succession)**: Rapidly spamming undo unwinds all operations cleanly.
- **T2-F30-04 (Interleaved Actions)**: Undo, add new shape, verify redo stack is completely cleared.
- **T2-F30-05 (Undo Text Modification)**: Undoing text edits restores previous character sequence accurately.

### Feature 31: Color Swatch Bar Boundaries
- **T2-F31-01 (Clicking Currently Selected Swatch)**: Re-clicking active swatch maintains state idempotently.
- **T2-F31-02 (Rapid Swatch Clicking)**: Clicking through all 8 swatches in 1 second updates active color smoothly.
- **T2-F31-03 (Swatch Contrast on Dark/Light Background)**: Swatches remain visible regardless of underlying screen content.
- **T2-F31-04 (Black Swatch Border)**: Pure black swatch displays subtle light border so it is visible against dark backgrounds.
- **T2-F31-05 (Recolor With Multiple Selection)**: Recolor applies to currently active selection.

### Feature 32: Custom HEX Input Picker Boundaries
- **T2-F32-01 (Leading/Trailing Whitespace)**: Hex input `"  #FF3B30  "` trims whitespace and parses valid color.
- **T2-F32-02 (Short Hex #RGB)**: Parsing 3-character hex `"#F00"` expands to `"#FF0000"`.
- **T2-F32-03 (Pasting Formatted Text)**: Pasting formatted RTF string into hex field extracts plain ASCII hex text.
- **T2-F32-04 (Hex Input Focus Loss)**: Clicking away from hex input commits valid color or restores previous color.
- **T2-F32-05 (Duplicate Preset Addition)**: Adding an already existing hex color to presets is handled safely.

### Feature 33: Screen Eyedropper Tool Boundaries
- **T2-F33-01 (Sampling at Exact Screen Edge)**: Eyedropper at `(0, 0)` samples edge pixel without out-of-bounds crash.
- **T2-F33-02 (Sampling Across Displays)**: Moving eyedropper across display boundary updates magnification loupe seamlessly.
- **T2-F33-03 (Rapid Mouse Movement)**: Moving cursor fast does not leave trails of loupe windows.
- **T2-F33-04 (Sampling Under Modal Window)**: Samples pixels from underlying windows.
- **T2-F33-05 (Eyedropper Window Level)**: Loupe window floats above all other overlays.

### Feature 34: Floating Action Toolbar Boundaries
- **T2-F34-01 (Rapid Button Double-Click)**: Double-clicking Copy or Save button triggers action once without duplicate files.
- **T2-F34-02 (Save Cancelation)**: Canceling `NSSavePanel` returns user to overlay cleanly without closing selection.
- **T2-F34-03 (Clipboard Locked by Another App)**: Retries or handles clipboard write safely if another app holds lock.
- **T2-F34-04 (Share Sheet on Headless System)**: Handles systems where sharing services are unavailable.
- **T2-F34-05 (Keyboard Shortcut Equivalents)**: Cmd+C, Cmd+S, Esc fire corresponding button actions identically.

### Feature 35: High-Fidelity Rasterizer Boundaries
- **T2-F35-01 (Zero-Dimension Selection 0x0)**: Rejects rasterization of 0x0 area safely.
- **T2-F35-02 (Odd Pixel Dimensions 101x307)**: Handles odd pixel dimensions without raster misalignment.
- **T2-F35-03 (Transparent Pixels in Base Image)**: Preserves alpha channel transparency if present.
- **T2-F35-04 (Maximum Memory Allocation Check)**: Verifies bitmap buffer allocation succeeds before rasterizing.
- **T2-F35-05 (Color Profile Fidelity)**: Output image embeds source display ICC color profile.

### Feature 36: Scroll Event Synthesizer Boundaries
- **T2-F36-01 (Zero-Delta Step)**: Handles zero scroll delta step gracefully without freezing loop.
- **T2-F36-02 (High Scroll Speed)**: Fast scroll delta (50pt) does not cause frame skips or desynchronization.
- **T2-F36-03 (Window Focus Loss During Scroll)**: Pauses or continues auto-scroll safely if another window gains focus.
- **T2-F36-04 (Continuous Scroll 60 Seconds)**: Synthesizes continuous scroll events for 60s without event queue starvation.
- **T2-F36-05 (Inverted Scroll Direction)**: Rejects negative scroll deltas in downward auto-scroll mode.

### Feature 37: Manual Scroll Mode Boundaries
- **T2-F37-01 (Zero Movement During Manual Capture)**: User leaving document static triggers zero unnecessary frame captures.
- **T2-F37-02 (Upward Scroll Rejection)**: User scrolling upwards does not stitch inverted backwards content.
- **T2-F37-03 (Rapid Scroll Flick)**: Rapid trackpad flick buffers frames without dropping displacement.
- **T2-F37-04 (Horizontal Scroll Rejection)**: Sideways horizontal scroll movement is ignored in vertical stitcher.
- **T2-F37-05 (Manual Done After 1 Frame)**: Completing after only 1 frame exports standard single-frame screenshot.

### Feature 38: Live Stitched Preview Boundaries
- **T2-F38-01 (Extreme Height 20,000px Preview)**: Downscaling 20,000px tall image to preview thumbnail maintains aspect ratio.
- **T2-F38-02 (Preview Window Draggable)**: Preview window can be moved by user if it obscures content.
- **T2-F38-03 (Display Edge Clamping)**: Preview window clamps inside screen visible frame.
- **T2-F38-04 (Zero-Frame Initial State)**: Displays clean initial placeholder before first stitch occurs.
- **T2-F38-05 (Memory Efficient Downscaling)**: Thumbnail generation uses low-overhead ImageIO downsampling.

### Feature 39: Scrollbar Strip Exclusion Boundaries
- **T2-F39-01 (Overlay Scrollbars Disabled)**: Functions identically on systems with macOS "Always show scrollbars" setting.
- **T2-F39-02 (Narrow Selection Box 100px)**: Clamps scrollbar exclusion width so search area never drops below 50% width.
- **T2-F39-03 (Zero Scrollbar Strip Width)**: Setting strip width to 0 evaluates full width.
- **T2-F39-04 (Dark and Light Scrollbars)**: Ignores scrollbar thumb regardless of dark or light theme appearance.
- **T2-F39-05 (Custom Web Scrollbars)**: Excludes custom CSS scrollbars located on right edge.

### Feature 40: Sticky Header Detection Boundaries
- **T2-F40-01 (Variable Height Sticky Header)**: Accurately identifies sticky header heights ranging from 20px to 150px.
- **T2-F40-02 (Semi-Transparent Sticky Header)**: Detects sticky header with blur/transparency backdrop.
- **T2-F40-03 (Zero Sticky Header Presence)**: Page with zero fixed elements matches top rows with 0 duplicate stripping.
- **T2-F40-04 (Animating Sticky Header)**: Handles header that shrinks on scroll gracefully.
- **T2-F40-05 (Sticky Header Taller Than Half Viewport)**: Clamps header deduplication to safe ceiling (`headerDedupHeight`).

### Feature 41: Sticky Footer Detection Boundaries
- **T2-F41-01 (Sticky Cookie Banner)**: Detects and deduplicates fixed cookie notice bar at bottom of frame.
- **T2-F41-02 (Floating Action Button at Bottom)**: Identifies stationary floating button without removing scrolling body.
- **T2-F41-03 (Zero Sticky Footer Presence)**: Page with zero bottom fixed elements stitches normal scrolling content.
- **T2-F41-04 (Footer Height Exceeds Boundary)**: Clamps footer deduplication to safe ceiling (`footerDedupHeight`).
- **T2-F41-05 (Dismissed Banner Mid-Scroll)**: Handles cookie banner dismissed mid-scroll cleanly.

### Feature 42: Vertical Overlap Matching Boundaries
- **T2-F42-01 (Identical Successive Frames)**: Successive identical frames yield offset delta 0.
- **T2-F42-02 (Completely Dissimilar Frames)**: Frames with zero visual correlation trigger failure or fallback.
- **T2-F42-03 (Repetitive Patterned Content)**: Code or table rows with repeating line heights resolve correct global offset.
- **T2-F42-04 (Solid White Page Content)**: Blank whitespace content avoids false positive offsets.
- **T2-F42-05 (1-Pixel Shift Accuracy)**: Accurately detects subtle 1px vertical displacement.

### Feature 43: Auto-Stop on End-of-Page Boundaries
- **T2-F43-01 (Bouncing Overscroll)**: Ignores macOS elastic overscroll bounce at bottom of page.
- **T2-F43-02 (Infinite Scroll Feed)**: Auto-stop defers to `maxScrollHeightPx` when page has infinite lazy loading.
- **T2-F43-03 (Immediate Bottom of Short Page)**: Halts after 2 frames if document is shorter than viewport.
- **T2-F43-04 (Temporary Network Lag)**: Requires 3 consecutive zero-delta frames to prevent premature stop on lag.
- **T2-F43-05 (Clean Canvas Hand-off)**: Ensures final frame seam is flush before opening canvas.

### Feature 44: maxScrollHeightPx Clamp Boundaries
- **T2-F44-01 (Exact Clamp at 15,000 px)**: Final image height never exceeds 15,000px when default clamp is active.
- **T2-F44-02 (Minimum Clamp 5,000 px)**: Clamping at 5,000px halts early on long documents.
- **T2-F44-03 (Maximum Clamp 30,000 px)**: Stitches successfully up to 30,000px without memory exhaustion.
- **T2-F44-04 (Short Document Well Below Clamp)**: 2,000px page finishes at 2,000px without padding to clamp limit.
- **T2-F44-05 (Reaching Clamp Mid-Frame)**: Cuts frame cleanly at exact ceiling pixel height.

### Feature 45: User Done Stop Trigger Boundaries
- **T2-F45-01 (Done Pressed Immediately)**: Pressing Done within 100ms of starting yields valid initial frame.
- **T2-F45-02 (Done Pressed While Event In Flight)**: Cancels in-flight scroll event cleanly.
- **T2-F45-03 (Multiple Rapid Return Presses)**: Multiple Return key presses execute stop once without duplicate transitions.
- **T2-F45-04 (Spacebar in Input Field)**: Spacebar terminates capture only when canvas/overlay has focus.
- **T2-F45-05 (Escape Pressed After Partial Stitch)**: Purges partial stitch frames and restores desktop state.

### Feature 46: Tall Image Scroll Canvas Boundaries
- **T2-F46-01 (Scrolling 30,000px Image)**: Scrolling to bottom of 30,000px image maintains smooth 60fps frame rate.
- **T2-F46-02 (Window Resize)**: Resizing canvas window updates scroll view clipping bounds cleanly.
- **T2-F46-03 (Jump to Top / Bottom Keys)**: Home and End keys scroll directly to top and bottom of tall image.
- **T2-F46-04 (Zoom at 30,000px)**: Zooming tall image to 200% handles memory without exceeding texture bounds.
- **T2-F46-05 (Trackpad Pinch-to-Zoom)**: Smooth pinch gesture adjusts scale dynamically.

### Feature 47: Tall Canvas Vector Annotations Boundaries
- **T2-F47-01 (Annotation Spanning Viewport Boundaries)**: Drawing arrow that begins on-screen and ends scrolled off-screen works cleanly.
- **T2-F47-02 (100 Annotations on Tall Canvas)**: 100 vector objects distributed across 20,000px render without lag.
- **T2-F47-03 (Blur Tool at 15,000px Offset)**: Region blur applies correctly to pixels at deep scroll offsets.
- **T2-F47-04 (Selecting Object While Scrolled)**: Hit-testing translates viewport scroll position to canvas coordinate space accurately.
- **T2-F47-05 (Full Rasterization of Annotated Tall Canvas)**: Exporting composite image produces single valid tall PNG file.

### Feature 48: NSStatusItem Controller Boundaries
- **T2-F48-01 (Rapid Alternating Clicks)**: Alternating left and right clicks toggles popover and menu cleanly without collision.
- **T2-F48-02 (Menu Bar Overflow)**: Functions cleanly when system menu bar has dozens of active items.
- **T2-F48-03 (Status Item Removal on Termination)**: Removes status item cleanly from system status bar on quit.
- **T2-F48-04 (Dark and Light Menu Bar)**: Status icon template adapts to dark and light macOS menu bar styling.
- **T2-F48-05 (Secondary Screen Menu Bar)**: Left-clicking status item on secondary screen opens popover on that screen.

### Feature 49: History Popover View Boundaries
- **T2-F49-01 (Empty History View)**: Renders clean empty state ("No screenshots yet") when history count is 0.
- **T2-F49-02 (100 History Items Scrolling)**: Smooth scrolling through 100 history items with view virtualization.
- **T2-F49-03 (All Pinned Items View)**: History list displays only Pinned section when unpinned history is empty.
- **T2-F49-04 (Deleted Asset File)**: Displays placeholder icon if original image file was manually removed on disk.
- **T2-F49-05 (Popover Height Clamping)**: Popover height clamps to maximum 600pt and scrolls internally.

### Feature 50: Instant History Search Boundaries
- **T2-F50-01 (Search With Regex Meta-Characters)**: Query `"[0-9]+.*?"` treats characters as literal substrings without crashing.
- **T2-F50-02 (Search With 1,000 Characters)**: Very long search query handles safely and returns empty list immediately.
- **T2-F50-03 (Case and Diacritics Invariance)**: Localized query matches accented text regardless of case.
- **T2-F50-04 (Search by Resolution String)**: Query `"1920x1080"` matches all screenshots of that exact dimension.
- **T2-F50-05 (Rapid Typing & Deleting)**: Typing and backspacing fast updates filtered list without stutter.

### Feature 51: Hover Zoom Preview Boundaries
- **T2-F51-01 (Hover Near Screen Right Edge)**: Magnified preview flips to left of popover to avoid extending off-screen.
- **T2-F51-02 (Hover Near Screen Bottom)**: Preview shifts upwards to remain fully visible.
- **T2-F51-03 (Rapid Row Hovering)**: Moving cursor fast across 10 rows updates preview without ghost panels.
- **T2-F51-04 (Hover on Tall Screenshot)**: Tall aspect ratio screenshot preview fits within maximum panel dimensions.
- **T2-F51-05 (Hover on Corrupted Image)**: Displays missing image placeholder without crashing.

### Feature 52: Circular Keyboard Nav Boundaries
- **T2-F52-01 (Navigation on Single-Item List)**: Pressing Up or Down arrow on 1-item list keeps selection on that item.
- **T2-F52-02 (Navigation on Empty List)**: Arrow keys on empty list execute no-op safely.
- **T2-F52-03 (Navigation Through Section Boundaries)**: Down arrow navigates seamlessly from last pinned item to first recent item.
- **T2-F52-04 (Holding Down Arrow Key)**: Key repeat scrolls selection smoothly down list.
- **T2-F52-05 (Selection State Persistence)**: Toggling popover resets selection to top item cleanly.

### Feature 53: 1..9 Quick Select Boundaries
- **T2-F53-01 (Pressing Key 0)**: Key `0` does not trigger selection.
- **T2-F53-02 (Key 1 on Empty List)**: Pressing `1` when list is empty causes no error.
- **T2-F53-03 (Numpad Key 1..9 Equivalents)**: Numpad digits trigger quick selection identically to top-row keys.
- **T2-F53-04 (Modifier + Number Key)**: Cmd+1 or Option+1 is ignored by the quick select row handler.
- **T2-F53-05 (Quick Select During Background Save)**: Selecting item while disk queue is writing executes copy reliably.

### Feature 54: Direct Auto-Paste Service Boundaries
- **T2-F54-01 (Denied AX Permissions)**: Copies to clipboard and displays transient notification without hanging.
- **T2-F54-02 (Target App Is SuperShot Itself)**: Suppresses paste injection if target app is SuperShot.
- **T2-F54-03 (Target App Quits Before Paste)**: Handles target application terminating before synthetic keystroke arrives.
- **T2-F54-04 (Modal Dialog in Target App)**: Pastes safely even if target app is displaying a sheet.
- **T2-F54-05 (High-Frequency Auto-Paste)**: 10 rapid auto-pastes dispatch in orderly sequence without stuck modifier keys.

### Feature 55: Context Menu Boundaries
- **T2-F55-01 (Right-Clicking While Popover Open)**: Closes popover and opens context menu cleanly.
- **T2-F55-02 (Menu Invocation During Screen Capture)**: Disabled or safely handled while capture overlay is active.
- **T2-F55-03 (Clear Unpinned History Confirmation)**: Prompts or executes immediately according to user preference.
- **T2-F55-04 (Quit With Pending Writes)**: Flushes serial file queue to disk before terminating process.
- **T2-F55-05 (Preferences Shortcut Cmd+,)**: Pressing Cmd+, while context menu is open summons Preferences.

### Feature 56: 4-Tab Settings Window Boundaries
- **T2-F56-01 (Re-Opening Settings When Open)**: Brings existing Settings window to front rather than opening duplicate window.
- **T2-F56-02 (Switching Tabs Rapidly)**: Rapidly clicking tabs switches views without view hierarchy leaks.
- **T2-F56-03 (Closing Window via Red Button)**: Closes window cleanly and flushes modified settings.
- **T2-F56-04 (Escape Key in Settings)**: Closes settings window or dismisses focused text field.
- **T2-F56-05 (Permission Status Changes Dynamically)**: Granting Screen Recording in System Settings updates badge dynamically.

### Feature 57: Flexible Save Modes Boundaries
- **T2-F57-01 (File Name Collision)**: If file `SuperShot_1.png` exists, automatically increments to `SuperShot_2.png`.
- **T2-F57-02 (Destination Folder Removed)**: Re-creates destination folder or falls back to Desktop.
- **T2-F57-03 (JPEG Compression 0.1 vs 1.0)**: Supports minimum and maximum JPEG quality settings.
- **T2-F57-04 (Saving Massive 30,000px Image)**: Writes huge image to disk without exhausting memory buffer.
- **T2-F57-05 (Disk Quota Exceeded on Save)**: Displays user-friendly alert if disk runs out of space.

### Feature 58: Launch at Login Boundaries
- **T2-F58-01 (Register When Already Registered)**: Idempotent call leaves login item registered cleanly.
- **T2-F58-02 (Unregister When Not Registered)**: Idempotent call causes no error.
- **T2-F58-03 (App Moved to Different Directory)**: Updates login item reference to new application path.
- **T2-F58-04 (Sandboxed Environment Permission)**: Operates within macOS sandbox rules via `SMAppService`.
- **T2-F58-05 (System Service Unavailable)**: Handles failure of `SMAppService` with informative status notice.

### Feature 59: Documentation Sync Boundaries
- **T2-F59-01 (Markdown Syntax Integrity)**: README.md parses valid Markdown without broken formatting tags.
- **T2-F59-02 (Links Validity)**: All relative and absolute links in documentation resolve properly.
- **T2-F59-03 (Table Alignment)**: Markdown feature tables align columns cleanly.
- **T2-F59-04 (Zero Emojis in All Language Sections)**: English and Vietnamese sections contain 0 emojis.
- **T2-F59-05 (Accuracy of CLI Flags)**: All documented Makefile arguments match executable rules.

### Feature 60: E2E Regression Pass Boundaries
- **T2-F60-01 (Single Test Suite Failure)**: If 1 out of 600 tests fails, runner returns non-zero exit code immediately.
- **T2-F60-02 (Adversarial Stress Runner)**: Handles 1,000 rapid image operations in adversarial mode.
- **T2-F60-03 (Memory Leak Detection)**: Verifies process RSS does not grow unboundedly after 1,000 capture/stitch cycles.
- **T2-F60-04 (Zero Zombie Windows)**: Confirms 0 leftover borderless windows or panels in window server.
- **T2-F60-05 (Rosetta 2 x86_64 Verification)**: Full regression pass executes with 100% pass rate under Rosetta 2 translation.

---

## 5. Tier 3: Pairwise Combinations & Cross-Feature Interactions

Total Pairwise Suites: **30 interaction scenarios**.

| ID | Feature A | Feature B | Interaction Scenario & Expected Verification Behavior |
|---|---|---|---|
| T3-P01 | F05 (ColorPreset) | F21 (Select/Move) | Selecting an existing vector rectangle and clicking a color preset swatch updates the object's color immediately and updates active color. |
| T3-P02 | F06 (Preset Persistence) | F32 (Custom Hex) | Saving a custom hex preset via popover persists to `AppSettings` and survives cold restart of application. |
| T3-P03 | F09 (StorageManager) | F11 (Pinned Protection) | Adding 50 unpinned screenshots past capacity preserves all pinned items while evicting oldest unpinned items in strict FIFO order. |
| T3-P04 | F10 (In-Memory Cache) | F09 (StorageManager) | Loading an image populates `NSCache`; subsequent deletion removes the image from both disk and in-memory cache. |
| T3-P05 | F11 (Pinned Protection) | F49 (History Popover) | History popover displays pinned screenshots in dedicated top "Pinned" section and persists across clear unpinned history action. |
| T3-P06 | F12 (Localization) | F49 (History Popover) | Switching language dynamically updates all UI strings in `MainShotView` (buttons, headers, empty states) without restart. |
| T3-P07 | F13 (HotKeyManager) | F15 (Retina Freeze) | Triggering `Option + S` freezes active screen at 2x resolution and presents selection overlay within 50ms. |
| T3-P08 | F13 (HotKeyManager) | F36 (Scroll Synthesizer) | Triggering `Option + Shift + S` initiates scrolling capture directly with auto-scroll active at selection center. |
| T3-P09 | F17 (Outside Dimming) | F18 (8-Handle Box) | Resizing selection box via any of the 8 grab handles dynamically updates the clear cutout region in the dimming overlay at 60fps. |
| T3-P10 | F18 (8-Handle Box) | F19 (Dimension Badge) | Live dimension badge updates text `"<W> x <H> px"` in real time as selection box is dragged or resized. |
| T3-P11 | F18 (8-Handle Box) | F20 (Edge Repositioning) | When selection box is moved adjacent to display edges, floating toolbars flip to opposite sides without overlapping selection. |
| T3-P12 | F22 (Rectangle) | F30 (Undo/Redo) | Drawing a rectangle, clicking Undo removes the rectangle; clicking Redo restores it with identical dimensions and color. |
| T3-P13 | F28 (Editable Text) | F07 (AppSettings) | Creating a new text annotation uses `activeFontSize` and `activeColorHex` from `AppSettings` as initial formatting. |
| T3-P14 | F29 (Region Blur) | F35 (Rasterizer) | Compositing a screenshot containing a region blur applies pixelation filter over underlying image in exported file. |
| T3-P15 | F31 (Color Swatch) | F26 (Freehand Pen) | Clicking a color preset updates active drawing color; subsequent pen strokes render with new color. |
| T3-P16 | F33 (Eyedropper) | F05 (ColorPreset) | Sampling a pixel on screen with eyedropper converts RGB to `#RRGGBB` hex string and allows saving to favorite presets. |
| T3-P17 | F34 (Action Toolbar) | F35 (Rasterizer) | Clicking Copy button on toolbar triggers high-fidelity rasterizer and writes composite `CGImage` to `NSPasteboard.general`. |
| T3-P18 | F36 (Scroll Synthesizer) | F38 (Stitched Preview) | Each synthesized scroll step captures a frame, matches overlap, and updates live stitched thumbnail and height badge. |
| T3-P19 | F39 (Scrollbar Exclusion) | F42 (Overlap Matcher) | Right-edge 24px scrollbar is excluded from correlation calculation, preventing moving scrollbar thumb from corrupting vertical seam matching. |
| T3-P20 | F40 (Sticky Header Dedup) | F42 (Overlap Matcher) | Stationary header at top of scrolling frame is detected and deduplicated, appearing exactly once in stitched result. |
| T3-P21 | F41 (Sticky Footer Dedup) | F42 (Overlap Matcher) | Stationary footer at bottom of scrolling frame is detected and deduplicated, appearing exactly once at bottom of stitched result. |
| T3-P22 | F43 (Auto-Stop on End) | F46 (Tall Scroll Canvas) | Auto-stop on reaching page bottom terminates scrolling and automatically opens tall stitched image in `ScrollableAnnotationCanvas`. |
| T3-P23 | F44 (Max Height Clamp) | F36 (Scroll Synthesizer) | Reaching `maxScrollHeightPx` (e.g. 15,000px) immediately stops scroll event synthesis and transitions to canvas. |
| T3-P24 | F46 (Tall Canvas) | F47 (Tall Annotations) | Annotations added to tall image canvas scroll synchronously with image content and maintain correct coordinate offsets. |
| T3-P25 | F48 (StatusItem) | F55 (Context Menu) | Right-clicking status item opens context menu with Take Screenshot, Preferences, Clear History, and Quit items. |
| T3-P26 | F50 (Instant Search) | F53 (1..9 Quick Select) | Typing a search query filters history list; pressing `1` immediately selects and copies 1st visible filtered result. |
| T3-P27 | F51 (Hover Zoom) | F52 (Circular Nav) | Navigating with Up/Down arrow keys updates active row and updates floating hover zoom preview panel smoothly. |
| T3-P28 | F54 (Auto-Paste Service) | F49 (History Popover) | Selecting screenshot from history writes image to clipboard and injects synthetic Cmd+V into previous active app if AX is granted. |
| T3-P29 | F56 (4-Tab Settings) | F57 (Flexible Save) | Changing save mode in Settings to auto-save and selecting custom directory causes subsequent captures to auto-save directly. |
| T3-P30 | F58 (Launch at Login) | F56 (4-Tab Settings) | Toggling Launch at Login switch in Settings registers app with `SMAppService` and updates displayed state. |

---

## 6. Tier 4: Real-World Application Workload Scenarios (>=5 Scenarios)

### Scenario 1: Developer Bug Report & Code Annotation Workflow
- **Realistic Workload**:
  - Developer triggers in-place capture via `Option + S` over an IDE displaying a Swift compile error.
  - Drags 8-handle selection box around the code error and terminal output (1440x800 px).
  - Selects Rectangle tool with Red preset (`#FF3B30`, stroke width 3.0pt) to highlight failing code line.
  - Selects Arrow tool to draw pointer from error description to line number.
  - Selects In-place Editable Text tool (`activeFontSize = 16pt`) and types `"Fix race condition here"`.
  - Selects Region Blur tool to redact sensitive API token in the console log.
  - Presses `Cmd + Z` to undo text, retypes revised note, presses `Cmd + Shift + Z` to verify redo stack.
  - Clicks Copy to Clipboard (`Cmd + C`), dismisses overlay.
- **Verification Criteria**:
  - Overlay opens in < 50ms at 2x Retina resolution.
  - All 4 vector objects (rectangle, arrow, text, blur) composite cleanly without raster distortion.
  - API token under blur region is 100% illegible.
  - Composite image written to pasteboard with correct dimensions and color fidelity.
  - Shot record saved to history with thumbnail and metadata.

### Scenario 2: Web Designer Long-Page Scrolling & Vector Annotation
- **Realistic Workload**:
  - Designer opens full-page documentation site in Safari.
  - Triggers scrolling capture via `Option + Shift + S` or toolbar button.
  - Auto-scroll captures 40 vertical frames across 12,000 px tall page.
  - Page features 60px fixed sticky navigation header and 24px right scrollbar.
  - Live Stitched Preview displays progressive thumbnail and updating height badge (`1280 x 12000 px`).
  - Auto-stop halts scrolling when end-of-page zero delta is detected.
  - Tall image opens in `ScrollableAnnotationCanvas`.
  - Designer scrolls to offset 8,000 px and applies Highlighter tool over a paragraph.
  - Designer scrolls to offset 11,500 px and places a Rectangle around a footer link.
  - Saves screenshot to file via `Cmd + S` in PNG format.
- **Verification Criteria**:
  - Sticky header appears exactly once at top of stitched image and is not repeated throughout the 12,000 px height.
  - Right-edge scrollbar strip does not introduce seam artifacts.
  - Seam matching is pixel-perfect with zero duplicate or skipped text lines.
  - Total stitched height matches cumulative document height.
  - Exported PNG file opens and verifies with resolution `1280 x 12000 px`.

### Scenario 3: Security & Compliance Auditor Redaction Session
- **Realistic Workload**:
  - Security auditor performs rapid-fire captures of 20 confidential audit logs.
  - For each capture:
    - Draws selection box over sensitive credential dump.
    - Draws 5 distinct Region Blur rectangles over passwords, credit cards, IP addresses, and private keys.
    - Selects Black preset (`#000000`) and draws solid redaction rectangles over names.
    - Copies each redacted image to pasteboard and saves to disk.
  - Auditor pins the 3 most critical compliance breach screenshots in history popover.
  - Auditor clicks "Clear unpinned history" in context menu.
- **Verification Criteria**:
  - Every blurred and blacked-out region has 0% plaintext visual recovery.
  - History retains exactly the 3 pinned screenshots; 17 unpinned screenshots are completely deleted from disk and memory.
  - Disk assets for the 17 unpinned items are purged from `shots/` and `thumbnails/`.
  - The 3 pinned items reload with full image fidelity and correct metadata.

### Scenario 4: Power User Keyboard-Only Multi-Monitor Capture & History Workflow
- **Realistic Workload**:
  - Power user operates dual-monitor setup (built-in Retina 2560x1600 + external 3840x2160).
  - Cursor is on external display; presses `Option + S`.
  - Overlay correctly summons on external display.
  - User selects region, presses Return key to copy.
  - User summons History Popover by left-clicking menu bar or hotkey.
  - Automatically focused search field receives immediate keyboard input `"error"`.
  - Filtered list presents 4 matching screenshots.
  - User presses Down arrow twice to navigate to 2nd item, then presses `2` to quick-select.
  - AutoPasteService injects Cmd+V into previous active Slack window.
- **Verification Criteria**:
  - Multi-monitor coordinate translation places overlay and toolbars on active screen.
  - Search filtering executes in < 5ms per keystroke.
  - Quick-select key `2` copies exact 2nd filtered screenshot to clipboard.
  - Synthetic Cmd+V pastes image into target application without modal hangs.
  - Zero emojis present across search UI, badges, and status items.

### Scenario 5: High-Frequency Rapid Capture Burst & Storage Eviction Stress
- **Realistic Workload**:
  - Automated stress simulation generates 100 rapid screenshot capture events in under 10 seconds.
  - Mix of standard captures (800x600 px) and tall scrolling captures (1200x5000 px).
  - StorageManager capacity is configured to 25 items.
  - 5 items are pinned during ingestion at items 10, 20, 30, 40, 50.
  - Concurrent background file queue writes images and generates downscaled thumbnails.
  - Application undergoes sudden simulated restart.
  - StorageManager cold re-initializes from disk metadata.
- **Verification Criteria**:
  - StorageManager handles 100 rapid saves without deadlocks or thread crashes.
  - Unpinned storage strictly caps at configured capacity 25.
  - All 5 pinned items survive capacity overflow eviction.
  - Total items post-eviction = 30 (25 unpinned + 5 pinned).
  - Cold restart recovers all 30 items with 100% metadata schema integrity.
  - In-memory `NSCache` correctly manages memory pressure without out-of-memory errors.

---

## 7. Execution Harness & Toolchain Verification

### 7.1 Automated Verification Suite Execution
To execute the automated verification runner, static emoji scanner, and headless test suites:
```bash
make test
```
Or directly via shell script:
```bash
./Scripts/verify.sh
```

### 7.2 Static Zero-Emoji Scanner
```bash
python3 Scripts/lint_emojis.py Sources/ Tests/ Scripts/ Makefile Package.swift README.md LICENSE
```

### 7.3 Standalone Programmatic Verification Runner Compilation
```bash
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk swiftc \
  -target "$(uname -m)-apple-macos13.0" \
  -I .build/modules \
  -L .build/lib \
  -lSuperShotCore \
  -Xlinker -rpath -Xlinker .build/lib \
  -parse-as-library \
  -O \
  Tests/Common/TestHarness.swift \
  Tests/SuperShotCoreTests/*.swift \
  Tests/VerificationRunner/main.swift \
  -o SuperShotVerifier
./SuperShotVerifier
```

### 7.4 Universal 2 Bundle and App Verification
```bash
make verify-app
```
Runs 8-step verification checking Mach-O headers (`lipo -archs`), embedded dylibs, inside-out codesigning, `LSUIElement` in `Info.plist`, and dual-architecture headless launch.
