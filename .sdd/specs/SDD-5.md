---
spec_id: SDD-5
spec_type: feature
spec_title: Add YouTrack Source Adapter
branch: feature/SDD-5-Add-YouTrack-Source-Adapter
source: local
source_ref: null
---

# Spec: Add YouTrack Source Adapter

## Context / Background

The SDD toolkit currently supports two spec sources: `local` (plain markdown files in `.sdd/specs/`) and `jira` (via `acli`). Source adapters plug in through a four-operation contract (`pull` / `adapt` / `push` / `detect_conflict`) described in `sdd/sources.md` and invoked through the `spec-source` skill. Teams using JetBrains YouTrack as their issue tracker have no way to sync specs with their tickets and must fall back to `local` or mirror everything manually into Jira.

## Summary

Add YouTrack as a first-class spec source alongside `local` and `jira`. Users should be able to pull a YouTrack issue as a draft spec, push spec updates back to the issue, and run drift detection against the cached last-known remote. The `setup.sh` wizard should offer YouTrack as an option and persist credentials/workspace in `.sdd/config.json`. Behavior should match the existing `jira` adapter's contract so no changes to `/spec-*` commands are required.

## Functional Requirements

- `sdd/sources.md` documents a new `youtrack` adapter with the same four-operation contract as `jira`.
- `.sdd/config.json` gains a `youtrack` block under `sources` with at least: `enabled`, `base_url`, and whatever auth identifier the adapter needs.
- `setup.sh` prompts the user to enable YouTrack, collects the required fields, and writes them to `config.json`.
- `spec-source` skill gains a YouTrack branch for each of `pull`, `adapt`, `push`, `detect_conflict`.
- Pulled YouTrack issues are adapted into the spec template; user must type `continue` before the adapted body is accepted.
- Successful `pull` and `push` write `.sdd/specs/.cache/<ref>.youtrack.md`.
- `push` strips spec frontmatter before sending; the remote never sees `spec_id`, `branch`, or any local-only fields.
- Drift detection diffs the remote against the cache; mismatch requires explicit `continue` before overwrite.
- `/spec-*` commands remain unchanged — adding YouTrack is doc + skill + config only.

## Non-Goals / Out of Scope

- Two-way realtime sync or webhook-driven updates.
- Migrating existing Jira-sourced specs to YouTrack.
- Supporting YouTrack Cloud and self-hosted with different auth flows in one release — pick one for v1.
- Mapping YouTrack custom fields beyond what the spec template needs.
- Attachments, comments, or work items other than the issue body.

## Possible Edge Cases

- YouTrack issue has no description — `pull` must return an empty body and let the user fill the template.
- Auth token is missing or expired — surface a clear error, do not fall back to `local` silently.
- `base_url` has a trailing slash or is missing the protocol — normalize or reject with a clear message.
- Remote issue was deleted between `pull` and `push` — `push` fails cleanly; cache is not updated.
- User enables YouTrack but leaves required fields blank — `setup.sh` must re-prompt or refuse to finalize.
- Network failure mid-`pull` — no partial cache file is written.
- Same `source_ref` exists in both Jira and YouTrack — commands already pick source per-spec via frontmatter, so no collision, but document this.

## Acceptance Criteria

- `sdd/sources.md` describes the YouTrack adapter with the same level of detail as the Jira entry.
- Running `setup.sh` on a throwaway directory and enabling YouTrack produces a `config.json` with a valid `youtrack` block.
- `/spec-draft <id>` with YouTrack selected pulls the issue, shows the adapted body, and (on `continue`) writes the spec file and cache.
- `/spec-build` push-back flow updates the YouTrack issue and refreshes the cache.
- Drift between remote and cache prompts the user before overwrite.
- A project configured with `jira: enabled: false` and `youtrack: enabled: true` works end-to-end with no references to Jira in the lifecycle.
- Existing `local` and `jira` flows are unchanged.

## Open Questions

- Auth: personal permanent token vs. OAuth — which does v1 support?
- Tooling: shell out to `curl` against the YouTrack REST API, or rely on a CLI (e.g., `yt`)? Jira uses `acli`; is there an equivalent we want to standardize on?
- Cloud vs. self-hosted YouTrack — do both work with the same adapter, or does self-hosted need different handling?
- Field mapping: which YouTrack fields populate which spec template sections during `adapt`?
- Should `setup.sh` validate the token by making a test call, or trust the user's input?
- Does `push` create a new issue when `source_ref` is null, or is YouTrack pull-only in v1?

