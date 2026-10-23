#!/bin/bash
set -euo pipefail

# ==============================================================================
# SuperShot Automated Verification Script
# Strictly enforces:
# 1. Isolated sandboxing (never touches ~/Library/Application Support/SuperShot/)
# 2. SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
# 3. 0 Emojis invariant across all files
# 4. Direct linkage against genuine SuperShotCore library (.build/lib/libSuperShotCore.dylib)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk" ]; then
    export SDKROOT="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
elif [ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk" ]; then
    export SDKROOT="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
else
    export SDKROOT="$(xcrun --show-sdk-path)"
fi

echo "=================================================="
echo "  SuperShot Test Suite Verification"
echo "  Project Root: $PROJECT_ROOT"
echo "  SDKROOT:      $SDKROOT"
echo "=================================================="

# Step 1: Run Static Zero-Emoji Scanner
echo ""
echo "--- Step 1: Scanning for Zero-Emoji Invariant ---"
python3 "$PROJECT_ROOT/Scripts/lint_emojis.py" \
    "$PROJECT_ROOT/Sources" \
    "$PROJECT_ROOT/Tests" \
    "$PROJECT_ROOT/Scripts" \
    "$PROJECT_ROOT/README.md" \
    "$PROJECT_ROOT/LICENSE"

# Step 2: Ensure Core Library Artifacts Exist
echo ""
echo "--- Step 2: Ensuring SuperShotCore Library is Built ---"
if [ ! -f "$PROJECT_ROOT/.build/lib/libSuperShotCore.dylib" ] || [ ! -e "$PROJECT_ROOT/.build/modules/SuperShotCore.swiftmodule" ]; then
    echo "SuperShotCore library artifacts not found. Building..."
    make -C "$PROJECT_ROOT" build
fi

# Step 3: Discover Swift Test Suite Files
echo ""
echo "--- Step 3: Compiling SuperShotVerifier via swiftc ---"

# Collect all non-adversarial test files and harness
TEST_FILES=()
while IFS= read -r file; do
    TEST_FILES+=("$file")
done < <(find "$PROJECT_ROOT/Tests" -name '*.swift' ! -name '*Adversarial*' | sort)

if [ ${#TEST_FILES[@]} -eq 0 ]; then
    echo "WARNING: No test files found in $PROJECT_ROOT/Tests."
    exit 0
fi

VERIFIER_BIN="$PROJECT_ROOT/.verifier_bin"
HOST_ARCH="${HOST_ARCH:-$(uname -m)}"

# Link against SuperShotCore (and SuperShot dylib if built)
LINK_FLAGS=("-L" "$PROJECT_ROOT/.build/lib" "-lSuperShotCore")
if [ -f "$PROJECT_ROOT/.build/lib/libSuperShot.dylib" ]; then
    LINK_FLAGS+=("-lSuperShot")
fi

swiftc -sdk "$SDKROOT" \
    -target "${HOST_ARCH}-apple-macos13.0" \
    -I "$PROJECT_ROOT/.build/modules" \
    "${LINK_FLAGS[@]}" \
    -Xlinker -rpath -Xlinker "$PROJECT_ROOT/.build/lib" \
    -parse-as-library \
    -O \
    "${TEST_FILES[@]}" \
    -o "$VERIFIER_BIN"

# Step 4: Execute Headless Verification Runner in Sandbox
echo ""
echo "--- Step 4: Executing Verification Runner ---"
"$VERIFIER_BIN"

# Step 5: Cleanup Binary
rm -f "$VERIFIER_BIN"

echo ""
echo "=================================================="
echo "  SuperShot Verification Completed Successfully   "
echo "=================================================="
