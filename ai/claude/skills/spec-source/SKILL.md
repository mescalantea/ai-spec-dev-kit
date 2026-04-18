---
name: spec-source
description: Pull, adapt, push, and detect drift for specs stored in external systems (Jira, future YouTrack, etc.). Use whenever a spec command needs to sync `.sdd/specs/<id>.md` with its external source of truth.
---

# spec-source

Unified adapter for reading and writing specs across multiple backends. Used by `/spec-draft`, `/spec-plan`, `/spec-build`.

Adapter catalog: `.sdd/sources.md`. Config: `.sdd/config.json`.

## Operations

### `pull(source, ref) -> body`

Returns the external description as a markdown body (no frontmatter).

1. `source == "local"` → return empty template body.
2. Else → follow pull procedure for `source` in `.sdd/sources.md`.
3. Auth failure → print:
   ```
   <source> authentication failed. Run `<source auth command>`, then type "continue" to retry.
   ```
   Wait. On `continue`, retry. On anything else, stop.

### `adapt(source, body) -> proposed_body`

Transforms raw external content into the spec template layout from `.sdd/specs/template/spec.md`.

1. Body already matches template → return unchanged.
2. Else:
   - Map content into closest matching template sections.
   - Un-matched sections → placeholder `...`.
   - Un-mapped content → append under `## Original Description`.
3. Show proposed markdown and print:
   ```
   Review the proposed spec body above. Type "continue" to accept, or provide edits.
   ```
   Wait. On `continue`, return. On edits, revise and re-show. Loop until `continue`.

### `push(source, ref, body)`

Sends local body to the external source and refreshes the cache.

1. `source == "local"` → no-op.
2. Call `detect_conflict` first. If conflict and user does not `continue` → stop, do not overwrite.
3. Strip frontmatter (everything between the first and second `---`, inclusive).
4. Write stripped body to a temp file.
5. Follow push procedure for `source` in `.sdd/sources.md` using the temp file.
6. Auth failure → handle same as `pull`.
7. Success → overwrite `.sdd/specs/.cache/<ref>.<source>.md` with pushed body. Create `.sdd/specs/.cache/` if missing.

### `detect_conflict(source, ref) -> (has_conflict, diff)`

Checks for external drift since the last known sync.

1. `source == "local"` → return `(false, "")`.
2. `.sdd/specs/.cache/<ref>.<source>.md` missing → pull remote, write cache, return `(false, "")`.
3. Pull current remote body.
4. `diff -u` against cache.
5. If different, print:
   ```
   <source> description for <ref> has changed externally since the last sync.
   Diff:
   <diff output>

   Type "continue" to overwrite with the local spec, or "abort" to stop.
   ```
   Wait. `abort` → return `(true, diff)`, caller must not push. `continue` → return `(true, diff)` and proceed.

## Guarantees

- **Frontmatter is local-only.** Never push it. Always strip between first and second `---`.
- **Cache is authoritative** for last-known remote. Only `pull` and successful `push` may overwrite it.
- **No silent overwrites.** On drift, user must type `continue` before `push` proceeds.
- **Auth failures recoverable.** Always offer retry via `continue`.

## Adding an adapter

1. Add a section in `.sdd/sources.md` with wire calls for `pull` and `push`.
2. Add a key under `sources` in `.sdd/config.json` with its config (project key, workspace, token env, etc.).
3. No skill or command changes needed — this skill reads the catalog at runtime.
