# ==============================================================================
# SuperShot Makefile
# Native macOS Menu Bar Screenshot, Scrolling Capture & Vector Annotation App
# ==============================================================================

APP_NAME = SuperShot
BUNDLE_NAME = $(APP_NAME).app
BUNDLE_DIR = $(BUNDLE_NAME)/Contents
MACOS_DIR = $(BUNDLE_DIR)/MacOS
FRAMEWORKS_DIR = $(BUNDLE_DIR)/Frameworks
RESOURCES_DIR = $(BUNDLE_DIR)/Resources
BUILD_DIR = .build

# Detect or select a valid SDK supporting both arm64 and x86_64
ifneq ($(wildcard /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk),)
    SDK_PATH := /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
else ifneq ($(wildcard /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk),)
    SDK_PATH := /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
else
    SDK_PATH := $(shell xcrun --show-sdk-path)
endif
export SDKROOT := $(SDK_PATH)

SWIFTC = swiftc
SWIFT = swift
PYTHON = python3
CODESIGN = codesign
INSTALL_NAME_TOOL = install_name_tool
LIPO = lipo

# Architecture targets (Universal 2: Apple Silicon arm64 + Intel x86_64)
TARGET_ARM64 = arm64-apple-macos13.0
TARGET_X86_64 = x86_64-apple-macos13.0
HOST_ARCH = $(shell uname -m)
TARGET_HOST = $(HOST_ARCH)-apple-macos13.0
VERSION = 1.0.29
BUILD_NUMBER = 29
PACKAGE_ZIP = SuperShot-v$(VERSION).zip
PACKAGE_DMG = SuperShot-v$(VERSION).dmg
DMG_STAGING_DIR = $(BUILD_DIR)/dmg-staging

# Source file discovery
CORE_SRCS = $(shell find Sources/SuperShotCore -name '*.swift' 2>/dev/null)
APP_SRCS  = $(shell find Sources/SuperShot -name '*.swift' 2>/dev/null)
ALL_SRCS  = $(CORE_SRCS) $(APP_SRCS)

# Compiler flags
SWIFTC_FLAGS_COMMON = -sdk $(SDKROOT)
SWIFTC_FLAGS_DEBUG  = $(SWIFTC_FLAGS_COMMON) -g -Onone
SWIFTC_FLAGS_RELEASE= $(SWIFTC_FLAGS_COMMON) -O -whole-module-optimization

.PHONY: all build release bundle app package icon verify-app test verify lint clean help adversarial dmg

all: build

help:
	@echo "SuperShot Build System Targets:"
	@echo "  make build       - Compile debug dylib and binary artifacts"
	@echo "  make release     - Compile optimized release artifacts"
	@echo "  make icon        - Programmatically generate AppIcon.icns"
	@echo "  make app         - Assemble and codesign standalone SuperShot.app bundle"
	@echo "  make bundle      - Assemble and codesign standalone SuperShot.app bundle (alias for app)"
	@echo "  make package     - Assemble, codesign, and package Universal 2 zip archive"
	@echo "  make dmg         - Assemble and package Universal 2 DMG disk image"
	@echo "  make verify-app  - Verify SuperShot.app bundle integrity & headless launch"
	@echo "  make lint        - Verify strict 0-emoji constraint"
	@echo "  make test        - Run automated test suite"
	@echo "  make verify      - Run programmatic verification runner"
	@echo "  make adversarial - Run adversarial stress test suite"
	@echo "  make clean       - Remove build artifacts and app bundle"

