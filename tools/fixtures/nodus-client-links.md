# Plain-text links in Nodus clients

Client presentation contract, version 1. No API, schema, stored-text, or sync changes.

## Detection

- Linkify explicit `http://` and `https://` URLs, case-insensitively. Bare domains, `www.example.com`, email addresses, and other schemes stay plain text. Do not add a scheme on the user's behalf.
- A URL begins at the start of text, after whitespace, or after one of `(`, `[`, `{`, `<`, `>`, single/double quotes, curly opening quotes, comma, semicolon, exclamation mark, or question mark. Do not extract an embedded URL from a word, email, or another scheme such as `javascript:https://example.com`.
- Read up to whitespace, a control character (U+0000–001F or U+007F–009F), `<`, `>`, a single/double quote (including curly `‘ ’ “ ”`), backtick, or backslash. A newline ends the URL; display the original multiline text unchanged.
- Remove trailing sentence punctuation `. , ! ? ; :` from the link span, not from the displayed text. Remove a trailing `)`, `]`, or `}` only when it has no matching opening character within the candidate. Repeat until no trim applies. Balanced parentheses/brackets/braces inside a URL are retained. This deliberately treats ambiguous terminal punctuation as prose.
- Require a nonempty authority/host after `://`, not just dots/hyphens. Do not link user-info authorities (`user:password@host`), malformed ports, or candidates containing control/bidirectional-format characters (U+061C, U+200E–200F, U+202A–202E, U+2066–2069). Hosts may contain ASCII letters/digits, dots and hyphens or Unicode characters; optional decimal ports are 1–65535. Bracketed IPv6 literals may contain hexadecimal digits, dots and colons and must contain a colon. Reject other reserved characters in a host. The platform may additionally reject a malformed destination when opening.
- Preserve Unicode and percent-encoded characters in labels and destinations. IDNA/percent encoding required by the platform opener is transport handling, not a stored-text rewrite. Do not decode text before detection. Do not use HTML/Markdown interpretation to implement plain-text links.

Each match is the original text substring plus that same substring as its destination. Concatenating all linked and unlinked segments must reproduce the exact input, including spaces, line breaks, punctuation and markup-looking text. Existing and completed checklist items use the same rules.

## Opening and interaction

- Open only a validated absolute HTTP(S) destination using the platform's ordinary external browser mechanism. Recheck the allowed scheme at the opening boundary; do not launch shell commands.
- Open only on deliberate link activation. No network requests, previews, credential handling or server updates occur during rendering.
- Link activation must not toggle the containing checkbox, activate its label, open a note editor, or initiate a note mutation. Ordinary checkbox/text-row interactions remain intact.
- Web links use native anchors, a new tab, `rel="noopener noreferrer"`, and stop link-click propagation. Native clients consume the corresponding link gesture and use their safe URL opener. Preserve keyboard accessibility and ordinary text selection.
- Editable text fields remain raw text. Provide links on existing read-only surfaces; do not replace editable input with rich text or automatically save/reformat it.

## Approved Noctalia presentation fallback

The current native Noctalia plugin API has no inline-link spans; its Markdown renderer discards link destinations. The owner approved using existing native actions instead of changing the host: make URL-only text clickable/wrapping, and preserve mixed text with separate per-URL actions below it. Active/completed checklist actions remain independent of checkbox activation. Use validated direct argv for `xdg-open`, never a shell. This is a presentation limitation, not identical inline UX or a text-selection guarantee. No source text is converted to Markdown.

## Existing Markdown

The web's established Markdown rendering remains available when `markdownEnabled` is true. Explicit Markdown links/code and GFM syntax retain their existing rendering semantics and sanitization. This contract governs plain-text linkification (including checklist labels and notes with Markdown disabled), not a replacement Markdown parser. Normal explicit HTTP(S) text URLs already rendered by Markdown must remain clickable and must not bubble into note actions. Other clients need not add Markdown support for this feature.

## Shared acceptance fixtures

[`web/tests/fixtures/client-link-fixtures.json`](../web/tests/fixtures/client-link-fixtures.json) supplies input strings and ordered expected link labels/destinations. All three clients should run those fixtures and preserve the complete original input. Add client-specific interaction checks: active/completed checklist links open without toggling, note links do not open an editor, raw editing is unchanged, and unsafe schemes do not open. Tests must use synthetic content and stub or intercept the external opener, not contact destinations.

Source ownership: this repository owns server and web only; Android and Noctalia implement and validate the same fixtures in their own repositories. This feature does not authorize publication or deployment.
