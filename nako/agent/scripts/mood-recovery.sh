#!/bin/bash
# 奈子的情绪恢复 - 用户发消息时调用
# 情绪值恢复 20-40，上限 100

WORKSPACE="${OPENCLAW_AGENT_WORKSPACE:-$(cd "$(dirname "$0")/.." && pwd)}"
STATE_FILE="$WORKSPACE/memory/heartbeat-state.json"
mkdir -p "$(dirname "$STATE_FILE")"
TIMESTAMP=$(date -Iseconds)

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
  STATE_FILE="$STATE_FILE" \
  TIMESTAMP="$TIMESTAMP" \
  NEW_VALUE="$NEW_VALUE" \
  LAST_TRIGGER="$LAST_TRIGGER" \
  TRIGGER_COUNT="$TRIGGER_COUNT" \
  NEW_MOOD="$NEW_MOOD" \
  MOOD_VALUE="$MOOD_VALUE" \
  MOOD_RECOVERY="$MOOD_RECOVERY" \
  MOOD_TIER="$MOOD_TIER" \
  CURRENT_VALUE="$CURRENT_VALUE" \
  NOTES="主人大人来啦！思念值清零，情绪值回血 $MOOD_RECOVERY 到 $NEW_MOOD ($MOOD_TIER) ❤️" \
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

function jsonEnv(name, fallback) {
  const raw = process.env[name];
  if (raw == null || raw === "") return fallback;
  try {
    return JSON.parse(raw);
  } catch (_) {
    return fallback;
  }
}

const state = readExistingState();

state.current_value = numberEnv("NEW_VALUE", 0);
state.last_update = process.env.TIMESTAMP;
state.last_trigger = jsonEnv("LAST_TRIGGER", null);
state.trigger_count = numberEnv("TRIGGER_COUNT", 0);
state.mood_value = numberEnv("NEW_MOOD", 100);
state.mood_log = {
  mood_before: numberEnv("MOOD_VALUE", 100),
  mood_decay: null,
  mood_recovery: numberEnv("MOOD_RECOVERY", 0),
  mood_tier: process.env.MOOD_TIER || ""
};
state.growth_log = {
  previous_value: numberEnv("CURRENT_VALUE", 0),
  reset: true
};
state.is_forbidden_time = false;
state.should_trigger = false;
state.notes = process.env.NOTES || "";

fs.mkdirSync(path.dirname(stateFile), { recursive: true });
fs.writeFileSync(stateFile, `${JSON.stringify(state, null, 2)}\n`);
NODE
}

IFS=$'\t' read -r CURRENT_VALUE LAST_TRIGGER TRIGGER_COUNT MOOD_VALUE < <(read_state)

MOOD_RECOVERY=$((RANDOM % 21 + 20))
NEW_MOOD=$((MOOD_VALUE + MOOD_RECOVERY))
[ "$NEW_MOOD" -gt 100 ] && NEW_MOOD=100
NEW_VALUE=0
MOOD_TIER=$(get_mood_tier $NEW_MOOD)

write_state

echo "情绪恢复: $MOOD_VALUE -> $NEW_MOOD (+$MOOD_RECOVERY)"
echo "思念值重置: $CURRENT_VALUE -> 0"
