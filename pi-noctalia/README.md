# pi-noctalia

Noctalia-native plugin that shows live coding-agent activity in a compact bar capsule and a detailed panel.

In the panel, clicking a session row opens a new terminal and resumes that pi session. It prefers the exact pi session when session metadata is available, and otherwise falls back to `pi -c` in the session project directory.

## Install

Add this repository as a custom Noctalia plugin source, then install `pi-noctalia` from the plugin registry.

Repository:

- `https://github.com/ovestokke/noctalia-plugins`

After installation or updates, restart or reload Noctalia Shell if needed.

## Entry points

- `Main.qml` — shared state + IPC handlers
- `BarWidget.qml` — compact capsule for the bar
- `Panel.qml` — stacked session rows
- `Settings.qml` — persisted plugin settings

## IPC contract

```bash
qs -c noctalia-shell ipc call plugin:pi-noctalia update <id> <project> <status> <detail> <prompt> <ctxPct> <cwd> <sessionId> <sessionFile>
qs -c noctalia-shell ipc call plugin:pi-noctalia done <id>
qs -c noctalia-shell ipc call plugin:pi-noctalia error <id> [detail]
qs -c noctalia-shell ipc call plugin:pi-noctalia remove <id>
qs -c noctalia-shell ipc call plugin:pi-noctalia clear
qs -c noctalia-shell ipc call plugin:pi-noctalia demo
```

Supported statuses:

- `thinking`
- `reading`
- `editing`
- `writing`
- `running`
- `searching`
- `done`
- `error`
