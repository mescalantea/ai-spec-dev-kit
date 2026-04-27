# Spec-Driven Toolkit

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
- **`spec-source` skill** — reusable pull / adapt / push / conflict-detection across spec backends (`local`, `jira`, `youtrack`, extensible to Linear / GitHub Issues).
- **`spec-caveman` skill** — terse-response style that auto-activates inside SDD commands to cut token usage without losing technical substance. Commits and PRs are never compressed.
- **Adapter catalog** (`.sdd/sources.md`) — agent-neutral description of each source's wire calls.
- **`sdd` CLI** (`scripts/sdd.sh`) — global facade with subcommands: `init`, `upgrade`, `version`, `help`.
- **Setup wizard** (`scripts/setup.sh`) — POSIX bash, macOS + Linux. Copies commands, skills, template, and generates `.sdd/config.json` from your answers. Invoked via `sdd init`.
- **Installer** (`scripts/install.sh`) — symlinks `sdd` onto PATH and installs the auto-update shell hook.

---

## 🧠 Goals

- Make specs the **single source of truth**, whether they live in the repo (`.sdd/specs/<id>.md`) or an external system (Jira, YouTrack, more adapters later). Either way, the local Markdown file is the canonical working copy.
- Enforce a **multi-step flow with human review** — draft, plan, build — so AI never jumps straight to code.
- Support **non-linear iteration** — each phase can be re-entered as requirements shift, preserving history and marking obsolete steps instead of deleting them.
- Stay **agent-neutral where it matters** — sources, config, and template live outside `.claude/` so other agents can plug in later.
- Be **token-efficient** — the `spec-caveman` skill compresses prose automatically inside SDD commands.

---

## ✅ Requirements

- **Bash** 3.2+ (macOS default) or any modern bash on Linux. The scripts declare `#!/usr/bin/env bash`, so they run under bash regardless of your login shell (zsh, bash, fish — all fine).
- **Git** — the toolkit manages branches per spec.
- **Claude Code** CLI.
- **Atlassian CLI (`acli`)** — only if you enable the Jira source. Run `acli auth login` once before using Jira-backed specs.
- **`curl` + `jq` (or `python3`)** — only if you enable the YouTrack source. Set the `YOUTRACK_TOKEN` env var to a permanent YouTrack token.

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
- copies the `spec-source` and `spec-caveman` skills into `.claude/skills/`
- creates `.sdd/` with `sources.md` and `config.json`
- copies the spec template into `.sdd/specs/template/spec.md`
- creates `.sdd/specs/.cache/` and adds it to `.gitignore`
- asks whether to enable Jira; if yes, collects the project key and `acli` workspace
- asks whether to enable YouTrack; if yes, collects the base URL, project key, and token env var name
- asks whether to gitignore the toolkit directories (`.sdd/`, `.claude/commands/`, `.claude/skills/`) — default no (commit by default)

Re-run `sdd init` any time to reinitialize — existing files are overwritten. `.sdd/specs/<id>.md` files and `.sdd/specs/.cache/` contents are left untouched.

---

## 🔄 CLI Commands

| Command | Description |
|---|---|
| `sdd init` | Initialize or re-initialize the SDD toolkit in the current project |
| `sdd upgrade` | Pull the latest toolkit changes from the remote repository |
| `sdd version` | Show installed version (commit hash) and latest available |
| `sdd uninstall` | Remove the `sdd` CLI symlink and shell hook |
| `sdd help` | Show available commands |

### Auto-update check

Every time you open a new terminal, the shell hook compares the local commit hash against the remote. If an update is available, you’re prompted:

```
SDD toolkit update available: abc1234 -> def5678
Install now? [Y/n]:
```

Press Enter or `Y` to update (runs `git pull`). Press `N` to skip. The check runs at most once every 24 hours.

If you’re in a directory with `.sdd/` (an SDD-enabled project), the hook also reminds you:

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

`/spec-draft` creates the feature branch, pulls the description from the source (Jira, or an empty template for `local`), and writes `.sdd/specs/PAR-224.md`. `/spec-plan` analyzes the codebase, asks you to resolve open questions, and appends an Implementation Plan. `/spec-build` walks the plan step by step, pausing after each so you can review before it commits.

### Non-linear iteration

Real work isn't linear. The commands are designed for re-entry:

