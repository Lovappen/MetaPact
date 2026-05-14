#!/bin/bash
# skill-log.sh — Shared structured logging for OpenClaw skills
# Source this file: source "$(dirname "$0")/../../skill-log.sh" 2>/dev/null || true
#
# Usage:
#   skill_log <skill> <action> <status> [key=value ...]
#
# Example:
#   skill_log voice tts_generate success provider=minimax voice_id=female-tianmei duration_ms=3200 channel=oc_xxx
#   skill_log selfie image_generate failure provider=fal error="API timeout"
#   skill_log selfie video_send success provider=fal video_url=https://... message_id=om_xxx channel=ou_xxx

# Log file resolves to the calling skill's own directory
# e.g. workspace/agent-nako/skills/voice/logs/skill.jsonl
# Set SKILL_LOG_FILE before sourcing to override
if [ -z "${SKILL_LOG_FILE:-}" ]; then
  # Derive from the script that sourced us: script → scripts/ → skill_dir → logs/
  _CALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[1]:-$0}")" && pwd)"
  _SKILL_DIR="$(dirname "$_CALLER_DIR")"
  SKILL_LOG_DIR="${_SKILL_DIR}/logs"
  SKILL_LOG_FILE="${SKILL_LOG_DIR}/skill.jsonl"
fi

mkdir -p "$(dirname "$SKILL_LOG_FILE")" 2>/dev/null

skill_log() {
  local skill="${1:-unknown}"
  local action="${2:-unknown}"
  local status="${3:-unknown}"  # success | failure | start | skip
  shift 3 2>/dev/null || true

  # Build JSON from remaining key=value pairs
  local extras=""
  for kv in "$@"; do
    local key="${kv%%=*}"
    local val="${kv#*=}"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    # Escape quotes in value
    val="${val//\\/\\\\}"
    val="${val//\"/\\\"}"
    val="${val//$'\n'/\\n}"
    val="${val//$'\r'/\\r}"
    val="${val//$'\t'/\\t}"
    extras="${extras},\"${key}\":\"${val}\""
  done

  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

  local agent="${OPENCLAW_AGENT:-unknown}"
  local line="{\"ts\":\"${ts}\",\"agent\":\"${agent}\",\"skill\":\"${skill}\",\"action\":\"${action}\",\"status\":\"${status}\"${extras}}"

  # Append to log file (atomic-ish via >>)
  echo "$line" >> "$SKILL_LOG_FILE" 2>/dev/null

  # Also print to stderr for script visibility
  echo -e "\033[0;90m[LOG] ${skill}/${action} ${status}\033[0m" >&2
}

# Convenience wrappers
skill_log_start()   { skill_log "$1" "$2" "start" "${@:3}"; }
skill_log_ok()      { skill_log "$1" "$2" "success" "${@:3}"; }
skill_log_fail()    { skill_log "$1" "$2" "failure" "${@:3}"; }
skill_log_skip()    { skill_log "$1" "$2" "skip" "${@:3}"; }
