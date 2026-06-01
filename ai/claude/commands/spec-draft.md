---
description: Draft (create or refresh) a spec file and branch from a ticket ID and short description
argument-hint: "SPEC-123 feature short description of the task"
allowed-tools: Read, Write, Glob, Bash(git:*), Bash(git switch:*), Bash(git checkout:*), Bash(git branch:*), Bash(git status:*), Bash(mkdir:*), Bash(cat:*)
---

Draft a new spec or refresh an existing one. Adhere to CLAUDE.md.

User input: $ARGUMENTS

Output style: terse. No filler, no narration. Code, git commit messages, PR bodies, and verbatim interactive prompts pass through unchanged.

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

- **Exists** → refresh mode. Skip branch prompt. Refresh body and commit as a standalone commit.
- **Missing** → new draft mode. Do dirty tree check and proceed to branch prompt.

Read `.sdd/config.json`. Extract `track_specs` (top-level boolean field). If absent, non-boolean, or `config.json` is missing, default to `true`. Store as `TRACK_SPECS`.

### 3. Dirty tree check

Run `git status --porcelain`.

- New draft: non-empty → abort, ask user to commit or stash.
- Refresh: anything other than `.sdd/specs/<spec_id>.md` → abort.
- When `TRACK_SPECS` is `false`: `.sdd/` files are gitignored and will not appear in `git status` output. Only non-ignored dirty files matter for the check.

### 4. Branch prompt (new draft only)

Skip in refresh mode.

Call the `AskUserQuestion` tool with these arguments **verbatim** (only `<branch_name>` substitutes):

- `question`: `Create branch <branch_name> from HEAD?`
- `header`: `Branch`
- `multiSelect`: `false`
- `options`:
  - `label`: `Yes (create branch)` — `description`: `Switch to a new branch named <branch_name> from the current HEAD.`
  - `label`: `No (stay here)` — `description`: `Skip branch creation. Stay on the current branch.`

`Yes (create branch)` is the recommended option (list it first).

**STOP after the tool call. Wait for the user's selection.**

- Selected `Yes (create branch)` → switch to new branch from HEAD using `branch_name`. If taken, append `-v2`, `-v3`, etc. Set frontmatter `branch: <branch_name>`.
- Selected `No (stay here)` → skip branch creation. Set frontmatter `branch: <none>`. Stay on the current branch.

### 5. Write spec file

Read `.sdd/specs/template/spec.md`. Create `.sdd/specs/<spec_id>.md` with:

- Frontmatter:
  ```yaml
  ---
  spec_id: <spec_id>
  spec_type: <spec_type>
  spec_title: <spec_title>
  branch: <branch_name or <none>>
  ---
  ```
- Body = template sections with empty placeholders. The user fills the spec; nothing is auto-populated from external sources.

Refresh mode: preserve any local-only sections added by the user (`## Clarifications`, `## Analysis`, `## Implementation Plan`) by appending them after the refreshed body. Do not silently drop planning work.

No implementation details, code examples, or file paths — product-level document.

### 6. Commit (refresh only)

Refresh mode, after writing:

If `TRACK_SPECS` is `true`:
```
git add .sdd/specs/<spec_id>.md
git commit -m "<type>: refresh spec"
# subject above; if a Co-Authored-By trailer is expected, add it yourself at the
# end of the message — don't assume it is appended automatically, don't force a bare subject
```

`<type>` is a Conventional-Commits prefix. Default to `docs` (a spec refresh is documentation work); pick a different prefix when the refresh content clearly belongs elsewhere. The subject must not contain the spec_id, the step number, internal ticket numbers, customer information, credentials, or any other sensitive identifier. As in `/spec-build` §6.2, the message may carry an extended body; SDD neither forces nor suppresses the `Co-Authored-By` trailer, and does not append it automatically — if expected, include it yourself at the end of the message. Do not constrain the commit to a bare single-line subject.

If `TRACK_SPECS` is `false`: skip — the spec update lives on disk only.

New draft: leave uncommitted — user commits after review.

### 7. Output

Print exactly:

```
Spec:    .sdd/specs/<spec_id>.md
Branch:  <branch_name or <none>>
Title:   <spec_title>
Mode:    <new|refreshed>

Next: /spec-plan <spec_id>
```

Do not print spec contents unless asked.
