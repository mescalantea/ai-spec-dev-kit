#!/usr/bin/env bash
# Install a global `spec-init` command that runs scripts/setup.sh from any directory.
#
# Usage:
#   /path/to/ai-spec-dev-kit/scripts/install-global.sh
#
# The script picks an install directory on your PATH (prefers $HOME/.local/bin),
# and creates a symlink named `spec-init` pointing back at scripts/setup.sh.
# Safe to re-run — it will replace the symlink if it already points elsewhere.
#
# Compatible with macOS default bash (3.2) and Linux.

set -eu

COMMAND_NAME="spec-init"

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
SETUP_SCRIPT="$SCRIPT_DIR/setup.sh"

if [ ! -f "$SETUP_SCRIPT" ]; then
  echo "Error: cannot find $SETUP_SCRIPT" >&2
  exit 1
fi

chmod +x "$SETUP_SCRIPT"

# Pick an install directory already on PATH.
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

if [ -e "$LINK_PATH" ] || [ -L "$LINK_PATH" ]; then
  rm -f "$LINK_PATH"
fi

ln -s "$SETUP_SCRIPT" "$LINK_PATH"

echo "Installed: $LINK_PATH -> $SETUP_SCRIPT"
echo
echo "Now you can run '$COMMAND_NAME' from any project root."
