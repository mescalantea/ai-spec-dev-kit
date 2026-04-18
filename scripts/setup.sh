#!/usr/bin/env bash
# spec-init — wizard that copies the SDD toolkit into the current project.
#
# Usage:
#   cd /path/to/target/project
#   /path/to/ai-spec-dev-kit/scripts/setup.sh
#
# Or after running scripts/install-global.sh:
#   cd /path/to/target/project
#   spec-init
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
SRC_SOURCES_DOC="$REPO_ROOT/sdd/sources.md"
SRC_TEMPLATE="$REPO_ROOT/templates/spec.md"

# Destinations in the target project.
DST_CLAUDE="$TARGET_DIR/.claude"
DST_COMMANDS="$DST_CLAUDE/commands"
DST_SKILLS="$DST_CLAUDE/skills"
DST_SDD="$TARGET_DIR/.sdd"
DST_SOURCES_DOC="$DST_SDD/sources.md"
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

if [ ! -d "$SRC_SKILLS" ]; then
  echo "Error: cannot find skills directory at $SRC_SKILLS" >&2
  exit 1
fi

if [ ! -f "$SRC_TEMPLATE" ]; then
  echo "Error: cannot find spec template at $SRC_TEMPLATE" >&2
  exit 1
fi

if [ ! -f "$SRC_SOURCES_DOC" ]; then
  echo "Error: cannot find sources adapter doc at $SRC_SOURCES_DOC" >&2
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
  # Use cp -R on both macOS and Linux; copies files and nested dirs (skill folders).
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
  • copy slash commands into .claude/commands/
  • copy skills into .claude/skills/
  • create .sdd/ with sources.md and config.json
  • copy the spec template into .sdd/specs/template/
  • create .sdd/specs/.cache/ for source sync state
  • add .sdd/specs/.cache/ to .gitignore

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

echo
echo "Source configuration"
echo "--------------------"

JIRA_ENABLED=$(prompt_yn "Enable Jira as a spec source?" "n")
JIRA_PROJECT_KEY=""
JIRA_WORKSPACE=""

if [ "$JIRA_ENABLED" = "true" ]; then
  if ! command -v acli >/dev/null 2>&1; then
    echo
    echo "Warning: 'acli' (Atlassian CLI) is not on PATH."
    echo "         You can continue — install it later via your package manager."
    echo "         The Jira source commands will fail until acli is installed and authenticated."
  fi
  JIRA_PROJECT_KEY=$(prompt "Default Jira project key (e.g. PAR)" "")
  JIRA_WORKSPACE=$(prompt "acli workspace" "")
fi

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

# Skills (nested directories).
copy_dir_contents "$SRC_SKILLS" "$DST_SKILLS"

# Source adapter doc.
cp "$SRC_SOURCES_DOC" "$DST_SOURCES_DOC"
echo "  wrote $DST_SOURCES_DOC"

# Spec template.
cp "$SRC_TEMPLATE" "$DST_TEMPLATE_DIR/spec.md"
echo "  wrote $DST_TEMPLATE_DIR/spec.md"

# Config.
cat > "$DST_CONFIG" <<EOF
{
  "sources": {
    "local": {
      "enabled": true,
      "path": ".sdd/specs"
    },
    "jira": {
      "enabled": $JIRA_ENABLED,
      "project_key": "$JIRA_PROJECT_KEY",
      "workspace": "$JIRA_WORKSPACE"
    }
  }
}
EOF
echo "  wrote $DST_CONFIG"

ensure_gitignore_line ".specs/.cache/"
echo "  updated $DST_GITIGNORE"

# ---------------------------------------------------------------------------
# Summary.
# ---------------------------------------------------------------------------

cat <<EOF

────────────────────────────────────────────────────
Done.

Enabled sources:
  local: true
  jira:  $JIRA_ENABLED
EOF

if [ "$JIRA_ENABLED" = "true" ]; then
  cat <<EOF
    project_key: $JIRA_PROJECT_KEY
    workspace:   $JIRA_WORKSPACE

  Make sure you have run:   acli auth login
EOF
fi

cat <<EOF

Commands available in Claude Code:
  /spec-draft <SPEC-ID> <type> <title>
  /spec-plan  <SPEC-ID> [changes]
  /spec-build <SPEC-ID>
  /spec-status [SPEC-ID]

Next: open this project in Claude Code and run
      /spec-draft <SPEC-ID> <type> <short title>
────────────────────────────────────────────────────
EOF
