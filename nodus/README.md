# Nodus for Noctalia (local prototype)

Read text and checklist notes, browse active/archive/trash, create text notes and checklists, and mark existing checklist items done or not done in Nodus v2. This is an **experimental catalog entry**, not a production-ready sync client. Editing existing text/item content, adding or deleting existing items, offline writes, reminders, conflict resolution and recovery from a changed realm are not supported. Do not use it for irreplaceable notes until the server's deployment and backup gates are complete.

## Linux setup

Requires Noctalia plugin API 24+, `go`, `secret-tool` (libsecret), an unlocked Secret Service keyring and a working Nodus v2 server. The helper and plugin run as your desktop user.

```sh
cd nodus/helper
go build -o ~/.local/bin/nodus-noctalia .
# In the Nodus web app: create a short-lived pairing code.
~/.local/bin/nodus-noctalia pair https://YOUR-NODUS-ORIGIN
```

Run pairing **in a terminal**: it reads the code from `/dev/tty` with echo disabled. Never put the code, credential or note contents on a command line. Only HTTPS origins are accepted outside loopback. The paired credential and pending redemption tuple live in Secret Service; the helper does not store bearer material in its state directory. If redemption has an unknown outcome, run `pair` again with the **same origin** to retry the original tuple. Do not generate another pairing automatically.

From the repository root, add this checkout as a local source and enable the plugin:

```sh
noctalia msg plugins source add nodus-dev path "$PWD"
noctalia msg plugins enable ovestokke/nodus
```

Add its bar widget, open the panel, and press Refresh. The helper is expected at `~/.local/bin/nodus-noctalia`; restart Noctalia if its plugin API is older than 24. No files in the Nodus CLI's private directory are imported, moved, or modified.

The helper uses `$XDG_STATE_HOME/nodus-noctalia` (or `~/.local/state/nodus-noctalia`) for a private 0700 profile, exact-write journal, drafts and full feed cache. These contain **unencrypted note content**, not credentials. The Go helper writes its state with file and directory sync. Noctalia passes note intent to the helper through a pre-created private 0600 draft file, not argv. Only the helper makes authenticated HTTP requests. If the keyring is unavailable, the plugin does not fall back to plaintext credentials.

## Safety and limits

- Changes are read from `/api/v2/changes` at a fixed watermark, 10 events per page. The UI loads 40 cached notes at a time; Refresh continues the feed. Opening the note or list composer switches the small drawer to a full-height editor; Save returns to browsing, while Discard confirms before removing a non-empty local draft. The adjacent list action creates checklists with initial items. Existing checklists support only absolute check/uncheck using each item's revision. Checked items move below a divider and are struck through **in the panel only**; no reorder request changes the server's item positions.
- Creates and check/uncheck are online-only. Before sending, the helper durably records the exact request bytes and identity. A lost response blocks further creates. **Retry exact request** uses that journal, never a new request ID. If the credential or realm changes, the old journal is preserved and replay is blocked.
- A server realm change is deliberately blocked. Keep the state directory and resolve the old graph/outbox manually; do not delete journals to bypass this state.
- The helper keeps private unencrypted note snapshots/drafts; the Noctalia UI receives note content to display it. Other plugins or processes running as the same OS user may be able to access that content. There is no encrypted offline cache.
- On first load, a large history takes multiple polls. The panel shows cached notes while the remaining pages load. No background work occurs while Noctalia is stopped.

## Checks

```sh
(cd nodus/helper && go test -count=1 ./... && go vet ./...)
noctalia plugins lint nodus
python3 tools/smoke.py
```

The helper's tests use a fake Secret Service command and a disposable HTTP server. They do **not** test live pairing, a real unlocked keyring, or Noctalia's UI runtime; those require a local end-to-end check before release.
