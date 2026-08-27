#!/bin/bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$PROJECT_DIR/Scripts/display_test_helper.swift"
VERSION="$(tr -d '[:space:]' < "$PROJECT_DIR/VERSION")"
DMG_PATH="$PROJECT_DIR/dist/cpsmart-$VERSION-universal.dmg"
VALIDATION_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cpsmart-display-validation.XXXXXX")"
MOUNT_DIR="$VALIDATION_DIR/mount"
INSTALLED_DIR="$(mktemp -d "/Applications/cpsmart-display-validation.XXXXXX")"
APP_PATH="$INSTALLED_DIR/cpsmart.app"
IS_MOUNTED=false
SKIP_BUILD=false

if [[ "${1:-}" == "--skip-build" ]]; then
    SKIP_BUILD=true
elif [[ $# -gt 0 ]]; then
    echo "Usage: $0 [--skip-build]" >&2
    exit 2
fi

cleanup() {
    if [[ "$IS_MOUNTED" == true ]]; then
        hdiutil detach "$MOUNT_DIR" -quiet || true
    fi
    rm -rf "$INSTALLED_DIR"
    rm -rf "$VALIDATION_DIR"
}
trap cleanup EXIT

swift "$HELPER" environment
SCREEN_COUNT="$(swift "$HELPER" count)"

if [[ "$SKIP_BUILD" == false ]]; then
    "$PROJECT_DIR/Scripts/build_dmg.sh" --local
elif [[ ! -f "$DMG_PATH" ]]; then
    echo "Missing DMG for --skip-build: $DMG_PATH" >&2
    exit 1
fi
mkdir -p "$MOUNT_DIR"
hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$MOUNT_DIR" -quiet
IS_MOUNTED=true
ditto "$MOUNT_DIR/cpsmart.app" "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
ARCHITECTURES="$(lipo -archs "$APP_PATH/Contents/MacOS/cpsmart")"
[[ "$ARCHITECTURES" == *arm64* && "$ARCHITECTURES" == *x86_64* ]]

for ((screen_index = 0; screen_index < SCREEN_COUNT; screen_index++)); do
    swift "$HELPER" warp "$screen_index"
    REPORT_PATH="$VALIDATION_DIR/screen-$screen_index.json"
    ISOLATED_HOME="$VALIDATION_DIR/home-$screen_index"
    mkdir -p "$ISOLATED_HOME"
    CFFIXED_USER_HOME="$ISOLATED_HOME" HOME="$ISOLATED_HOME" \
        CPSMART_PACKAGE_SMOKE_ROOT="$ISOLATED_HOME/package-smoke" \
        "$APP_PATH/Contents/MacOS/cpsmart" \
        --package-smoke-test \
        --package-smoke-report "$REPORT_PATH" \
        --expected-screen-index "$screen_index"
    swift "$HELPER" verify "$REPORT_PATH" "$screen_index"
done

echo "Multi-display installed-package validation passed on $SCREEN_COUNT screens."
