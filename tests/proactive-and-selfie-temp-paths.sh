#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/proactive-selfie-temp.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

! grep -Fq '/tmp/nako-proactive-send.log' "$ROOT/nako/agent/scripts/send-active-message.sh"
! grep -Fq '/tmp/selfie_$(date +%s)' "$ROOT/nako/skills/selfie/scripts/selfie.sh"
grep -Fq 'mktemp "${TMPDIR:-/tmp}/nako-proactive-send.XXXXXX"' "$ROOT/nako/agent/scripts/send-active-message.sh"
grep -Fq 'selfie_temp_file()' "$ROOT/nako/skills/selfie/scripts/selfie.sh"

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/workspace-agent-nako/scripts"
cat > "$TMP_DIR/bin/cc-connect" <<'SH'
#!/usr/bin/env bash
printf 'send failed for test\n' >&2
exit 7
SH
chmod +x "$TMP_DIR/bin/cc-connect"

set +e
PATH="$TMP_DIR/bin:$PATH" \
HOME="$TMP_DIR" \
OPENCLAW_AGENT_WORKSPACE="$TMP_DIR/workspace-agent-nako" \
TMPDIR="$TMP_DIR" \
bash "$ROOT/nako/agent/scripts/send-active-message.sh" "hello" >/dev/null 2>&1
status=$?
set -e
test "$status" -eq 1
grep -Fq 'proactive-send-failed send failed for test' "$TMP_DIR/workspace-agent-nako/memory/heartbeat-state.json.log"
! ls "$TMP_DIR"/nako-proactive-send.* >/dev/null 2>&1

echo "proactive and selfie temp path checks passed"
