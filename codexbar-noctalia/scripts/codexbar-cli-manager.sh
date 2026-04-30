#!/usr/bin/env bash
# Check, install, or update the CodexBar Linux CLI from GitHub Releases.
# Default install location: ~/.local/bin/codexbar -> ~/.local/bin/CodexBarCLI

set -euo pipefail

REPO="steipete/CodexBar"
INSTALL_DIR="${CODEXBAR_INSTALL_DIR:-$HOME/.local/bin}"
COMMAND="check"
JSON=0
FORCE=0

usage() {
  cat <<'USAGE'
Usage: scripts/codexbar-cli-manager.sh [check|install|update] [options]

Commands:
  check       Report whether codexbar is installed and whether an update exists (default)
  install     Install codexbar if missing; update if older than latest release
  update      Same as install, but intended for explicit refresh actions

Options:
  --install-dir DIR   Install CodexBarCLI and codexbar symlink into DIR
                      Default: $CODEXBAR_INSTALL_DIR or ~/.local/bin
  --json              Emit machine-readable JSON status
  --force             Reinstall latest even if the installed version matches
  -h, --help          Show this help

Environment:
  GITHUB_TOKEN        Optional token for GitHub API rate limits
  CODEXBAR_INSTALL_DIR Override default install directory
USAGE
}

log() {
  if [[ "$JSON" != 1 ]]; then
    printf '%s\n' "$*" >&2
  fi
}

fail() {
  local msg="$1"
  if [[ "$JSON" == 1 ]]; then
    python3 - "$msg" <<'PY'
import json, sys
print(json.dumps({"ok": False, "error": sys.argv[1]}))
PY
  else
    printf 'error: %s\n' "$msg" >&2
  fi
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      check|install|update) COMMAND="$1"; shift ;;
      --install-dir) INSTALL_DIR="${2:-}"; [[ -n "$INSTALL_DIR" ]] || fail "--install-dir requires a value"; shift 2 ;;
      --json) JSON=1; shift ;;
      --force) FORCE=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) fail "unknown argument: $1" ;;
    esac
  done
}

arch_name() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'x86_64' ;;
    aarch64|arm64) printf 'aarch64' ;;
    *) fail "unsupported architecture: $(uname -m)" ;;
  esac
}

curl_auth_args=()
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  curl_auth_args=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

fetch_latest() {
  local arch api tmp
  arch="$(arch_name)"
  api="https://api.github.com/repos/${REPO}/releases/latest"
  tmp="$(mktemp)"
  curl -fsSL "${curl_auth_args[@]}" "$api" -o "$tmp" || fail "failed to fetch latest CodexBar release from GitHub"
  python3 - "$tmp" "$arch" <<'PY'
import json, sys
path, arch = sys.argv[1], sys.argv[2]
release = json.load(open(path))
tag = release.get("tag_name") or ""
asset_suffix = f"-linux-{arch}.tar.gz"
asset = None
sha = None
for a in release.get("assets", []):
    name = a.get("name", "")
    if name.endswith(asset_suffix) and not name.endswith(".sha256"):
        asset = a
    if name.endswith(asset_suffix + ".sha256"):
        sha = a
if not tag:
    raise SystemExit("missing tag_name in GitHub release")
if asset is None:
    raise SystemExit(f"missing Linux CLI asset for arch {arch}")
print(tag)
print(asset["name"])
print(asset["browser_download_url"])
print(sha.get("browser_download_url", "") if sha else "")
PY
  rm -f "$tmp"
}

normalize_version() {
  python3 - "$1" <<'PY'
import re, sys
s = sys.argv[1]
m = re.search(r'v?([0-9]+(?:\.[0-9]+)+(?:[-+][0-9A-Za-z.-]+)?)', s)
print('v' + m.group(1) if m else '')
PY
}

installed_path() {
  if command -v codexbar >/dev/null 2>&1; then
    command -v codexbar
  elif [[ -x "$INSTALL_DIR/codexbar" ]]; then
    printf '%s/codexbar\n' "$INSTALL_DIR"
  else
    return 1
  fi
}

installed_version() {
  local path out version marker
  path="$(installed_path 2>/dev/null)" || return 1
  out="$($path --version 2>/dev/null || true)"
  version="$(normalize_version "$out")"
  if [[ -n "$version" ]]; then
    printf '%s\n' "$version"
    return 0
  fi

  # If the binary cannot start because a shared library is missing, --version
  # will fail. For installs performed by this helper, keep a sidecar marker so
  # update checks can still distinguish "current but broken runtime" from
  # "older release".
  marker="$INSTALL_DIR/.codexbar-version"
  if [[ -r "$marker" ]]; then
    version="$(normalize_version "$(<"$marker")")"
    [[ -n "$version" ]] && printf '%s\n' "$version"
  fi
}

missing_libraries() {
  local path
  path="$1"
  [[ -n "$path" ]] || return 0
  command -v ldd >/dev/null 2>&1 || return 0
  ldd "$path" 2>/dev/null | awk '/not found/ {print $1}' | sort -u
}

dependency_hint() {
  local missing="$1"
  if grep -qx 'libxml2.so.2' <<<"$missing"; then
    printf 'Install the legacy libxml2 SONAME. On Arch/CachyOS: sudo pacman -S libxml2-legacy. Note: current libxml2 provides libxml2.so.16, but this CodexBarCLI build requires libxml2.so.2.'
  fi
}

