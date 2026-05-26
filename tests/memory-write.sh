#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/memory-write.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

workspace="$TMP_DIR/workspace-agent-nako"
mkdir -p "$workspace"

cat > "$workspace/MEMORY.md" <<'EOF'
# MEMORY - 野木奈子 记忆档案（测试）

**当前好感阶段**：1（初识阶段）
**好感值**：0/100
**最后互动时间**：—

## 短期记忆（最近 5 条）

> 每次对话结束后追加。保持简洁真实。

1. 旧记忆 1
2. 旧记忆 2
3. 旧记忆 3
4. 旧记忆 4
5. 旧记忆 5

## 长期记忆（关键事件）

- 初次相遇：—

## 用户个人信息库

- 喜欢食物：

## 自定义保留段落

这一段不能被脚本删除。
EOF

OPENCLAW_AGENT_WORKSPACE="$workspace" \
  bash "$ROOT/nako/agent/scripts/memory-write.sh" \
  --category preference \
  --summary "用户喜欢周末听爵士乐" \
  --long "用户明确说周末会听爵士乐放松" \
  --affinity-delta 35 \
  >/dev/null

today="$(date +%F)"
test -f "$workspace/memory/$today.md"
grep -Fq "用户喜欢周末听爵士乐" "$workspace/memory/$today.md"

node - "$workspace/MEMORY.md" <<'NODE'
const fs = require("fs");
const text = fs.readFileSync(process.argv[2], "utf8");

function assert(condition, message) {
  if (!condition) {
    console.error(message);
    process.exit(1);
  }
}

assert(text.includes("**当前好感阶段**：2（互有好感阶段）"), "affinity stage should advance to stage 2");
assert(text.includes("**好感值**：35/100"), "affinity value should be updated");
assert(!text.includes("**最后互动时间**：—"), "last interaction time should be updated");
assert(text.includes("用户明确说周末会听爵士乐放松"), "long-term note should be appended");
assert(text.includes("[preference]"), "memory entries should include the category");
assert(text.includes("这一段不能被脚本删除。"), "custom sections should be preserved");

const shortMatch = text.match(/## 短期记忆（最近 5 条）\n([\s\S]*?)\n## 长期记忆/);
assert(shortMatch, "short-term memory section should exist");
const items = shortMatch[1].split("\n").filter((line) => /^\d+\.\s+\S/.test(line));
assert(items.length === 5, `short-term memory should keep exactly 5 items, got ${items.length}`);
assert(items[0].includes("用户喜欢周末听爵士乐"), "new summary should be first short-term item");
assert(!items.some((line) => line.includes("旧记忆 5")), "oldest short-term item should be trimmed");
NODE

OPENCLAW_AGENT_WORKSPACE="$workspace" \
  bash "$ROOT/nako/agent/scripts/memory-write.sh" \
  --category fact \
  --summary "第二条记忆" \
  --affinity 88 \
  >/dev/null

node - "$workspace/MEMORY.md" <<'NODE'
const fs = require("fs");
const text = fs.readFileSync(process.argv[2], "utf8");
if (!text.includes("**当前好感阶段**：4（陷入热恋阶段）")) {
  console.error("absolute affinity should advance to stage 4");
  process.exit(1);
}
if (!text.includes("**好感值**：88/100")) {
  console.error("absolute affinity should be written");
  process.exit(1);
}
if (!text.match(/1\. .*第二条记忆/)) {
  console.error("second summary should be first item after second write");
  process.exit(1);
}
NODE

if OPENCLAW_AGENT_WORKSPACE="$workspace" \
  bash "$ROOT/nako/agent/scripts/memory-write.sh" \
  --summary "没有类别的记忆" \
  >"$TMP_DIR/missing-category.out" 2>"$TMP_DIR/missing-category.err"; then
  echo "memory write without --category should fail" >&2
  exit 1
fi
grep -Fq 'memory-write: --category is required' "$TMP_DIR/missing-category.err"

if OPENCLAW_AGENT_WORKSPACE="$workspace" \
  bash "$ROOT/nako/agent/scripts/memory-write.sh" \
  --category routine \
  --summary "普通寒暄不该入库" \
  >"$TMP_DIR/invalid-category.out" 2>"$TMP_DIR/invalid-category.err"; then
  echo "memory write with invalid category should fail" >&2
  exit 1
fi
grep -Fq 'memory-write: --category must be one of' "$TMP_DIR/invalid-category.err"

long_summary="$(printf '%*s' 181 '' | tr ' ' 'x')"
if OPENCLAW_AGENT_WORKSPACE="$workspace" \
  bash "$ROOT/nako/agent/scripts/memory-write.sh" \
  --category fact \
  --summary "$long_summary" \
  >"$TMP_DIR/long-summary.out" 2>"$TMP_DIR/long-summary.err"; then
  echo "memory write with long summary should fail" >&2
  exit 1
fi
grep -Fq 'memory-write: --summary must be 180 characters or less' "$TMP_DIR/long-summary.err"

grep -Fq 'memory-write.sh' "$ROOT/nako/agent/AGENTS.md"
grep -Fq 'memory-write.sh' "$ROOT/nako/agent/TOOLS.md"
grep -Fq 'memory-write.sh' "$ROOT/nako/agent/MEMORY.md"

echo "memory write checks passed"
