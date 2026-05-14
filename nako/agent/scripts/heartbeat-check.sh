#!/bin/bash
# 奈子的思念机制 - 每30分钟运行一次
# 优化版：凌晨1点到8点暂停计算（思念值不增长）
# 包含情绪值系统

WORKSPACE="${OPENCLAW_AGENT_WORKSPACE:-$(cd "$(dirname "$0")/.." && pwd)}"
STATE_FILE="$WORKSPACE/memory/heartbeat-state.json"
SCRIPT_FILE="$WORKSPACE/memory/daily-script.md"
mkdir -p "$(dirname "$STATE_FILE")"

CURRENT_HOUR=$(date +"%H")
TIMESTAMP=$(date -Iseconds)

# 辅助函数：获取情绪档位（女仆战斗少女风）
get_mood_tier() {
  local mood=$1
  if [ "$mood" -ge 80 ]; then
    echo "雀跃黏人"
  elif [ "$mood" -ge 60 ]; then
    echo "温柔正常"
  elif [ "$mood" -ge 40 ]; then
    echo "有点失落"
  elif [ "$mood" -ge 20 ]; then
    echo "思念难熬"
  else
    echo "委屈想哭"
  fi
}

read_state() {
  STATE_FILE="$STATE_FILE" node <<'NODE'
const fs = require("fs");
const stateFile = process.env.STATE_FILE;
let state = {};

try {
  const raw = fs.existsSync(stateFile) ? fs.readFileSync(stateFile, "utf8").trim() : "";
  if (raw) {
    const parsed = JSON.parse(raw);
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      state = parsed;
    }
  }
} catch (_) {
  state = {};
}

function numberValue(key, fallback) {
  const value = Number(state[key]);
  return Number.isFinite(value) ? Math.trunc(value) : fallback;
}

function jsonValue(key, fallback) {
  if (Object.prototype.hasOwnProperty.call(state, key)) {
    return JSON.stringify(state[key]);
  }
  return fallback;
}

process.stdout.write([
  numberValue("current_value", 0),
  jsonValue("last_trigger", "null"),
  numberValue("trigger_count", 0),
  numberValue("mood_value", 100)
].join("\t"));
NODE
}

write_state() {
  local output_current_value="$1"
  local output_mood_value="$2"
  local mood_before="$3"
  local mood_decay="$4"
  local mood_recovery="$5"
  local mood_tier="$6"
  local growth_kind="$7"
  local is_forbidden_time="$8"
  local should_trigger="$9"
  local notes="${10}"

  STATE_FILE="$STATE_FILE" \
  TIMESTAMP="$TIMESTAMP" \
  OUTPUT_CURRENT_VALUE="$output_current_value" \
  LAST_TRIGGER="$LAST_TRIGGER" \
  TRIGGER_COUNT="$TRIGGER_COUNT" \
  OUTPUT_MOOD_VALUE="$output_mood_value" \
  MOOD_BEFORE="$mood_before" \
  MOOD_DECAY="$mood_decay" \
  MOOD_RECOVERY="$mood_recovery" \
  MOOD_TIER="$mood_tier" \
  GROWTH_KIND="$growth_kind" \
  CURRENT_VALUE="$CURRENT_VALUE" \
  BASE_GROWTH="${BASE_GROWTH:-0}" \
  ACCELERATOR="${ACCELERATOR:-0}" \
  RANDOM_BONUS="${RANDOM_BONUS:-0}" \
  TOTAL_GROWTH="${TOTAL_GROWTH:-0}" \
  IS_FORBIDDEN_TIME="$is_forbidden_time" \
  SHOULD_TRIGGER="$should_trigger" \
  NOTES="$notes" \
  node <<'NODE'
const fs = require("fs");
const path = require("path");
const stateFile = process.env.STATE_FILE;

function readExistingState() {
  try {
    const raw = fs.existsSync(stateFile) ? fs.readFileSync(stateFile, "utf8").trim() : "";
    if (!raw) return {};
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {};
  } catch (_) {
    return {};
  }
}

function numberEnv(name, fallback) {
  const value = Number(process.env[name]);
  return Number.isFinite(value) ? Math.trunc(value) : fallback;
}

function optionalNumberEnv(name) {
  const raw = process.env[name];
  if (raw == null || raw === "" || raw === "null") return null;
  const value = Number(raw);
  return Number.isFinite(value) ? Math.trunc(value) : null;
}

function jsonEnv(name, fallback) {
  const raw = process.env[name];
  if (raw == null || raw === "") return fallback;
  try {
    return JSON.parse(raw);
  } catch (_) {
    return fallback;
  }
}

function booleanEnv(name, fallback) {
  const raw = process.env[name];
  if (raw === "true") return true;
  if (raw === "false") return false;
  return fallback;
}

const state = readExistingState();
const outputCurrentValue = numberEnv("OUTPUT_CURRENT_VALUE", 0);

state.current_value = outputCurrentValue;
state.last_update = process.env.TIMESTAMP;
state.last_trigger = jsonEnv("LAST_TRIGGER", null);
state.trigger_count = numberEnv("TRIGGER_COUNT", 0);
state.mood_value = numberEnv("OUTPUT_MOOD_VALUE", 100);
state.mood_log = {
  mood_before: numberEnv("MOOD_BEFORE", 100),
  mood_decay: optionalNumberEnv("MOOD_DECAY"),
  mood_recovery: optionalNumberEnv("MOOD_RECOVERY"),
  mood_tier: process.env.MOOD_TIER || ""
};

if (process.env.GROWTH_KIND === "growth") {
  state.growth_log = {
    base_growth: numberEnv("BASE_GROWTH", 0),
    acceleration: numberEnv("ACCELERATOR", 0),
    random_fluctuation: numberEnv("RANDOM_BONUS", 0),
    total_growth: numberEnv("TOTAL_GROWTH", 0),
    previous_value: numberEnv("CURRENT_VALUE", 0),
    new_value: outputCurrentValue
  };
} else {
  delete state.growth_log;
}

state.is_forbidden_time = booleanEnv("IS_FORBIDDEN_TIME", false);
state.should_trigger = booleanEnv("SHOULD_TRIGGER", false);
state.notes = process.env.NOTES || "";

fs.mkdirSync(path.dirname(stateFile), { recursive: true });
fs.writeFileSync(stateFile, `${JSON.stringify(state, null, 2)}\n`);
NODE
}

