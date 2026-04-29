#!/usr/bin/env bash
# sdd-publish.sh — push a local spec to its configured external source.
#
# Usage:
#   sdd publish <spec_id>
#
# Reads .sdd/config.json's `source` field and dispatches:
#   local    -> no-op (prints hint, exits 0)
#   jira     -> markdown -> Jira wiki conversion + acli push (positional ref; fixes #21)
#   youtrack -> stub (not implemented)
#
# Errors print verbatim. AI is only invoked if the user asks it to interpret a failure.
# Compatible with macOS default bash (3.2) and Linux. Requires python3.

set -eu

SPEC_ID="${1:-}"
if [ -z "$SPEC_ID" ]; then
  echo "Usage: sdd publish <spec_id>" >&2
  exit 1
fi

PROJECT_ROOT="$(pwd)"
SPEC_FILE="$PROJECT_ROOT/.sdd/specs/$SPEC_ID.md"
CONFIG_FILE="$PROJECT_ROOT/.sdd/config.json"
CACHE_DIR="$PROJECT_ROOT/.sdd/specs/.cache"

if [ ! -f "$SPEC_FILE" ]; then
  echo "Error: spec not found: $SPEC_FILE" >&2
  exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: config not found: $CONFIG_FILE" >&2
  echo "       run 'sdd init' first." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 is required (config parsing + markdown conversion)." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Read source from config.
# ---------------------------------------------------------------------------

SOURCE="$(python3 -c "
import json, sys
try:
    with open('$CONFIG_FILE') as f:
        cfg = json.load(f)
    print(cfg.get('source') or 'local')
except Exception:
    print('local')
")"

# ---------------------------------------------------------------------------
# Extract spec body: strip YAML frontmatter and the first '# Spec: …' heading.
# Output goes to stdout.
# ---------------------------------------------------------------------------

extract_body() {
  python3 - "$1" <<'PY'
import sys, re
path = sys.argv[1]
with open(path) as f:
    text = f.read()
# Strip frontmatter (between first two '---' lines).
lines = text.splitlines()
i = 0
if lines and lines[0].strip() == '---':
    j = 1
    while j < len(lines) and lines[j].strip() != '---':
        j += 1
    if j < len(lines):
        i = j + 1
body = '\n'.join(lines[i:])
# Strip leading blank lines and the first '# Spec: …' heading if present.
body = re.sub(r'\A\s*# Spec:[^\n]*\n', '', body)
sys.stdout.write(body)
PY
}

# ---------------------------------------------------------------------------
# Markdown -> Jira wiki conversion (python3).
# Reads markdown on stdin, writes wiki markup on stdout.
# Conversion table tracked in CLAUDE.md.
# ---------------------------------------------------------------------------

md_to_jira() {
  python3 <<'PY'
import sys, re

text = sys.stdin.read()
lines = text.splitlines()
out = []

in_code = False
in_quote = False

i = 0
while i < len(lines):
    line = lines[i]

    # Fenced code blocks: passthrough verbatim, wrap with {code[:lang]}/{code}.
    m = re.match(r'^(\s*)```([A-Za-z0-9_+-]*)\s*$', line)
    if m and not in_code:
        if in_quote:
            out.append('{quote}')
            in_quote = False
        lang = m.group(2)
        out.append('{code:' + lang + '}' if lang else '{code}')
        in_code = True
        i += 1
        continue
    if in_code:
        if re.match(r'^\s*```\s*$', line):
            out.append('{code}')
            in_code = False
        else:
            out.append(line)
        i += 1
        continue

    # Blockquote folding.
    if re.match(r'^> ?', line):
        if not in_quote:
            out.append('{quote}')
            in_quote = True
        out.append(re.sub(r'^> ?', '', line))
        i += 1
        continue
    if in_quote:
        out.append('{quote}')
        in_quote = False

    # Headings (longest first).
    line = re.sub(r'^#### (.*)$', r'h4. \1', line)
    line = re.sub(r'^### (.*)$', r'h3. \1', line)
    line = re.sub(r'^## (.*)$', r'h2. \1', line)
    line = re.sub(r'^# (.*)$', r'h1. \1', line)

    # Horizontal rule (standalone line of `---`).
    if re.match(r'^---\s*$', line):
        out.append('----')
        i += 1
        continue

    # Task list (before unordered list).
    line = re.sub(r'^(\s*)- \[ \] ', r'\1[] ', line)
    line = re.sub(r'^(\s*)- \[x\] ', r'\1[x] ', line)

    # Nested unordered list (2-space indent).
    line = re.sub(r'^  - ', '** ', line)
    # Top-level unordered list.
    line = re.sub(r'^- ', '* ', line)

    # Ordered list.
    line = re.sub(r'^\d+\. ', '# ', line)

    # Inline code (before bold/italic so backtick contents are protected).
    line = re.sub(r'`([^`]+)`', r'{{\1}}', line)

    # Bold then italic (sentinel-protect bold so italic doesn't reopen it).
    line = re.sub(r'\*\*([^*]+)\*\*', r'@@BOLD_O@@\1@@BOLD_C@@', line)
    line = re.sub(r'(?<![*\w])\*([^*\n]+)\*(?!\w)', r'_\1_', line)
    line = line.replace('@@BOLD_O@@', '*').replace('@@BOLD_C@@', '*')

    # Strikethrough.
    line = re.sub(r'~~([^~]+)~~', r'-\1-', line)

    # Links.
    line = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', r'[\1|\2]', line)

    out.append(line)
    i += 1

if in_quote:
    out.append('{quote}')

sys.stdout.write('\n'.join(out))
if text.endswith('\n'):
    sys.stdout.write('\n')
PY
}

