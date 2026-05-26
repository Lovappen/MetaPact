#!/bin/bash
# Safe memory writer for Nako workspaces.
# Appends raw daily notes and updates MEMORY.md without replacing unrelated sections.

set -euo pipefail

WORKSPACE="${OPENCLAW_AGENT_WORKSPACE:-$(cd "$(dirname "$0")/.." && pwd)}"
MEMORY_FILE="$WORKSPACE/MEMORY.md"
DAILY_DIR="$WORKSPACE/memory"

usage() {
  cat >&2 <<'EOF'
Usage:
  memory-write.sh --category <kind> --summary <text> [--long <text>] [--affinity <0-100> | --affinity-delta <-100..100>]
  echo "<text>" | memory-write.sh --category <kind>

Categories:
  explicit, preference, fact, decision, lesson, task-state, relationship

Writes:
  - memory/YYYY-MM-DD.md as raw daily notes
  - MEMORY.md short-term memory, keeping the newest 5 entries
  - optional affinity value and stage
EOF
}

SUMMARY=""
LONG_NOTE=""
CATEGORY=""
AFFINITY=""
AFFINITY_DELTA=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --summary|-s)
      shift
      [ "$#" -gt 0 ] || { usage; exit 2; }
      SUMMARY="$1"
      ;;
    --category|-c)
      shift
      [ "$#" -gt 0 ] || { usage; exit 2; }
      CATEGORY="$1"
      ;;
    --long|-l)
      shift
      [ "$#" -gt 0 ] || { usage; exit 2; }
      LONG_NOTE="$1"
      ;;
    --affinity)
      shift
      [ "$#" -gt 0 ] || { usage; exit 2; }
      AFFINITY="$1"
      ;;
    --affinity-delta)
      shift
      [ "$#" -gt 0 ] || { usage; exit 2; }
      AFFINITY_DELTA="$1"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      if [ -z "$SUMMARY" ]; then
        SUMMARY="$1"
      else
        usage
        exit 2
      fi
      ;;
  esac
  shift
done

if [ -z "$SUMMARY" ] && ! [ -t 0 ]; then
  SUMMARY="$(cat)"
fi
SUMMARY="$(printf '%s' "${SUMMARY:-}" | sed 's/[[:space:]]*$//')"
[ -n "$SUMMARY" ] || { echo "memory-write: --summary is required" >&2; exit 2; }
[ -n "$CATEGORY" ] || { echo "memory-write: --category is required" >&2; exit 2; }

if [ -n "$AFFINITY" ] && [ -n "$AFFINITY_DELTA" ]; then
  echo "memory-write: use either --affinity or --affinity-delta, not both" >&2
  exit 2
fi

mkdir -p "$DAILY_DIR"

WORKSPACE="$WORKSPACE" \
MEMORY_FILE="$MEMORY_FILE" \
DAILY_DIR="$DAILY_DIR" \
SUMMARY="$SUMMARY" \
LONG_NOTE="$LONG_NOTE" \
CATEGORY="$CATEGORY" \
AFFINITY="$AFFINITY" \
AFFINITY_DELTA="$AFFINITY_DELTA" \
python3 <<'PY'
import os
import re
import sys
from datetime import datetime
from pathlib import Path

workspace = Path(os.environ["WORKSPACE"])
memory_file = Path(os.environ["MEMORY_FILE"])
daily_dir = Path(os.environ["DAILY_DIR"])
summary = os.environ.get("SUMMARY", "")
long_note = os.environ.get("LONG_NOTE", "")
category = os.environ.get("CATEGORY", "").strip()
affinity_raw = os.environ.get("AFFINITY", "")
affinity_delta_raw = os.environ.get("AFFINITY_DELTA", "")

now = datetime.now().astimezone()
date_key = now.strftime("%Y-%m-%d")
time_key = now.strftime("%Y-%m-%d %H:%M")

