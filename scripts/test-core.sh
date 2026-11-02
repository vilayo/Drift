#!/bin/bash
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
check_dir="$repo_dir/.build/core-checks"
mkdir -p "$check_dir"
xcrun swiftc -swift-version 5 -enable-testing -emit-library -emit-module -module-name DriftCore \
    Sources/DriftCore/*.swift -o "$check_dir/libDriftCore.dylib" -emit-module-path "$check_dir/DriftCore.swiftmodule"
xcrun swiftc -swift-version 5 -D DRIFT_STANDALONE_TESTS -I "$check_dir" -L "$check_dir" -lDriftCore \
    -Xlinker -rpath -Xlinker "$check_dir" \
    Tests/DriftCoreTests/*.swift scripts/CoreCheckRunner.swift -o "$check_dir/checks"
"$check_dir/checks"
