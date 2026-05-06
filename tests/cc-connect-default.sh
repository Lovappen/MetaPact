#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

grep -Fq 'CC_CONNECT_SOURCE="${CC_CONNECT_SOURCE:-lazycat}"' "$ROOT/install.sh"
grep -Fq 'QClaw runtime 使用 QClaw 自带模型路由，跳过 OpenClaw provider preset' "$ROOT/install.sh"
grep -Fq 'AGENT_WORKSPACE="$QCLAW_HOME/workspace-$AGENT_ID"' "$ROOT/install.sh"
grep -Fq 'name = identity.get("name") or agent_id' "$ROOT/install.sh"
grep -Fq '[string]$CcConnectSource = "lazycat"' "$ROOT/install.ps1"
grep -Fq '[ValidateSet("openclaw","hermes","qclaw")]' "$ROOT/install.ps1"
grep -Fq '[switch]$UninstallAllCcConnect' "$ROOT/install.ps1"
grep -Fq '@("--agent-id", $AgentId, "--uninstall-all")' "$ROOT/install.ps1"
grep -Fq 'Sync-QClawRuntime' "$ROOT/install.ps1"
grep -Fq '@("--agent-id", $AgentId, "--runtime", $Runtime)' "$ROOT/install.ps1"
grep -Fq 'QClaw 主模型继承' "$ROOT/install.ps1"
grep -Fq 'name = identity.get("name") or agent_id' "$ROOT/install.ps1"
grep -Fq 'OPENCLAW_CONFIG="${OPENCLAW_CONFIG:-$OPENCLAW_HOME/openclaw.json}"' "$ROOT/nako/scripts/lib.sh"
grep -Fq 'CONFIG="${OPENCLAW_CONFIG:-$OPENCLAW_HOME/openclaw.json}"' "$ROOT/nako/scripts/detect-models.sh"
grep -Fq 'CC_CONNECT_SOURCE="${CC_CONNECT_SOURCE:-lazycat}"' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'elif [ "$CC_CONNECT_SOURCE" = "lazycat" ] || [ "$CC_CONNECT_SOURCE" = "auto" ]; then' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'CC_CONNECT_GO_DOWNLOAD_VERSION="${CC_CONNECT_GO_DOWNLOAD_VERSION:-1.25.0}"' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'https://dl.google.com/go/go${CC_CONNECT_GO_DOWNLOAD_VERSION:-1.25.0}.linux-${arch}.tar.gz' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'CodeEagle/cc-connect 安装失败；请修复网络/Go 环境后重跑' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'should_npm_fallback' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq -- '--uninstall' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq -- '--uninstall-all' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'remove_cc_connect_project' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'uninstall_cc_connect_all' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'uninstall_agent_runtime_data' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'remove_agent_from_openclaw_config' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq '.nako-agent.bak-uninstall-all-' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq '.cc-connect.bak-uninstall-all-' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'ps -eo pid=,args=' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'looks_like_cc_connect_main(args)' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'kill -9 $old_pids' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'cc-connect daemon install --work-dir "$HOME/.cc-connect" --force' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'cc-connect daemon start --work-dir "$HOME/.cc-connect"' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'nohup cc-connect </dev/null >"$HOME/.cc-connect/cc-connect.log" 2>&1 &' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'ensure_cc_connect_running "$desc onboarding 完成"' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'CC_CONNECT_CHANGED=1' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'info "$desc 已配，跳过"' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'openclaw|hermes|qclaw)' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'QCLAW_OPENCLAW_MJS' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'QCLAW_CC_SESSION_SUFFIX="${QCLAW_CC_SESSION_SUFFIX:-session-cc-connect}"' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'ensure_qclaw_cc_session' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'f"agent:{agent_id}:{qclaw_session_suffix}"' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'sync_qclaw_runtime' "$ROOT/install.sh"
grep -Fq 'f"  - name: {yaml_quote(name)}"' "$ROOT/install.sh"
! grep -Fq 'f"  {name}:"' "$ROOT/install.sh"
grep -Fq 'https://cdn.jsdelivr.net/gh/Lovappen/MetaPact@${AGENTS_REF}/install.sh' "$ROOT/scripts/nako-agent-factory/install.sh"
grep -Fq 'https://cdn.jsdelivr.net/gh/Lovappen/MetaPact@{AGENTS_REF}/install.sh' "$ROOT/scripts/nako-agent-factory/nako-server.py"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
envfile="$tmp/bash_env"
cat > "$envfile" <<'EOF'
cc-connect() { return 127; }
ps() { return 0; }
kill() { return 0; }
sudo() { return 1; }
EOF
mkdir -p "$tmp/.cc-connect" \
  "$tmp/.openclaw/workspace/agent-test" "$tmp/.openclaw/agents/agent-test" \
  "$tmp/.hermes/workspace/agent-test" "$tmp/.hermes/skills/openclaw-imports" \
  "$tmp/.qclaw" "$tmp/.qclaw-state/workspace-agent-test" "$tmp/.qclaw-state/agents/agent-test"
