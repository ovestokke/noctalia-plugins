# CodexBar CLI install/update helper

Since CodexBar is not available in the AUR yet, this repo includes a Linux helper script:

```bash
scripts/codexbar-cli-manager.sh check
scripts/codexbar-cli-manager.sh install
scripts/codexbar-cli-manager.sh update
```

Default install target:

```text
~/.local/bin/CodexBarCLI
~/.local/bin/codexbar -> CodexBarCLI
```

The helper:

1. Checks whether `codexbar` exists on `PATH` or in the install directory.
2. Runs `ldd` on the executable and reports missing shared libraries.
3. Reads the installed version with `codexbar --version`.
4. Fetches the latest release from `https://api.github.com/repos/steipete/CodexBar/releases/latest`.
5. Selects the matching Linux asset for the current CPU architecture:
   - `CodexBarCLI-<tag>-linux-x86_64.tar.gz`
   - `CodexBarCLI-<tag>-linux-aarch64.tar.gz`
6. Compares installed version vs latest release tag.
7. On `install`/`update`, downloads the tarball and `.sha256`, verifies the checksum, installs `CodexBarCLI`, and creates/updates the `codexbar` symlink.

## Homebrew tap behavior

The upstream Homebrew tap formula is `steipete/homebrew-tap/Formula/codexbar.rb`.

As of CodexBar `v0.23`, it does **not** build from source and does **not** do anything special beyond downloading the same GitHub release tarball this helper uses:

```ruby
url "https://github.com/steipete/CodexBar/releases/download/v0.23/CodexBarCLI-v0.23-linux-x86_64.tar.gz"
sha256 "710c2697672516d7bec15e51b93a6a7bfb8de3056bc0690ad69d5ba6a6ece4e9"
depends_on :linux

def install
  bin.install "CodexBarCLI"
  bin.install_symlink "CodexBarCLI" => "codexbar"
end
```

For ARM Linux it switches to:

```ruby
CodexBarCLI-v#{version}-linux-aarch64.tar.gz
```

Important: the formula currently declares only `depends_on :linux`; it does **not** declare `libxml2` / `libxml2-legacy`. So using Brew would not reveal an extra installation step we were missing. It installs the same archive and symlink layout as our script.

## Runtime dependencies

The Linux CLI currently needs system shared libraries such as `libxml2.so.2`. On current Arch/CachyOS, `libxml2` provides `libxml2.so.16`, not the older `libxml2.so.2` SONAME that the current CodexBarCLI release expects. Install the legacy package:

```bash
sudo pacman -S libxml2-legacy
```

If the binary exists but a library is missing, `check --json` reports `runtimeOk: false`, `missingLibraries`, and a `dependencyHint`.

`install` and `update` now fail with a non-zero exit code if the installed binary still has missing shared libraries after download/extract. The plugin should treat that as a dependency error and not continue into normal CodexBar polling.

Machine-readable status for QML/plugin integration:

```bash
scripts/codexbar-cli-manager.sh check --json
```

Example output:

```json
{
  "ok": true,
  "installed": false,
  "path": null,
  "currentVersion": null,
  "latestVersion": "v0.23",
  "latestAsset": "CodexBarCLI-v0.23-linux-x86_64.tar.gz",
  "updateAvailable": true
}
```

Options:

```bash
scripts/codexbar-cli-manager.sh install --install-dir ~/.local/bin
scripts/codexbar-cli-manager.sh update --force
CODEXBAR_INSTALL_DIR=/opt/codexbar/bin scripts/codexbar-cli-manager.sh install
GITHUB_TOKEN=... scripts/codexbar-cli-manager.sh check --json
```

## Plugin integration notes

Initial plugin states can be derived from `check --json`:

- `installed=false`: show missing dependency state + “Install CodexBar CLI” action.
- `installed=true, updateAvailable=true`: show “Update available” action.
- `installed=true, updateAvailable=false`: proceed with normal `codexbar --format json` polling.

For safety, the plugin should not auto-install/update silently. It should ask the user first, then run:

```bash
scripts/codexbar-cli-manager.sh install --json
```

or:

```bash
scripts/codexbar-cli-manager.sh update --json
```
