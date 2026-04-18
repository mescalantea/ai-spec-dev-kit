---
description: Build (implement) a planned spec step by step, pausing for review before each commit
argument-hint: "SPEC-123"
allowed-tools: Read, Write, Glob, Grep, Bash, Bash(git push:*), Bash(gh pr create:*), Bash(gh pr edit:*), Bash(gh pr view:*), Bash(gh pr list:*)
---

Build a previously planned spec. Work one step at a time, pause after each for user review before committing. Adhere to CLAUDE.md.

User input: $ARGUMENTS

- Adapter catalog: `.sdd/sources.md`.
- Source I/O: delegate `push`, `detect_conflict`, and cache management to the `spec-source` skill.
- Response style: `spec-caveman` skill applies (lite; exceptions for code/commits/prompts).

## Workflow

### 1. Load and validate

Read `.sdd/specs/<spec_id>.md`. Parse frontmatter (`source`, `source_ref`). Body must contain an `## Implementation Plan` section with checkboxes. Missing → tell user to run `/spec-plan <spec_id>` first and stop.

### 2. Find next step

First unchecked step (`- [ ]`). Superseded steps (`- [x] ~~...~~ _(superseded: ...)_`) count as done — skip. All checked or superseded → go to **Completion**.

### 3. Build the step

Read the step carefully. It names specific files and actions. Follow:
- Coding conventions from CLAUDE.md.
- Closest analogous patterns in the codebase.

### 4. Pause for review

After implementing, print:

```
──────────────────────────────────────
Step N/<total>: <step description>
──────────────────────────────────────

Files changed:
  - <list of files modified or created>

Summary: <brief description of what was done>

Type "continue" to commit and proceed to the next step.
Type "abort" to stop without committing.
Type any feedback to request changes before committing.
──────────────────────────────────────
```

**STOP. Do not commit. Do not proceed. Wait for user.**

### 5. Handle response

- `continue` → go to step 6.
- `abort` → stop immediately, do not commit, print how many steps remain.
- Anything else → treat as feedback:
  1. Apply the requested changes.
  2. Re-display the §4 pause prompt **byte-identical** to the first display (same wording, same border lines, updated "Files changed" and "Summary" if the changes affected them).
  3. Wait for user response. Loop indefinitely until `continue` or `abort`.

  The prompt re-display is mandatory after every feedback round, regardless of how many iterations the loop has run.

### 6. Commit and mark done

1. `git add -A`
2. Commit: `<spec_id>: step N - <short step description>`
3. Update spec: change `- [ ] Step N:` to `- [x] Step N:` for the completed step.
4. `git add .sdd/specs/<spec_id>.md && git commit --amend --no-edit`
5. Print: `✓ Step N committed. Moving to next step...`

### 7. Loop

Back to step 2. Repeat until done.

### 7a. CLAUDE.md update

Runs once, after all steps are checked/superseded, **only if at least one step was committed in this run.**

1. Assess whether the completed build introduced behaviors, invariants, commands, or architectural facts that belong in the target's `CLAUDE.md`.
2. If `CLAUDE.md` is absent in the project root → skip entirely.
3. If no CLAUDE.md-worthy changes were introduced → skip entirely (do not create a no-op commit).
4. Otherwise:
   - Edit `CLAUDE.md` to reflect the new facts (new commands, changed invariants, updated tail behaviors, etc.).
   - Commit: `<spec_id>: update CLAUDE.md with new behaviors`
5. Then proceed to §8.

### 8. Completion

All checked or superseded:

1. Sync to source. `source == "local"` → skip. Otherwise invoke `spec-source`:
   - `push(source, source_ref, body_of(.sdd/specs/<spec_id>.md))`.
   - Skill handles drift detection, user confirmation, frontmatter stripping, cache update.
   - Capture result: `pushed | aborted by user | skipped (conflict unresolved)`.

2. **Push / PR prompt.** Print:

   ```
   ──────────────────────────────────────
   Ready to push branch: <branch>

   Type "push" to push the branch to origin.
   Type "push + PR" to push and create or update a pull request.
   Type "skip" to exit without touching the remote.
   ──────────────────────────────────────
   ```

   **STOP. Wait for user.**

   - `skip` → print `Branch <branch> is ready locally. No remote changes made.` and proceed to step 3.
   - `push` → run `git push -u origin <branch>`. On success print the remote URL. On failure print the error verbatim and proceed to step 3.
   - `push + PR`:
     1. Run `git push -u origin <branch>`. On push failure print the error verbatim and proceed to step 3 (do not attempt PR).
     2. Check whether an open PR already tracks this branch: `gh pr list --head <branch> --state open --json number,url`.
        - Open PR found → run `gh pr edit <number> --body "<auto-body>"`.
        - No open PR → run `gh pr create --title "<spec_title>" --body "<auto-body>"`.
     3. Auto-body format:
        ```
        ## Summary
        <spec Summary section verbatim>

        ## Commits
        <output of: git log origin/main..<branch> --oneline>

        🤖 Generated with [Claude Code](https://claude.com/claude-code)
        ```
     4. On `gh` success print the PR URL.
     5. On `gh` failure (not installed, not authenticated, etc.): keep the push, print the error verbatim, and print the equivalent manual command the user can run.

3. Print:
   ```
   ──────────────────────────────────────
   Build complete: <spec_id>
   Branch:  <current branch>
   Commits: <number of steps completed>
   Source:  <skipped|pushed to <source>:<source_ref>|aborted by user>
   Remote:  <skipped|pushed|pushed + PR <url>|push failed>
   ──────────────────────────────────────
   ```

4. Remind user to run the QA pipeline from CLAUDE.md if the last step didn't already cover it.
