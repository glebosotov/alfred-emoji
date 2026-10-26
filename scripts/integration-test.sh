#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export SDKROOT=$(/usr/bin/env -u SDKROOT -u DEVELOPER_DIR /usr/bin/xcrun --sdk macosx --show-sdk-path)
unset DEVELOPER_DIR CPATH LIBRARY_PATH
/usr/bin/xcrun swiftc -parse-as-library Tests/Integration.swift -o .build/integration-test
.build/integration-test
