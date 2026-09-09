# Noctalia plugins

Noctalia v5 plugins maintained by Ove Stokke.

## Plugins

| Plugin | Description |
| --- | --- |
| [`ovestokke/memos`](memos/) | Capture private Memos notes, browse recent notes, and receive synchronized reminders. |

## Install

Add this repository as a Noctalia git source, then enable the plugin:

```sh
noctalia msg plugins source add ovestokke git \
  https://github.com/ovestokke/noctalia-plugins
noctalia msg plugins enable ovestokke/memos
```

Add the Memos bar widget from Noctalia's widget picker. Under **Settings → Plugins → Memos**, configure the Memos instance URL. Open the plugin panel's settings view to save a personal access token locally.

Noctalia updates custom git sources automatically when plugin auto-updates are enabled. To update this source manually:

```sh
noctalia msg plugins update ovestokke
```

See [`memos/README.md`](memos/README.md) for configuration, security details, tests, and current limitations.

## Local development

Add the repository root as a path source:

```sh
noctalia msg plugins source add ovestokke-dev path /path/to/noctalia-plugins
noctalia msg plugins enable ovestokke/memos
```

Noctalia expects `catalog.toml` at the repository root and each plugin in its own subdirectory.
