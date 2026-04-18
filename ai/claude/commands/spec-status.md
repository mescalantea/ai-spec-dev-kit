---
description: Show the current phase of a spec (or all specs) and the next command to run
argument-hint: "[SPEC-123]"
allowed-tools: Read, Glob, Bash(git branch:*), Bash(git rev-parse:*), Bash(ls:*), Bash(stat:*)
---

Report the state of one or more specs. **Read-only**: do not modify files, do not call external services (no `acli`, no network).

Response style: `spec-caveman` skill applies (lite; exceptions for code/commits/prompts).

User input: $ARGUMENTS

## Workflow

### 1. Parse arguments

- Empty → list mode (all specs).
- Otherwise → single mode, `spec_id` = first token.

### 2. Locate specs

- Single: read `.sdd/specs/<spec_id>.md`. Missing → print:
  ```
  No spec found at .sdd/specs/<spec_id>.md
  Run: /spec-draft <spec_id> <type> <title>
  ```
  and stop.
- List: glob `.sdd/specs/*.md`, exclude `.sdd/specs/template/` and `.sdd/specs/.cache/`.

### 3. Derive state per spec

Parse YAML frontmatter: `spec_id`, `spec_type`, `spec_title`, `branch`, `source`, `source_ref`.

Derive `phase` from body:

| Condition | phase |
|---|---|
| No `## Implementation Plan` section | `drafted` |
| Plan exists, zero `- [x]` lines | `planned` |
| Plan exists, mix of `- [x]` and `- [ ]` | `building` |
| Plan exists, all `- [x]` or `~~...~~ _(superseded: ...)_` | `done` |

Counts when plan exists:
- `total` — `- [ ]` + `- [x]` lines in the Plan.
- `done` — `- [x]` NOT superseded.
- `superseded` — `- [x] ~~...~~ _(superseded: ...)_`.
- `pending` — `- [ ]`.

Source sync hints (no remote calls):
- Non-local source + cache exists at `.sdd/specs/.cache/<spec_id>.<source>.md` → `last_sync = mtime`.
- Non-local source + cache missing → `last_sync: never`.

Branch hint: run `git branch --show-current` once. Per spec: compare frontmatter `branch` to current; mark `on_branch: yes|no`.

### 4. Next command

| phase | next |
|---|---|
| `drafted` | `/spec-plan <spec_id>` |
| `planned` | `/spec-build <spec_id>` |
| `building` | `/spec-build <spec_id>` (resumes at next unchecked step) |
| `done` | none — complete. Suggest `/spec-plan <spec_id> <changes>` if scope expands. |

If spec is not on its declared branch, prepend hint: `git switch <branch>` before the next command.

### 5. Output

#### Single mode

```
Spec:      <spec_id> — <spec_title>
Type:      <spec_type>
Branch:    <branch>  (current: <current_branch>, on_branch: <yes|no>)
Source:    <source>[:<source_ref>]
Last sync: <timestamp|never|n/a>
Phase:     <phase>
Progress:  <done>/<total> done, <pending> pending, <superseded> superseded
Next:      <next command>
```

Omit `Last sync` when `source: local`.

#### List mode

One row per spec, most recently modified first:

```
SPEC-ID        PHASE      PROGRESS    SOURCE       NEXT
PAR-224        building   3/7         jira:PAR-224 /spec-build PAR-224
PAR-219        done       5/5         local        —
FOO-12         drafted    —           local        /spec-plan FOO-12
```

Right-trim columns; do not exceed 120 chars total. After the table, print the count per phase.

No spec bodies or analysis contents — dashboard only.
