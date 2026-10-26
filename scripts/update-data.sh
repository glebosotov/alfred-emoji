#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .cache .build
curl --fail --location --silent --show-error https://unicode.org/Public/cldr/48.2/core.zip -o .cache/cldr-48.2.zip
curl --fail --location --silent --show-error https://unicode.org/Public/17.0.0/emoji/emoji-test.txt -o .cache/emoji-17.0.txt
printf '%s\n' \
  'd2844f9dbf6124d11a7b047f5381a467902d82a673be3d658f4c0791ffa0b83b  .cache/cldr-48.2.zip' \
  '1d8a944f88d7952f7ef7c5167fef3c67995bcae24543949710231b03a201acda  .cache/emoji-17.0.txt' | /usr/bin/shasum -a 256 -c -
unzip -q -o .cache/cldr-48.2.zip -d .cache/cldr-48.2
export SDKROOT=$(/usr/bin/env -u SDKROOT -u DEVELOPER_DIR /usr/bin/xcrun --sdk macosx --show-sdk-path)
unset DEVELOPER_DIR CPATH LIBRARY_PATH
/usr/bin/xcrun swiftc Sources/Core.swift Tools/GenerateData.swift -o .build/generate-data
.build/generate-data .cache/cldr-48.2/common .cache/emoji-17.0.txt data
