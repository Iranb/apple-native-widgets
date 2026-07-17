#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

ROOT="${0:A:h}"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
SWIFTC="$(xcrun --find swiftc)"
BIN_DIR="/tmp/apple-native-widget-previews"
SOURCE_STAGE="$(mktemp -d /tmp/apple-native-widget-preview-source.XXXXXX)"
trap 'rm -rf "$SOURCE_STAGE"' EXIT
HPC_SNAPSHOT="$HOME/Library/Containers/com.example.bjtu-hpc-native-widget.widget/Data/Library/Application Support/BJTUHPCNativeWidget/snapshot.json"
DEADLINE_SNAPSHOT="$HOME/Library/Containers/com.example.ai-deadline-native-widget.widget/Data/Library/Application Support/AIDeadlineNativeWidget/snapshot.json"
LIVE_PREVIEWS=false
OUT="$ROOT/previews"
if [[ "${1:-}" == "--live" ]]; then
  LIVE_PREVIEWS=true
  OUT="$ROOT/previews-live"
fi

rm -rf "$BIN_DIR" "$OUT"
mkdir -p "$BIN_DIR" "$OUT" "$SOURCE_STAGE/HPC" "$SOURCE_STAGE/Deadline"
cp "$ROOT/HPC/HPCWidget.swift" "$SOURCE_STAGE/HPC/HPCWidget.swift"
cp "$ROOT/Deadline/DeadlineWidget.swift" "$SOURCE_STAGE/Deadline/DeadlineWidget.swift"
cp "$ROOT/PreviewRenderer.swift" "$SOURCE_STAGE/PreviewRenderer.swift"

"$SWIFTC" "$SOURCE_STAGE/HPC/HPCWidget.swift" "$SOURCE_STAGE/PreviewRenderer.swift" \
  -target arm64-apple-macosx14.0 -sdk "$SDK" -parse-as-library -O -D HPC_PREVIEW \
  -framework AppIntents -framework AppKit -framework SwiftUI -framework WidgetKit \
  -o "$BIN_DIR/hpc-preview"

"$SWIFTC" "$SOURCE_STAGE/Deadline/DeadlineWidget.swift" "$SOURCE_STAGE/PreviewRenderer.swift" \
  -target arm64-apple-macosx14.0 -sdk "$SDK" -parse-as-library -O \
  -framework AppIntents -framework AppKit -framework SwiftUI -framework WidgetKit \
  -o "$BIN_DIR/deadline-preview"

if [[ "$LIVE_PREVIEWS" == true ]]; then
  "$BIN_DIR/hpc-preview" "$OUT" "$HPC_SNAPSHOT"
  "$BIN_DIR/deadline-preview" "$OUT" "$DEADLINE_SNAPSHOT"
else
  "$BIN_DIR/hpc-preview" "$OUT"
  "$BIN_DIR/deadline-preview" "$OUT"
fi
echo "Rendered previews in $OUT"
