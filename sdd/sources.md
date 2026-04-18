# Source Adapters

Specs can come from different systems. Each source implements the same contract so `/spec-draft`, `/spec-plan`, and `/spec-build` can handle it uniformly via the `spec-source` skill.

Enabled adapters and their config live in `.sdd/config.json` under `sources`.

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

- `pull(ref)`: `acli jira workitem view <ref> --json`, extract `description`. Empty → empty template body.
- `adapt(body)`: match sections to template headers. If mismatched: map into closest sections, leave unmatched as `...`, append unmapped under `## Original Description`. Show proposal, require `continue` before writing.
- `push(ref, body)`: strip frontmatter, write to temp file, run `acli jira workitem edit <ref> --description-file=<tmp>`, then overwrite `.sdd/specs/.cache/<ref>.jira.md` with the pushed body.
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

- `pull(ref)`: `curl -sS -H "Authorization: Bearer $TOKEN" "$base_url/api/issues/$ref?fields=description"`, extract `description` field. Empty or null → empty template body.
- `adapt(body)`: same as Jira — match content against template headers; unmapped content → append under `## Original Description`; show proposal; require `continue` before writing.
- `push(ref, body)`: if `ref` is null/empty, print `YouTrack push skipped: no source_ref set. Create the issue in YouTrack and set source_ref in frontmatter.` and stop. Otherwise: strip frontmatter, write to temp file, run `curl -sS -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" "$base_url/api/issues/$ref" -d "{\"description\": $(jq -Rs . < "$tmpfile")}"`, then overwrite `.sdd/specs/.cache/<ref>.youtrack.md` with the pushed body.
- `detect_conflict(ref, cached_body)`: pull current remote body, diff against `cached_body`. If different, require `continue` before overwrite (same logic as Jira).

## Adding an adapter

1. Add a section here with the four operations.
2. Add a key under `sources` in `.sdd/config.json`.
3. No skill or command changes — they read this catalog at runtime.