# Compile Debug Binary / Module (Universal 2: arm64 + x86_64)
build: lint
	@if [ -f $(BUILD_DIR)/modules/SuperShotCore.swiftmodule ]; then rm -f $(BUILD_DIR)/modules/SuperShotCore.swiftmodule; fi
	@if [ -f $(BUILD_DIR)/modules/SuperShot.swiftmodule ]; then rm -f $(BUILD_DIR)/modules/SuperShot.swiftmodule; fi
	@mkdir -p $(BUILD_DIR)/modules/SuperShotCore.swiftmodule $(BUILD_DIR)/modules/SuperShot.swiftmodule
	@mkdir -p $(BUILD_DIR)/lib/arm64 $(BUILD_DIR)/lib/x86_64 $(BUILD_DIR)/bin/arm64 $(BUILD_DIR)/bin/x86_64
	@if [ -n "$(CORE_SRCS)" ]; then \
		echo "Compiling SuperShotCore slices (Debug)..."; \
		$(SWIFTC) $(SWIFTC_FLAGS_DEBUG) -target $(TARGET_ARM64) \
			-emit-library \
			-emit-module -emit-module-path $(BUILD_DIR)/modules/SuperShotCore.swiftmodule/arm64-apple-macos.swiftmodule \
			-module-name SuperShotCore \
			-parse-as-library \
			-Xlinker -install_name -Xlinker @rpath/libSuperShotCore.dylib \
			$(CORE_SRCS) \
			-o $(BUILD_DIR)/lib/arm64/libSuperShotCore.dylib; \
		$(SWIFTC) $(SWIFTC_FLAGS_DEBUG) -target $(TARGET_X86_64) \
			-emit-library \
			-emit-module -emit-module-path $(BUILD_DIR)/modules/SuperShotCore.swiftmodule/x86_64-apple-macos.swiftmodule \
			-module-name SuperShotCore \
			-parse-as-library \
			-Xlinker -install_name -Xlinker @rpath/libSuperShotCore.dylib \
			$(CORE_SRCS) \
			-o $(BUILD_DIR)/lib/x86_64/libSuperShotCore.dylib; \
		echo "Merging SuperShotCore dynamic library with lipo..."; \
		$(LIPO) -create -output $(BUILD_DIR)/lib/libSuperShotCore.dylib \
			$(BUILD_DIR)/lib/arm64/libSuperShotCore.dylib \
			$(BUILD_DIR)/lib/x86_64/libSuperShotCore.dylib; \
	fi
	@if [ -n "$(APP_SRCS)" ]; then \
		echo "Compiling SuperShot module slices (Debug)..."; \
		$(SWIFTC) $(SWIFTC_FLAGS_DEBUG) -target $(TARGET_ARM64) \
			-emit-library \
			-emit-module -emit-module-path $(BUILD_DIR)/modules/SuperShot.swiftmodule/arm64-apple-macos.swiftmodule \
			-module-name SuperShot \
			-parse-as-library \
			-I $(BUILD_DIR)/modules \
			-L $(BUILD_DIR)/lib/arm64 \
			-lSuperShotCore \
			-Xlinker -install_name -Xlinker @rpath/libSuperShot.dylib \
			$(APP_SRCS) \
			-o $(BUILD_DIR)/lib/arm64/libSuperShot.dylib; \
		$(SWIFTC) $(SWIFTC_FLAGS_DEBUG) -target $(TARGET_X86_64) \
			-emit-library \
			-emit-module -emit-module-path $(BUILD_DIR)/modules/SuperShot.swiftmodule/x86_64-apple-macos.swiftmodule \
			-module-name SuperShot \
			-parse-as-library \
			-I $(BUILD_DIR)/modules \
			-L $(BUILD_DIR)/lib/x86_64 \
			-lSuperShotCore \
			-Xlinker -install_name -Xlinker @rpath/libSuperShot.dylib \
			$(APP_SRCS) \
			-o $(BUILD_DIR)/lib/x86_64/libSuperShot.dylib; \
		echo "Merging SuperShot module library with lipo..."; \
		$(LIPO) -create -output $(BUILD_DIR)/lib/libSuperShot.dylib \
			$(BUILD_DIR)/lib/arm64/libSuperShot.dylib \
			$(BUILD_DIR)/lib/x86_64/libSuperShot.dylib; \
	fi
	@if [ -n "$(APP_SRCS)" ] && grep -r -q '@main' Sources/SuperShot 2>/dev/null; then \
		echo "Compiling $(APP_NAME) executable slices (Debug)..."; \
		$(SWIFTC) $(SWIFTC_FLAGS_DEBUG) -target $(TARGET_ARM64) \
			-I $(BUILD_DIR)/modules \
			-L $(BUILD_DIR)/lib/arm64 \
			-lSuperShotCore \
			-Xlinker -rpath -Xlinker $(BUILD_DIR)/lib \
			-parse-as-library \
			$(APP_SRCS) \
			-o $(BUILD_DIR)/bin/arm64/$(APP_NAME); \
		$(SWIFTC) $(SWIFTC_FLAGS_DEBUG) -target $(TARGET_X86_64) \
			-I $(BUILD_DIR)/modules \
			-L $(BUILD_DIR)/lib/x86_64 \
			-lSuperShotCore \
			-Xlinker -rpath -Xlinker $(BUILD_DIR)/lib \
			-parse-as-library \
			$(APP_SRCS) \
			-o $(BUILD_DIR)/bin/x86_64/$(APP_NAME); \
		echo "Merging $(APP_NAME) executable with lipo..."; \
		$(LIPO) -create -output $(BUILD_DIR)/bin/$(APP_NAME) \
			$(BUILD_DIR)/bin/arm64/$(APP_NAME) \
			$(BUILD_DIR)/bin/x86_64/$(APP_NAME); \
	fi
	@echo "Build complete."

