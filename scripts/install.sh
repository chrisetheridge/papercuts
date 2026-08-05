#!/bin/zsh
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"

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
