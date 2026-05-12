#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

grep -Fq 'function Get-PythonCommand' "$ROOT/install.ps1"
grep -Fq '$script:PythonCommand = @(Get-PythonCommand | Where-Object { $_ })' "$ROOT/install.ps1"
grep -Fq 'function Invoke-PythonInline' "$ROOT/install.ps1"
grep -Fq 'function Convert-PathForBash' "$ROOT/install.ps1"
grep -Fq 'wslpath -a "$winPath"' "$ROOT/install.ps1"
grep -Fq 'cygpath -u "$winPath"' "$ROOT/install.ps1"
grep -Fq '& $bashCmd $bashPath @Flags' "$ROOT/install.ps1"

grep -Fq 'Windows shell detected' "$ROOT/install.sh"
grep -Fq 'pwsh install.ps1' "$ROOT/install.sh"
grep -Fq 'Nako Agent Factory requires Linux/systemd' "$ROOT/scripts/nako-agent-factory/install.sh"
grep -Fq 'Nako Agent Factory requires Linux/systemd' "$ROOT/scripts/nako-agent-factory/uninstall.sh"

grep -Fq 'tasklist //FI "IMAGENAME eq cc-connect.exe" //FO CSV //NH' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'taskkill //PID "$pid"' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'windows-*) bin="$tmp/cc-connect-$platform.exe" ;;' "$ROOT/scripts/cc-connect-setup.sh"

echo "windows compatibility checks passed"