printf 'fake cc-connect\n' > "$tmp/cc-connect"
printf 'cc config\n' > "$tmp/.cc-connect/config.toml"
printf 'openclaw workspace\n' > "$tmp/.openclaw/workspace/agent-test/file.txt"
printf 'openclaw agent\n' > "$tmp/.openclaw/agents/agent-test/data.txt"
printf 'hermes workspace\n' > "$tmp/.hermes/workspace/agent-test/file.txt"
printf 'hermes env\n' > "$tmp/.hermes/skills/openclaw-imports/.env.agent-test"
printf 'qclaw workspace\n' > "$tmp/.qclaw-state/workspace-agent-test/file.txt"
printf 'qclaw agent\n' > "$tmp/.qclaw-state/agents/agent-test/data.txt"
python3 - "$tmp" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
(root / ".openclaw" / "openclaw.json").write_text(
    json.dumps({"agents": {"list": [{"id": "agent-test"}, {"id": "other"}]}}),
    encoding="utf-8",
)
(root / ".qclaw" / "qclaw.json").write_text(
    json.dumps({"stateDir": str(root / ".qclaw-state")}),
    encoding="utf-8",
)
(root / ".qclaw-state" / "qclaw.json").write_text(
    json.dumps({"configPath": str(root / ".qclaw-state" / "openclaw.json")}),
    encoding="utf-8",
)
(root / ".qclaw-state" / "openclaw.json").write_text(
    json.dumps({"agents": {"list": [{"id": "agent-test"}, {"id": "other"}]}}),
    encoding="utf-8",
)
PY
(
  cd "$tmp"
  HOME="$tmp" BASH_ENV="$envfile" bash "$ROOT/scripts/cc-connect-setup.sh" --agent-id agent-test --uninstall-all >/dev/null
)
python3 - "$tmp" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
removed = [
    ".openclaw/workspace/agent-test",
    ".openclaw/agents/agent-test",
    ".hermes/workspace/agent-test",
    ".hermes/skills/openclaw-imports/.env.agent-test",
    ".qclaw-state/workspace-agent-test",
    ".qclaw-state/agents/agent-test",
    ".cc-connect",
    "cc-connect",
]
for rel in removed:
    assert not (root / rel).exists(), rel
openclaw = json.loads((root / ".openclaw/openclaw.json").read_text(encoding="utf-8"))
qclaw = json.loads((root / ".qclaw-state/openclaw.json").read_text(encoding="utf-8"))
assert [x["id"] for x in openclaw["agents"]["list"]] == ["other"]
assert [x["id"] for x in qclaw["agents"]["list"]] == ["other"]
agent_baks = list(root.glob(".nako-agent.bak-uninstall-all-agent-test-*"))
cc_baks = list(root.glob(".cc-connect.bak-uninstall-all-*"))
assert len(agent_baks) == 1, agent_baks
assert len(cc_baks) == 1, cc_baks
expected = {
    "openclaw-workspace-agent-test/file.txt",
    "openclaw-agent-agent-test/data.txt",
    "hermes-workspace-agent-test/file.txt",
    "hermes-env-agent-test",
    "qclaw-workspace-agent-test/file.txt",
    "qclaw-agent-agent-test/data.txt",
}
found = {str(p.relative_to(agent_baks[0])) for p in agent_baks[0].rglob("*") if p.is_file()}
missing = expected - found
assert not missing, missing
PY

echo "cc-connect default source checks passed"
