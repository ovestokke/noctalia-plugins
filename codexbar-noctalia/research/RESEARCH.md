# Research Summary: Noctalia × CodexBar Plugin

**Date**: 2026-04-30

## What is CodexBar?

A macOS 14+ menu bar app by [steipete](https://github.com/steipete) that tracks AI coding assistant usage limits across **20+ providers**: Codex, Claude, Cursor, Gemini, Antigravity, Droid (Factory), Copilot, z.ai, Kiro, Vertex AI, Augment, Amp, JetBrains AI, OpenRouter, Perplexity, Abacus AI, DeepSeek, MiniMax, Mistral, Ollama, and more.

Key feature for us: ships a **CLI executable** (`codexbar`) with Linux support, purpose-built for script/CI/Waybar integration.

### Install

```bash
# Homebrew (Linux)
brew install steipete/tap/codexbar

# Or download tarball from GitHub Releases
# CodexBarCLI-v<tag>-linux-<arch>.tar.gz
```

### CLI basics

```bash
codexbar                          # text, all enabled providers
codexbar --format json --pretty   # JSON output
codexbar --provider claude        # specific provider
codexbar --provider all           # all providers
codexbar cost                     # local cost usage (last 30 days)
codexbar --status                 # include provider status/incidents
codexbar config validate          # check config
codexbar config dump              # print normalized config
```

See [codexbar-cli.md](codexbar-cli.md) for the full CLI reference.

---

## What is Noctalia?

A Wayland desktop shell (niri-based) with a QML plugin system. Plugin repo: [noctalia-dev/noctalia-plugins](https://github.com/noctalia-dev/noctalia-plugins).

Plugin structure:
```
plugin-name/
├── manifest.json      # Required
├── preview.png        # 16:9 @ 960x540 (required)
├── README.md          # Required
├── Main.qml           # Main component / IPC logic
├── BarWidget.qml      # Bar widget
├── Panel.qml          # Detail panel
├── Settings.qml       # Settings UI
└── i18n/              # Translations
```

Config lives at `~/.config/noctalia/plugins/<id>/`. Plugin registry managed via `plugins.json`.

---

## Existing Noctalia plugin: `model-usage`

**Closest existing plugin** — v0.2.1 by `cmptr`, in official registry.

Covers: Claude, Codex, Copilot, OpenRouter, Zen (5 providers).

### How it works
- Reads local files directly (`~/.codex/history.jsonl`, `~/.codex/sessions/*.jsonl`, `~/.claude/stats-cache.json`, etc.)
- Each provider is a separate QML file (`providers/Codex.qml`, `providers/Claude.qml`, etc.)
- Bar widget shows one metric for the active provider; panel shows detail cards

### Comparison with CodexBar CLI approach

| Aspect | `model-usage` plugin | CodexBar CLI approach |
|---|---|---|
| Data source | Reads local files directly | Calls `codexbar` CLI (handles auth, cookies, OAuth, APIs) |
| Providers | 5 (Claude, Codex, Copilot, OpenRouter, Zen) | **20+** (all CodexBar providers) |
| Auth handling | Reads credential files manually; no browser cookie/OAuth | CodexBar handles OAuth flows, browser cookies, API keys, Keychain |
| Session/weekly meters | Partial — parses rate_limits from Codex session JSONL | Full — structured `primary`/`secondary`/`tertiary` usage + reset times |
| Credits tracking | ❌ | ✅ Full credits, cost history, plan utilization |
| Provider status/incidents | ❌ | ✅ `--status` flag |
| Local cost data | ❌ | ✅ `codexbar cost` |
| Maintenance burden | High — each provider's file format changes independently | Low — `codexbar` binary is steipete's problem |
| Dependency | None (pure file reads) | Requires `codexbar` binary installed |

---

## Verdict: Build a CodexBar-backed plugin

### Why

1. **`model-usage` is architecturally limited** — manual file parsing per provider doesn't scale to 20+ providers and breaks when upstream formats change
2. **CodexBar CLI is purpose-built for this** — JSON output, Linux support, handles all auth complexity. The README explicitly mentions "Linux support via Omarchy: community Waybar module and TUI, driven by the `codexbar` executable"
3. **Plugin stays thin and durable** — just a QML wrapper around the CLI

### Architecture sketch

```
codexbar-noctalia/
├── manifest.json
├── Main.qml            # Process runner + timer + JSON parser + IPC
├── BarWidget.qml       # Compact usage capsule (cycle providers)
├── Panel.qml            # Per-provider cards: session %, weekly %, credits, resets, status
├── Settings.qml        # CLI path, enabled providers, refresh interval, display mode
├── i18n/en.json
├── preview.png
└── README.md
```

### Data flow

1. Timer fires (configurable interval, e.g. 30s / 1m / 2m / 5m)
2. Spawn `codexbar --format json [--status]` via QML `Process`
3. Parse JSON output — array of provider objects
4. Bind parsed properties to BarWidget + Panel QML
5. Optionally: `codexbar cost --format json` for local cost tab

### Settings

| Key | Type | Default | Notes |
|---|---|---|---|
| `codexbar.path` | string | `"codexbar"` | Path or name of CLI binary |
| `providers` | string[] | `[]` | Empty = all enabled in `~/.codexbar/config.json` |
| `refreshIntervalSec` | int | `120` | Timer interval |
| `barDisplayMode` | string | `"active"` | `"active"` / `"cycle"` / `"worst"` |
| `barCycleIntervalSec` | int | `5` | Cycle speed |
| `barMetric` | string | `"session"` | `"session"` / `"weekly"` / `"credits"` |
| `includeStatus` | bool | `true` | Fetch provider status pages |
| `includeCost` | bool | `false` | Also run `codexbar cost` |

### IPC contract (proposed)

```bash
qs -c noctalia-shell ipc call plugin:codexbar-noctalia refresh
qs -c noctalia-shell ipc call plugin:codexbar-noctalia toggle
qs -c noctalia-shell ipc call plugin:codexbar-noctalia open
qs -c noctalia-shell ipc call plugin:codexbar-noctalia close
```

---

## CodexBar JSON schema (key fields)

From `codexbar --format json --pretty`:

```json
[
  {
    "provider": "codex",
    "version": "0.6.0",
    "source": "openai-web",
    "status": {
      "indicator": "none",
      "description": "Operational",
      "updatedAt": "...",
      "url": "https://status.openai.com/"
    },
    "usage": {
      "primary": { "usedPercent": 28, "windowMinutes": 300, "resetsAt": "..." },
      "secondary": { "usedPercent": 59, "windowMinutes": 10080, "resetsAt": "..." },
      "tertiary": null,
      "updatedAt": "...",
      "identity": {
        "providerID": "codex",
        "accountEmail": "user@example.com",
        "accountOrganization": null,
        "loginMethod": "plus"
      }
    },
    "credits": { "remaining": 112.4, "updatedAt": "..." }
  }
]
```

From `codexbar cost --format json`:

```json
[
  {
    "provider": "codex",
    "source": "local",
    "updatedAt": "...",
    "sessionTokens": 12345,
    "sessionCostUSD": 0.45,
    "last30DaysTokens": 987654,
    "last30DaysCostUSD": 12.34,
    "daily": [
      {
        "date": "2025-12-04",
        "inputTokens": 5000,
        "outputTokens": 3000,
        "cacheReadTokens": 2000,
        "cacheCreationTokens": 100,
        "totalTokens": 10100,
        "totalCost": 1.23,
        "modelsUsed": ["o3"],
        "modelBreakdowns": [{ "modelName": "o3", "cost": 1.23 }]
      }
    ],
    "totals": { "inputTokens": ..., "outputTokens": ..., "totalTokens": ..., "totalCost": ... }
  }
]
```

---

## Open questions

1. **Provider icons** — CodexBar has its own icon set. Should we embed SVGs or use available symbolic icons?
2. **Error states** — how to surface CLI timeout, missing binary, auth failures in the bar widget
3. **Merge with `model-usage`?** — Could contribute a CodexBar provider module to the existing plugin, but architectures are fundamentally different (file reads vs. CLI calls)
4. **Multi-account** — CodexBar supports `--account` / `--all-accounts`. Worth exposing in the panel?
