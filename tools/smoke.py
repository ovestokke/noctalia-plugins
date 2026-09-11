#!/usr/bin/env python3
"""Small repository checks for the Noctalia Memos source."""

from __future__ import annotations

import json
import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLUGIN = ROOT / "memos"


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def load_toml(path: Path) -> dict:
    with path.open("rb") as handle:
        return tomllib.load(handle)


def main() -> int:
    manifest = load_toml(PLUGIN / "plugin.toml")
    catalog = load_toml(ROOT / "catalog.toml")

    if manifest.get("id") != "ovestokke/memos":
        fail("unexpected plugin id")
    if manifest.get("plugin_api") != 22:
        fail("plugin_api must stay at 22")
    catalog_plugins = catalog.get("plugin", [])
    if len(catalog_plugins) != 1:
        fail("catalog must index exactly one plugin")
    catalog_plugin = catalog_plugins[0]
    for field in (
        "id",
        "name",
        "version",
        "author",
        "license",
        "icon",
        "description",
        "plugin_api",
        "tags",
        "dependencies",
    ):
        if catalog_plugin.get(field) != manifest.get(field):
            fail(f"catalog and manifest field differs: {field}")

    entries = []
    for kind in ("widget", "panel", "service"):
        entries.extend(manifest.get(kind, []))
    for entry in entries:
        path = PLUGIN / entry["entry"]
        if not path.is_file():
            fail(f"missing entry file: {path.relative_to(ROOT)}")

    settings = {setting["key"] for setting in manifest.get("setting", [])}
    if settings != {"instance_url", "token_file"}:
        fail("the manifest must contain only instance_url and token_file settings")

    for locale in ("en", "nb"):
        path = PLUGIN / "translations" / f"{locale}.json"
        with path.open(encoding="utf-8") as handle:
            value = json.load(handle)
        if not isinstance(value, dict):
            fail(f"{path.relative_to(ROOT)} must contain a JSON object")

    source = "\n".join(path.read_text(encoding="utf-8") for path in PLUGIN.rglob("*.luau"))
    panel_source = (PLUGIN / "panel.luau").read_text(encoding="utf-8")
    service_source = (PLUGIN / "service.luau").read_text(encoding="utf-8")
    required = (
        "/api/v1/auth/me",
        "/api/v1/memos",
        "/api/v1/sse",
        "Authorization: Bearer ",
        'visibility = "PRIVATE"',
        "reminderTime",
        "noctalia.notify",
        "noctalia.httpStream",
    )
    for marker in required:
        if marker not in source:
            fail(f"missing required integration marker: {marker}")

    for key, hour in (("0700", 7), ("1200", 12), ("1600", 16), ("2000", 20)):
        if f'{{ key = "{key}", hour = {hour},' not in panel_source:
            fail(f"missing reminder preset: {key}")
    if "local initial = os.time() + 5 * 60" not in panel_source:
        fail("custom reminder must default to five minutes from now")

    # Preserve the locally tested stream handling; extra reconnect fetches
    # are intentionally outside this recovery change.
    if 'if line == ": connected" or line == ": heartbeat" then' not in service_source:
        fail("SSE connection and heartbeat handling changed")
    manual_refresh = re.search(
        r'if command\.action == "refresh" then\s+if connected then\s+'
        r'fetchMemos\(\)\s+fetchSpaces\(\)',
        service_source,
    )
    if manual_refresh is None:
        fail("manual refresh must reconcile memos and Spaces")

    if re.search(r"allow_insecure_tls\s*=\s*true", source):
        fail("TLS verification must not be disabled")
    if re.search(r"\bcurl\b", source):
        fail("credentials must stay in Noctalia's native HTTP client")
    if re.search(r"noctalia\.log\s*\(", source):
        fail("network code must not log credential-bearing values")

    print("Smoke checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
