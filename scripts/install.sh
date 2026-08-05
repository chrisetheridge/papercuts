#!/bin/zsh
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"

app_source="$root_dir/Papercuts.app"
if [[ ! -d "$app_source" ]]; then
    app_source="$root_dir/.build/Papercuts.app"
fi
if [[ ! -d "$app_source" ]]; then
    if ! command -v swift >/dev/null 2>&1; then
        echo "Papercuts.app is missing and Swift is not installed. Build or download Papercuts first." >&2
        exit 1
    fi
    app_source="$($root_dir/scripts/build-app.sh)"
fi

app_destination="$HOME/Applications/Papercuts.app"
mkdir -p "$HOME/Applications"
ditto "$app_source" "$app_destination"

cli_link="$HOME/.local/bin/papercuts"
mkdir -p "$(dirname "$cli_link")"
if [[ -e "$cli_link" && ! -L "$cli_link" ]]; then
    echo "Refusing to replace existing path: $cli_link" >&2
    exit 1
fi
ln -sfn "$app_destination/Contents/MacOS/PapercutsCLI" "$cli_link"

skill_link="$HOME/.agents/skills/papercuts"
mkdir -p "$(dirname "$skill_link")"
if [[ -L "$skill_link" ]]; then
    rm "$skill_link"
fi
if [[ -e "$skill_link" ]]; then
    echo "Refusing to replace existing path: $skill_link" >&2
    exit 1
fi
ln -s "$root_dir/skills/papercuts" "$skill_link"

echo "Installed the Papercuts agent skill to $skill_link"
echo "Installed the Papercuts CLI to $cli_link"
if [[ ":${PATH}:" != *":$HOME/.local/bin:"* ]]; then
    echo "Add $HOME/.local/bin to PATH to run 'papercuts' directly from a shell."
fi
