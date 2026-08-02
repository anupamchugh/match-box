#!/usr/bin/env zsh
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_name="Match Box"
bundle_path="$root_dir/dist/$app_name.app"
binary_path="$root_dir/.build/debug/MatchInboxApp"

cd "$root_dir"
swift build --product MatchInboxApp

if pgrep -x MatchInboxApp >/dev/null 2>&1; then
  pkill -x MatchInboxApp || true
fi

mkdir -p "$bundle_path/Contents/MacOS"
cp "$binary_path" "$bundle_path/Contents/MacOS/MatchInboxApp"
plutil -create xml1 "$bundle_path/Contents/Info.plist"
plutil -replace CFBundlePackageType -string APPL "$bundle_path/Contents/Info.plist"
plutil -replace CFBundleExecutable -string MatchInboxApp "$bundle_path/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string com.anupamchugh.matchinbox "$bundle_path/Contents/Info.plist"
plutil -replace CFBundleName -string "$app_name" "$bundle_path/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string "$app_name" "$bundle_path/Contents/Info.plist"
plutil -replace LSMinimumSystemVersion -string 15.0 "$bundle_path/Contents/Info.plist"
plutil -replace NSPrincipalClass -string NSApplication "$bundle_path/Contents/Info.plist"
plutil -replace NSScreenCaptureUsageDescription -string "Match Box captures an iPhone Mirroring window you select to read visible context locally." "$bundle_path/Contents/Info.plist"

open -n "$bundle_path"
