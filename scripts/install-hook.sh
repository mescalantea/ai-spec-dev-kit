#!/usr/bin/env bash
# install-hook.sh — injects the ai-spec-dev-kit auto-update hook into your shell profile.
#
# Usage:
#   /path/to/ai-spec-dev-kit/scripts/install-hook.sh
#
# Detects your shell from $SHELL, resolves the profile (~/.zshrc or ~/.bash_profile),
# and appends a one-line hook that runs check-update.sh on each new terminal session.
# Safe to re-run — the hook line is injected only once (idempotent).
#
# Compatible with macOS default bash (3.2) and Linux.

set -eu

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
CHECK_SCRIPT="$REPO_ROOT/scripts/check-update.sh"

if [ ! -f "$CHECK_SCRIPT" ]; then
  echo "Error: cannot find $CHECK_SCRIPT" >&2
  exit 1
fi

chmod +x "$CHECK_SCRIPT"

# Detect shell profile.
case "$SHELL" in
  */zsh)  PROFILE="$HOME/.zshrc" ;;
  */bash) PROFILE="$HOME/.bash_profile" ;;
  *)      PROFILE="$HOME/.zshrc" ;;
esac

HOOK_LINE="[ -x \"$CHECK_SCRIPT\" ] && \"$CHECK_SCRIPT\""

# Check if already installed.
if [ -f "$PROFILE" ] && grep -Fxq "$HOOK_LINE" "$PROFILE"; then
  echo "Hook already present in $PROFILE — nothing to do."
  exit 0
fi

# Inject the hook line.
if [ -w "$PROFILE" ] || [ ! -e "$PROFILE" ]; then
  # Guard: ensure trailing newline before appending.
  if [ -s "$PROFILE" ] && [ "$(tail -c 1 "$PROFILE" | wc -l)" -eq 0 ]; then
    printf '\n' >> "$PROFILE"
  fi
  printf '%s\n' "$HOOK_LINE" >> "$PROFILE"
  echo "Installed update check hook in $PROFILE"
  echo
  echo "Open a new terminal session (or run: source $PROFILE) to activate."
else
  echo "Cannot write to $PROFILE — add this line manually:"
  echo
  echo "  $HOOK_LINE"
fi
