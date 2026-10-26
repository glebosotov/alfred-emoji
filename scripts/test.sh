#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
export SDKROOT=$(/usr/bin/env -u SDKROOT -u DEVELOPER_DIR /usr/bin/xcrun --sdk macosx --show-sdk-path)
unset DEVELOPER_DIR CPATH LIBRARY_PATH
/usr/bin/xcrun swiftc -O Sources/Core.swift Tests/main.swift -o .build/tests
.build/tests
