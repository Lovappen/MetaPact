#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

test -f "$ROOT/scripts/cc-connect-setup.ps1"
grep -Fq 'cc-connect setup for Windows PowerShell' "$ROOT/scripts/cc-connect-setup.ps1"
grep -Fq 'function Install-CcConnectRelease' "$ROOT/scripts/cc-connect-setup.ps1"
grep -Fq 'cc-connect-$CcConnectLazycatVersion-$platform.tar.gz' "$ROOT/scripts/cc-connect-setup.ps1"
grep -Fq 'cc-connect-$platform.exe' "$ROOT/scripts/cc-connect-setup.ps1"
grep -Fq 'function Update-CcConnectConfig' "$ROOT/scripts/cc-connect-setup.ps1"
grep -Fq 'function Setup-CcPlatform' "$ROOT/scripts/cc-connect-setup.ps1"
grep -Fq 'function Ensure-CcConnectRunning' "$ROOT/scripts/cc-connect-setup.ps1"
grep -Fq 'Get-Process -Name "cc-connect"' "$ROOT/scripts/cc-connect-setup.ps1"

grep -Fq 'cc-connect-setup.ps1' "$ROOT/install.ps1"
grep -Fq 'Convert-CcSetupFlagsToPowerShellArgs' "$ROOT/install.ps1"
grep -Fq '& $psHost.Source -NoProfile -File $ccSetupPs @psArgs' "$ROOT/install.ps1"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/.openclaw/workspace/agent-test" "$tmp/.openclaw"
cat > "$tmp/bin/cc-connect" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  --version) echo "cc-connect v1.3.3"; exit 0 ;;
  daemon) exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$tmp/bin/cc-connect"
printf '{"gateway":{"auth":{"token":"tok_test"}}}\n' > "$tmp/.openclaw/openclaw.json"

NAKO_HOME="$tmp" PATH="$tmp/bin:$PATH" pwsh -NoProfile -File "$ROOT/scripts/cc-connect-setup.ps1" \
  -AgentId agent-test -Runtime openclaw -CcConnectSource skip -NonInteractive >/dev/null

python3 - "$tmp" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
cfg = (root / ".cc-connect" / "config.toml").read_text(encoding="utf-8")
assert 'name = "agent-test"' in cfg
assert 'command = "openclaw"' in cfg
assert 'args = ["acp", "--session", "agent:agent-test:main"]' in cfg
assert 'OPENCLAW_GATEWAY_TOKEN = "tok_test"' in cfg
assert 'NAKO_CCCONNECT_PROJECT = "agent-test"' in cfg
assert '[stream_preview]' in cfg
assert 'tool_messages = false' in cfg
assert not re.search(r'\[\[projects\.platforms\]\]', cfg)
PY

echo "cc-connect PowerShell checks passed"
