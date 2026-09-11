# Memos

Memos adds a small bar status widget and an attached capture panel to Noctalia v5. It reads your own recent memos, creates private memos with optional reminders, and refreshes the list when the server sends a live change event.

## Plugin

| Field | Value |
| --- | --- |
| ID | `ovestokke/memos` |
| Entries | Widget: `bar`; panel: `panel`; service: `service` |
| Required plugin API | 22 |

The service owns the personal access token and all network requests. The panel and widget receive status and memo data through Noctalia's in-memory plugin state. The token is never copied into that shared state.

## Usage

### 1. Add this source

Add the published repository as a git source:

```sh
noctalia msg plugins source add ovestokke git \
  https://github.com/ovestokke/noctalia-plugins
noctalia msg plugins enable ovestokke/memos
```

For local development, add the repository root, not the `memos/` subdirectory:

```sh
noctalia msg plugins source add ovestokke-dev path /path/to/noctalia-plugins
noctalia msg plugins enable ovestokke/memos
```

### 2. Configure Memos

Create a personal access token in your Memos account settings. Open **Settings → Plugins → Memos** and set **Instance URL** to the base URL, for example `https://memos.example.com`. HTTPS is required unless the instance is on `localhost`, `127.0.0.1`, or `[::1]`.

Open the Memos panel, select the settings button, paste the token into the **Access token** field, and select **Save token**. The plugin stores it under Noctalia's persistent plugin data directory. It sets the directory to mode `0700` before writing and the token file to mode `0600` afterward. The token is not stored in TOML, shared plugin state, logs, or process arguments.

An advanced **External token file** setting is available for users who manage credentials outside Noctalia. When set, it overrides the token saved from the panel. Create that file yourself and protect it:

```sh
install -d -m 700 ~/.config/noctalia
printf '%s\n' 'YOUR_MEMOS_PAT' > ~/.config/noctalia/memos.token
chmod 600 ~/.config/noctalia/memos.token
```

Add the `bar` widget from the bar widget picker. Click it to open the panel. The service validates the token with `GET /api/v1/auth/me`, lists the authenticated user's latest 20 memos, and opens an authenticated `/api/v1/sse` stream. A `memo.changed` event triggers a fresh list request. Reconnect delays increase to 60 seconds; there is no periodic memo polling.

The capture field accepts multiline Markdown. A reminder can be omitted, entered as an exact local date and time, or selected with the `07:00`, `12:00`, `16:00`, and `20:00` shortcuts. A shortcut chooses its next occurrence: if that time has already passed today, it schedules tomorrow. Press **Ctrl+Enter** or click **Save memo**. New memos use `state: NORMAL`. The Space selector in the header controls both the list and the destination for new memos: **Personal** creates private notes without a Space; selecting a Space creates notes shared with its members. The list includes accessible notes from other members, but their edit, pin, and archive actions are disabled. Open reminder options with the calendar button.

Reminder timestamps are stored in Memos' standard `reminderTime` field, so every client sees the same schedule. The Noctalia service fetches the authenticated user's reminders and emits a local Noctalia notification when one becomes due, with a 24-hour catch-up window after sleep or downtime. Memos itself does not send reminder push notifications: each web or mobile client must schedule its own local notification. A future mobile client can therefore reuse the synced timestamp, but reliable mobile background alerts are not provided by this plugin alone.

Open the panel directly when testing:

```sh
noctalia msg panel-toggle ovestokke/memos:panel
```

Force a connection validation and refresh through the service:

```sh
noctalia msg plugin ovestokke/memos:service all validate
```

Each memo has icon buttons to pin or unpin, edit its content, and archive it. Pinned memos appear first. Archiving removes a memo from this list without permanently deleting it. Editing preserves its visibility and reminder.

## Settings

`instance_url` and the optional `token_file` override are plugin-level Noctalia settings. The panel's settings view manages the personal access token separately so it never enters Noctalia's TOML configuration. Noctalia restarts the service when either manifest setting changes.

## Checks

Run the repository smoke check and Noctalia's offline plugin lint:

```sh
python3 tools/smoke.py
python3 tools/test_crud.py
python3 tools/test_spaces.py
noctalia plugins lint memos
nix shell nixpkgs#luau --command sh -lc \
  'for file in memos/*.luau memos/lib/*.luau; do luau-compile "$file" >/dev/null || exit 1; done'
nix shell nixpkgs#luau-lsp --command luau-lsp analyze \
  --definitions noctalia.d.luau --base-luaurc .luaurc --platform standard \
  memos/bar.luau memos/panel.luau memos/service.luau \
  memos/lib/client.luau memos/lib/format.luau memos/lib/reminder.luau
```

Run the vendored official publication validator:

```sh
python3 .github/workflows/validate-plugins.py --root .
```

`luau-lsp` uses the current official Noctalia definitions through `.vscode/settings.json`. The local lint and static checks do not execute network callbacks or render the panel, so connection, capture, SSE, and notification behavior should also be tested in a running Noctalia session.

## Security notes

- HTTPS certificate and hostname verification remain enabled. The plugin never sets `allow_insecure_tls`.
- Plain HTTP is accepted only for loopback hosts.
- Authorization uses `Bearer` headers in Noctalia's native HTTP APIs. The token does not appear in a process command line.
- The managed credential directory is changed to mode `0700` before the token is written; the token is then changed to mode `0600`.
- Error state contains only a status category and HTTP status number. Response bodies and credentials are not logged.

## Not in this version

Permanent deletion, attachments, moving notes between Spaces, Space administration, and launcher integration are not implemented in this release.
