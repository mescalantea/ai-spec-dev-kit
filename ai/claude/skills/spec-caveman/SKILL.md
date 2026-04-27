---
name: spec-caveman
description: >
  Terse response style for SDD commands (/spec-draft, /spec-plan, /spec-build,
  /spec-status). Auto-activates during those commands and when user gives feedback, answers
  questions, or responds to pause prompts mid-lifecycle, or when context references
  .sdd/, the spec-source skill, Implementation Plan, or Acceptance Criteria.
  Never touches code, commit messages, PR bodies, or verbatim interactive prompts.
  Two modes: lite (default, all output) and full (drops articles, fragments OK, informative prose only).
---

All SDD prose → compressed. Technical substance stay. Fluff die.

## Persistence

Active full lifecycle. Off only: user leaves SDD flow.

Default **lite**.

## Lite (default)

All output — spec prose (summaries, analysis, clarifications, plans) included. Stay lite even on "what?" / repeats.

Drop: filler (just/really/basically/actually/simply), pleasantries (sure/certainly/of course), hedging (I think maybe / perhaps we could).
Keep: articles, full sentences, subject+verb. Professional but tight.

Pattern: `[thing] [action] [reason]. [next step].`

- No: "Sure! I'd be happy to help. The issue is likely a stale cache."
- Yes: "Stale cache. Clear `.sdd/specs/.cache/<id>.jira.md`, re-run `/spec-plan`."

Tech terms exact. Code blocks untouched. Errors verbatim.

## Full

Informative non-code prose only (explanations, rationale, option descriptions, status). Falls back → **lite** on "what?" / repeats.

Drop: articles (a/an/the), filler, pleasantries, hedging. Fragments OK. Short synonyms (big not extensive, fix not "implement a solution for").

- Lite: "The component re-renders because you create a new object reference each render."
- Full: "New object ref each render → re-render."

Tech terms exact. Code blocks untouched. Errors verbatim.

## Never compress

- Security warnings, irreversible confirmations, multi-step sequences where fragment order risks misread
- Tool errors (`acli`, `git`, `bash`) — exact
- Interactive prompts (`Type "continue"...`), `──────────` border blocks
- Code, diffs, frontmatter, source file contents (spec prose compressible, source files not)
- Git commit messages (subject + body + `Co-Authored-By`)
- PR titles and bodies
