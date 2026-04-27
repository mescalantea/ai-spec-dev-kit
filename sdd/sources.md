# Source Adapters

Specs can come from different systems. Each source implements the same contract so `/spec-draft`, `/spec-plan`, and `/spec-build` can handle it uniformly via the `spec-source` skill.

The active adapter is set by the top-level `source` field in `.sdd/config.json` (one of `local`, `jira`, `youtrack`). Per-adapter config lives under the `sources` key.

## Contract

Every adapter defines four operations:

| Operation | Input | Output | Used by |
|---|---|---|---|
| `pull(ref)` | external reference | markdown body (no frontmatter) | `/spec-draft` |
| `adapt(body)` | raw external body | markdown matching `.sdd/specs/template/spec.md` | `/spec-draft` |
| `push(ref, body)` | reference + body (frontmatter stripped) | success/failure | `/spec-plan`, `/spec-build` |
| `detect_conflict(ref, cached_body)` | reference + last-known body | `(has_conflict, diff)` | `/spec-plan`, `/spec-build` |

Cache: `.sdd/specs/.cache/<spec_id>.<source>.md`, written on every successful `pull` or `push`, gitignored.

## Frontmatter rule

Frontmatter is local-only. Never push it. Always strip between the first and second `---` before pushing. `pull` returns body only — frontmatter in the local file is preserved and updated separately.

## Registered adapters

### `local` (default)

- `pull`: no-op, empty template body.
- `adapt`: no-op.
- `push`: no-op (local file IS source of truth).
- `detect_conflict`: always `(false, "")`.

### `jira`

Uses the Atlassian CLI (`acli`). Requires prior `acli auth login`. On auth failure, print:
```
Run `acli auth login`, then type "continue" to retry.
```
and wait.

- `pull(ref)`: `acli jira workitem view --key <ref> --json`, extract `description`. Empty → empty template body. The returned description may be in Jira wiki markup — convert it to markdown (reverse of the `push` conversion table) before returning the body.
- `adapt(body)`: match sections to template headers. If mismatched: map into closest sections, leave unmatched as `...`, append unmapped under `## Original Description`. Show proposal, require `continue` before writing.
- `push(ref, body)`:
  1. Strip frontmatter (everything between the first and second `---`, inclusive).
  2. Strip the first `# Spec: …` heading line — Jira already uses the ticket summary as the title; a duplicate h1 in the description is redundant and renders poorly.
  3. Strip HTML comments (`<!-- … -->`).
  4. **Convert markdown → Jira wiki markup** before writing to the temp file. Jira descriptions do not render markdown; they require Jira wiki notation. Apply these transformations in order:

     | Markdown | Jira wiki |
     |---|---|
     | `#### heading` | `h4. heading` |
     | `### heading` | `h3. heading` |
     | `## heading` | `h2. heading` |
     | `# heading` | `h1. heading` |
     | `**bold**` | `*bold*` |
     | `*italic*` (when not inside a list marker) | `_italic_` |
     | `` `inline code` `` | `{{inline code}}` |
     | ` ```lang\n…\n``` ` | `{code:lang}\n…\n{code}` (omit `:lang` when absent) |
     | `[text](url)` | `[text\|url]` |
     | `~~strikethrough~~` | `-strikethrough-` |
     | `> blockquote` (consecutive lines) | `{quote}\n…\n{quote}` |
     | `---` (horizontal rule, standalone line) | `----` |
     | `- [ ] item` | `* (x) item` |
     | `- [x] item` | `* (/) item` |
     | `- item` (unordered list) | `* item` |
     | `  - nested` (2-space indent) | `** nested` |
     | `1. item` (ordered list) | `# item` |

     Process fenced code blocks first (preserve their contents verbatim), then apply the remaining transformations to non-code-block text.

  5. Write the converted body to a temp file.
  6. Run `acli jira workitem edit --key <ref> --description-file=<tmp>`.
  7. On success → overwrite `.sdd/specs/.cache/<ref>.jira.md` with the **original markdown** body (not the converted wiki markup) so that `detect_conflict` and future pushes compare markdown against markdown.

- `detect_conflict(ref, cached_body)`: pull current Jira body, diff against `cached_body`. If different, require `continue` before overwrite.

### `youtrack`

Uses the YouTrack REST API via `curl`. Requires the `YOUTRACK_TOKEN` env var (or the name configured in `token_env`) to be set to a permanent YouTrack token. Also requires `jq` (preferred) or `python3` for JSON extraction — both must be on PATH.

`base_url` must be the instance root with no trailing slash and no `/api` suffix (e.g. `https://myteam.youtrack.cloud` or `https://youtrack.example.com`).

**Do not log or echo the Authorization header or token value in error messages.**

On auth failure (HTTP 401/403), print:
```
Set $<token_env> to a valid YouTrack permanent token, then type "continue" to retry.
```
and wait.

JSON extraction (apply to all operations that read responses):
```bash
# Preferred (jq):
description=$(echo "$response" | jq -r '.description // ""')

# Fallback (python3):
description=$(echo "$response" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('description') or '')")
```

**`$type` field:** YouTrack responses include a `$type` key. In jq, `.$type` is a syntax error (`$` starts a variable binding). Always use bracket notation: `.["$type"]`.

- `pull(ref)`: `curl -sS -H "Authorization: Bearer $TOKEN" "$base_url/api/issues/$ref?fields=description"`, extract `description` field. Empty or null → empty template body.
- `adapt(body)`: same as Jira — match content against template headers; unmapped content → append under `## Original Description`; show proposal; require `continue` before writing.
- `push(ref, body)`: if `ref` is null/empty, print `YouTrack push skipped: no source_ref set. Create the issue in YouTrack and set source_ref in frontmatter.` and stop. Otherwise: strip frontmatter, strip the first `# Spec: …` heading line (YouTrack already displays the issue summary), strip HTML comments (`<!-- … -->`), write to temp file, run `curl -sS -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" "$base_url/api/issues/$ref" -d "{\"description\": $(jq -Rs . < "$tmpfile")}"`. Verify success: `echo "$response" | jq -e '.["$type"] == "Issue"'` (or python3 equivalent). On success, overwrite `.sdd/specs/.cache/<ref>.youtrack.md` with the pushed body. On failure, print the response body and stop.
- `detect_conflict(ref, cached_body)`: pull current remote body, diff against `cached_body`. If different, require `continue` before overwrite (same logic as Jira).

## Adding an adapter

1. Add a section here with the four operations.
2. Add a key under `sources` in `.sdd/config.json`. The user selects the adapter during `spec-init` via the top-level `source` field.
3. No skill or command changes — they read this catalog at runtime.
