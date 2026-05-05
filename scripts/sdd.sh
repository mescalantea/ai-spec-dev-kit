#!/usr/bin/env bash
# sdd — CLI facade for the Spec-Driven Development Toolkit.
#
# Usage:
#   sdd <command> [options]
#
# Commands:
#   init      Initialize or re-initialize the SDD toolkit in the current project
#   upgrade   Update the toolkit to the latest version
#   version   Show installed and latest available versions
#   publish   Push a local spec to its configured external source
#   uninstall Remove the sdd CLI and shell hook
#   help      Show this help message
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

VERSION_FILE="$REPO_ROOT/.sdd_version"

# ---------------------------------------------------------------------------
# Helpers.
# ---------------------------------------------------------------------------

get_local_sha() {
  git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo "unknown"
}

get_remote_sha() {
  tmp_sha=$(mktemp 2>/dev/null) || { echo "unknown"; return; }
  (git -C "$REPO_ROOT" ls-remote origin HEAD 2>/dev/null | awk '{print $1}' > "$tmp_sha") &
  fetch_pid=$!

  i=0
  while [ $i -lt 5 ]; do
    sleep 1
    kill -0 "$fetch_pid" 2>/dev/null || break
    i=$((i + 1))
  done

  if kill -0 "$fetch_pid" 2>/dev/null; then
    kill "$fetch_pid" 2>/dev/null || true
    rm -f "$tmp_sha"
    echo "unknown"
    return
  fi
  wait "$fetch_pid" 2>/dev/null || true

  sha=$(cat "$tmp_sha" 2>/dev/null) || true
  rm -f "$tmp_sha"
  if [ -n "$sha" ]; then
    echo "$sha"
  else
    echo "unknown"
  fi
}

short_sha() {
  sha="$1"
  if [ "$sha" = "unknown" ]; then
    echo "unknown"
  else
    echo "${sha:0:7}"
  fi
}

# ---------------------------------------------------------------------------
# Commands.
# ---------------------------------------------------------------------------

cmd_help() {
  cat <<'EOF'
sdd — Spec-Driven Development Toolkit CLI

Usage:
  sdd <command> [options]

Commands:
  init             Initialize or re-initialize the SDD toolkit in the current project
  upgrade          Update the toolkit to the latest version
  version          Show installed and latest available versions
  publish <id>     Push a local spec to its configured external source
  uninstall        Remove the sdd CLI and shell hook
  help             Show this help message

Run 'sdd init' from your project root to set up the spec commands and configuration.
Run 'sdd upgrade' to pull the latest toolkit changes from the remote repository.
Run 'sdd publish <spec_id>' from a project to sync that spec to Jira/YouTrack.
EOF
}

cmd_version() {
  local_sha="$(get_local_sha)"
  printf 'Installed: %s\n' "$(short_sha "$local_sha")"

  printf 'Checking latest version...\r'
  remote_sha="$(get_remote_sha)"
  # Clear the "Checking..." line.
  printf '                              \r'

  if [ "$remote_sha" = "unknown" ]; then
    printf 'Latest:    (could not reach remote)\n'
  else
    printf 'Latest:    %s\n' "$(short_sha "$remote_sha")"
    if [ "$local_sha" = "$remote_sha" ]; then
      echo "Up to date."
    else
      echo "Update available. Run 'sdd upgrade' to update."
    fi
  fi
}

cmd_upgrade() {
  echo "Checking for updates..."

  local_sha="$(get_local_sha)"
  remote_sha="$(get_remote_sha)"

  if [ "$remote_sha" = "unknown" ]; then
    echo "Error: could not reach remote. Check your network connection." >&2
    exit 1
  fi

  if [ "$local_sha" = "$remote_sha" ]; then
    echo "Already up to date ($(short_sha "$local_sha"))."
    return
  fi

  printf 'Updating %s -> %s ...\n' "$(short_sha "$local_sha")" "$(short_sha "$remote_sha")"

  if git -C "$REPO_ROOT" pull 2>&1; then
    new_sha="$(get_local_sha)"
    printf 'Updated to %s.\n' "$(short_sha "$new_sha")"
    echo
    echo "Re-run 'sdd init' in each project that uses the SDD toolkit to apply the changes."
  else
    echo "Update failed. Try manually: git -C \"$REPO_ROOT\" pull" >&2
    exit 1
  fi
}

cmd_init() {
  exec "$SCRIPT_DIR/setup.sh" "$@"
}

cmd_uninstall() {
  exec "$SCRIPT_DIR/uninstall.sh"
}

cmd_publish() {
  exec "$SCRIPT_DIR/sdd-publish.sh" "$@"
}

# ---------------------------------------------------------------------------
# Dispatch.
# ---------------------------------------------------------------------------

COMMAND="${1:-help}"

case "$COMMAND" in
  init)
    shift
    cmd_init "$@"
    ;;
  upgrade)
    cmd_upgrade
    ;;
  version)
    cmd_version
    ;;
  uninstall)
    cmd_uninstall
    ;;
  publish)
    shift
    cmd_publish "$@"
    ;;
  help|--help|-h)
    cmd_help
    ;;
  *)
    echo "Error: unknown command '$COMMAND'" >&2
    echo >&2
    cmd_help >&2
    exit 1
    ;;
esac