fail_missing_libraries() {
  local missing="$1"
  local hint
  [[ -z "$missing" ]] && return 0
  hint="$(dependency_hint "$missing")"
  if [[ -n "$hint" ]]; then
    fail "codexbar cannot run; missing shared libraries: ${missing//$'\n'/, }. $hint"
  else
    fail "codexbar cannot run; missing shared libraries: ${missing//$'\n'/, }"
  fi
}

emit_status() {
  local installed path current latest asset update_available missing runtime_ok hint
  installed="$1"; path="$2"; current="$3"; latest="$4"; asset="$5"; update_available="$6"; missing="$7"
  runtime_ok=1
  [[ -n "$missing" ]] && runtime_ok=0
  hint="$(dependency_hint "$missing")"
  if [[ "$JSON" == 1 ]]; then
    python3 - "$installed" "$path" "$current" "$latest" "$asset" "$update_available" "$runtime_ok" "$missing" "$hint" <<'PY'
import json, sys
installed = sys.argv[1] == "1"
update = sys.argv[6] == "1"
runtime_ok = sys.argv[7] == "1"
missing = [line for line in sys.argv[8].splitlines() if line]
print(json.dumps({
  "ok": True,
  "installed": installed,
  "path": sys.argv[2] or None,
  "currentVersion": sys.argv[3] or None,
  "latestVersion": sys.argv[4] or None,
  "latestAsset": sys.argv[5] or None,
  "updateAvailable": update,
  "runtimeOk": runtime_ok if installed else None,
  "missingLibraries": missing,
  "dependencyHint": sys.argv[9] or None,
}, indent=2))
PY
  else
    if [[ "$installed" == 1 ]]; then
      printf 'codexbar installed: %s\n' "$path"
      printf 'current version: %s\n' "${current:-unknown}"
      if [[ "$runtime_ok" == 1 ]]; then
        printf 'runtime ok: yes\n'
      else
        printf 'runtime ok: no\n'
        printf 'missing libraries:\n'
        sed 's/^/  - /' <<<"$missing"
        [[ -n "$hint" ]] && printf '%s\n' "$hint"
      fi
    else
      printf 'codexbar installed: no\n'
    fi
    printf 'latest version: %s\n' "$latest"
    printf 'latest asset: %s\n' "$asset"
    if [[ "$update_available" == 1 ]]; then
      printf 'update available: yes\n'
    else
      printf 'update available: no\n'
    fi
  fi
}

install_latest() {
  local latest asset url sha_url tmp tarball sha_file expected actual extract_dir
  latest="$1"; asset="$2"; url="$3"; sha_url="$4"
  tmp="$(mktemp -d)"
  tarball="$tmp/$asset"
  sha_file="$tmp/$asset.sha256"
  extract_dir="$tmp/extract"
  mkdir -p "$extract_dir" "$INSTALL_DIR"

  log "Downloading $asset"
  curl -fL "${curl_auth_args[@]}" "$url" -o "$tarball" || fail "failed to download $asset"

  if [[ -n "$sha_url" ]]; then
    curl -fsSL "${curl_auth_args[@]}" "$sha_url" -o "$sha_file" || fail "failed to download checksum for $asset"
    expected="$(awk '{print $1; exit}' "$sha_file")"
    actual="$(sha256sum "$tarball" | awk '{print $1}')"
    [[ "$expected" == "$actual" ]] || fail "checksum mismatch for $asset"
  else
    log "No checksum asset found; skipping checksum verification"
  fi

  tar -xzf "$tarball" -C "$extract_dir" || fail "failed to extract $asset"
  [[ -x "$extract_dir/CodexBarCLI" ]] || fail "release archive did not contain executable CodexBarCLI"
  install -m 0755 "$extract_dir/CodexBarCLI" "$INSTALL_DIR/CodexBarCLI"
  ln -sfn "CodexBarCLI" "$INSTALL_DIR/codexbar"
  printf '%s\n' "$latest" > "$INSTALL_DIR/.codexbar-version"
  rm -rf "$tmp"

  log "Installed codexbar $latest to $INSTALL_DIR/codexbar"
}

main() {
  parse_args "$@"
  need curl
  need python3
  need tar
  need sha256sum

  mapfile -t latest_info < <(fetch_latest)
  local latest asset url sha_url path current installed update_available missing
  latest="${latest_info[0]}"
  asset="${latest_info[1]}"
  url="${latest_info[2]}"
  sha_url="${latest_info[3]:-}"

  path="$(installed_path 2>/dev/null || true)"
  current="$(installed_version 2>/dev/null || true)"
  missing="$(missing_libraries "$path")"
  installed=0
  [[ -n "$path" ]] && installed=1

  update_available=0
  if [[ "$installed" == 0 || -z "$current" || "$current" != "$latest" || "$FORCE" == 1 ]]; then
    update_available=1
  fi

  case "$COMMAND" in
    check)
      emit_status "$installed" "$path" "$current" "$latest" "$asset" "$update_available" "$missing"
      ;;
    install|update)
      if [[ "$update_available" == 1 ]]; then
        install_latest "$latest" "$asset" "$url" "$sha_url"
        path="$INSTALL_DIR/codexbar"
        current="$latest"
        missing="$(missing_libraries "$path")"
        installed=1
        update_available=0
      else
        log "codexbar is already up to date ($current)"
      fi
      fail_missing_libraries "$missing"
      emit_status "$installed" "$path" "$current" "$latest" "$asset" "$update_available" "$missing"
      ;;
  esac
}

main "$@"
