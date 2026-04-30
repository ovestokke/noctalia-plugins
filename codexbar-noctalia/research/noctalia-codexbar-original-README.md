# nocatalia-codexbar

> Noctalia plugin that surfaces AI coding assistant usage data via the [CodexBar](https://github.com/steipete/CodexBar) CLI executable.

## Why this plugin?

[CodexBar](https://github.com/steipete/CodexBar) (by Peter Steinberger / steipete) is a macOS menu bar app tracking AI usage limits across 20+ providers. It ships a **CLI executable** (`codexbar`) with full JSON output and **Linux support** — purpose-built for scripts, CI, and Waybar integration.

Noctalia (our Wayland desktop shell) has no plugin that leverages this executable. The closest existing plugin, `model-usage`, manually parses local provider files (limited to 5 providers, no cookie/OAuth support, no credits, no status). A CodexBar-backed plugin would be thinner, more durable, and cover all 20+ providers with zero per-provider parsing logic.

## Status

🔍 **Research phase** — no code yet. See [research/](research/) for findings.

## Quick links

- [Research summary](research/RESEARCH.md)
- [CodexBar CLI install/update helper](research/codexbar-cli-install-update.md)
- [CodexBar CLI reference](research/codexbar-cli.md)
- [Existing plugin analysis](research/existing-plugins.md)
