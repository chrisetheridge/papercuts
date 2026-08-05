#!/bin/zsh
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"

osascript -e 'tell application id "com.papercuts.app" to quit' >/dev/null 2>&1 || true

for _ in {1..20}; do
    if ! pgrep -x Papercuts >/dev/null 2>&1; then break; fi
    sleep 0.1
done

"$root_dir/scripts/build-app.sh" >/dev/null
open "$root_dir/.build/Papercuts.app"
echo "Papercuts relaunched"
