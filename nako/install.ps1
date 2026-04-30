# Compatibility shim. The canonical installer lives at repo root: .\install.ps1.

$ErrorActionPreference = "Stop"

if ($PSCommandPath) {
  $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
} else {
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "git required"
    exit 1
  }
  $TmpDl = Join-Path $env:TEMP ("agents-install-" + [guid]::NewGuid().ToString('N'))
  Write-Host "正在克隆 MetaPact 仓库 → $TmpDl ..."
  git clone --depth 1 https://github.com/Lovappen/MetaPact.git $TmpDl 2>$null | Out-Null
  $RepoRoot = $TmpDl
}

& (Join-Path $RepoRoot "install.ps1") @args
