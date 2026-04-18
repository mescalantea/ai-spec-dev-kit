#!/usr/bin/env bash
# check-update.sh — checks for ai-spec-dev-kit updates on terminal open.
# Silent on all failures; must not block shell startup.

SCRIPT_PATH="$0"
while [ -L "$SCRIPT_PATH" ]; do
  link=$(readlink "$SCRIPT_PATH")
  case "$link" in
    /*) SCRIPT_PATH="$link" ;;
    *)  SCRIPT_PATH="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)/$link" ;;
  esac
done
REPO_ROOT="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"

COOLDOWN_FILE="$HOME/.sdd/.last_update_check"
COOLDOWN_SECONDS=86400

_check_update() {
  # Cooldown: skip if checked within 24 hours
  if [ -f "$COOLDOWN_FILE" ]; then
    last=$(cat "$COOLDOWN_FILE" 2>/dev/null) || return 0
    now=$(date +%s 2>/dev/null) || return 0
    elapsed=$((now - last))
    if [ "$elapsed" -lt "$COOLDOWN_SECONDS" ]; then
      return 0
    fi
  fi

  # Must be a git repo with a valid HEAD
  git -C "$REPO_ROOT" rev-parse HEAD >/dev/null 2>&1 || return 0

  # Only run for GitHub remotes (HTTPS or SSH)
  remote_url=$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null) || return 0
  case "$remote_url" in
    https://github.com/*|git@github.com:*) ;;
    *) return 0 ;;
  esac

  # Fetch remote HEAD SHA in background with a 5-second timeout
  tmp_sha=$(mktemp 2>/dev/null) || return 0
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
    return 0
  fi
  wait "$fetch_pid" 2>/dev/null || true

  remote_sha=$(cat "$tmp_sha" 2>/dev/null) || true
  rm -f "$tmp_sha"
  [ -n "$remote_sha" ] || return 0

  local_sha=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null) || return 0
  [ -n "$local_sha" ] || return 0

  # Record the check time regardless of update availability
  mkdir -p "$HOME/.sdd" 2>/dev/null || true
  date +%s > "$COOLDOWN_FILE" 2>/dev/null || true

  # No update available
  [ "$local_sha" != "$remote_sha" ] || return 0

  local_short="${local_sha:0:7}"
  remote_short="${remote_sha:0:7}"

  printf '\nai-spec-dev-kit update available: %s -> %s\n' "$local_short" "$remote_short"
  printf 'Type "update" to apply, or press Enter to skip: '
  read -r answer < /dev/tty || return 0

  [ "$answer" = "update" ] || return 0

  if git -C "$REPO_ROOT" pull 2>&1; then
    new_sha=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null) || true
    printf 'Updated to %s.\n' "${new_sha:0:7}"
  else
    printf 'Update failed. Try: git -C "%s" pull\n' "$REPO_ROOT"
  fi
}

_check_update || true
