#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/.qclaw/skills"
cat > "$tmp/.qclaw/skills/skill-log.sh" <<'EOF'
: "${SKILL_LOG_MARKER:?}"
printf 'sourced\n' >> "$SKILL_LOG_MARKER"
skill_log_start() { :; }
skill_log_ok() { :; }
skill_log_fail() { :; }
EOF

scripts=(
  "selfie/scripts/selfie.sh"
  "selfie/scripts/video.sh"
  "voice/scripts/voice.sh"
  "voice/scripts/sing.sh"
  "hearing/scripts/stt.sh"
)

for rel in "${scripts[@]}"; do
  mkdir -p "$tmp/.qclaw/skills/$(dirname "$rel")"
  cp "$ROOT/nako/skills/$rel" "$tmp/.qclaw/skills/$rel"
done

for rel in "${scripts[@]}"; do
  marker="$tmp/${rel//\//_}.marker"
  : > "$marker"
  env -i HOME="$tmp" PATH="${PATH:-/usr/bin:/bin}" SKILL_LOG_MARKER="$marker" SKILL_LOG_SH="$tmp/missing-skill-log.sh" \
    bash "$tmp/.qclaw/skills/$rel" >/dev/null 2>&1 || true
  grep -Fq 'sourced' "$marker"
done

mkdir -p "$tmp/.qclaw/workspace-agent-nako"
for rel in "selfie/scripts/selfie.sh" "selfie/scripts/video.sh" "voice/scripts/voice.sh" "voice/scripts/sing.sh"; do
  funcs="$(
    awk '
      /^_infer_ccconnect_project\(\) \{/ { capture=1 }
      capture && /^_ccconnect_session_files\(\) \{/ { exit }
      capture { print }
    ' "$tmp/.qclaw/skills/$rel"
  )"
  project="$(
    cd "$tmp/.qclaw/workspace-agent-nako"
    eval "$funcs"
    _infer_ccconnect_project
  )"
  test "$project" = "agent-nako"
done

mkdir -p "$tmp/.cc-connect/sessions"
cat > "$tmp/.cc-connect/sessions/agent-nako_main.json" <<'EOF'
{
  "active_session": {
    "weixin:wx-room": "w1",
    "feishu:oc_chat_123:ou_user_456": "f1"
  },
  "sessions": {
    "w1": {"updated_at": "2026-05-08T10:00:00+08:00"},
    "f1": {"updated_at": "2026-05-08T11:00:00+08:00"}
  }
}
EOF

for rel in "selfie/scripts/selfie.sh" "selfie/scripts/video.sh"; do
  funcs="$(
    awk '
      /^_infer_ccconnect_project\(\) \{/ { capture=1 }
      capture && /^_feishu_cc_credentials\(\) \{/ { exit }
      capture { print }
    ' "$tmp/.qclaw/skills/$rel"
  )"
  session="$(
    cd "$tmp/.qclaw/workspace-agent-nako"
    HOME="$tmp"
    CC_CONNECT_SESSION_DIR="$tmp/.cc-connect/sessions"
    export HOME CC_CONNECT_SESSION_DIR
    eval "$funcs"
    _infer_ccconnect_session agent-nako
  )"
  test "$session" = "feishu:oc_chat_123:ou_user_456"

  receive="$(
    cd "$tmp/.qclaw/workspace-agent-nako"
    HOME="$tmp"
    CHANNEL=""
    CC_CONNECT_SESSION_DIR="$tmp/.cc-connect/sessions"
    export HOME CHANNEL CC_CONNECT_SESSION_DIR
    eval "$funcs"
    _infer_feishu_receive
  )"
  test "$receive" = $'chat_id\toc_chat_123'
done

echo "skill-log path checks passed"
