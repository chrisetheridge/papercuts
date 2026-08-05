<div align="center">
  <p>
    <img src="assets/scissors.svg" width="72" alt="Papercuts scissors mark" />
  </p>
  <h1>Papercuts</h1>
  <p><strong>Small fixes for better agents.</strong></p>
  <p>A macOS menubar utility for capturing the small workflow frictions discovered by coding agents.</p>
</div>

## Install the agent skill

From a source checkout, run:

```sh
scripts/install.sh
```

From a downloaded release, run the same command from the unzipped release directory:

```sh
cd Papercuts-<version>-macos
scripts/install.sh
```

The installer links the skill into `~/.agents/skills`. It does not install a CLI; agents communicate with the running app through the Unix socket.

## Get Papercuts

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

## Record a papercut

When an agent finds a small workflow or quality issue, it checks the Papercuts Unix socket before adding a new entry:

```text
~/Library/Application Support/Papercuts/papercuts.sock
```

The protocol sends one newline-delimited JSON request and receives one newline-delimited JSON response. It supports `list` for duplicate checks, `add` for new papercuts, and `edit` for corrections. The app detects the repository and current Git branch from `repositoryPath`.

The skill includes a Python standard-library example. No CLI is required. Papercuts must be running before an agent can connect.

## Review the list

Click the scissors icon in the menubar. Papercuts groups entries by repository. Click a repository header to expand or collapse its entries, then click a papercut to read the details and copy its prompt.

Right-click an entry to open its repository in a detected terminal app or delete it after the issue is fixed.

# Inspiration

- https://x.com/steveruizok/status/2075303919664734295
- https://github.com/wevm/frog
