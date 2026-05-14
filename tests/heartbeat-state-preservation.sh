#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/heartbeat-state-preservation.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

make_workspace() {
  local workspace="$1"
  local current_value="${2:-72}"
  mkdir -p "$workspace/memory"
  cat > "$workspace/memory/heartbeat-state.json" <<JSON
{
  "current_value": $current_value,
  "last_update": "2026-05-14T00:00:00+08:00",
  "last_trigger": "previous-trigger",
  "trigger_count": 4,
  "mood_value": 55,
  "affinity_value": 88,
  "affinity_stage": 3,
  "favorability": {
    "value": 88,
    "stage": "stage-3"
  },
  "custom_state": {
    "keep": true
  }
}
JSON
}

assert_preserved_state() {
  local state_file="$1"
  local expected_current_value="$2"
  node - "$state_file" "$expected_current_value" <<'NODE'
const fs = require("fs");
const stateFile = process.argv[2];
const expectedCurrentValue = Number(process.argv[3]);
const state = JSON.parse(fs.readFileSync(stateFile, "utf8"));

function assert(condition, message) {
  if (!condition) {
    console.error(message);
    process.exit(1);
  }
}

assert(state.current_value === expectedCurrentValue, `current_value should be ${expectedCurrentValue}`);
assert(state.last_trigger === "previous-trigger", "last_trigger string should survive state rewrite");
assert(state.trigger_count === 4, "trigger_count should survive state rewrite");
assert(state.affinity_value === 88, "affinity_value should not be reset or dropped");
assert(state.affinity_stage === 3, "affinity_stage should not be reset or dropped");
assert(state.favorability && state.favorability.value === 88, "favorability object should not be dropped");
assert(state.favorability && state.favorability.stage === "stage-3", "favorability stage should not be dropped");
assert(state.custom_state && state.custom_state.keep === true, "unknown state fields should be preserved");
NODE
}

recovery_workspace="$TMP_DIR/recovery-workspace"
make_workspace "$recovery_workspace"
OPENCLAW_AGENT_WORKSPACE="$recovery_workspace" bash "$ROOT/nako/agent/scripts/mood-recovery.sh" >/dev/null
assert_preserved_state "$recovery_workspace/memory/heartbeat-state.json" 0

heartbeat_workspace="$TMP_DIR/heartbeat-workspace"
make_workspace "$heartbeat_workspace" 20
OPENCLAW_AGENT_WORKSPACE="$heartbeat_workspace" bash "$ROOT/nako/agent/scripts/heartbeat-check.sh" >/dev/null
node - "$heartbeat_workspace/memory/heartbeat-state.json" <<'NODE'
const fs = require("fs");
const state = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
if (!Number.isInteger(state.current_value) || state.current_value < 20) {
  console.error(`heartbeat current_value should keep or increase from 20, got ${state.current_value}`);
  process.exit(1);
}
NODE
assert_preserved_state "$heartbeat_workspace/memory/heartbeat-state.json" "$(node -e 'const fs=require("fs"); console.log(JSON.parse(fs.readFileSync(process.argv[1],"utf8")).current_value)' "$heartbeat_workspace/memory/heartbeat-state.json")"

echo "heartbeat state preservation tests passed"
