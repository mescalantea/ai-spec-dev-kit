---
description: Build (implement) a planned spec step by step, pausing for review before each commit
argument-hint: "SPEC-123"
allowed-tools: Read, Write, Glob, Grep, Bash, Bash(git push:*), Bash(gh pr create:*), Bash(gh pr edit:*), Bash(gh pr view:*), Bash(gh pr list:*)
---

Build a previously planned spec. Work one step at a time, pause after each for user review before committing. Adhere to CLAUDE.md.

User input: $ARGUMENTS

Output style: terse. No filler, no narration. Code, git commit messages, PR bodies, and verbatim interactive prompts pass through unchanged.

## Workflow

### 1. Load and validate

Read `.sdd/specs/<spec_id>.md`. Parse frontmatter (`branch`). Body must contain an `## Implementation Plan` section with checkboxes. Missing → tell user to run `/spec-plan <spec_id>` first and stop.

If `branch` is `<none>`, the spec is being built on the current branch — do not refuse to build, do not switch branches.

Read `.sdd/config.json`. Extract `track_specs` (top-level boolean field). If absent, non-boolean, or `config.json` is missing, default to `true`. Store as `TRACK_SPECS` for use in §6.

### 2. Find next step

First unchecked step (`- [ ]`). Numbering may have gaps where prior re-plans deleted invalidated steps — that is expected. All steps checked → go to **Completion**.

### 3. Build the step

Read the step carefully. It names specific files and actions. Follow:
- Coding conventions from CLAUDE.md.
- Closest analogous patterns in the codebase.
- The `## Coding Standards` section at the end of this file (comment style + sensitive-info policy) — re-read it before writing code and before drafting the commit message in §6.

### 4. Pause for review

After implementing, print this context block (so the user can see what changed before answering):

```
──────────────────────────────────────
Step N/<total>: <step description>
──────────────────────────────────────

Files changed:
  - <list of files modified or created>

Summary: <brief description of what was done>
──────────────────────────────────────
```

Then call the `AskUserQuestion` tool with these arguments **verbatim** (only `N` and `<short step description>` substitute):

- `question`: `Commit step N — "<short step description>"?`
- `header`: `Step N`
- `multiSelect`: `false`
- `options`:
  - `label`: `Continue` — `description`: `Commit this step and proceed to the next.`
  - `label`: `Abort` — `description`: `Stop the build without committing this step.`

`AskUserQuestion` automatically surfaces an `Other` affordance that lets the user type free-form feedback; do not list `Other` explicitly in the options array.

**STOP after the tool call. Do not commit. Do not proceed. Wait for the user's selection.**

### 5. Handle response

