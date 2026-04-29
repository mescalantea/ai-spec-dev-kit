# Spec-Driven Development Toolkit

A practical toolkit to adopt **Spec-Driven Development (SDD)** in modern software projects using AI-assisted workflows.

Specs are the primary source of truth. The flow is explicitly multi-step — draft → plan → build — with human review at each gate. AI tooling acts on well-structured specs instead of vibe-coding.

---

## 🚀 What is Spec-Driven Development?

Spec-Driven Development treats **specifications as the source of truth** that guides implementation, rather than an afterthought. Combined with AI, a well-structured spec lets the agent reason about *what* to build before writing *how*.

The toolkit enforces the split by shipping four distinct slash commands, one per phase. Each phase pauses for a human checkpoint.

---

## 📦 What's included

- **Spec template** — Markdown template with YAML frontmatter (`.sdd/specs/template/spec.md`). Covers Context, Summary, Functional Requirements, Non-Goals, Edge Cases, Acceptance Criteria, Open Questions, Dependencies, Success Metrics, Testing Guidelines.
- **Four slash commands** for Claude Code — `/spec-draft`, `/spec-plan`, `/spec-build`, `/spec-status`.
- **`sdd publish`** — pure-bash command that pushes a local spec to its configured external source (Jira today; YouTrack stub). Lives outside Claude's context — zero tokens on the happy path.
- **`sdd` CLI** (`scripts/sdd.sh`) — global facade with subcommands: `init`, `upgrade`, `version`, `publish`, `uninstall`, `help`.
- **Setup wizard** (`scripts/setup.sh`) — POSIX bash, macOS + Linux. Copies commands, template, and generates `.sdd/config.json` (records the toolkit version). Invoked via `sdd init`.
- **Installer** (`scripts/install.sh`) — symlinks `sdd` onto PATH and installs the auto-update shell hook.

---

## 🧠 Goals

- Make the local Markdown file under `.sdd/specs/` the **single source of truth** during the build. External systems (Jira, YouTrack) are pushed to via `sdd publish` when the user explicitly asks — never automatically.
- Enforce a **multi-step flow with human review** — draft, plan, build — so AI never jumps straight to code.
- Support **non-linear iteration** — each phase can be re-entered as requirements shift. Re-plans delete invalidated steps outright; numbering never renumbers, so gaps mark where superseded work used to live.
- Stay **agent-neutral where it matters** — config and template live outside `.claude/` so other agents can plug in later.
- Be **token-efficient** — the `/spec-*` commands carry a single one-line brevity directive; external source sync moves to a shell script, so adapter machinery costs zero tokens on the happy path.

---

## ✅ Requirements

- **Bash** 3.2+ (macOS default) or any modern bash on Linux. The scripts declare `#!/usr/bin/env bash`, so they run under bash regardless of your login shell (zsh, bash, fish — all fine).
- **Git** — the toolkit manages branches per spec.
- **Claude Code** CLI.
- **`python3`** — required by `sdd publish` (config parsing + markdown → wiki conversion). Already present on macOS and most Linux distros.
- **Atlassian CLI (`acli`)** — only if you publish to Jira (`sdd publish <SPEC-ID>` with `"source": "jira"`). Run `acli auth login` once before publishing.
- **`curl`** — only if you publish to YouTrack (currently a stub — implement when needed).

---

## ⚡ Install

### 1. Clone this repo

```bash
git clone https://github.com/mescalantea/ai-spec-dev-kit.git
cd ai-spec-dev-kit
```

### 2. Install the `sdd` CLI

```bash
./scripts/install.sh
```

This does two things:

1. **Symlinks `sdd`** into the first writable directory on your PATH (`$HOME/.local/bin`, `/usr/local/bin`, or `/opt/homebrew/bin`).
2. **Installs a shell hook** that checks for updates every time you open a new terminal session. The hook detects your shell (`$SHELL`), resolves the right profile (`~/.zshrc` for zsh, `~/.bash_profile` for bash), and appends a one-line hook. Safe to re-run.

### 3. Initialize the toolkit in your target project

```bash
cd /path/to/your/project
sdd init
```

The wizard:

- copies `/spec-*` slash commands into `.claude/commands/`
- creates `.sdd/` with `config.json` (records the toolkit short SHA in `sdd_version`)
- copies the spec template into `.sdd/specs/template/spec.md`
- creates `.sdd/specs/.cache/` for publish state
- always gitignores the SDD-specific globs `.claude/commands/spec-*.md`, `.claude/skills/spec-*/`, and `.sdd/specs/.cache/` — your own commands/skills under `.claude/` are left alone
- asks whether to track `.sdd/` specs in git (default Yes)
- asks whether to include Claude as a co-author in commits (default Yes)

