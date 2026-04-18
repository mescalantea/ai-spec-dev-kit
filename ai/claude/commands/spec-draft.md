---
description: Draft (create or refresh) a spec file and branch from a ticket ID and short description
argument-hint: "SPEC-123 feature short description of the task"
allowed-tools: Read, Write, Glob, Bash(git:*), Bash(git switch:*), Bash(git checkout:*), Bash(git branch:*), Bash(git status:*), Bash(mkdir:*), Bash(cat:*)
---

Draft a new spec or refresh an existing one. Adhere to CLAUDE.md.

User input: $ARGUMENTS

- Enabled sources: `.sdd/config.json`.
- Adapter catalog: `.sdd/sources.md`.
- Source I/O: delegate `pull`, `adapt`, and cache management to the `spec-source` skill.
- Response style: `spec-caveman` skill applies (lite; exceptions for code/commits/prompts).

## Workflow

### 1. Parse arguments

Extract from `$ARGUMENTS`:

| Field | Rules | Example |
|---|---|---|
| `spec_id` | Uppercase `A-Z`, `0-9`, `-` only | `PAR-224` |
| `spec_type` | One of: `feature`, `bugfix`, `refactor`, `chore`, `docs`, `experiment`, `hotfix`, `release`, `support` | `bugfix` |
| `spec_title` | Short Title Case description | `Same Value Min Max Validation` |

Derive `branch_name` = `<spec_type>/<spec_id>-<Title-Case-Words-Joined-By-Dashes>`.

If any field cannot be inferred, ask the user — do not guess.

### 2. Detect re-entry

Check whether `.sdd/specs/<spec_id>.md` exists.

- **Exists** → refresh mode. Skip branch creation. Refresh body and commit as a standalone commit.
- **Missing** → new draft mode. Do dirty tree check and create branch.

### 3. Dirty tree check

Run `git status --porcelain`.

- New draft: non-empty → abort, ask user to commit or stash.
- Refresh: anything other than `.sdd/specs/<spec_id>.md` → abort.

### 4. Choose source

Read `.sdd/config.json`, list sources with `enabled: true`.

- Only `local` enabled → `source = local`, skip to step 6.
- Otherwise → ask user to pick.

Non-local source → ask for `source_ref` if different from `spec_id`. Default: `source_ref = spec_id`.

### 5. Pull and adapt (skill)

Invoke `spec-source`:

1. `pull(source, source_ref)` → raw body.
2. `adapt(source, body)` → proposed body (user must `continue` to accept).
3. Skill writes `.sdd/specs/.cache/<source_ref>.<source>.md` on success.

### 6. Create branch (new draft only)

Skip in refresh mode. Switch to a new branch from HEAD using `branch_name`. If taken, append `-v2`, `-v3`, etc.

### 7. Write spec file

Read `.sdd/specs/template/spec.md`. Create `.sdd/specs/<spec_id>.md` with:

- Frontmatter:
  ```yaml
  ---
  spec_id: <spec_id>
  spec_type: <spec_type>
  spec_title: <spec_title>
  branch: <branch_name>
  source: <source>
  source_ref: <source_ref or null>
  ---
  ```
- Body = template sections populated from the adapted body (empty placeholders for `local`).
- Fill what the source provides. Leave the rest for the user before `/spec-plan`.

Refresh mode: preserve any local-only sections added by the user (`## Clarifications`, `## Analysis`, `## Implementation Plan`) by appending them after the refreshed body. Do not silently drop planning work. If the body meaningfully changed, warn the user that the prior plan may be stale and recommend `/spec-plan <spec_id> <changes>`.

No implementation details, code examples, or file paths — product-level document.

### 8. Commit (refresh only)

Refresh mode, after writing:

```
git add .sdd/specs/<spec_id>.md .sdd/specs/.cache/<spec_id>.<source>.md 2>/dev/null
git commit -m "<spec_id>: refresh spec from <source>"
```

New draft: leave uncommitted — user commits after review.

### 9. Output

Print exactly:

```
Spec:    .sdd/specs/<spec_id>.md
Branch:  <branch_name>
Title:   <spec_title>
Source:  <source>[:<source_ref>]
Mode:    <new|refreshed>

Next: /spec-plan <spec_id>
```

Do not print spec contents unless asked.