- Selected `Continue` → go to §6.
- Selected `Abort` → stop immediately, do not commit, print how many steps remain.
- Selected `Other` (free-form feedback in the tool's notes/text field):
  1. Apply the requested changes.
  2. Re-print the §4 context block (border lines + Step header + Files changed + Summary, refreshed if the feedback affected them).
  3. Call `AskUserQuestion` again with **identical** `question`, `header`, and `options` arrays as in §4 (byte-identical tool-call arguments). Only the context block above the tool call may change.
  4. Loop indefinitely until the user selects `Continue` or `Abort`.

The §4 `AskUserQuestion` invocation is the canonical pause point. Its arguments must be byte-identical across re-displays — same `question` text, same `header`, same option `label`/`description` strings, in the same order.

### 6. Commit and mark done

1. `git add -A`
2. Commit message. The subject is `<type>: <short description of the change>`; the message may also carry an extended body (the paragraphs after the subject's blank line). Do not commit with a bare single-line subject — leave room for an extended body. SDD does not manage commit attribution: it neither forces nor suppresses the `Co-Authored-By` trailer. Do not assume it is appended automatically — if a trailer is expected, whoever writes the commit must include it at the end of the message.
   - `<type>` is a Conventional-Commits prefix (no scope). Derive it from the spec's frontmatter `spec_type` via this mapping: `feature`→`feat`, `bugfix`→`fix`, `refactor`→`refactor`, `chore`→`chore`, `docs`→`docs`, `experiment`→`experiment`, `hotfix`→`fix`, `release`→`chore`, `support`→`chore`. When the step's actual change clearly belongs to a different category (e.g., a `feature`-typed spec whose step is a pure typo fix), pick the type that matches the change instead.
   - The subject must NOT contain the spec_id, the step number, internal ticket numbers, customer information, credentials, API keys, internal URLs, or external system names. See `## Coding Standards` below.
3. Update spec: change `- [ ] Step N:` to `- [x] Step N:` for the completed step.
4. If `TRACK_SPECS` is `true`: `git add .sdd/specs/<spec_id>.md && git commit --amend --no-edit`
   If `TRACK_SPECS` is `false`: skip — the checkbox update lives on disk only.
5. Print: `✓ Step N committed. Moving to next step...`

### 7. Loop

Back to step 2. Repeat until done.

### 7a. CLAUDE.md update

Runs once, after all steps are checked, **only if at least one step was committed in this run.**

1. Assess whether the completed build introduced behaviors, invariants, commands, or architectural facts that belong in the target's `CLAUDE.md`.
2. If `CLAUDE.md` is absent in the project root → skip entirely.
3. If no CLAUDE.md-worthy changes were introduced → skip entirely (do not create a no-op commit).
4. Otherwise:
   - Edit `CLAUDE.md` to reflect the new facts (new commands, changed invariants, updated tail behaviors, etc.).
   - Commit subject: `docs: <short description of what was documented>` — same Conventional-Commits format and message rules as §6.2. No spec_id, no step number.
5. Then proceed to §8.

### 8. Completion

All steps checked:

1. **Push / PR prompt.** Print this context block:

   ```
   ──────────────────────────────────────
   Ready to push branch: <branch>
   ──────────────────────────────────────
   ```

   Then call the `AskUserQuestion` tool with these arguments **verbatim**:

   - `question`: `Push branch <branch> to origin?`
   - `header`: `Push`
   - `multiSelect`: `false`
   - `options`:
     - `label`: `Push` — `description`: `Push the branch to origin without creating a PR.`
     - `label`: `Push + PR` — `description`: `Push the branch and create or update a pull request.`
     - `label`: `Skip` — `description`: `Exit without touching the remote.`

   **STOP after the tool call. Wait for the user's selection.**

   - Selected `Skip` → print `Branch <branch> is ready locally. No remote changes made.` and proceed to step 2.
   - Selected `Push` → run `git push -u origin <branch>`. On success print the remote URL. On failure print the error verbatim and proceed to step 2.
   - Selected `Push + PR`:
     1. Run `git push -u origin <branch>`. On push failure print the error verbatim and proceed to step 2 (do not attempt PR).
     2. Check whether an open PR already tracks this branch: `gh pr list --head <branch> --state open --json number,url`.
        - Open PR found → run `gh pr edit <number> --body "<pr-body>"`.
        - No open PR → run `gh pr create --title "<spec_title>" --body "<pr-body>"`.
     3. **PR body generation** — build `<pr-body>` as follows:

        **a. Discover PR template.** Search these paths in order and use the first that exists:
           1. `.github/PULL_REQUEST_TEMPLATE.md`
           2. `.github/pull_request_template.md`
           3. `.gitlab/merge_request_templates/Default.md`
           4. `docs/pull_request_template.md`
           5. `PULL_REQUEST_TEMPLATE.md` (repo root)
           6. `pull_request_template.md` (repo root)

        **b. Template found → it is authoritative.** Honor the repo's PR/MR template structure verbatim; do not introduce headings or sections that the template does not define.
           - Parse the template into sections (split on markdown headings `## …` / `### …`). Any content before the first heading is the *preamble*.
           - **Preamble handling**: If the preamble contains explicit removal instructions (e.g., "remove before submitting", ✂ markers, or similar prompts directed at the PR author), strip the entire preamble. Otherwise preserve it, including any HTML comments (`<!-- … -->`).
           - Prepare spec data:
             - `SUMMARY` = spec `## Summary` section body (verbatim).
             - `IMPLEMENTATION` = spec `## Analysis` section body + the step descriptions from `## Implementation Plan` (without checkboxes/status markup). If `## Analysis` is absent, use only the plan steps.
           - PR bodies must not include a commit list, changelog, or `## Commits` section. The commit list is already visible in the PR's own "Commits" tab and would be a duplicate. Do not append such a section even when the template lacks one.
           - For each template section, decide by reading the section heading and any placeholder/prompt text:
             - Section asks for a **description, summary, overview, goal, purpose, or context** → replace its body with `SUMMARY`.
             - Section asks for **implementation, approach, or how something is done** → replace its body with `IMPLEMENTATION`.
             - Section asks for **changes, changelog, or what changed** → replace its body with `IMPLEMENTATION` (the step descriptions describe what changed without duplicating the commit list).
             - Section asks for **references, links, or related issues** → fill sub-items that can be derived from spec data and remove sub-items that cannot be filled. If no sub-items can be filled, remove the entire section.
             - Section cannot be filled **but its placeholder text suggests a default value** (e.g., "just write 'Standard deployment'") → keep the section and replace its body with that default.
             - Section cannot be filled and has no suggested default (e.g., "Screenshots", "Testing checklist") → remove the section entirely (heading + body).

        **c. No template found → use default format.**
           ```
           ## Summary
           <spec Summary section verbatim>
           ```
           No commit list or changelog is appended.

     4. On `gh` success print the PR URL.
     5. On `gh` failure (not installed, not authenticated, etc.): keep the push, print the error verbatim, and print the equivalent manual command the user can run.

2. Print:
   ```
   ──────────────────────────────────────
   Build complete: <spec_id>
   Branch:  <current branch>
   Commits: <number of steps completed>
   Remote:  <skipped|pushed|pushed + PR <url>|push failed>
   ──────────────────────────────────────
   ```

3. Remind user to run the QA pipeline from CLAUDE.md if the last step didn't already cover it.

4. If the spec is configured for a non-local source (`source` field in `.sdd/config.json`), suggest: `Run 'sdd publish <spec_id>' to sync the spec to <source>.` Do not call the publish script automatically — it is a separate user action.

## Coding Standards

These standards apply to every piece of code Claude writes during a build, every commit message it drafts, and every PR body it generates. Re-read this section at the start of each step (§3) and before writing the commit message (§6.2).

### Code comments

- Default to writing no comments. Only add a comment when the *why* is non-obvious (a hidden constraint, a subtle invariant, a workaround for a specific bug, behavior that would surprise a reader). If removing the comment would not confuse a future reader, do not write it.
- Keep comments terse — one line whenever possible, never multi-paragraph. Well-named identifiers already document *what* the code does; comments cover only *why*.
- Comments must not reference the spec_id, the step number, the current task, the originating ticket, or any other transient artifact of the development flow. The code outlives the spec; those references rot. Use git history and the spec file for that context, not in-code comments.
- Do not annotate removed code with "// removed", "// was X", or similar markers. Delete the code outright.

### Sensitive information

The following must not appear anywhere in source files, comments, commit subjects, commit bodies, PR titles, or PR bodies produced by `/spec-build`:

- Internal ticket numbers, project keys, or any other identifier that exposes the issue-tracking system in use.
- Customer names, customer identifiers, account numbers, email addresses, or other personally identifying information.
- API keys, tokens, passwords, certificates, private URLs, signing secrets, or anything that grants access to a system.
- Internal hostnames, internal service names, internal DNS, internal subdomains, or internal IP ranges.
- External system or vendor names where the relationship is not public (e.g., undisclosed third-party providers).
- Security-related details that would aid an attacker (specific CVE chains being mitigated, authentication algorithm choices, rate-limit thresholds, vulnerable code paths).

When such information is genuinely needed to explain a change, generalise it: "the upstream ticket tracker" rather than the project key; "the customer-facing surface" rather than a customer name; "the credential store" rather than the env-var name of a specific secret.

### Commit and PR phrasing

- Subjects use the Conventional-Commits format from §6.2 — no spec_id, no step number, no internal references.
- Bodies, when present, describe *what* the change does and *why*, in normal prose. They must not list the spec_id, step number, or any of the sensitive-information items above.
- PR bodies follow §8.3 — no commit list.
