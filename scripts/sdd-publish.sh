#!/usr/bin/env bash
# sdd-publish.sh — push a local spec to its configured external source.
#
# Usage:
#   sdd publish <spec_id>
#
# Reads .sdd/config.json's `source` field and dispatches:
#   local    -> no-op (prints hint, exits 0)
#   jira     -> markdown -> ADF JSON + acli push (--key form, per acli help)
#   youtrack -> stub (not implemented)
#
# Errors print verbatim. AI is only invoked if the user asks it to interpret a failure.
# Compatible with macOS default bash (3.2) and Linux.
# Requires python3 + markdown-it-py (pip3 install --user markdown-it-py).

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
# Markdown -> ADF (Atlassian Document Format) JSON.
# Reads markdown on stdin, writes a canonical ADF doc on stdout.
#
# Why ADF: Jira Cloud's description field is ADF-only. `acli --description-file`
# accepts plain text or ADF; plain text (markdown or wiki markup) renders
# verbatim because acli wraps the file content into a single ADF text node.
# Sending structured ADF JSON is the only path that renders correctly.
# ---------------------------------------------------------------------------

md_to_adf() {
  python3 <<'PY'
import sys, json, re, uuid

try:
    from markdown_it import MarkdownIt
except ImportError:
    sys.stderr.write("Error: 'markdown-it-py' is not installed.\n")
    sys.stderr.write("       run: pip3 install --user markdown-it-py\n")
    sys.exit(2)

md = MarkdownIt("commonmark", {"html": False, "breaks": False, "linkify": False, "typographer": False})
md.enable("table")
md.enable("strikethrough")

TASK_RE = re.compile(r"^\[([ xX])\]\s+")


def new_id():
    return str(uuid.uuid4())


def attr_get(token, key):
    """markdown-it Token.attrs is a dict in newer versions, list-of-pairs in older."""
    a = getattr(token, "attrs", None)
    if a is None:
        return None
    if isinstance(a, dict):
        return a.get(key)
    for k, v in a:
        if k == key:
            return v
    return None


def consume_inline(token, mark_stack=None):
    if mark_stack is None:
        mark_stack = []

    def snapshot():
        return [dict(m) for m in mark_stack]

    def pop_last(mtype):
        for j in range(len(mark_stack) - 1, -1, -1):
            if mark_stack[j].get("type") == mtype:
                mark_stack.pop(j)
                return

    nodes = []
    for child in (token.children or []):
        t = child.type
        if t == "text":
            if child.content:
                node = {"type": "text", "text": child.content}
                if mark_stack:
                    node["marks"] = snapshot()
                nodes.append(node)
        elif t == "softbreak":
            nodes.append({"type": "text", "text": " "})
        elif t == "hardbreak":
            nodes.append({"type": "hardBreak"})
        elif t == "code_inline":
            marks = snapshot() + [{"type": "code"}]
            nodes.append({"type": "text", "text": child.content, "marks": marks})
        elif t == "strong_open":
            mark_stack.append({"type": "strong"})
        elif t == "strong_close":
            pop_last("strong")
        elif t == "em_open":
            mark_stack.append({"type": "em"})
        elif t == "em_close":
            pop_last("em")
        elif t == "s_open":
            mark_stack.append({"type": "strike"})
        elif t == "s_close":
            pop_last("strike")
        elif t == "link_open":
            href = ""
            a = getattr(child, "attrs", None)
            if isinstance(a, dict):
                href = a.get("href", "") or ""
            elif a:
                for k, v in a:
                    if k == "href":
                        href = v
            mark_stack.append({"type": "link", "attrs": {"href": href}})
        elif t == "link_close":
            pop_last("link")

    # Coalesce adjacent text nodes that share identical marks.
    merged = []
    for n in nodes:
        if (n.get("type") == "text" and merged
                and merged[-1].get("type") == "text"
                and n.get("marks", []) == merged[-1].get("marks", [])):
            merged[-1]["text"] += n["text"]
        else:
            merged.append(n)
    return merged


def detect_task(item_blocks):
    """If item_blocks[0] is a paragraph whose leading text starts with [ ]/[x],
    return (state, modified_inline_content). Else None."""
    if not item_blocks or item_blocks[0].get("type") != "paragraph":
        return None
    para_content = item_blocks[0].get("content", [])
    if not para_content:
        return None

    # Reconstruct the prefix from leading mark-less text nodes.
    leading = ""
    leading_count = 0
    for n in para_content:
        if n.get("type") == "text" and not n.get("marks"):
            leading += n["text"]
            leading_count += 1
        else:
            break
    m = TASK_RE.match(leading)
    if not m:
        return None
    state = "DONE" if m.group(1).lower() == "x" else "TODO"
    new_leading = leading[m.end():]
    rest = para_content[leading_count:]
    new_content = []
    if new_leading:
        new_content.append({"type": "text", "text": new_leading})
    new_content.extend(rest)
    return state, new_content


def walk(tokens, idx, end_type=None):
    nodes = []
    while idx < len(tokens):
        tok = tokens[idx]
        if end_type and tok.type == end_type:
            return nodes, idx + 1

        tt = tok.type
        if tt == "heading_open":
            level = int(tok.tag[1])
            idx += 1
            inline_tok = tokens[idx]; idx += 1
            content = consume_inline(inline_tok)
            idx += 1  # heading_close
            node = {"type": "heading", "attrs": {"level": level}}
            if content:
                node["content"] = content
            nodes.append(node)

        elif tt == "paragraph_open":
            idx += 1
            inline_tok = tokens[idx]; idx += 1
            content = consume_inline(inline_tok)
            idx += 1  # paragraph_close
            node = {"type": "paragraph"}
            if content:
                node["content"] = content
            nodes.append(node)

        elif tt in ("bullet_list_open", "ordered_list_open"):
            is_ordered = (tt == "ordered_list_open")
            close_type = "ordered_list_close" if is_ordered else "bullet_list_close"
            order_attr = attr_get(tok, "start") if is_ordered else None
            idx += 1
            items = []
            while tokens[idx].type != close_type:
                if tokens[idx].type == "list_item_open":
                    idx += 1
                    inner, idx = walk(tokens, idx, end_type="list_item_close")
                    items.append(inner)
                else:
                    idx += 1
            idx += 1  # close

            if not is_ordered:
                task_results = [detect_task(it) for it in items]
                if items and all(r is not None for r in task_results):
                    task_items = []
                    for state, inline_content in task_results:
                        ti = {"type": "taskItem",
                              "attrs": {"localId": new_id(), "state": state}}
                        if inline_content:
                            ti["content"] = inline_content
                        task_items.append(ti)
                    nodes.append({
                        "type": "taskList",
                        "attrs": {"localId": new_id()},
                        "content": task_items
                    })
                    continue

            list_items = []
            for it in items:
                li = {"type": "listItem",
                      "content": it if it else [{"type": "paragraph"}]}
                list_items.append(li)
            list_node = {"type": "orderedList" if is_ordered else "bulletList",
                         "content": list_items}
            if is_ordered and order_attr:
                try:
                    n = int(order_attr)
                    if n != 1:
                        list_node["attrs"] = {"order": n}
                except ValueError:
                    pass
            nodes.append(list_node)

        elif tt == "fence":
            lang = (tok.info or "").strip()
            content_text = (tok.content or "").rstrip("\n")
            node = {"type": "codeBlock"}
            if lang:
                node["attrs"] = {"language": lang}
            if content_text:
                node["content"] = [{"type": "text", "text": content_text}]
            nodes.append(node)
            idx += 1

        elif tt == "code_block":
            content_text = (tok.content or "").rstrip("\n")
            node = {"type": "codeBlock"}
            if content_text:
                node["content"] = [{"type": "text", "text": content_text}]
            nodes.append(node)
            idx += 1

        elif tt == "blockquote_open":
            idx += 1
            inner, idx = walk(tokens, idx, end_type="blockquote_close")
            node = {"type": "blockquote"}
            if inner:
                node["content"] = inner
            nodes.append(node)

        elif tt == "hr":
            nodes.append({"type": "rule"})
            idx += 1

        elif tt == "table_open":
            idx += 1
            rows = []
            while tokens[idx].type != "table_close":
                section = tokens[idx].type
                if section in ("thead_open", "tbody_open"):
                    section_close = "thead_close" if section == "thead_open" else "tbody_close"
                    idx += 1
                    while tokens[idx].type != section_close:
                        if tokens[idx].type == "tr_open":
                            idx += 1
                            cells = []
                            while tokens[idx].type != "tr_close":
                                cell_tag = tokens[idx].type  # th_open or td_open
                                cell_type = "tableHeader" if cell_tag == "th_open" else "tableCell"
                                idx += 1
                                inline_tok = tokens[idx]; idx += 1
                                cell_inline = consume_inline(inline_tok)
                                idx += 1  # close
                                cell_content = ([{"type": "paragraph", "content": cell_inline}]
                                                if cell_inline else [{"type": "paragraph"}])
                                cells.append({"type": cell_type, "content": cell_content})
                            idx += 1  # tr_close
                            rows.append({"type": "tableRow", "content": cells})
                        else:
                            idx += 1
                    idx += 1  # section close
                else:
                    idx += 1
            idx += 1  # table_close
            nodes.append({
                "type": "table",
                "attrs": {"isNumberColumnEnabled": False, "layout": "default"},
                "content": rows
            })

        else:
            idx += 1
    return nodes, idx


text = sys.stdin.read()
tokens = md.parse(text)
content, _ = walk(tokens, 0)

doc = {"type": "doc", "version": 1, "content": content}
sys.stdout.write(json.dumps(doc, indent=2, sort_keys=False))
PY
}

