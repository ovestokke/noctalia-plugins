# Nodus for Noctalia

Read text and checklist notes, browse active/archive/trash, create text notes and checklists, and mark existing checklist items done or not done in Nodus v2. This is an **experimental catalog entry**, not a production-ready sync client. Editing existing text/item content, adding or deleting existing items, offline writes, reminders, conflict resolution and recovery from a changed realm are not supported. Do not use it for irreplaceable notes until the server's deployment and backup gates are complete.

## Plugin

- ID: `ovestokke/nodus`
- Widget: `bar` opens the notes panel.
- Panel: `panel` shows notes, checklists and connection setup.
- Service: `service` runs the bundled helper and refreshes notes.

To toggle the panel through IPC:

```sh
noctalia msg panel-toggle ovestokke/nodus:panel
```

## Usage

No repository checkout, Go installation or manual build is required. The plugin includes static Linux helpers for **x86_64 and ARM64** and selects the matching binary automatically. Helpers update with the plugin; `~/.local/bin/nodus-noctalia` is no longer used.

Requirements:

- Noctalia plugin API 24+ on Linux x86_64 or ARM64.
- `secret-tool` and a running, unlocked Secret Service keyring, such as GNOME Keyring.
- A terminal configured in Noctalia for the pairing prompt.
- A working Nodus v2 server.

If `secret-tool` is missing, install it with `sudo pacman -Syu --needed libsecret` on Arch / EndeavourOS, or `sudo apt install libsecret-tools` on Debian / Ubuntu. Installing this command does not start a keyring service; use your desktop's keyring. Noctalia and the helper run as your desktop user.

1. Add this repository as a Noctalia plugin source (see the [repository install instructions](../README.md#install)). Install and enable **Nodus** from the catalog, then add its bar widget.
2. Under **Settings → Plugins → Nodus**, set the server address, for example `https://nodus.vstokke.com`.
3. In Nodus Web, create a short-lived pairing code.
4. Open the Nodus panel and select **Pair device**. A terminal opens automatically. Enter the code there; it is visible as you type. Lowercase letters are converted to uppercase automatically. You do not need to type any commands.
5. Notes load automatically after successful pairing. Press Enter to close the terminal. The panel's gear button returns to connection setup.

If the source is already installed, update it through Noctalia to receive the bundled helper. A missing bundle is an installation error: update or reinstall the plugin, rather than installing Go.

Pairing reads the code from `/dev/tty` with echo enabled because Noctalia's process API does not expose stdin. The short-lived code is visible in the terminal, so avoid sharing that terminal while pairing. The code is never placed in plugin settings, process arguments or a plaintext input file. Only HTTPS origins are accepted outside loopback. The credential and pending redemption tuple live in Secret Service. Incorrect or expired codes show **Incorrect code. Try again.** and prompt for another code in the same terminal. A rejected attempt is cleared; network failures and temporary errors retain the original attempt. If redemption has an unknown outcome, select **Pair device** again with the **same server address** to retry the original tuple. Changing the server setting does not replace an existing pairing.

Existing helper profiles remain usable. No files in the separate Nodus CLI's private directory are imported, moved or modified.

The helper uses `$XDG_STATE_HOME/nodus-noctalia` (or `~/.local/state/nodus-noctalia`) for a private 0700 profile, exact-write journal, drafts and full feed cache. These contain **unencrypted note content**, not credentials. The Go helper writes its state with file and directory sync. Noctalia passes note intent to the helper through a pre-created private 0600 draft file, not argv. Only the helper makes authenticated HTTP requests. If the keyring is unavailable, the plugin does not fall back to plaintext credentials.

## Settings

`instance_url` is the Nodus server's HTTPS origin, with no path or query. Set it under **Settings → Plugins → Nodus** before pairing. It is used only for pairing; an existing profile retains its original server. Pairing codes and credentials are never saved in plugin settings.

## Safety and limits

- Changes are read from `/api/v2/changes` at a fixed watermark, 10 events per page. The UI loads 40 cached notes at a time; Refresh continues the feed. Opening the note or list composer switches the small drawer to a full-height editor; Save returns to browsing, while Discard confirms before removing a non-empty local draft. The adjacent list action creates checklists with initial items. Existing checklists support only absolute check/uncheck using each item's revision. Checked items move below a divider and are struck through **in the panel only**; no reorder request changes the server's item positions.
- Creates and check/uncheck are online-only. Before sending, the helper durably records the exact request bytes and identity. A lost response blocks further creates. **Retry exact request** uses that journal, never a new request ID. If the credential or realm changes, the old journal is preserved and replay is blocked.
- A server realm change is deliberately blocked. Keep the state directory and resolve the old graph/outbox manually; do not delete journals to bypass this state.
- The helper keeps private unencrypted note snapshots/drafts; the Noctalia UI receives note content to display it. Other plugins or processes running as the same OS user may be able to access that content. There is no encrypted offline cache.
- On first load, a large history takes multiple polls. The panel shows cached notes while the remaining pages load. No background work occurs while Noctalia is stopped.

## Development and bundled helpers

**Go is a developer build dependency, not a plugin user dependency.** The helper source requires Go 1.23+. Install Go with `sudo pacman -Syu --needed go` on Arch / EndeavourOS, or `sudo apt install golang-go` on Debian / Ubuntu. Check `go version`; if the distribution version is too old, use the [official installation instructions](https://go.dev/doc/install). For the official `/usr/local/go` installation in fish, add it with `fish_add_path /usr/local/go/bin`.

From the repository root, rebuild both bundled architectures:

```sh
python3 tools/build_nodus.py
```

The script uses the official Go version pinned in `helper/toolchain.txt`, downloading that toolchain when necessary. It disables cgo, strips debug symbols and removes local build paths. Commit the resulting binaries, `bin/SHA256SUMS` and `bin/GO-LICENSE` with the source changes. They are ordinary Git files, not Git LFS pointers, so Noctalia's git-source installation receives runnable helpers without a separate download. This adds about 13 MB to the checkout.

CI rebuilds both binaries and compares them byte-for-byte with the bundle. When updating the Go toolchain, change `helper/toolchain.txt` and regenerate the bundle. Do not edit or replace a binary without its corresponding source.

For a local development source:

```sh
noctalia msg plugins source add nodus-dev path "$PWD"
noctalia msg plugins enable ovestokke/nodus
```

## Checks

```sh
go -C nodus/helper test -count=1 ./...
go -C nodus/helper vet ./...
python3 tools/build_nodus.py --check
python3 tools/test_nodus.py
noctalia plugins lint nodus
python3 tools/smoke.py
```

Tests use a fake Secret Service command and a disposable HTTP server. The bundle tests run the shipped helper without Go and verify that code entry is visible before submission through a real pseudo-terminal. They do **not** test live pairing, a real unlocked keyring, or Noctalia's UI runtime; those require a local end-to-end check before release.
