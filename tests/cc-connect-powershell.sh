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
grep -Fq 'function Open-CcQrImage' "$ROOT/scripts/cc-connect-setup.ps1"
grep -Fq 'function Remove-CcPlatformBinding' "$ROOT/scripts/cc-connect-setup.ps1"
grep -Fq 'Confirm-Choice "$Label is already configured. Unbind and rescan QR?" "n"' "$ROOT/scripts/cc-connect-setup.ps1"
grep -Fq 'function Test-CcIsWindows' "$ROOT/scripts/cc-connect-setup.ps1"
grep -Fq -- '--qr-image' "$ROOT/scripts/cc-connect-setup.ps1"
grep -Fq 'Start-Process -FilePath $Path' "$ROOT/scripts/cc-connect-setup.ps1"
grep -Fq 'Start-Process -FilePath $cmd -ArgumentList $args' "$ROOT/scripts/cc-connect-setup.ps1"
grep -Fq '"--set-allow-from-empty"' "$ROOT/scripts/cc-connect-setup.ps1"
! grep -Fq 'ArgumentList.Add' "$ROOT/scripts/cc-connect-setup.ps1"
grep -Fq 'Get-Process -Name "cc-connect"' "$ROOT/scripts/cc-connect-setup.ps1"

grep -Fq 'cc-connect-setup.ps1' "$ROOT/install.ps1"
grep -Fq 'Convert-CcSetupFlagsToPowerShellArgs' "$ROOT/install.ps1"
grep -Fq 'function Test-CcPlatformBound' "$ROOT/install.ps1"
grep -Fq '& $psHost.Source -NoProfile -File $ccSetupPs @psArgs 2>&1 | ForEach-Object { Write-Host $_ }' "$ROOT/install.ps1"
grep -Fq 'return [int]$exitCode' "$ROOT/install.ps1"
! grep -Fq 'return $LASTEXITCODE' "$ROOT/install.ps1"
grep -Fq 'scripts/cc-connect-setup.ps1 -AgentId' "$ROOT/install.ps1"
grep -Fq 'cc-connect 绑定已写入配置，但后续启动/收尾失败' "$ROOT/install.ps1"
! grep -Fq 'cc-connect 配置未完成（可后续手动跑 scripts/cc-connect-setup.sh）' "$ROOT/install.ps1"
grep -Fq 'exit 0' "$ROOT/scripts/cc-connect-setup.ps1"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/.openclaw/workspace/agent-test" "$tmp/.openclaw"
cat > "$tmp/bin/cc-connect" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  --version) echo "cc-connect v1.3.3"; exit 0 ;;
  daemon) exit 0 ;;
  weixin)
    shift
    [ "${1:-}" = "setup" ] || exit 2
    has_qr=0
    has_allow=0
    qr_path=
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --qr-image) has_qr=1; qr_path="${2:-}"; shift 2 ;;
        --set-allow-from-empty) has_allow=1; shift ;;
        *) shift ;;
      esac
    done
    [ "$has_allow" = "1" ] || exit 9
    if [ "$has_qr" = "1" ] && [ -n "$qr_path" ]; then
      mkdir -p "$(dirname "$qr_path")"
      printf 'fake qr image\n' > "$qr_path"
    fi
    if [ "$has_qr" = "1" ] && [ -n "${FAKE_CC_CONNECT_QR_MARKER:-}" ]; then
      : > "$FAKE_CC_CONNECT_QR_MARKER"
    fi
    if [ "$has_qr" = "1" ] && [ -n "${FAKE_CC_CONNECT_APPEND_CONFIG:-}" ]; then
      cat >> "$FAKE_CC_CONNECT_APPEND_CONFIG" <<'CFG'

[[projects.platforms]]
type = "weixin"

[projects.platforms.options]
token = "new-token"
CFG
    fi
    exit 0
    ;;
  *) exit 0 ;;
esac
EOF
cat > "$tmp/bin/open" <<'EOF'
#!/usr/bin/env bash
if [ -n "${FAKE_OPEN_MARKER:-}" ]; then
  printf '%s\n' "$1" > "$FAKE_OPEN_MARKER"
fi
exit 0
EOF
cp "$tmp/bin/open" "$tmp/bin/xdg-open"
chmod +x "$tmp/bin/cc-connect"
chmod +x "$tmp/bin/open" "$tmp/bin/xdg-open"
printf '{"gateway":{"auth":{"token":"tok_test"}}}\n' > "$tmp/.openclaw/openclaw.json"

NAKO_HOME="$tmp" PATH="$tmp/bin:$PATH" pwsh -NoProfile -File "$ROOT/scripts/cc-connect-setup.ps1" \
  -AgentId agent-test -Runtime openclaw -CcConnectSource skip -NonInteractive >/dev/null

FAKE_CC_CONNECT_QR_MARKER="$tmp/qr-marker" FAKE_OPEN_MARKER="$tmp/open-marker" \
  NAKO_HOME="$tmp" PATH="$tmp/bin:$PATH" \
  pwsh -NoProfile -File "$ROOT/scripts/cc-connect-setup.ps1" \
  -AgentId agent-test -Runtime openclaw -CcConnectSource skip -WithWeixin >/dev/null
test -f "$tmp/qr-marker"
test -s "$tmp/.cc-connect/qr/agent-test-weixin.png"
test -s "$tmp/open-marker"
grep -Fq "agent-test-weixin.png" "$tmp/open-marker"

cat >> "$tmp/.cc-connect/config.toml" <<'EOF'

[[projects.platforms]]
type = "weixin"

[projects.platforms.options]
token = "old-token"
base_url = "https://ilinkai.weixin.qq.com"
EOF
printf 'y\n' | FAKE_CC_CONNECT_QR_MARKER="$tmp/rebind-marker" FAKE_OPEN_MARKER="$tmp/rebind-open-marker" \
  FAKE_CC_CONNECT_APPEND_CONFIG="$tmp/.cc-connect/config.toml" NAKO_HOME="$tmp" PATH="$tmp/bin:$PATH" \
  pwsh -NoProfile -File "$ROOT/scripts/cc-connect-setup.ps1" \
  -AgentId agent-test -Runtime openclaw -CcConnectSource skip -WithWeixin >/dev/null
test -f "$tmp/rebind-marker"
python3 - "$tmp" <<'PY'
import sys
from pathlib import Path

cfg = (Path(sys.argv[1]) / ".cc-connect" / "config.toml").read_text(encoding="utf-8")
assert 'token = "old-token"' not in cfg
assert 'token = "new-token"' in cfg
PY

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
assert 'token = "new-token"' in cfg
PY

echo "cc-connect PowerShell checks passed"
