#!/bin/bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$BUILD_DIR/cpsmart.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
STAGING_DIR="$BUILD_DIR/dmg-staging"
DMG_PATH="$DIST_DIR/cpsmart-1.4.0-universal.dmg"
SDK_PATH="${CPSMART_SDK_PATH:-}"

if [[ -z "$SDK_PATH" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ]]; then
    SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
fi
if [[ -z "$SDK_PATH" ]]; then
    SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
fi

mkdir -p "$BUILD_DIR" "$DIST_DIR" "$MACOS_DIR" "$RESOURCES_DIR"

build_architecture() {
    local architecture="$1"
    local scratch_path="$PROJECT_DIR/.build/$architecture"
    local module_cache="$PROJECT_DIR/.build/module-cache-$architecture"
    mkdir -p "$module_cache"
    SDKROOT="$SDK_PATH" \
    CLANG_MODULE_CACHE_PATH="$module_cache" \
    SWIFTPM_MODULECACHE_OVERRIDE="$module_cache" \
    swift build \
        --package-path "$PROJECT_DIR" \
        --disable-sandbox \
        --configuration release \
        --product cpsmart \
        --triple "$architecture-apple-macosx13.0" \
        --scratch-path "$scratch_path"
    echo "$scratch_path/$architecture-apple-macosx/release/cpsmart"
}

X86_BINARY="$(build_architecture x86_64 | tail -n 1)"
ARM_BINARY="$(build_architecture arm64 | tail -n 1)"

lipo -create "$X86_BINARY" "$ARM_BINARY" -output "$MACOS_DIR/cpsmart"
chmod 755 "$MACOS_DIR/cpsmart"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

rm -rf "$ICONSET_DIR"
CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache-icon" \
    swift -sdk "$SDK_PATH" "$PROJECT_DIR/Scripts/generate_icon.swift" "$ICONSET_DIR"
CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache-icon" \
    swift -sdk "$SDK_PATH" "$PROJECT_DIR/Scripts/create_icns.swift" \
    "$ICONSET_DIR" "$RESOURCES_DIR/AppIcon.icns"

codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
ditto "$APP_DIR" "$STAGING_DIR/cpsmart.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
    -volname "cpsmart 安装" \
    -srcfolder "$STAGING_DIR" \
    -format UDZO \
    -ov \
    "$DMG_PATH"

echo "$DMG_PATH"