# ---------------------------------------------------------------------------
# Source dispatch.
# ---------------------------------------------------------------------------

case "$SOURCE" in
  local)
    echo "no remote source configured — edit .sdd/config.json sources.jira (or sources.youtrack)"
    exit 0
    ;;

  jira)
    if ! command -v acli >/dev/null 2>&1; then
      echo "Error: 'acli' is not on PATH." >&2
      echo "       install it and run 'acli auth login' before publishing to Jira." >&2
      exit 1
    fi

    REF="$SPEC_ID"
    CACHE_FILE="$CACHE_DIR/$REF.jira.md"
    mkdir -p "$CACHE_DIR"

    BODY_MD="$(extract_body "$SPEC_FILE")"

    # Drift detection: compare current remote against last-known cache.
    if [ -f "$CACHE_FILE" ]; then
      remote_json="$(acli jira workitem view "$REF" --json 2>/dev/null || true)"
      if [ -n "$remote_json" ]; then
        remote_desc="$(printf '%s' "$remote_json" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
print(d.get('description') or d.get('fields', {}).get('description') or '')
" 2>/dev/null || true)"
        cached="$(cat "$CACHE_FILE" 2>/dev/null || true)"
        if [ -n "$remote_desc" ] && [ "$remote_desc" != "$cached" ]; then
          echo "──────────────────────────────────────"
          echo "Drift detected on $REF — remote has changed since last sync."
          echo "──────────────────────────────────────"
          diff -u <(printf '%s\n' "$cached") <(printf '%s\n' "$remote_desc") || true
          echo "──────────────────────────────────────"
          printf 'Type "continue" to overwrite remote with local body, anything else to abort: '
          read -r answer < /dev/tty || answer=""
          if [ "$answer" != "continue" ]; then
            echo "Aborted."
            exit 1
          fi
        fi
      fi
    fi

    TMP_FILE="$(mktemp)"
    trap 'rm -f "$TMP_FILE"' EXIT
    printf '%s' "$BODY_MD" | md_to_jira > "$TMP_FILE"

    # Positional ref, no --key. Fixes issue #21 (acli flag was renamed upstream).
    if ! acli jira workitem edit "$REF" --description-file="$TMP_FILE"; then
      echo "Error: acli push failed for $REF." >&2
      acli --version 2>/dev/null || true
      exit 1
    fi

    # Cache the pre-conversion markdown so future drift diffs stay consistent.
    printf '%s' "$BODY_MD" > "$CACHE_FILE"

    echo "Published $REF to Jira."
    ;;

  youtrack)
    echo "Error: youtrack publish is not implemented yet." >&2
    echo "       implement md_to_youtrack + REST push when needed." >&2
    exit 1
    ;;

  *)
    echo "Error: unknown source '$SOURCE' in .sdd/config.json" >&2
    exit 1
    ;;
esac