- **Refresh the spec** — run `/spec-draft <id> ...` again on an existing spec. Branch creation is skipped, the body is re-pulled from the source, and local-only sections (`Clarifications`, `Analysis`, `Implementation Plan`) are preserved. You're warned if they may now be stale.
- **Re-plan after feedback** — run `/spec-plan <id> <what changed and why>`. The `changes` argument is **required** on re-runs. Checked steps still valid are kept; invalidated checked steps are rewritten with a strikethrough and `_(superseded: <reason>)_` marker; obsolete unchecked steps are removed; new work is appended continuing the step numbering.
- **Resume a build** — `/spec-build <id>` always picks up at the next unchecked step, including after a re-plan.
- **Check where you are** — `/spec-status <id>` (or no ID for a table of all specs) shows the current phase (`drafted` / `planned` / `building` / `done`), progress counts, source sync state, and the next command to run.

### Commit style

`/spec-build` commits each step individually with a message like `<spec_id>: step N - <short description>`. Commit messages and PR bodies are **not** compressed by the caveman skill — your repo's conventions (including any `Co-Authored-By` footer) are preserved.

---

## 🔌 Spec sources

Specs can come from multiple backends. Each backend implements a simple four-operation contract (`pull`, `adapt`, `push`, `detect_conflict`) described in `.sdd/sources.md`. The `spec-source` skill is the single point of entry — commands delegate all external I/O to it.

### Built-in adapters

| Source | Requires | Notes |
|---|---|---|
| `local` | nothing | Default. The Markdown file under `.sdd/specs/` IS the source of truth. |
| `jira` | Atlassian CLI (`acli`) + prior `acli auth login` | `/spec-draft` pulls the description, adapts it to the template (asking you to review), and caches it. `/spec-plan` and `/spec-build` push the updated body back at the end, after detecting any external drift and asking for confirmation. |
| `youtrack` | `curl`, `jq` or `python3`, `YOUTRACK_TOKEN` env var | Same lifecycle as Jira. Uses the YouTrack REST API directly — no CLI dependency. Set `YOUTRACK_TOKEN` to a permanent YouTrack token. `base_url` in config must be the instance root with no trailing slash (e.g. `https://myteam.youtrack.cloud`). |

Conflict detection uses a cache at `.sdd/specs/.cache/<spec_id>.<source>.md` (gitignored). If the remote has drifted since the last sync, you're shown a diff and asked to type `continue` before any overwrite.

### Adding a new source

1. Add a section to `.sdd/sources.md` describing the adapter's pull/push wire calls.
2. Add a key under `sources` in `.sdd/config.json` with its configuration (project key, workspace, token env, etc.).

No command or skill changes needed — the skill reads the catalog at runtime.

---

## 🏗️ Repository layout

```
.
├── ai/
│   └── claude/
│       ├── commands/           # /spec-draft, /spec-plan, /spec-build, /spec-status
│       └── skills/
│           ├── spec-source/    # Source I/O adapter skill
│           └── spec-caveman/   # Terse-response style skill
├── sdd/
│   └── sources.md              # Source adapter catalog (agent-neutral)
├── templates/
│   └── spec.md                 # Spec template with YAML frontmatter
├── scripts/
│   ├── sdd.sh                  # CLI facade (symlinked as `sdd`)
│   ├── setup.sh                # Wizard invoked by `sdd init`
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
│   ├── commands/               # spec-draft, spec-plan, spec-build, spec-status
│   └── skills/
│       ├── spec-source/
│       └── spec-caveman/
└── .sdd/
    ├── config.json             # Wizard-generated source config
    ├── sources.md              # Adapter catalog
    └── specs/
        ├── template/spec.md    # Spec template
        ├── .cache/             # Last-known remote state (gitignored)
        └── <SPEC-ID>.md        # One file per spec
```

---

## 🔄 Updating / reinitializing

- **Toolkit update** — run `sdd upgrade`, then `sdd init` in each target project. Existing commands, skills, template, and `sources.md` are overwritten; your specs and config are not.
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

## 🙏 Credits & attribution

The `spec-caveman` skill is adapted from **Julius Brussee's `caveman`** project:
<https://github.com/JuliusBrussee/caveman> — MIT License.

The fork reduces the feature set to a single level (`lite`), wires it to auto-activate inside the SDD command lifecycle, and adds exceptions so git commit messages, PR bodies, and verbatim user prompts are never compressed. All credit for the original compression rules and intensity-level design goes to the upstream author.

---

## 📄 License

This project is licensed under the MIT License — see [`LICENSE`](./LICENSE).

> [!NOTE]
> 🚧 Work in progress — feedback and PRs welcome.
