---
description: Produce (or refresh) a step-by-step implementation plan from a spec
argument-hint: "SPEC-123 [description of changes, required on re-run]"
allowed-tools: Read, Write, Glob, Grep, Bash(grep:*), Bash(find:*), Bash(wc:*), Bash(head:*), Bash(tail:*), Bash(cat:*), Bash(git log:*), Bash(git diff:*), Bash(git status:*), Bash(mkdir:*)
---

Senior software analyst. Understand the spec, explore the codebase, surface risks, get user decisions, produce a concrete implementation plan. Adhere to CLAUDE.md.

User input: $ARGUMENTS

- Adapter catalog: `.sdd/sources.md`.
- Source I/O: delegate `push`, `detect_conflict`, and cache management to the `spec-source` skill.
- Response style: `spec-caveman` skill applies (lite; exceptions for code/commits/prompts).

## Workflow

### 1. Parse arguments

- `spec_id` = first whitespace-separated token.
- `changes` = rest. May be empty.

### 2. Load spec

Read `.sdd/specs/<spec_id>.md`. Missing → tell user to run `/spec-draft <spec_id> ...` and stop.

Parse YAML frontmatter. Remember `source`, `source_ref`.

### 3. First run vs re-run

Check for `## Implementation Plan` section in the body.

- Missing → first run. `changes` optional.
- Present → re-run. `changes` required. If empty, print:
  ```
  This spec already has an Implementation Plan. Re-running /spec-plan requires a description of what changed.
  Usage: /spec-plan <spec_id> <what changed and why>
  ```
  and stop.

### 4. Codebase exploration

Be thorough, not superficial. Read-only — **do not write or modify code.**

Must investigate:
- Files affected.
- Similar features already implemented — find closest analogous pattern and follow it.
- Existing tests — patterns to follow.

Re-run → focus on areas touched by `changes`.

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

#### 7a. First run

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

#### 7b. Re-run

1. Prepend a new entry to `## Clarifications` with the `changes` input and the user's answers from step 6.
2. Update `## Analysis` subsections with new/changed Affected Files, Risks, Decisions. Do NOT delete prior entries — append or amend with dated notes (current date).
3. Refresh `## Implementation Plan`:
   - Checked step still valid (`- [x] Step N: ...`) → keep.
   - Checked step invalidated → rewrite as `- [x] ~~Step N: <original text>~~ _(superseded: <one-line reason>)_`.
   - Unchecked step still valid → keep.
   - Unchecked step no longer relevant → remove.
   - New work → append with numbering continuing the sequence (do not renumber existing steps).

Plan rules (both modes):
- Each step atomic — reviewable and committable independently.
- Each step names specific files to create or modify.
- Order by dependency — foundational layers first.
- Include a testing step per layer where tests are needed.
- Final step = run the QA pipeline defined in CLAUDE.md.
- 3–15 steps total depending on complexity.

### 8. Sync to source

`source == "local"` → skip.

Otherwise, invoke `spec-source`:

1. `push(source, source_ref, body_of(.sdd/specs/<spec_id>.md))`.
2. Skill handles drift detection, user confirmation, frontmatter stripping, and cache update.
3. Capture result: `pushed | aborted by user | skipped (conflict unresolved)`.

### 9. Output

Print exactly:

```
Plan complete for <spec_id>: <spec_title>
Mode:   <first-run|re-run>
Steps:  <N> total (<K> carried over, <S> superseded, <M> new)
Source: <skipped|pushed to <source>:<source_ref>|aborted by user>

Next: /spec-build <spec_id>
```
