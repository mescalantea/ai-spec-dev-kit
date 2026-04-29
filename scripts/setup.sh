#!/usr/bin/env bash
# setup.sh — wizard that copies the SDD toolkit into the current project.
#
# Usage:
#   cd /path/to/target/project
#   sdd init
#
# Or directly:
#   /path/to/ai-spec-dev-kit/scripts/setup.sh
#
# Compatible with macOS default bash (3.2) and Linux.

set -eu

# ---------------------------------------------------------------------------
# Locate this script and the repo it lives in (resolves symlinks).
# ---------------------------------------------------------------------------

resolve_path() {
  target="$1"
  while [ -L "$target" ]; do
    link=$(readlink "$target")
    case "$link" in
      /*) target="$link" ;;
      *)  target="$(cd "$(dirname "$target")" && pwd)/$link" ;;
    esac
  done
  cd "$(dirname "$target")" && printf '%s\n' "$(pwd)/$(basename "$target")"
}

SCRIPT_PATH="$(resolve_path "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_DIR="$(pwd)"

# Sources in the toolkit repo.
SRC_COMMANDS="$REPO_ROOT/ai/claude/commands"
SRC_SKILLS="$REPO_ROOT/ai/claude/skills"
SRC_TEMPLATE="$REPO_ROOT/templates/spec.md"

# Destinations in the target project.
DST_CLAUDE="$TARGET_DIR/.claude"
DST_COMMANDS="$DST_CLAUDE/commands"
DST_SKILLS="$DST_CLAUDE/skills"
DST_SDD="$TARGET_DIR/.sdd"
DST_CONFIG="$DST_SDD/config.json"
DST_TEMPLATE_DIR="$TARGET_DIR/.sdd/specs/template"
DST_CACHE_DIR="$TARGET_DIR/.sdd/specs/.cache"
DST_GITIGNORE="$TARGET_DIR/.gitignore"

# ---------------------------------------------------------------------------
# Sanity checks.
# ---------------------------------------------------------------------------

if [ ! -d "$SRC_COMMANDS" ]; then
  echo "Error: cannot find commands directory at $SRC_COMMANDS" >&2
  exit 1
fi

if [ ! -f "$SRC_TEMPLATE" ]; then
  echo "Error: cannot find spec template at $SRC_TEMPLATE" >&2
  exit 1
fi

if [ "$TARGET_DIR" = "$REPO_ROOT" ]; then
  echo "Error: refusing to install the toolkit into its own source directory." >&2
  echo "       cd into your target project first, then run this script." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Helpers.
# ---------------------------------------------------------------------------

prompt() {
  question="$1"
  default="${2:-}"
  if [ -n "$default" ]; then
    printf '%s [%s]: ' "$question" "$default" > /dev/tty
  else
    printf '%s: ' "$question" > /dev/tty
  fi
  read -r answer < /dev/tty || answer=""
  if [ -z "$answer" ]; then
    answer="$default"
  fi
  printf '%s' "$answer"
}

prompt_yn() {
  question="$1"
  default="${2:-n}"
  case "$default" in
    y|Y) hint="Y/n" ;;
    *)   hint="y/N" ;;
  esac
  while :; do
    printf '%s [%s]: ' "$question" "$hint" > /dev/tty
    read -r answer < /dev/tty || answer=""
    [ -z "$answer" ] && answer="$default"
    case "$answer" in
      y|Y|yes|YES) printf 'true';  return ;;
      n|N|no|NO)   printf 'false'; return ;;
    esac
  done
}

ensure_gitignore_line() {
  line="$1"
  if [ ! -f "$DST_GITIGNORE" ]; then
    printf '%s\n' "$line" > "$DST_GITIGNORE"
    return
  fi
  if ! grep -Fxq "$line" "$DST_GITIGNORE"; then
    # Guard: if file is non-empty and last byte is not \n, add one.
    # tail -c 1 | wc -l returns 1 when last byte is \n, 0 for any other byte.
    if [ -s "$DST_GITIGNORE" ] && [ "$(tail -c 1 "$DST_GITIGNORE" | wc -l)" -eq 0 ]; then
      printf '\n' >> "$DST_GITIGNORE"
    fi
    printf '%s\n' "$line" >> "$DST_GITIGNORE"
  fi
}

copy_dir_contents() {
  src="$1"
  dst="$2"
  mkdir -p "$dst"
  for entry in "$src"/* "$src"/.??*; do
    [ -e "$entry" ] || continue
    name="$(basename "$entry")"
    case "$name" in
      .gitkeep|.DS_Store) continue ;;
    esac
    cp -R "$entry" "$dst/"
    echo "  wrote $dst/$name"
  done
}

# ---------------------------------------------------------------------------
# Banner.
# ---------------------------------------------------------------------------

cat <<EOF
────────────────────────────────────────────────────
Spec-Driven Development Toolkit — setup wizard
────────────────────────────────────────────────────
Repo:    $REPO_ROOT
Target:  $TARGET_DIR

This will:
  • copy /spec-* slash commands into .claude/commands/
  • create .sdd/ with config.json (records the toolkit version)
  • copy the spec template into .sdd/specs/template/
  • create .sdd/specs/.cache/ for publish state
  • always gitignore .claude/commands/spec-*.md, .claude/skills/spec-*/, .sdd/specs/.cache/
  • ask whether to track .sdd/ specs in git

Existing files will be overwritten.
────────────────────────────────────────────────────
EOF

confirm=$(prompt_yn "Proceed?" "y")
if [ "$confirm" != "true" ]; then
  echo "Aborted."
  exit 0
fi

# ---------------------------------------------------------------------------
# Wizard questions.
# ---------------------------------------------------------------------------

CLAUDE_ATTRIBUTION=$(prompt_yn "Include Claude as a co-author in commits and PR bodies?" "y")

echo
echo "Version control"
echo "---------------"
echo "Spec files under .sdd/specs/ can be committed alongside your code or kept local-only."
TRACK_SPECS=$(prompt_yn "Track .sdd/ specs in git?" "y")

# ---------------------------------------------------------------------------
# Compute toolkit version (short SHA of REPO_ROOT HEAD).
# ---------------------------------------------------------------------------

SDD_VERSION="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")"

