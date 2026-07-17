#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

ROOT="${0:A:h}"
BUILD="${APPLE_NATIVE_WIDGET_BUILD_DIR:-/tmp/apple-native-widgets-build}"
XCODE_BUILD="${APPLE_NATIVE_WIDGET_XCODE_BUILD_DIR:-/tmp/apple-native-widgets-xcode}"
ARCH="$(uname -m)"

rm -rf "$BUILD" "$XCODE_BUILD"
mkdir -p "$BUILD"

cmake -S "$ROOT/xcode" -B "$XCODE_BUILD" -G Xcode \
  -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 >/dev/null

for scheme in BJTUHPCNativeWidget AIDeadlineNativeWidget; do
  xcodebuild \
    -quiet \
    -project "$XCODE_BUILD/AppleNativeWidgets.xcodeproj" \
    -scheme "$scheme" \
    -configuration Release \
    -derivedDataPath "$XCODE_BUILD/DerivedData" \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    build
done

HPC_SOURCE="$XCODE_BUILD/Release/BJTUHPCNativeWidget.app"
DEADLINE_SOURCE="$XCODE_BUILD/Release/AIDeadlineNativeWidget.app"
[[ -d "$HPC_SOURCE" ]] || { print -u2 "Missing Xcode output: $HPC_SOURCE"; exit 1; }
[[ -d "$DEADLINE_SOURCE" ]] || { print -u2 "Missing Xcode output: $DEADLINE_SOURCE"; exit 1; }

ditto "$HPC_SOURCE" "$BUILD/BJTU HPC Native Widget.app"
ditto "$DEADLINE_SOURCE" "$BUILD/AI Deadline Native Widget.app"

codesign --verify --deep --strict "$BUILD/BJTU HPC Native Widget.app"
codesign --verify --deep --strict "$BUILD/AI Deadline Native Widget.app"

HPC_METADATA="$BUILD/BJTU HPC Native Widget.app/Contents/PlugIns/BJTUHPCWidgetExtension.appex/Contents/Resources/Metadata.appintents"
[[ -d "$HPC_METADATA" ]] || { print -u2 "Missing HPC App Intents metadata: $HPC_METADATA"; exit 1; }

print "Built and verified Xcode app-extension products in $BUILD"