# ---------------------------------------------------------------------------
# Canonicalize ADF JSON for drift comparison (sorted keys, compact).
# ---------------------------------------------------------------------------

canonicalize_adf() {
  python3 -c "
import json, sys
try:
    obj = json.load(sys.stdin)
except Exception:
    sys.exit(1)
print(json.dumps(obj, sort_keys=True, separators=(',', ':')))
"
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

    if ! python3 -c "import markdown_it" >/dev/null 2>&1; then
      echo "Error: 'markdown-it-py' is not installed." >&2
      echo "       run: pip3 install --user markdown-it-py" >&2
      exit 1
    fi

    REF="$SPEC_ID"
    CACHE_FILE="$CACHE_DIR/$REF.jira.json"
    mkdir -p "$CACHE_DIR"

    BODY_MD="$(extract_body "$SPEC_FILE")"
    ADF_JSON="$(printf '%s' "$BODY_MD" | md_to_adf)"

    # Drift detection: compare current remote ADF (canonicalized) against the
    # canonical form of what we last pushed. ADF is structured JSON, so a
    # textual diff would be unreadable — we just gate on equality.
    if [ -f "$CACHE_FILE" ]; then
      remote_json="$(acli jira workitem view --key "$REF" --json 2>/dev/null || true)"
      if [ -n "$remote_json" ]; then
        remote_desc_canonical="$(printf '%s' "$remote_json" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
desc = d.get('description')
if desc is None:
    desc = (d.get('fields') or {}).get('description')
if isinstance(desc, dict):
    print(json.dumps(desc, sort_keys=True, separators=(',', ':')))
elif isinstance(desc, str):
    # Plain string description — emit a single ADF text-paragraph for parity.
    print(json.dumps({'type': 'doc', 'version': 1,
                      'content': [{'type': 'paragraph',
                                   'content': [{'type': 'text', 'text': desc}]}]},
                     sort_keys=True, separators=(',', ':')))
" 2>/dev/null || true)"
        cached_canonical="$(printf '%s' "$(cat "$CACHE_FILE")" | canonicalize_adf 2>/dev/null || true)"
        if [ -n "$remote_desc_canonical" ] && [ "$remote_desc_canonical" != "$cached_canonical" ]; then
          echo "──────────────────────────────────────"
          echo "Drift detected on $REF — the Jira description has changed since the last sdd publish."
          echo "(ADF JSON diffs are not human-readable; inspect the issue in Jira directly.)"
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
    printf '%s' "$ADF_JSON" > "$TMP_FILE"

    # Use --key per the acli help: `acli jira workitem edit --key "KEY-1" ...`.
    # The `acli --version` print on failure helps spot upstream flag drift.
    if ! acli jira workitem edit --key "$REF" --description-file="$TMP_FILE"; then
      echo "Error: acli push failed for $REF." >&2
      acli --version 2>/dev/null || true
      exit 1
    fi

    # Cache the ADF JSON we pushed (pretty-printed for readability; drift
    # detection canonicalizes both sides before comparing).
    printf '%s\n' "$ADF_JSON" > "$CACHE_FILE"

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
