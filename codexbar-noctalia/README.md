# CodexBar Noctalia

Noctalia plugin that surfaces AI coding assistant usage through the [`codexbar`](https://github.com/steipete/CodexBar) CLI.

## Current status

Early development. Step one is implemented:

- Check whether `codexbar` is installed.
- Check the latest GitHub release.
- Detect missing shared libraries with `ldd`.
- Install/update the Linux CLI from GitHub Releases without Homebrew.
- Expose check/install/update state to the plugin UI.

## Linux notes

CodexBar web/auto sources are macOS-only. On Linux, configure the plugin to use:

```text
source = cli
provider = all
```

`provider = all` means: read `codexbar config dump --format json`, take only enabled providers, then query those providers one by one. This avoids CodexBar's Linux `--provider all` behavior where unsupported/disabled providers can hang or emit extra JSON.

For one specific provider, set `provider = codex`, `claude`, `gemini`, etc. For API-backed providers, use `source = api`.

The current upstream Linux binary requires `libxml2.so.2`. On current Arch/CachyOS this is provided by:

```bash
sudo pacman -S libxml2-legacy
```

## Manual helper usage

```bash
./scripts/codexbar-cli-manager.sh check
./scripts/codexbar-cli-manager.sh check --json
./scripts/codexbar-cli-manager.sh install
./scripts/codexbar-cli-manager.sh update
```

Default install location:

```text
~/.local/bin/CodexBarCLI
~/.local/bin/codexbar -> CodexBarCLI
```

## IPC

```bash
qs -c noctalia-shell ipc call plugin:codexbar-noctalia check
qs -c noctalia-shell ipc call plugin:codexbar-noctalia refresh
qs -c noctalia-shell ipc call plugin:codexbar-noctalia install
qs -c noctalia-shell ipc call plugin:codexbar-noctalia update
qs -c noctalia-shell ipc call plugin:codexbar-noctalia toggle
```