# Compile Release Binary / Module (Universal 2: arm64 + x86_64)
release: lint
	@if [ -f $(BUILD_DIR)/modules/SuperShotCore.swiftmodule ]; then rm -f $(BUILD_DIR)/modules/SuperShotCore.swiftmodule; fi
	@if [ -f $(BUILD_DIR)/modules/SuperShot.swiftmodule ]; then rm -f $(BUILD_DIR)/modules/SuperShot.swiftmodule; fi
	@mkdir -p $(BUILD_DIR)/modules/SuperShotCore.swiftmodule $(BUILD_DIR)/modules/SuperShot.swiftmodule
	@mkdir -p $(BUILD_DIR)/lib/arm64 $(BUILD_DIR)/lib/x86_64 $(BUILD_DIR)/bin/arm64 $(BUILD_DIR)/bin/x86_64
	@if [ -n "$(CORE_SRCS)" ]; then \
		echo "Compiling SuperShotCore slices (Release)..."; \
		$(SWIFTC) $(SWIFTC_FLAGS_RELEASE) -target $(TARGET_ARM64) \
			-emit-library \
			-emit-module -emit-module-path $(BUILD_DIR)/modules/SuperShotCore.swiftmodule/arm64-apple-macos.swiftmodule \
			-module-name SuperShotCore \
			-parse-as-library \
			-Xlinker -install_name -Xlinker @rpath/libSuperShotCore.dylib \
			$(CORE_SRCS) \
			-o $(BUILD_DIR)/lib/arm64/libSuperShotCore.dylib; \
		$(SWIFTC) $(SWIFTC_FLAGS_RELEASE) -target $(TARGET_X86_64) \
			-emit-library \
			-emit-module -emit-module-path $(BUILD_DIR)/modules/SuperShotCore.swiftmodule/x86_64-apple-macos.swiftmodule \
			-module-name SuperShotCore \
			-parse-as-library \
			-Xlinker -install_name -Xlinker @rpath/libSuperShotCore.dylib \
			$(CORE_SRCS) \
			-o $(BUILD_DIR)/lib/x86_64/libSuperShotCore.dylib; \
		echo "Merging SuperShotCore dynamic library with lipo..."; \
		$(LIPO) -create -output $(BUILD_DIR)/lib/libSuperShotCore.dylib \
			$(BUILD_DIR)/lib/arm64/libSuperShotCore.dylib \
			$(BUILD_DIR)/lib/x86_64/libSuperShotCore.dylib; \
	fi
	@if [ -n "$(APP_SRCS)" ]; then \
		echo "Compiling SuperShot module slices (Release)..."; \
		$(SWIFTC) $(SWIFTC_FLAGS_RELEASE) -target $(TARGET_ARM64) \
			-emit-library \
			-emit-module -emit-module-path $(BUILD_DIR)/modules/SuperShot.swiftmodule/arm64-apple-macos.swiftmodule \
			-module-name SuperShot \
			-parse-as-library \
			-I $(BUILD_DIR)/modules \
			-L $(BUILD_DIR)/lib/arm64 \
			-lSuperShotCore \
			-Xlinker -install_name -Xlinker @rpath/libSuperShot.dylib \
			$(APP_SRCS) \
			-o $(BUILD_DIR)/lib/arm64/libSuperShot.dylib; \
		$(SWIFTC) $(SWIFTC_FLAGS_RELEASE) -target $(TARGET_X86_64) \
			-emit-library \
			-emit-module -emit-module-path $(BUILD_DIR)/modules/SuperShot.swiftmodule/x86_64-apple-macos.swiftmodule \
			-module-name SuperShot \
			-parse-as-library \
			-I $(BUILD_DIR)/modules \
			-L $(BUILD_DIR)/lib/x86_64 \
			-lSuperShotCore \
			-Xlinker -install_name -Xlinker @rpath/libSuperShot.dylib \
			$(APP_SRCS) \
			-o $(BUILD_DIR)/lib/x86_64/libSuperShot.dylib; \
		echo "Merging SuperShot module library with lipo..."; \
		$(LIPO) -create -output $(BUILD_DIR)/lib/libSuperShot.dylib \
			$(BUILD_DIR)/lib/arm64/libSuperShot.dylib \
			$(BUILD_DIR)/lib/x86_64/libSuperShot.dylib; \
	fi
	@if [ -n "$(APP_SRCS)" ] && grep -r -q '@main' Sources/SuperShot 2>/dev/null; then \
		echo "Compiling $(APP_NAME) binary slices (Release)..."; \
		$(SWIFTC) $(SWIFTC_FLAGS_RELEASE) -target $(TARGET_ARM64) \
			-I $(BUILD_DIR)/modules \
			-L $(BUILD_DIR)/lib/arm64 \
			-lSuperShotCore \
			-Xlinker -rpath -Xlinker $(BUILD_DIR)/lib \
			-parse-as-library \
			$(APP_SRCS) \
			-o $(BUILD_DIR)/bin/arm64/$(APP_NAME); \
		$(SWIFTC) $(SWIFTC_FLAGS_RELEASE) -target $(TARGET_X86_64) \
			-I $(BUILD_DIR)/modules \
			-L $(BUILD_DIR)/lib/x86_64 \
			-lSuperShotCore \
			-Xlinker -rpath -Xlinker $(BUILD_DIR)/lib \
			-parse-as-library \
			$(APP_SRCS) \
			-o $(BUILD_DIR)/bin/x86_64/$(APP_NAME); \
		echo "Merging $(APP_NAME) executable with lipo..."; \
		$(LIPO) -create -output $(BUILD_DIR)/bin/$(APP_NAME) \
			$(BUILD_DIR)/bin/arm64/$(APP_NAME) \
			$(BUILD_DIR)/bin/x86_64/$(APP_NAME); \
	fi
	@echo "Release build complete."