# ---------------------------------------------------------------------------
# Apply.
# ---------------------------------------------------------------------------

echo
echo "Installing..."

mkdir -p "$DST_COMMANDS" "$DST_SKILLS" "$DST_SDD" "$DST_TEMPLATE_DIR" "$DST_CACHE_DIR"

# Commands (flat .md files).
for f in "$SRC_COMMANDS"/*.md; do
  [ -e "$f" ] || continue
  cp "$f" "$DST_COMMANDS/"
  echo "  wrote $DST_COMMANDS/$(basename "$f")"
done

# Skills (nested directories). Only copy if any exist; the toolkit may ship without
# any spec-* skills now that caveman/source have been removed.
if [ -d "$SRC_SKILLS" ] && ls "$SRC_SKILLS"/spec-* >/dev/null 2>&1; then
  copy_dir_contents "$SRC_SKILLS" "$DST_SKILLS"
fi

# Spec template.
cp "$SRC_TEMPLATE" "$DST_TEMPLATE_DIR/spec.md"
echo "  wrote $DST_TEMPLATE_DIR/spec.md"

# Config. Source defaults to "local"; users who need Jira/YouTrack edit this file
# directly and run `sdd publish <spec_id>` to sync.
cat > "$DST_CONFIG" <<EOF
{
  "sdd_version": "$SDD_VERSION",
  "claude_attribution": $CLAUDE_ATTRIBUTION,
  "track_specs": $TRACK_SPECS,
  "source": "local",
  "sources": {
    "local": {
      "path": ".sdd/specs"
    },
    "jira": {
      "project_key": "",
      "workspace": ""
    },
    "youtrack": {
      "base_url": "",
      "token_env": "YOUTRACK_TOKEN",
      "project_id": ""
    }
  }
}
EOF
echo "  wrote $DST_CONFIG"

# Always-ignore: SDD-specific paths under .claude/ + the publish cache.
# Scoped globs only — leave the user's own .claude/ content alone.
ensure_gitignore_line ".claude/commands/spec-*.md"
ensure_gitignore_line ".claude/skills/spec-*/"
ensure_gitignore_line ".sdd/specs/.cache/"

if [ "$TRACK_SPECS" = "false" ]; then
  ensure_gitignore_line ".sdd/"
fi
echo "  updated $DST_GITIGNORE"

# ---------------------------------------------------------------------------
# Summary.
# ---------------------------------------------------------------------------

cat <<EOF

────────────────────────────────────────────────────
Done.

Toolkit version:    $SDD_VERSION
Claude attribution: $CLAUDE_ATTRIBUTION
Track specs in git: $TRACK_SPECS
Source:             local

Commands available in Claude Code:
  /spec-draft  <SPEC-ID> <type> <title>
  /spec-plan   <SPEC-ID> [changes]
  /spec-build  <SPEC-ID>
  /spec-status [SPEC-ID]

To sync a spec to Jira:
  1) edit .sdd/config.json -> set "source": "jira" and fill sources.jira
  2) run 'acli auth login' if you have not already
  3) run 'sdd publish <SPEC-ID>'

Re-run 'sdd init' any time after 'sdd upgrade' to pick up changes.
────────────────────────────────────────────────────
EOF
