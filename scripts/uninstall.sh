#!/usr/bin/env bash
# uninstall.sh — Remove the `sdd` CLI symlink and the auto-update shell hook.
#
# Usage:
#   /path/to/ai-spec-dev-kit/scripts/uninstall.sh
#
# What it does:
#   1. Removes the `sdd` symlink from PATH.
#   2. Removes the auto-update hook line from your shell profile.
#   3. Optionally removes ~/.sdd/ (cooldown state).
#
# Does NOT touch target projects — .claude/ and .sdd/ in your projects are left as-is.
# Compatible with macOS default bash (3.2) and Linux.

set -eu

COMMAND_NAME="sdd"

# ---------------------------------------------------------------------------
# Resolve symlinks (macOS-compatible, no readlink -f).
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
CHECK_SCRIPT="$SCRIPT_DIR/check-update.sh"

# ---------------------------------------------------------------------------
# Helpers.
# ---------------------------------------------------------------------------

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
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO)   return 1 ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# Step 1: Remove the `sdd` symlink.
# ---------------------------------------------------------------------------

echo "Uninstalling the SDD Toolkit..."

REMOVED_LINK=false
for candidate in "$HOME/.local/bin" "/usr/local/bin" "/opt/homebrew/bin"; do
  LINK_PATH="$candidate/$COMMAND_NAME"
  if [ -L "$LINK_PATH" ]; then
    link_target=$(readlink "$LINK_PATH" 2>/dev/null) || true
    case "$link_target" in
      "$REPO_ROOT"*)
        rm -f "$LINK_PATH"
        echo "  removed $LINK_PATH"
        REMOVED_LINK=true
        ;;
    esac
  fi

  # Also clean up legacy spec-init symlink.
  OLD_LINK="$candidate/spec-init"
  if [ -L "$OLD_LINK" ]; then
    old_target=$(readlink "$OLD_LINK" 2>/dev/null) || true
    case "$old_target" in
      "$REPO_ROOT"*)
        rm -f "$OLD_LINK"
        echo "  removed legacy $OLD_LINK"
        ;;
    esac
  fi
done

if [ "$REMOVED_LINK" = false ]; then
  echo "  no 'sdd' symlink found on PATH — skipped"
fi

# ---------------------------------------------------------------------------
# Step 2: Remove the auto-update shell hook.
# ---------------------------------------------------------------------------

echo
echo "Removing auto-update shell hook..."

REMOVED_HOOK=false
for PROFILE in "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.bashrc"; do
  [ -f "$PROFILE" ] || continue
  if grep -Fq "$CHECK_SCRIPT" "$PROFILE" 2>/dev/null; then
    tmp_profile=$(mktemp 2>/dev/null) || continue
    grep -Fv "$CHECK_SCRIPT" "$PROFILE" > "$tmp_profile"
    mv "$tmp_profile" "$PROFILE"
    echo "  removed hook from $PROFILE"
    REMOVED_HOOK=true
  fi
done

if [ "$REMOVED_HOOK" = false ]; then
  echo "  no hook found in shell profiles — skipped"
fi

# ---------------------------------------------------------------------------
# Step 3: Optionally remove ~/.sdd/ (cooldown state).
# ---------------------------------------------------------------------------

if [ -d "$HOME/.sdd" ]; then
  echo
  if prompt_yn "Remove ~/.sdd/ (update check state)?" "y"; then
    rm -rf "$HOME/.sdd"
    echo "  removed ~/.sdd/"
  else
    echo "  kept ~/.sdd/"
  fi
fi

# ---------------------------------------------------------------------------
# Summary.
# ---------------------------------------------------------------------------

cat <<EOF

────────────────────────────────────────────────────
SDD Toolkit uninstalled.

Project directories (.claude/, .sdd/) were not touched.
To remove SDD from a project, delete .claude/commands/spec-*.md
and .sdd/ manually, then drop the SDD globs from .git/info/exclude.
────────────────────────────────────────────────────
EOF
