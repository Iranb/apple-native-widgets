#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

ROOT="${0:A:h:h}"
APP_PLIST="$ROOT/HPC/AppInfo.plist"
EXT_PLIST="$ROOT/HPC/ExtensionInfo.plist"
SOURCE="$ROOT/HPC/HPCWidget.swift"

plutil -lint "$APP_PLIST" "$EXT_PLIST"

app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PLIST")"
extension_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$EXT_PLIST")"
app_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PLIST")"
extension_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$EXT_PLIST")"

[[ "$app_version" == "$extension_version" ]]
[[ "$app_build" == "$extension_build" ]]

rg -q 'static let stable = "BJTUHPCNativeWidget"' "$SOURCE"
rg -q 'static let transitional = "BJTUHPCWidget"' "$SOURCE"
rg -q 'snapshot\.summary\.availableGPUCount' "$SOURCE"
rg -q 'node\.availableGPUCount' "$SOURCE"
rg -q 'ChangeHPCAccountPageIntent' "$SOURCE"

if rg -n 'com\.iranb|/Users/|Bearer[[:space:]]|BEGIN [A-Z ]*PRIVATE KEY' "$ROOT/HPC" "$ROOT/previews"; then
    print -u2 'Private or machine-specific content found.'
    exit 1
fi

sdk="$(xcrun --sdk macosx --show-sdk-path)"
arch="$(uname -m)"
test_root="$(mktemp -d "${TMPDIR%/}/hpc-availability-tests.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT

xcrun swiftc \
    "$SOURCE" \
    "$ROOT/Tests/HPCAvailabilityTests.swift" \
    -target "$arch-apple-macosx14.0" \
    -sdk "$sdk" \
    -parse-as-library \
    -O \
    -framework AppIntents \
    -framework AppKit \
    -framework SwiftUI \
    -framework WidgetKit \
    -o "$test_root/hpc-availability-tests"

"$test_root/hpc-availability-tests"

print "HPC release contract OK: $app_version ($app_build)"
