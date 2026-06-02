---
description: Create or modify a spec and produce its step-by-step implementation plan
argument-hint: "SPEC-123 [type title | description | changes]"
allowed-tools: Read, Write, Glob, Grep, Bash(git:*), Bash(git switch:*), Bash(git checkout:*), Bash(git branch:*), Bash(git status:*), Bash(git log:*), Bash(git diff:*), Bash(grep:*), Bash(find:*), Bash(wc:*), Bash(head:*), Bash(tail:*), Bash(cat:*), Bash(mkdir:*)
---

Senior software analyst. Create the spec if it does not exist, understand it, explore the codebase, surface risks, get user decisions, produce a concrete implementation plan. Adhere to CLAUDE.md.

User input: $ARGUMENTS

Output style: terse. No filler, no narration. Code, git commit messages, PR bodies, and verbatim interactive prompts pass through unchanged.

## Workflow

### 1. Parse arguments

- `spec_id` = first whitespace-separated token. Uppercase `A-Z`, `0-9`, `-` only.
- `rest` = everything after `spec_id`. Its meaning depends on mode (§2): the spec **description** (create mode) or the **changes** (modification mode). May be empty.

### 2. Load spec and detect mode

Read `.sdd/specs/<spec_id>.md`. Then read `.sdd/config.json`; extract `track_specs` (top-level boolean). If absent, non-boolean, or `config.json` is missing, default to `true`. Store as `TRACK_SPECS`.

Mode is driven by spec-file existence and plan presence:

- **File missing** → **create mode** (§3). The spec is created, its body filled from `rest`, then the same invocation continues into analysis (§4) and produces the plan.
- **File present, no `## Implementation Plan` section** → **first-plan mode**. `rest` optional. Skip §3; go to §4.
- **File present, `## Implementation Plan` present** → **modification mode** (re-plan). `rest` is the required `changes`. If empty, print:
  ```
  This spec already has an Implementation Plan. Re-running /spec-plan requires a description of what changed.
  Usage: /spec-plan <spec_id> <what changed and why>
  ```
  and stop.

### 3. Create mode

Runs only when the spec file is missing. Folds in the former `/spec-draft` responsibilities, then falls through to §4 — **do not stop after creating the file.**

#### 3.1 Derive metadata

From `spec_id`, `rest`, and any issue id / URL in the input, infer:

| Field | Rules | Example |
|---|---|---|
| `spec_type` | One of: `feature`, `bugfix`, `refactor`, `chore`, `docs`, `experiment`, `hotfix`, `release`, `support` | `bugfix` |
| `spec_title` | Short Title Case description | `Same Value Min Max Validation` |

Derive `branch_name` = `<spec_type>/<spec_id>-<Title-Case-Words-Joined-By-Dashes>`.

If `spec_type`, `spec_title`, or `spec_id` cannot be inferred from the input, **ask the user — do not guess.**

#### 3.2 Dirty tree check

Run `git status --porcelain`. Non-empty → abort, ask the user to commit or stash. When `TRACK_SPECS` is `false`, `.sdd/` files are gitignored and will not appear; only non-ignored dirty files matter.

#### 3.3 Branch prompt

Call the `AskUserQuestion` tool with these arguments **verbatim** (only `<branch_name>` substitutes):

- `question`: `Create branch <branch_name> from HEAD?`
- `header`: `Branch`
- `multiSelect`: `false`
- `options`:
  - `label`: `Yes (create branch)` — `description`: `Switch to a new branch named <branch_name> from the current HEAD.`
  - `label`: `No (stay here)` — `description`: `Skip branch creation. Stay on the current branch.`

`Yes (create branch)` is the recommended option (list it first).

**STOP after the tool call. Wait for the user's selection.**

- Selected `Yes (create branch)` → switch to a new branch from HEAD using `branch_name`. If taken, append `-v2`, `-v3`, etc. Set frontmatter `branch: <branch_name>`.
- Selected `No (stay here)` → skip branch creation. Set frontmatter `branch: <none>`. Stay on the current branch.

