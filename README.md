<div align="center">
  <p>
    <img src="assets/scissors.svg" width="72" alt="Papercuts scissors mark" />
  </p>
  <h1>Papercuts</h1>
  <p><strong>Small fixes for better agents.</strong></p>
  <p>A macOS menubar utility for capturing the small workflow frictions discovered by coding agents.</p>
</div>

## 1. Install the agent skill and CLI

From a source checkout, run:

```sh
scripts/install.sh
```

From a downloaded release, run the same command from the unzipped release directory:

```sh
cd Papercuts-<version>-macos
scripts/install.sh
```

The installer puts `papercut` in `/usr/local/bin` and links the skill into `~/.agents/skills`. It may ask for your administrator password.

## 2. Get Papercuts

Choose one option. Papercuts requires macOS 13 or later.

### Use the latest release

[Download the latest macOS release](https://github.com/chrisetheridge/papercuts/releases/latest), unzip it, run the installer from step 1, and open `Papercuts.app`. The app opens in the menubar.

### Build from source

From the repository root, run:

```sh
swift test
scripts/run-app.sh
```

The script builds and launches the app. Leave it running while you work.

## 3. Record a papercut

When an agent finds a small workflow or quality issue, run this from the affected repository:

```sh
papercut add \
  --model "gpt-5" \
  --title "Short issue title" \
  --description "What happened" \
  --why "Why it matters" \
  --prompt "How to fix it"
```

Papercuts detects the repository and current Git branch automatically. Use `--repo <path>` to record an issue for another repository.

## 4. Review the list

Click the scissors icon in the menubar. Papercuts groups entries by repository. Click a repository header to expand or collapse its entries, then click a papercut to read the details and copy its prompt.

Right-click an entry to open its repository in a detected terminal app or delete it after the issue is fixed.