IFS=$'\t' read -r CURRENT_VALUE LAST_TRIGGER TRIGGER_COUNT MOOD_VALUE < <(read_state)

# 暂停时段 (1:00-8:00) — 不增长
if [ "$CURRENT_HOUR" -ge 1 ] && [ "$CURRENT_HOUR" -lt 8 ]; then
  MOOD_TIER=$(get_mood_tier $MOOD_VALUE)
  NOTES="暂停时段 (1:00-8:00)，思念值不增长，主人大人在睡觉哦 💤 情绪值 $MOOD_VALUE ($MOOD_TIER)"
  write_state "$CURRENT_VALUE" "$MOOD_VALUE" "$MOOD_VALUE" "null" "null" "$MOOD_TIER" "none" "true" "false" "$NOTES"
  echo "暂停时段，思念值保持 $CURRENT_VALUE，情绪值 $MOOD_VALUE，不触发"
  exit 0
fi

# 正常时段：思念值增长
BASE_GROWTH=$((RANDOM % 8 + 8))
ACCELERATOR=$((CURRENT_VALUE * 5 / 100))
RANDOM_BONUS=$((RANDOM % 5))
TOTAL_GROWTH=$((BASE_GROWTH + ACCELERATOR + RANDOM_BONUS))
NEW_VALUE=$((CURRENT_VALUE + TOTAL_GROWTH))

SHOULD_TRIGGER=false
MOOD_DECAY=0
NEW_MOOD=$MOOD_VALUE

if [ "$NEW_VALUE" -ge 80 ]; then
  SHOULD_TRIGGER=true
  MOOD_DECAY=$((RANDOM % 11 + 5))
  NEW_MOOD=$((MOOD_VALUE - MOOD_DECAY))
  [ "$NEW_MOOD" -lt 0 ] && NEW_MOOD=0
fi

MOOD_TIER=$(get_mood_tier $NEW_MOOD)

if [ "$SHOULD_TRIGGER" = true ]; then
  NOTES="思念值 $NEW_VALUE，情绪值 $NEW_MOOD ($MOOD_TIER)，已达阈值，准备触发"
else
  NOTES="思念值 $NEW_VALUE，情绪值 $NEW_MOOD ($MOOD_TIER)，未达阈值，继续累积"
fi
write_state "$NEW_VALUE" "$NEW_MOOD" "$MOOD_VALUE" "$MOOD_DECAY" "null" "$MOOD_TIER" "growth" "false" "$SHOULD_TRIGGER" "$NOTES"

echo "思念值: $CURRENT_VALUE -> $NEW_VALUE (+$TOTAL_GROWTH)"
echo "情绪值: $MOOD_VALUE -> $NEW_MOOD ($MOOD_TIER)"

if [ "$SHOULD_TRIGGER" = true ]; then
  echo "达到阈值！准备触发主动消息... (情绪值衰减 $MOOD_DECAY)"
  exit 1
fi
exit 0