#### 3.4 Write the spec file

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
- Body = the template sections, **filled from the provided description** (`rest`, plus any linked issue). Expand the human's input into the product-level sections (Context, Summary, Functional Requirements, Non-Goals, Edge Cases, Acceptance Criteria, Open Questions, Testing Guidelines). Leave a section's placeholder only when the input genuinely says nothing about it. Product-level only — no implementation details, code, or file paths in the body.

Then continue to §4 in the same invocation.

### 4. Codebase exploration

Be thorough, not superficial. Read-only — **do not write or modify code.**

Must investigate:
- Files affected.
- Similar features already implemented — find closest analogous pattern and follow it.
- Existing tests — patterns to follow.

Modification mode → focus on areas touched by `changes`.

### 5. Risks

Document anything that could go wrong:
- Breaking changes to existing behavior.
- Performance implications.
- Missing test coverage.

### 6. Ask user

Present:
1. Open questions from the spec (if unanswered).
2. Technical decisions with multiple valid approaches — describe options, ask user to choose.
3. Risks needing user input.

**Option suggestions:** For each open question or decision where options can be reasonably inferred, propose 2–4 candidate answers and mark one as the default. Use this format:

```
Q: <question text>
  ★ (a) <option> — <one-line reason>  ← default
    (b) <option> — <one-line reason>
    (c) <option> — <one-line reason>
```

Infer options using this source-of-truth order:
1. Spec body (existing constraints or examples).
2. Codebase (closest analogous pattern already implemented).
3. Prior specs / `CLAUDE.md` (established conventions).
4. Generic defaults (common industry practice).

When no options are reasonably inferable from any of the above, ask the question open-ended without fabricated options.

**STOP and wait for answers.** Do not proceed until user responds.

### 7. Write/refresh spec sections

#### 7a. First run (create mode or first-plan mode)

Append to spec body (preserve all existing content above):

```markdown
## Clarifications
<!-- User's answers to open questions and decisions -->

## Analysis

### Affected Files
<!-- Every file to create or modify, grouped by layer -->

### Risks & Concerns
<!-- Problems and mitigations -->

### Decisions
<!-- Key technical decisions and rationale -->

## Implementation Plan
<!-- Ordered steps. Each step = one atomic, committable unit. -->
- [ ] Step 1: ...
- [ ] Step 2: ...
```

#### 7b. Modification mode (re-run)

1. Prepend a new entry to `## Clarifications` with the `changes` input and the user's answers from step 6. **Cap each re-run's append at ≤3 bullets** summarising what changed and why — do not enumerate every prior question.
2. Update `## Analysis` subsections with new/changed Affected Files, Risks, Decisions. Do NOT delete prior entries — append or amend with dated notes (current date).
3. Refresh `## Implementation Plan`:
   - Checked step still valid (`- [x] Step N: ...`) → keep.
   - Checked step invalidated → **delete the line outright.** Subsequent step numbers do not renumber — gaps are intentional and indicate where superseded work used to live. Record the *reason* the step was dropped as one of the ≤3 Clarifications bullets.
   - Unchecked step still valid → keep.
   - Unchecked step no longer relevant → remove.
   - New work → append with numbering continuing the sequence (do not renumber existing steps).

When `changes` revise the product requirements (not just the plan), amend the affected product-level sections (Summary, Functional Requirements, etc.) in place, preserving `## Clarifications` / `## Analysis` / `## Implementation Plan`.

Plan rules (both modes):
- Each step atomic — reviewable and committable independently.
- Each step names specific files to create or modify.
- Order by dependency — foundational layers first.
- Include a testing step per layer where tests are needed.
- Final step = run the QA pipeline defined in CLAUDE.md.
- 3–15 steps total depending on complexity.

### 8. Output

Print exactly:

```
Plan complete for <spec_id>: <spec_title>
Mode:   <create|first-plan|re-run>
Steps:  <N> total (<K> carried over, <D> deleted, <M> new)

Next: /spec-build <spec_id>
```