# Programmatic App Icon Generation
icon: $(BUILD_DIR)/Resources/AppIcon.icns

$(BUILD_DIR)/Resources/AppIcon.icns: Scripts/generate_icon.swift
	@mkdir -p $(BUILD_DIR)/Resources $(BUILD_DIR)/bin
	@echo "Generating SuperShot AppIcon.icns..."
	$(SWIFTC) $(SWIFTC_FLAGS_COMMON) -target $(TARGET_HOST) Scripts/generate_icon.swift -o $(BUILD_DIR)/bin/generate_icon
	$(BUILD_DIR)/bin/generate_icon $@
	@echo "AppIcon generation complete: $@"

# Standalone Application Bundle Packaging (Universal 2: arm64 + x86_64)
app: lint icon
	@echo "Packaging SuperShot.app standalone application bundle..."
	@mkdir -p $(MACOS_DIR) $(FRAMEWORKS_DIR) $(RESOURCES_DIR)
	@if [ -f $(BUILD_DIR)/modules/SuperShotCore.swiftmodule ]; then rm -f $(BUILD_DIR)/modules/SuperShotCore.swiftmodule; fi
	@if [ -f $(BUILD_DIR)/modules/SuperShot.swiftmodule ]; then rm -f $(BUILD_DIR)/modules/SuperShot.swiftmodule; fi
	@mkdir -p $(BUILD_DIR)/modules/SuperShotCore.swiftmodule $(BUILD_DIR)/modules/SuperShot.swiftmodule
	@mkdir -p $(BUILD_DIR)/lib/arm64 $(BUILD_DIR)/lib/x86_64 $(BUILD_DIR)/bin/arm64 $(BUILD_DIR)/bin/x86_64
	@echo "Compiling SuperShotCore dynamic library slices (arm64 + x86_64)..."
	$(SWIFTC) $(SWIFTC_FLAGS_RELEASE) -target $(TARGET_ARM64) \
		-emit-library \
		-emit-module -emit-module-path $(BUILD_DIR)/modules/SuperShotCore.swiftmodule/arm64-apple-macos.swiftmodule \
		-module-name SuperShotCore \
		-parse-as-library \
		-Xlinker -install_name -Xlinker @rpath/libSuperShotCore.dylib \
		$(CORE_SRCS) \
		-o $(BUILD_DIR)/lib/arm64/libSuperShotCore.dylib
	$(SWIFTC) $(SWIFTC_FLAGS_RELEASE) -target $(TARGET_X86_64) \
		-emit-library \
		-emit-module -emit-module-path $(BUILD_DIR)/modules/SuperShotCore.swiftmodule/x86_64-apple-macos.swiftmodule \
		-module-name SuperShotCore \
		-parse-as-library \
		-Xlinker -install_name -Xlinker @rpath/libSuperShotCore.dylib \
		$(CORE_SRCS) \
		-o $(BUILD_DIR)/lib/x86_64/libSuperShotCore.dylib
	@echo "Merging SuperShotCore dynamic library with lipo..."
	$(LIPO) -create -output $(BUILD_DIR)/lib/libSuperShotCore.dylib \
		$(BUILD_DIR)/lib/arm64/libSuperShotCore.dylib \
		$(BUILD_DIR)/lib/x86_64/libSuperShotCore.dylib
	@if [ -n "$(APP_SRCS)" ]; then \
		echo "Compiling SuperShot standalone executable slices (arm64 + x86_64)..."; \
		$(SWIFTC) $(SWIFTC_FLAGS_RELEASE) -target $(TARGET_ARM64) \
			-I $(BUILD_DIR)/modules \
			-L $(BUILD_DIR)/lib/arm64 \
			-lSuperShotCore \
			-parse-as-library \
			-Xlinker -rpath -Xlinker @executable_path/../Frameworks \
			$(APP_SRCS) \
			-o $(BUILD_DIR)/bin/arm64/$(APP_NAME); \
		$(SWIFTC) $(SWIFTC_FLAGS_RELEASE) -target $(TARGET_X86_64) \
			-I $(BUILD_DIR)/modules \
			-L $(BUILD_DIR)/lib/x86_64 \
			-lSuperShotCore \
			-parse-as-library \
			-Xlinker -rpath -Xlinker @executable_path/../Frameworks \
			$(APP_SRCS) \
			-o $(BUILD_DIR)/bin/x86_64/$(APP_NAME); \
		echo "Merging SuperShot standalone executable with lipo..."; \
		$(LIPO) -create -output $(MACOS_DIR)/$(APP_NAME) \
			$(BUILD_DIR)/bin/arm64/$(APP_NAME) \
			$(BUILD_DIR)/bin/x86_64/$(APP_NAME); \
		chmod 755 $(MACOS_DIR)/$(APP_NAME); \
	else \
		echo "Notice: No App sources in Sources/SuperShot yet. Skipping standalone binary compilation."; \
	fi
	@echo "Installing dynamic framework into bundle..."
	@cp -f $(BUILD_DIR)/lib/libSuperShotCore.dylib $(FRAMEWORKS_DIR)/libSuperShotCore.dylib
	@chmod 755 $(FRAMEWORKS_DIR)/libSuperShotCore.dylib
	$(INSTALL_NAME_TOOL) -id @rpath/libSuperShotCore.dylib $(FRAMEWORKS_DIR)/libSuperShotCore.dylib
	@echo "Installing bundle metadata and icon resources..."
	@cp -f Sources/SuperShot/App/Info.plist $(BUNDLE_DIR)/Info.plist
	@chmod 644 $(BUNDLE_DIR)/Info.plist
	@printf "APPL????" > $(BUNDLE_DIR)/PkgInfo
	@chmod 644 $(BUNDLE_DIR)/PkgInfo
	@cp -f $(BUILD_DIR)/Resources/AppIcon.icns $(RESOURCES_DIR)/AppIcon.icns
	@chmod 644 $(RESOURCES_DIR)/AppIcon.icns
	@echo "Signing application bundle inside-out with stable designated requirement..."
	$(CODESIGN) --force --sign - $(FRAMEWORKS_DIR)/libSuperShotCore.dylib
	@if [ -f $(MACOS_DIR)/$(APP_NAME) ]; then \
		$(CODESIGN) --force --sign - -r='designated => identifier "com.supershot.SuperShot"' $(MACOS_DIR)/$(APP_NAME); \
	fi
	$(CODESIGN) --force --sign - -r='designated => identifier "com.supershot.SuperShot"' $(BUNDLE_NAME)
	@echo "Verifying code signature integrity..."
	$(CODESIGN) -v --deep --strict $(BUNDLE_NAME)
	$(CODESIGN) --verify --verbose=4 $(FRAMEWORKS_DIR)/libSuperShotCore.dylib
	@if [ -f $(MACOS_DIR)/$(APP_NAME) ]; then \
		$(CODESIGN) --verify --verbose=4 $(MACOS_DIR)/$(APP_NAME); \
	fi
	@echo "SuperShot.app standalone packaging complete."

