#!/usr/bin/env bash
# check-update.sh — checks for SDD toolkit updates on terminal open.
# Silent on all failures; must not block shell startup.
# Compatible with macOS default bash (3.2) and Linux.

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
  # Cooldown: skip if checked within 24 hours.
  if [ -f "$COOLDOWN_FILE" ]; then
    last=$(cat "$COOLDOWN_FILE" 2>/dev/null) || return 0
    now=$(date +%s 2>/dev/null) || return 0
    elapsed=$((now - last))
    if [ "$elapsed" -lt "$COOLDOWN_SECONDS" ]; then
      # Even if we skip the remote check, still advise sdd init.
      _advise_reinit
      return 0
    fi
  fi

  # Must be a git repo with a valid HEAD.
  git -C "$REPO_ROOT" rev-parse HEAD >/dev/null 2>&1 || return 0

  # Only run for GitHub remotes (HTTPS or SSH).
  remote_url=$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null) || return 0
  case "$remote_url" in
    https://github.com/*|git@github.com:*) ;;
    *) return 0 ;;
  esac

  # Fetch remote HEAD SHA in background with a 5-second timeout.
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

  # Record the check time regardless of update availability.
  mkdir -p "$HOME/.sdd" 2>/dev/null || true
  date +%s > "$COOLDOWN_FILE" 2>/dev/null || true

  # No update available — still advise reinit if in an SDD project.
  if [ "$local_sha" = "$remote_sha" ]; then
    _advise_reinit
    return 0
  fi

  local_short="${local_sha:0:7}"
  remote_short="${remote_sha:0:7}"

  printf '\nSDD toolkit update available: %s -> %s\n' "$local_short" "$remote_short"
  printf 'Install now? [Y/n]: '
  read -r answer < /dev/tty || return 0

  case "$answer" in
    n|N|no|NO) return 0 ;;
  esac

  if git -C "$REPO_ROOT" pull 2>&1; then
    new_sha=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null) || true
    printf 'Updated to %s.\n' "${new_sha:0:7}"
    _advise_reinit
  else
    printf 'Update failed. Try: sdd upgrade\n'
  fi
}

# If the current directory contains .sdd/, advise the user to re-run sdd init.
# When .sdd/config.json carries an `sdd_version` field, compare it against the
# toolkit's current short SHA and print an explicit version mismatch line.
_advise_reinit() {
  config="$PWD/.sdd/config.json"
  if [ ! -f "$config" ]; then
    [ -d "$PWD/.sdd" ] && printf '\n  Tip: Run "sdd init" to apply toolkit updates to this project.\n'
    return 0
  fi

  if command -v python3 >/dev/null 2>&1; then
    project_sha=$(python3 -c "import json,sys
try:
    print(json.load(open('$config')).get('sdd_version') or '')
except Exception:
    pass" 2>/dev/null || echo "")
  else
    project_sha=""
  fi

  toolkit_sha=$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo "")

  if [ -n "$project_sha" ] && [ -n "$toolkit_sha" ] && [ "$project_sha" != "$toolkit_sha" ]; then
    printf '\n  [sdd] this project was initialised with %s; toolkit is at %s\n' "$project_sha" "$toolkit_sha"
    printf '  [sdd] run "sdd init" here to refresh.\n'
  elif [ -z "$project_sha" ]; then
    printf '\n  Tip: Run "sdd init" to apply toolkit updates to this project.\n'
  fi
}

_check_update || true