The wizard does **not** prompt for source/Jira/YouTrack config. Source defaults to `local`. To publish to Jira, edit `.sdd/config.json`'s `source` field and `sources.jira` block, then run `sdd publish <SPEC-ID>`.

Re-run `sdd init` any time to reinitialize — existing files are overwritten. `.sdd/specs/<id>.md` files and `.sdd/specs/.cache/` contents are left untouched. `sdd_version` is rewritten on every `sdd init`.

---

## 🔄 CLI Commands

| Command | Description |
|---|---|
| `sdd init` | Initialize or re-initialize the SDD toolkit in the current project |
| `sdd upgrade` | Pull the latest toolkit changes from the remote repository |
| `sdd version` | Show installed version (commit hash) and latest available |
| `sdd publish <id>` | Push a local spec to its configured external source (Jira) |
| `sdd uninstall` | Remove the `sdd` CLI symlink and shell hook |
| `sdd help` | Show available commands |

### Auto-update check

Every time you open a new terminal, the shell hook compares the local commit hash against the remote. If an update is available, you’re prompted:

```
SDD toolkit update available: abc1234 -> def5678
Install now? [Y/n]:
```

Press Enter or `Y` to update (runs `git pull`). Press `N` to skip. The check runs at most once every 24 hours.

If you're in a directory with `.sdd/` (an SDD-enabled project), the hook also compares the project's recorded `sdd_version` against the toolkit's current short SHA. When they differ:

```
  [sdd] this project was initialised with abc1234; toolkit is at def5678
  [sdd] run "sdd init" here to refresh.
```

When `sdd_version` is missing (older config), it falls back to the generic tip:

```
  Tip: Run "sdd init" to apply toolkit updates to this project.
```

---

## 🛠️ Usage

All commands are invoked inside Claude Code:

```
/spec-draft  <SPEC-ID> <type> <title>   # create or refresh a spec + branch
/spec-plan   <SPEC-ID> [changes]        # produce/refresh the implementation plan
/spec-build  <SPEC-ID>                  # walk the plan step by step
/spec-status [SPEC-ID]                  # dashboard: phase + next command
```

`<type>` is one of `feature`, `bugfix`, `refactor`, `chore`, `docs`, `experiment`, `hotfix`, `release`, `support`.

### The happy path

```
/spec-draft PAR-224 bugfix Same Value Min Max Validation
/spec-plan  PAR-224
/spec-build PAR-224
```

`/spec-draft` asks whether to create a new branch (default Yes; press `n` to stay on the current branch), then writes an empty-template `.sdd/specs/PAR-224.md` for you to fill. `/spec-plan` analyzes the codebase, asks you to resolve open questions, and appends an Implementation Plan. `/spec-build` walks the plan step by step, pausing after each so you can review before it commits. To sync the spec to Jira, run `sdd publish PAR-224` separately when you're ready.

### Non-linear iteration

Real work isn't linear. The commands are designed for re-entry:

- **Refresh the spec** — run `/spec-draft <id> ...` again on an existing spec. The branch prompt is skipped, the body template is rewritten, and local-only sections (`Clarifications`, `Analysis`, `Implementation Plan`) are preserved.
- **Re-plan after feedback** — run `/spec-plan <id> <what changed and why>`. The `changes` argument is **required** on re-runs. Checked steps still valid are kept; **invalidated steps are deleted outright** (numbering never renumbers — gaps are intentional and indicate where superseded work used to live). The reason for each deletion is recorded as one of ≤3 Clarifications bullets per re-run. New work is appended continuing the step numbering.
- **Resume a build** — `/spec-build <id>` always picks up at the next unchecked step, including after a re-plan.
- **Check where you are** — `/spec-status <id>` (or no ID for a table of all specs) shows the current phase (`drafted` / `planned` / `building` / `done`), progress counts, and the next command to run.

### Commit style

`/spec-build` commits each step individually with a message like `<spec_id>: step N - <short description>`. Commit messages and PR bodies are not compressed — your repo's conventions (including any `Co-Authored-By` footer) are preserved.

---

## 🔌 Publishing specs to external systems

