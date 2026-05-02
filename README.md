# Ove's Noctalia Plugin Registry

This is a small custom Noctalia plugin registry containing a few experimental plugins:

- `pi-noctalia` — Dynamic-Island-style coding-agent activity capsule for Noctalia Shell
- `codexbar-noctalia` — AI coding assistant usage monitor backed by the CodexBar CLI

## Install as a custom registry

Add this repository as a custom plugin source in Noctalia Shell, then install `pi-noctalia` or `codexbar-noctalia` from the registry.

Repository:

- `https://github.com/ovestokke/noctalia-plugins`

This registry is intended to stay minimal while `pi-noctalia` evolves outside the official plugin registry.

## Repository layout

```text
pi-noctalia/
codexbar-noctalia/
registry.json
schema.json
README.md
```

## Notes

This fork is intentionally trimmed down to personal/experimental plugins so they are easier to maintain while evolving.

If a plugin matures enough for upstreaming, it can later be proposed to the official Noctalia plugins repository.
