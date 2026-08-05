#!/bin/zsh
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root_dir"

swift build -c release

app_dir="$root_dir/.build/Papercuts.app"
rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"

icon_work_dir="$(mktemp -d "${TMPDIR:-/tmp}/papercuts-icon.XXXXXX")"
iconset_dir="$icon_work_dir/Papercuts.iconset"
mkdir -p "$iconset_dir"
trap 'rm -rf "$icon_work_dir"' EXIT
for size in 16 32 128 256 512; do
    sips -s format png -z "$size" "$size" "$root_dir/assets/scissors.svg" \
        --out "$iconset_dir/icon_${size}x${size}.png" >/dev/null
    double_size=$((size * 2))
    sips -s format png -z "$double_size" "$double_size" "$root_dir/assets/scissors.svg" \
        --out "$iconset_dir/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset_dir" -o "$app_dir/Contents/Resources/Papercuts.icns"

cp .build/release/PapercutsMenuBar "$app_dir/Contents/MacOS/Papercuts"
cp .build/release/PapercutsCLI "$app_dir/Contents/MacOS/PapercutsCLI"
cp Resources/PapercutsMenuBar-Info.plist "$app_dir/Contents/Info.plist"

echo "$app_dir"