Specs are authored locally — the Markdown file under `.sdd/specs/<id>.md` is the working copy. To sync a spec to an external system, run `sdd publish <SPEC-ID>`. The publish step is **separate from `/spec-build`**: nothing happens automatically.

### Configuring a source

Edit `.sdd/config.json`:

```json
{
  "source": "jira",
  "sources": {
    "jira": {
      "project_key": "PAR",
      "workspace": "your-workspace"
    }
  }
}
```

Then run `acli auth login` (Jira) and you're ready.

### Built-in sources

| Source | Status | Requires |
|---|---|---|
| `local` | Default | nothing — `sdd publish` is a no-op |
| `jira` | Working | Atlassian CLI (`acli`) + `acli auth login`. Uses positional refs (`acli jira workitem edit <ref> --description-file=…`). |
| `youtrack` | Stub | not implemented yet |

### Drift detection

`sdd publish` writes a cache at `.sdd/specs/.cache/<spec_id>.<source>.md` (gitignored) on every successful push. On the next push it pulls the remote, diffs against this cache, and if the remote has drifted you're shown a diff and asked to type `continue` before any overwrite.

---

## 🏗️ Repository layout

```
.
├── ai/
│   └── claude/
│       ├── commands/           # /spec-draft, /spec-plan, /spec-build, /spec-status
│       └── skills/             # (none ship today)
├── templates/
│   └── spec.md                 # Spec template with YAML frontmatter
├── scripts/
│   ├── sdd.sh                  # CLI facade (symlinked as `sdd`)
│   ├── setup.sh                # Wizard invoked by `sdd init`
│   ├── sdd-publish.sh          # `sdd publish <id>` — push to Jira/YouTrack
│   ├── install.sh              # Installs `sdd` on PATH + shell hook
│   ├── uninstall.sh            # Removes `sdd` from PATH + shell hook
│   └── check-update.sh         # Auto-update check run by the shell hook
├── CLAUDE.md
├── LICENSE
└── README.md
```

Layout inside a target project after running the wizard:

```
your-project/
├── .claude/
│   └── commands/               # spec-draft, spec-plan, spec-build, spec-status
└── .sdd/
    ├── config.json             # Wizard-generated config (sdd_version, source, etc.)
    └── specs/
        ├── template/spec.md    # Spec template
        ├── .cache/             # Last-known remote state (gitignored)
        └── <SPEC-ID>.md        # One file per spec
```

---

## 🔄 Updating / reinitializing

- **Toolkit update** — run `sdd upgrade`, then `sdd init` in each target project. Existing commands and template are overwritten; your specs and the rest of `config.json` are not (only `sdd_version` is rewritten).
- **Reset a single project** — delete `.claude/commands/spec-*.md`, `.claude/skills/spec-*/`, `.sdd/`, then re-run `sdd init`.
- **Move off the toolkit** — `.sdd/specs/` is just Markdown; it keeps working without the commands.
- **Legacy `.specs/` directory** — if you have spec files from an older install under `.specs/`, the wizard leaves them untouched. Move them to `.sdd/specs/` manually after reinitializing.

---

## 🔔 Auto-Update Check

The shell hook is installed automatically by `scripts/install.sh` (see [Install step 2](#2-install-the-sdd-cli)). When a new terminal session opens, the hook silently checks whether the upstream repository has a newer commit. If one is found, it prompts for confirmation (`Y/n`) before applying anything.

The check:
- runs at most once per 24 hours (cooldown stored in `~/.sdd/.last_update_check`)
- times out after 5 seconds if the network is unavailable, and fails silently
- only prompts when your local commit differs from the remote HEAD
- applies the update with `git pull` in your toolkit clone — target projects are not touched
- advises you to run `sdd init` if the current directory is an SDD-enabled project

### Manual installation

If you prefer to add the hook line yourself rather than running `scripts/install.sh`:

**zsh** — add to `~/.zshrc`:

```zsh
[ -x "/path/to/ai-spec-dev-kit/scripts/check-update.sh" ] && "/path/to/ai-spec-dev-kit/scripts/check-update.sh"
```

**bash** — add to `~/.bash_profile`:

```bash
[ -x "/path/to/ai-spec-dev-kit/scripts/check-update.sh" ] && "/path/to/ai-spec-dev-kit/scripts/check-update.sh"
```

Replace `/path/to/ai-spec-dev-kit` with the absolute path to your clone.

---

## 📄 License

This project is licensed under the MIT License — see [`LICENSE`](./LICENSE).

> [!NOTE]
> 🚧 Work in progress — feedback and PRs welcome.
