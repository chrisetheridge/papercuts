#!/bin/zsh
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root_dir"

swift build -c release

app_dir="$root_dir/.build/Papercuts.app"
rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp .build/release/PapercutsMenuBar "$app_dir/Contents/MacOS/Papercuts"
cp Resources/PapercutsMenuBar-Info.plist "$app_dir/Contents/Info.plist"

echo "$app_dir"