## Dependencies

- `sdd/sources.md` (adapter catalog).
- `ai/claude/skills/spec-source/SKILL.md` (skill dispatch).
- `scripts/setup.sh` (wizard; bash 3.2 constraints apply).
- `.sdd/config.json` schema.
- YouTrack REST API or chosen CLI tool.

## Success Metrics

- At least one downstream project switches from `local` or `jira` to `youtrack` and completes a full `/spec-draft → /spec-plan → /spec-build` cycle without falling back.
- Zero regressions in existing `local` and `jira` flows.

## Testing Guidelines

- Run `setup.sh` against a throwaway directory; enable YouTrack; inspect `config.json` for a valid `youtrack` block.
- Run `setup.sh` and leave YouTrack disabled; confirm no `youtrack` block (or `enabled: false`) and no prompt regressions.
- With a valid YouTrack test instance and token, run `/spec-draft <ticket-id>` and verify the pulled body, adapted spec file, and cache file.
- Edit the spec locally and run `/spec-build` push-back; verify the remote issue updated and cache refreshed.
- Edit the remote issue out-of-band, then attempt `push`; verify drift detection prompts for `continue`.
- Run with `base_url` malformed; confirm a clear error.
- Run with an invalid token; confirm a clear error and no cache write.
- Confirm existing `jira` and `local` specs continue to work unchanged.

## Clarifications

- **Transport:** `curl` against YouTrack REST API. No third-party CLI dependency. JSON extraction via a minimal tool (`jq` if present, falling back to `python3 -c` — both are universally available on macOS/Linux dev boxes and bash 3.2 compatible).
- **Auth:** permanent token, read from an env var whose name is configured in `config.json` (`token_env`, default `YOUTRACK_TOKEN`). Bearer header: `Authorization: Bearer <token>`.
- **Cloud vs self-hosted:** single adapter. The `base_url` field drives it — cloud users point at `https://<workspace>.youtrack.cloud`, self-hosted users at their instance URL. REST API surface is identical.
- **Null `source_ref` on `push`:** pull-only in v1. `push` with null ref warns and no-ops. Creating new YouTrack issues from a local draft is out of scope; user must create the issue in YouTrack, then set `source_ref` in frontmatter.
- **`adapt` behavior:** mirror Jira exactly. Match body against template headers; un-matched template sections get `...`; un-mapped content appended under `## Original Description`; user must `continue` to accept.
- **Wizard validation:** `setup.sh` does not test the token. Trusts user input, matching Jira's wizard (which also doesn't test `acli auth`).
- **`config.json` schema for `youtrack`:** `{enabled, base_url, token_env, project_id}`. `project_id` optional, reserved for a later create-on-push spec.

## Analysis

### Affected Files

