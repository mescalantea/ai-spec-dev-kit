#!/usr/bin/env bash
# install.sh — Install the `sdd` CLI globally and set up the auto-update shell hook.
#
# Usage:
#   /path/to/ai-spec-dev-kit/scripts/install.sh
#
# What it does:
#   1. Symlinks scripts/sdd.sh as `sdd` in a writable directory on PATH.
#   2. Injects an auto-update hook into your shell profile (~/.zshrc or ~/.bash_profile).
#
# Safe to re-run — the symlink and hook are updated/skipped as needed.
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
SDD_SCRIPT="$SCRIPT_DIR/sdd.sh"
CHECK_SCRIPT="$SCRIPT_DIR/check-update.sh"

if [ ! -f "$SDD_SCRIPT" ]; then
  echo "Error: cannot find $SDD_SCRIPT" >&2
  exit 1
fi

chmod +x "$SDD_SCRIPT"

if [ -f "$CHECK_SCRIPT" ]; then
  chmod +x "$CHECK_SCRIPT"
fi

# ---------------------------------------------------------------------------
# Step 1: Symlink `sdd` onto PATH.
# ---------------------------------------------------------------------------

echo "Installing the 'sdd' CLI..."

INSTALL_DIR=""
for candidate in "$HOME/.local/bin" "/usr/local/bin" "/opt/homebrew/bin"; do
  case ":$PATH:" in
    *":$candidate:"*)
      if [ -w "$candidate" ] || [ ! -e "$candidate" ]; then
        INSTALL_DIR="$candidate"
        break
      fi
      ;;
  esac
done

if [ -z "$INSTALL_DIR" ]; then
  echo "Could not find a writable directory on your PATH."
  echo "Candidates tried: \$HOME/.local/bin, /usr/local/bin, /opt/homebrew/bin"
  echo
  echo "Create one and add it to PATH, for example:"
  echo "  mkdir -p \$HOME/.local/bin"
  echo "  # zsh:"
  echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc"
  echo "  # bash:"
  echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
  exit 1
fi

mkdir -p "$INSTALL_DIR"
LINK_PATH="$INSTALL_DIR/$COMMAND_NAME"

# Remove old spec-init symlink if it points into this repo.
OLD_LINK="$INSTALL_DIR/spec-init"
if [ -L "$OLD_LINK" ]; then
  old_target=$(readlink "$OLD_LINK" 2>/dev/null) || true
  case "$old_target" in
    "$REPO_ROOT"*)
      rm -f "$OLD_LINK"
      echo "  removed old 'spec-init' symlink"
      ;;
  esac
fi

if [ -e "$LINK_PATH" ] || [ -L "$LINK_PATH" ]; then
  rm -f "$LINK_PATH"
fi

ln -s "$SDD_SCRIPT" "$LINK_PATH"
echo "  $LINK_PATH -> $SDD_SCRIPT"

# ---------------------------------------------------------------------------
# Step 2: Install auto-update shell hook.
# ---------------------------------------------------------------------------

if [ -f "$CHECK_SCRIPT" ]; then
  echo
  echo "Installing auto-update shell hook..."

  case "${SHELL:-/bin/zsh}" in
    */zsh)  PROFILE="$HOME/.zshrc" ;;
    */bash) PROFILE="$HOME/.bash_profile" ;;
    *)      PROFILE="$HOME/.zshrc" ;;
  esac

  HOOK_LINE="[ -x \"$CHECK_SCRIPT\" ] && \"$CHECK_SCRIPT\""

  # Remove old hook lines that reference this repo's check-update.sh
  # (in case the path format changed between versions).
  if [ -f "$PROFILE" ]; then
    # Check for any existing hook pointing at our check-update.sh.
    if grep -Fq "$CHECK_SCRIPT" "$PROFILE" 2>/dev/null; then
      if grep -Fxq "$HOOK_LINE" "$PROFILE"; then
        echo "  hook already present in $PROFILE — skipped"
      else
        # Old format hook exists; replace it.
        tmp_profile=$(mktemp 2>/dev/null) || true
        if [ -n "$tmp_profile" ]; then
          grep -Fv "$CHECK_SCRIPT" "$PROFILE" > "$tmp_profile"
          mv "$tmp_profile" "$PROFILE"
        fi
        # Fall through to inject updated line below.
      fi
    fi
  fi

  # Inject if not already present.
  if ! { [ -f "$PROFILE" ] && grep -Fxq "$HOOK_LINE" "$PROFILE"; }; then
    if [ -s "$PROFILE" ] && [ "$(tail -c 1 "$PROFILE" | wc -l)" -eq 0 ]; then
      printf '\n' >> "$PROFILE"
    fi
    printf '%s\n' "$HOOK_LINE" >> "$PROFILE"
    echo "  installed hook in $PROFILE"
  fi
else
  echo
  echo "Warning: check-update.sh not found — auto-update hook not installed."
fi

# ---------------------------------------------------------------------------
# Summary.
# ---------------------------------------------------------------------------

cat <<EOF

────────────────────────────────────────────────────
SDD Toolkit installed.

Commands:
  sdd init       Set up the toolkit in a project
  sdd upgrade    Update to the latest version
  sdd version    Show version info
  sdd uninstall  Remove sdd CLI and shell hook
  sdd help       Show available commands

Get started:
  cd /path/to/your/project
  sdd init
────────────────────────────────────────────────────
EOF