def one_line(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip()

summary_line = one_line(summary)
long_line = one_line(long_note)

allowed_categories = {
    "explicit",
    "preference",
    "fact",
    "decision",
    "lesson",
    "task-state",
    "relationship",
}
if category not in allowed_categories:
    allowed = ", ".join(sorted(allowed_categories))
    raise SystemExit(f"memory-write: --category must be one of: {allowed}")

if len(summary_line) > 180:
    raise SystemExit("memory-write: --summary must be 180 characters or less")
if len(long_line) > 500:
    raise SystemExit("memory-write: --long must be 500 characters or less")

def clamp(value: int) -> int:
    return max(0, min(100, value))

def stage_for(value: int) -> tuple[int, str]:
    if value >= 85:
        return 4, "陷入热恋阶段"
    if value >= 60:
        return 3, "感情亲密阶段 / 男女朋友"
    if value >= 30:
        return 2, "互有好感阶段"
    return 1, "初识阶段"

def parse_int(name: str, value: str) -> int:
    try:
        return int(value, 10)
    except ValueError:
        raise SystemExit(f"memory-write: {name} must be an integer")

def default_memory() -> str:
    return """# MEMORY - 野木奈子 记忆档案

**当前好感阶段**：1（初识阶段）
**好感值**：0/100
**最后互动时间**：—

## 短期记忆（最近 5 条）

> 每次对话结束后追加。保持简洁真实。

1.
2.
3.
4.
5.

## 长期记忆（关键事件）

- 初次相遇：—
"""

try:
    text = memory_file.read_text(encoding="utf-8")
except FileNotFoundError:
    text = default_memory()

current_match = re.search(r"\*\*好感值\*\*：\s*(\d+)\s*/\s*100", text)
current_affinity = int(current_match.group(1)) if current_match else 0
new_affinity = None
if affinity_raw:
    new_affinity = clamp(parse_int("--affinity", affinity_raw))
elif affinity_delta_raw:
    new_affinity = clamp(current_affinity + parse_int("--affinity-delta", affinity_delta_raw))

daily_file = daily_dir / f"{date_key}.md"
if daily_file.exists():
    daily_text = daily_file.read_text(encoding="utf-8")
else:
    daily_text = f"# {date_key}\n"

daily_parts = [daily_text.rstrip(), "", f"## {time_key}", f"- [{category}] {summary_line}"]
if long_line:
    daily_parts.append(f"- [{category}] 长期候选：{long_line}")
if new_affinity is not None:
    stage_num, stage_name = stage_for(new_affinity)
    daily_parts.append(f"- 好感值：{new_affinity}/100（阶段{stage_num}，{stage_name}）")
daily_file.write_text("\n".join(daily_parts).rstrip() + "\n", encoding="utf-8")

def ensure_line(pattern: str, replacement: str, source: str) -> str:
    if re.search(pattern, source, flags=re.MULTILINE):
        return re.sub(pattern, replacement, source, count=1, flags=re.MULTILINE)
    lines = source.splitlines()
    insert_at = 1 if lines and lines[0].startswith("# ") else 0
    lines.insert(insert_at, replacement)
    return "\n".join(lines).rstrip() + "\n"

text = ensure_line(r"^\*\*最后互动时间\*\*：.*$", f"**最后互动时间**：{time_key}", text)
if new_affinity is not None:
    stage_num, stage_name = stage_for(new_affinity)
    text = ensure_line(r"^\*\*当前好感阶段\*\*：.*$", f"**当前好感阶段**：{stage_num}（{stage_name}）", text)
    text = ensure_line(r"^\*\*好感值\*\*：.*$", f"**好感值**：{new_affinity}/100", text)

short_header = "## 短期记忆（最近 5 条）"
long_header = "## 长期记忆"
short_pattern = re.compile(rf"({re.escape(short_header)}\n)(.*?)(\n{re.escape(long_header)})", re.S)
short_match = short_pattern.search(text)
if short_match:
    old_body = short_match.group(2)
    existing = []
    for line in old_body.splitlines():
        match = re.match(r"\s*\d+\.\s+(.+?)\s*$", line)
        if match:
            value = match.group(1).strip()
            if value and value != ".":
                existing.append(value)
    new_item = f"{time_key} [{category}] - {summary_line}"
    existing = [item for item in existing if not item.endswith(f" - {summary_line}") and item != summary_line]
    items = [new_item] + existing
    items = items[:5]
    rendered = "> 每次对话结束后追加。保持简洁真实。\n\n" + "\n".join(
        f"{idx}. {item}" for idx, item in enumerate(items, 1)
    )
    text = text[:short_match.start(2)] + rendered + text[short_match.end(2):]
else:
    block = (
        f"\n{short_header}\n\n"
        "> 每次对话结束后追加。保持简洁真实。\n\n"
        f"1. {time_key} - {summary_line}\n"
    )
    marker = "\n## 长期记忆"
    if marker in text:
        text = text.replace(marker, block + marker, 1)
    else:
        text = text.rstrip() + block

if long_line:
    long_pattern = re.compile(r"(## 长期记忆（关键事件）\n)(.*?)(\n## |\Z)", re.S)
    long_match = long_pattern.search(text)
    long_item = f"- {date_key} [{category}]：{long_line}"
    if long_match:
        body = long_match.group(2).rstrip()
        body = (body + "\n" + long_item).strip() + "\n"
        text = text[:long_match.start(2)] + body + text[long_match.end(2):]
    else:
        text = text.rstrip() + f"\n\n## 长期记忆（关键事件）\n\n{long_item}\n"

memory_file.parent.mkdir(parents=True, exist_ok=True)
memory_file.write_text(text.rstrip() + "\n", encoding="utf-8")
print(f"memory-write: updated {memory_file.relative_to(workspace)} and memory/{date_key}.md")
PY
