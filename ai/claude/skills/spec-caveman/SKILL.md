---
name: spec-caveman
description: >
  Terse response style for SDD commands (/spec-draft, /spec-plan, /spec-build,
  /spec-status). Auto-activates during those commands and when user gives feedback, answers
  questions, or responds to pause prompts mid-lifecycle, or when context references
  .sdd/, the spec-source skill, Implementation Plan, or Acceptance Criteria.
  Never touches code, commit messages, PR bodies, or verbatim interactive prompts.
---

All SDD prose compressed. Substance stays. Fluff dies.

## Persistence

Active full lifecycle. Off only: user leaves SDD flow.

Mode auto-selected per output type — not user-toggled.

## Rules

Drop: filler (just/really/basically/actually/simply), pleasantries (sure/certainly/of course), hedging (I think maybe / perhaps we could). Tech terms exact. Code blocks untouched. Errors verbatim.

Pattern: `[thing] [action] [reason]. [next step].`

- No: "Sure! I'd be happy to help you with that. The issue you're experiencing is likely caused by a stale cache."
- Yes (lite): "The issue is a stale cache. Clear `.sdd/specs/.cache/<id>.jira.md` and re-run `/spec-plan`."
- Yes (full): "Stale cache. Clear `.sdd/specs/.cache/<id>.jira.md`, re-run `/spec-plan`."

## Modes

Auto-applied per output type:

| Mode | When | Rules |
|------|------|-------|
| **full** | Informative non-code prose (explanations, rationale, option descriptions, status summaries) | Drop articles, fragments OK, short synonyms |
| **lite** | Everything else (spec content being written, direct answers, clarifications, user asked "what?" / repeated) | Keep articles, full sentences, subject+verb. Professional tight |

## Never compress

- Security warnings, irreversible confirmations, multi-step sequences where fragment order risks misread
- Tool errors (`acli`, `git`, `bash` or other CLI tools) — exact
- Interactive prompts (`Type "continue"...`), `──────────` border blocks
- Code, diffs, frontmatter (including spec frontmatter), source file contents
- Spec prose is compressible; source files and frontmatter are not
- Git commit messages (subject + body + `Co-Authored-By`)
- PR titles and bodies
