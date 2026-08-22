#!/bin/bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/core-tests"
MODULE_CACHE="$PROJECT_DIR/.build/module-cache-tests"
SDK_PATH="${CLIPSHELF_SDK_PATH:-}"

if [[ -z "$SDK_PATH" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ]]; then
    SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
fi
if [[ -z "$SDK_PATH" ]]; then
    SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
fi

mkdir -p "$BUILD_DIR" "$MODULE_CACHE"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" swiftc \
    -sdk "$SDK_PATH" \
    -target "$(uname -m)-apple-macosx13.0" \
    "$PROJECT_DIR/Sources/ClipShelf/Models.swift" \
    "$PROJECT_DIR/Sources/ClipShelf/HistoryStore.swift" \
    "$PROJECT_DIR/Scripts/core_tests.swift" \
    -o "$BUILD_DIR/ClipShelfCoreTests"

"$BUILD_DIR/ClipShelfCoreTests"
