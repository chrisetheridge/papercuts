<div align="center">
  <p>
    <img src="assets/scissors.svg" width="72" alt="Papercuts scissors mark" />
  </p>
  <h1>Papercuts</h1>
  <p><strong>Small fixes for better agents.</strong></p>
  <p>A macOS menubar utility for capturing the small workflow frictions discovered by coding agents—then keeping them visible until someone fixes them.</p>
</div>

## How it works

1. An agent finds a small friction and logs it with the CLI.
2. Papercuts records the repository, branch, model, context, and suggested fix.
3. You review the list from the menubar and copy a complete fix prompt when ready.

## Capture a papercut

```sh
papercut add \
  --model "gpt-5" \
  --title "Short issue title" \
  --description "What happened" \
  --why "Why it matters" \
  --prompt "How to fix it"
```

The repository and current Git branch are detected automatically.

## Install the agent skill

From the repository root, symlink the skill into your global agent skills directory:

```sh
mkdir -p ~/.agents/skills
ln -s "$PWD/skills/papercuts" ~/.agents/skills/papercuts
```

The symlink keeps the global skill updated as the repository changes.

## Build

```sh
swift test
swift build -c release
scripts/build-app.sh
scripts/run-app.sh
```