bundle: app

package: app
	@echo "Packaging distributable Universal 2 archive: $(PACKAGE_ZIP)..."
	@rm -f $(PACKAGE_ZIP)
	@ditto -c -k --sequesterRsrc --keepParent $(BUNDLE_NAME) $(PACKAGE_ZIP)
	@echo "Universal 2 distribution archive created: $(PACKAGE_ZIP)"

dmg: app
	@echo "Packaging distributable Universal 2 DMG: $(PACKAGE_DMG)..."
	@rm -rf $(DMG_STAGING_DIR) $(PACKAGE_DMG)
	@mkdir -p $(DMG_STAGING_DIR)
	@cp -R $(BUNDLE_NAME) $(DMG_STAGING_DIR)/
	@ln -s /Applications $(DMG_STAGING_DIR)/Applications
	@hdiutil create -volname "$(APP_NAME)" -srcfolder "$(DMG_STAGING_DIR)" -ov -format UDZO $(PACKAGE_DMG)
	@rm -rf $(DMG_STAGING_DIR)
	@echo "Universal 2 distribution DMG created: $(PACKAGE_DMG)"

# Standalone App Bundle Verification
verify-app: bundle
	@echo "Executing SuperShot.app standalone bundle verifications..."
	@bash Scripts/verify_app.sh $(BUNDLE_NAME)
	@bash Scripts/verify_bundle.sh
	@echo "All standalone bundle verifications PASSED."

# Static Zero-Emoji Lint Check
lint:
	@echo "Verifying strict styling constraints (0 emojis)..."
	@$(PYTHON) Scripts/lint_emojis.py Sources/ Tests/ Scripts/ Makefile Package.swift README.md LICENSE
	@echo "Styling check passed: 0 emojis detected, SF Symbols compliant."

# Automated Verification Runner
verify: build
	@echo "Executing SuperShot automated verification suite..."
	@bash Scripts/verify.sh

# Unit Tests
test: verify

# Adversarial Stress Tests
adversarial: build
	@echo "Executing SuperShot adversarial stress test suite..."
	@bash Scripts/run_adversarial.sh

# Clean Artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD_DIR) $(BUNDLE_NAME) SuperShot-*.zip SuperShot-*.dmg $(DMG_STAGING_DIR) .verifier_bin* .adversarial_runner* /tmp/SuperShot_* /tmp/supershot_*
	@echo "Clean completed."
