#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build dist
# Use Apple's SDK/toolchain for a distributable binary without Nix store references.
SDK=$(/usr/bin/env -u SDKROOT -u DEVELOPER_DIR /usr/bin/xcrun --sdk macosx --show-sdk-path)
export SDKROOT="$SDK"
unset DEVELOPER_DIR CPATH LIBRARY_PATH
for arch in arm64 x86_64; do
  /usr/bin/xcrun swiftc -O -sdk "$SDK" -target "$arch-apple-macosx13.0" Sources/Core.swift Sources/main.swift -o ".build/emoji-$arch"
done
/usr/bin/lipo -create .build/emoji-arm64 .build/emoji-x86_64 -output .build/emoji
/usr/bin/codesign --force --sign - .build/emoji
/usr/bin/xcrun swiftc Tools/Package.swift -o .build/package-tool
stage=dist/Emoji.alfredworkflow.contents
rm -rf "$stage"
rm -f dist/Emoji.alfredworkflow
mkdir -p "$stage"
cp .build/emoji "$stage/emoji"
cp -R data Emoji.alfredui "$stage/"
.build/package-tool "$stage"
EMOJI_DATA="$PWD/data" alfred_workflow_cache="$PWD/.build/icons" .build/emoji render-icon 👀 > "$stage/icon.png"
(cd "$stage" && zip -q -r ../Emoji.alfredworkflow .)
printf 'Built dist/Emoji.alfredworkflow\n'
