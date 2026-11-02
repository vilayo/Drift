#!/bin/bash
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
output_dir="${1:-$repo_dir/dist}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
if [[ ! -f Sources/Drift/Resources/quiet-current.mp4 || ! -f Sources/Drift/Resources/quiet-current.png ]]; then
    xcrun swift scripts/generate-demo.swift Sources/Drift/Resources
fi
swift build -c release --jobs 2
bin_dir="$(swift build -c release --show-bin-path)"
app_dir="$output_dir/Drift.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/Drift" "$app_dir/Contents/MacOS/Drift"
resource_bundle="$(find "$bin_dir" -maxdepth 1 -type d -name '*Drift*.bundle' -print -quit)"
if [[ -z "$resource_bundle" ]]; then
    echo "SwiftPM resource bundle was not found" >&2
    exit 1
fi
ditto "$resource_bundle/Resources" "$app_dir/Contents/Resources/Wallpapers"
if [[ -d "$app_dir/Contents/Resources/Drift_Drift.bundle" ]]; then
    rm -rf "$app_dir/Contents/Resources/Drift_Drift.bundle"
fi
icon_dir="$repo_dir/.build/Drift.iconset"
xcrun swift scripts/generate-icon.swift "$icon_dir"
iconutil -c icns "$icon_dir" -o "$app_dir/Contents/Resources/Drift.icns"
cp scripts/Info.plist "$app_dir/Contents/Info.plist"
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$output_dir/Drift-macOS.zip"
echo "Built $app_dir"