**`sdd/sources.md`**
- Add `### youtrack` subsection under "Registered adapters" with the four-operation wire calls (mirrors the Jira entry's level of detail).
- Document auth failure message: `Set $<YOUTRACK_TOKEN env var>, then type "continue" to retry.`
- Document that `push` with null `source_ref` no-ops with a warning.

**`scripts/setup.sh`**
- In "Source configuration" block (around lines 188–205): add `YOUTRACK_ENABLED` prompt and, when true, prompts for `YOUTRACK_BASE_URL`, `YOUTRACK_TOKEN_ENV` (default `YOUTRACK_TOKEN`), `YOUTRACK_PROJECT_ID` (optional).
- Warn if `curl` is missing (unlikely) and if the chosen env var is not set in the current shell (soft warning, not fatal).
- Extend the `config.json` heredoc (lines 241–256) with a `youtrack` block under `sources`.
- Extend the summary block (lines 272–290) to include `youtrack: <enabled>` and the base URL when enabled.

**`ai/claude/skills/spec-source/SKILL.md`**
- Update the `description` frontmatter line — the current copy says "Jira, future YouTrack, etc." Drop the "future". No operational changes: the skill dispatches via `.sdd/sources.md`, so no per-adapter code lives in the skill.

### Risks & Concerns

- **JSON parsing in bash 3.2.** Extracting `description` from a YouTrack REST response needs either `jq` or a `python3` one-liner. Both are ubiquitous on developer machines but not strictly guaranteed. Mitigation: document the dependency in `sdd/sources.md` next to the adapter; `setup.sh` warns if neither is on PATH.
- **Base URL normalization.** Trailing slash, missing protocol, or `/api` appended will break every call. Mitigation: document the expected shape (`https://<host>[:<port>]`, no trailing slash, no `/api`) in `sources.md` and in the wizard's prompt hint.
- **Token leakage.** The token must never be echoed in error messages or committed. Mitigation: read from env var at call time; `sources.md` explicitly tells the adapter not to log the Authorization header.
- **Drift detection cost.** YouTrack API round-trip on every `push` — same cost profile as Jira, acceptable.
- **No automated test suite in this repo.** QA is manual via `setup.sh` run against a throwaway dir. Real end-to-end YouTrack validation requires a live instance and is deferred to the downstream consumer running the adapter for the first time.
- **YouTrack markdown dialect.** YouTrack supports its own markdown-ish syntax; round-tripping through the spec template may lose formatting. For v1, pass the body through unchanged and let the user clean up in the `adapt` review step.

### Decisions

- Transport: `curl` + YouTrack REST API.
- JSON extraction: prefer `jq`, fall back to `python3 -c "import json,sys; ..."`. Document both.
- Auth: permanent token via env var named in `config.json` (`token_env`, default `YOUTRACK_TOKEN`).
- Single adapter for cloud + self-hosted, driven by `base_url`.
- `push` with null `source_ref`: warn and no-op (pull-only v1).
- `adapt`: mirror Jira's header-matching + `## Original Description` append behavior.
- Wizard does not validate the token — matches Jira.
- `config.json` shape for `youtrack`: `{enabled, base_url, token_env, project_id}`.
- YouTrack lives as a peer of Jira under `sources` in `config.json`. Both can be enabled simultaneously; per-spec selection already happens via frontmatter.

## Implementation Plan

- [x] Step 1: Edit `sdd/sources.md` — add a `### youtrack` subsection under "Registered adapters" documenting the four operations (`pull`, `adapt`, `push`, `detect_conflict`) as `curl` calls against the YouTrack REST API. Include: Bearer auth from env var named in `token_env`, GET `/api/issues/<ref>?fields=description` for `pull`, POST `/api/issues/<ref>` with `{description: ...}` for `push`, `jq` preferred with `python3` fallback for JSON extraction, `adapt` mirroring the Jira behavior, auth-failure retry message, and the "null `source_ref` → warn and no-op" rule for `push`.
- [ ] Step 2: Edit `scripts/setup.sh` — in the "Source configuration" block add `YOUTRACK_ENABLED` via `prompt_yn` (default `n`); when true, prompt for `YOUTRACK_BASE_URL` (no trailing slash, no `/api`), `YOUTRACK_TOKEN_ENV` (default `YOUTRACK_TOKEN`), and `YOUTRACK_PROJECT_ID` (optional, allow empty). Add a soft warning if `curl` is missing or the chosen env var is unset. Add a `youtrack` block to the `config.json` heredoc under `sources` with `enabled`, `base_url`, `token_env`, `project_id`. Extend the final summary block to report `youtrack` status and base URL when enabled.
- [ ] Step 3: Edit `ai/claude/skills/spec-source/SKILL.md` — update the `description` frontmatter to list YouTrack as a supported source (remove the "future" qualifier). No changes to the skill's operations: dispatch stays catalog-driven via `.sdd/sources.md`.
- [ ] Step 4: QA — run `scripts/setup.sh` against a throwaway directory. Verify (a) default flow produces `config.json` with `youtrack.enabled: false` and a well-formed `youtrack` block; (b) enabling YouTrack and filling the fields produces a valid `youtrack` block with the chosen `base_url`, `token_env`, and `project_id`; (c) the summary output lists the YouTrack status correctly; (d) `sources.md` is copied to `.sdd/sources.md` with the new adapter section intact; (e) existing `local` and `jira` output is unchanged. Trace the `spec-source` skill dispatch for `source: youtrack` through `pull`, `push`, and `detect_conflict` to confirm catalog-driven behavior works without skill edits.

