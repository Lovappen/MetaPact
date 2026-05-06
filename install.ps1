# install.ps1 — Nako agent pack installer for Windows PowerShell 7+
#
# Usage:
#   iex (iwr -UseBasicParsing https://cdn.jsdelivr.net/gh/Lovappen/MetaPact@main/install.ps1).Content
#   # or: pwsh install.ps1 [-Force] [-AgentId agent-nako] [-Runtime openclaw|hermes|qclaw] [-NonInteractive] [-SkipSkills] [-SkipModels] [-ResetSecrets] [-WithFeishu] [-WithWeixin] [-CcConnectSource auto|npm|lazycat|skip]

[CmdletBinding()]
param(
  [switch]$Force,
  [string]$Agent = "nako",
  [string]$AgentId = "agent-nako",
  [ValidateSet("openclaw","hermes","qclaw")]
  [string]$Runtime = "openclaw",
  [switch]$NonInteractive,
  [switch]$SkipSkills,
  [switch]$SkipModels,
  [switch]$ResetSecrets,
  [switch]$WithCcConnect,
  [switch]$WithFeishu,
  [switch]$WithWeixin,
  [switch]$UninstallCcConnect,
  [switch]$UninstallAllCcConnect,
  [switch]$PurgeCcConnect,
  [ValidateSet("auto","npm","lazycat","skip")]
  [string]$CcConnectSource = "lazycat"
)

$ErrorActionPreference = "Stop"
if ($env:NAKO_AGENT_RUNTIME -and -not $PSBoundParameters.ContainsKey("Runtime")) {
  if ($env:NAKO_AGENT_RUNTIME -in @("openclaw","hermes","qclaw")) {
    $Runtime = $env:NAKO_AGENT_RUNTIME
  } else {
    Write-Host "[✗] NAKO_AGENT_RUNTIME 只支持 openclaw|hermes|qclaw" -ForegroundColor Red
    exit 1
  }
}

# ─── Colored output helpers ─────────────────────────────────────────────────
function Info($m)  { Write-Host "[✓] $m" -ForegroundColor Green }
function Warn($m)  { Write-Host "[!] $m" -ForegroundColor Yellow }
function ErrL($m)  { Write-Host "[✗] $m" -ForegroundColor Red }
function Step($m)  { Write-Host ""; Write-Host "▸ $m" -ForegroundColor Cyan -BackgroundColor Black }
function Dim($m)   { Write-Host $m -ForegroundColor DarkGray }

function Ask($q, $default = "") {
  if ($default) { $p = "? $q [$default]: " } else { $p = "? ${q}: " }
  $r = Read-Host -Prompt $p
  if ([string]::IsNullOrWhiteSpace($r)) { return $default }
  return $r
}

function AskSecret($q) {
  $sec = Read-Host -Prompt "? $q (hidden)" -AsSecureString
  $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
  try { return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) }
  finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Confirm($q, $default = "n") {
  $hint = if ($default -eq "y") { "[Y/n]" } else { "[y/N]" }
  $r = Read-Host -Prompt "? $q $hint"
  if ([string]::IsNullOrWhiteSpace($r)) { $r = $default }
  return ($r -match '^[Yy]')
}

function AskChoice($prompt, [string[]]$opts) {
  Write-Host "? $prompt" -ForegroundColor Cyan
  for ($i=0; $i -lt $opts.Count; $i++) { Write-Host "  $($i+1)) $($opts[$i])" }
  while ($true) {
    $n = Read-Host -Prompt "  选择 (1-$($opts.Count))"
    if ($n -match '^\d+$' -and [int]$n -ge 1 -and [int]$n -le $opts.Count) {
      return $opts[[int]$n - 1]
    }
    Warn "无效选择"
  }
}

# ─── Resolve pack root ──────────────────────────────────────────────────────
if ($PSCommandPath) {
  $RepoRoot = Split-Path -Parent $PSCommandPath
} else {
  # piped via iex → clone repo
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    ErrL "git required"; exit 1
  }
  $TmpDl = Join-Path $env:TEMP ("nako-pack-" + [guid]::NewGuid().ToString('N'))
  Write-Host "正在克隆 MetaPact 仓库 → $TmpDl ..."
  git clone --depth 1 https://github.com/Lovappen/MetaPact.git $TmpDl 2>$null | Out-Null
  $RepoRoot = $TmpDl
}
$PackRoot = Join-Path $RepoRoot "nako"
if ($Agent -ne "nako") {
  ErrL "Agent '$Agent' 不存在；当前仓库只提供 nako"
  exit 1
}
$ScriptDir = Join-Path $PackRoot "scripts"

function Get-CcSetupPath {
  $repoRootForSetup = Split-Path -Parent $PackRoot
  $ccSetup = Join-Path $repoRootForSetup "scripts\cc-connect-setup.sh"
  if (-not (Test-Path $ccSetup)) {
    $ccSetup = Join-Path $ScriptDir "cc-connect-setup.sh"
  }
  return $ccSetup
}

function Invoke-CcSetup([string[]]$Flags) {
  $ccSetup = Get-CcSetupPath
  if (-not (Get-Command bash -ErrorAction SilentlyContinue)) {
    Warn "未发现 bash。请安装 Git Bash / WSL 后运行：bash scripts/cc-connect-setup.sh $($Flags -join ' ')"
    return 1
  }
  if (-not (Test-Path $ccSetup)) {
    Warn "未找到 cc-connect-setup.sh，跳过 cc-connect 操作。"
    return 1
  }
  & bash $ccSetup @Flags
  return $LASTEXITCODE
}

if ($UninstallAllCcConnect) {
  Step "cc-connect + agent 一键完整卸载"
  $rc = Invoke-CcSetup @("--agent-id", $AgentId, "--uninstall-all")
  exit $rc
}

if ($UninstallCcConnect) {
  Step "cc-connect 卸载接入"
  $flags = @("--agent-id", $AgentId, "--uninstall")
  if ($PurgeCcConnect) { $flags += "--purge-cc-connect" }
  $rc = Invoke-CcSetup $flags
  exit $rc
}

function Resolve-InstallPath($path) {
  if ([string]::IsNullOrWhiteSpace($path)) { return $path }
  $expanded = [Environment]::ExpandEnvironmentVariables($path)
  if ($expanded -eq "~") { $expanded = $env:USERPROFILE }
  elseif ($expanded.StartsWith('~\')) { $expanded = Join-Path $env:USERPROFILE $expanded.Substring(2) }
  elseif ($expanded.StartsWith("~/")) { $expanded = Join-Path $env:USERPROFILE $expanded.Substring(2) }
  return [System.IO.Path]::GetFullPath($expanded)
}

function Get-QClawAppValue($path, $key) {
  if (-not (Test-Path $path)) { return "" }
  try {
    $cur = Get-Content $path -Raw | ConvertFrom-Json
    foreach ($part in $key.Split(".")) {
      if ($null -eq $cur) { return "" }
      $prop = $cur.PSObject.Properties[$part]
      if ($null -eq $prop) { return "" }
      $cur = $prop.Value
    }
    if ($cur -is [string]) { return $cur }
  } catch {}
  return ""
}

$DefaultOpenclawHome = Join-Path $env:USERPROFILE ".openclaw"
$HermesHome = if ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-Path $env:USERPROFILE ".hermes" }
$QclawHomeInput = if ($env:QCLAW_HOME) { $env:QCLAW_HOME } else { Join-Path $env:USERPROFILE ".qclaw" }
$QclawHome = Resolve-InstallPath $QclawHomeInput

if ($Runtime -eq "qclaw") {
  $qclawAppConfig = Join-Path $QclawHome "qclaw.json"
  $qclawStateDir = Get-QClawAppValue $qclawAppConfig "stateDir"
  if ($qclawStateDir) {
    $QclawHome = Resolve-InstallPath $qclawStateDir
    $qclawAppConfig = Join-Path $QclawHome "qclaw.json"
  }
  $qclawConfigPath = Get-QClawAppValue $qclawAppConfig "configPath"
  if ($qclawConfigPath) { $qclawConfigPath = Resolve-InstallPath $qclawConfigPath }
  else { $qclawConfigPath = Join-Path $QclawHome "openclaw.json" }

  $OpenclawHome = $QclawHome
  $OpenclawConfig = $qclawConfigPath
  $OpenclawSkills = Join-Path $QclawHome "skills"
  $AgentWorkspace = Join-Path $QclawHome "workspace-$AgentId"
} else {
  $OpenclawHome = $DefaultOpenclawHome
  $OpenclawConfig = Join-Path $OpenclawHome "openclaw.json"
  $OpenclawSkills = Join-Path $OpenclawHome "skills"
  $AgentWorkspace = Join-Path $OpenclawHome "workspace\$AgentId"
}
$AgentDataDir = Join-Path $OpenclawHome "agents\$AgentId"
$AgentConfigDir = Join-Path $AgentDataDir "agent"

if ($WithFeishu -or $WithWeixin) { $WithCcConnect = $true }

Write-Host ""
Write-Host "野木奈子 Agent Pack - 安装器 (Windows)" -ForegroundColor White -BackgroundColor DarkBlue
Dim "  Repo:  github.com/Lovappen/MetaPact"
Dim "  Agent: $AgentId"
Dim "  Runtime: $Runtime"
Dim "  Pack:  $PackRoot"
Write-Host ""

# ─── Preflight ──────────────────────────────────────────────────────────────
Step "1. 前置检查"

$MissingHard = @()
foreach ($b in @("python", "jq", "curl")) {
  if (Get-Command $b -ErrorAction SilentlyContinue) { Info $b }
  else { ErrL $b; $MissingHard += $b }
}

if ($Runtime -eq "qclaw") {
  $qclawAppConfig = Join-Path $QclawHome "qclaw.json"
  if (-not (Test-Path $qclawAppConfig)) {
    ErrL "选择 QClaw runtime，但找不到 $qclawAppConfig。请先下载安装并启动一次 QClaw。"
    exit 1
  }
  Info "QClaw 目录 $QclawHome"
  if (-not (Test-Path $OpenclawConfig)) { ErrL "QClaw openclaw.json 不存在: $OpenclawConfig"; exit 1 }
  Info "QClaw openclaw.json"
} else {
  if (-not (Test-Path $OpenclawHome)) {
    ErrL "$OpenclawHome 不存在 — 请先 npm i -g openclaw"; exit 1
  }
  Info "openclaw 目录 $OpenclawHome"

  if (-not (Test-Path $OpenclawConfig)) { ErrL "openclaw.json 不存在"; exit 1 }
  Info "openclaw.json"
}

if ($MissingHard.Count -gt 0) {
  ErrL "请先装：$($MissingHard -join ', ')"
  Dim "Windows 建议: choco install $($MissingHard -join ' ')"
  Dim "        或: winget install python jq"
  exit 1
}

$MissingSoft = @()
foreach ($b in @("whisper", "ffmpeg", "ffprobe", "doki")) {
  if (Get-Command $b -ErrorAction SilentlyContinue) { Info "$b (可选)" }
  else { Warn "$b 缺失 (可选)"; $MissingSoft += $b }
}
if ($MissingSoft.Count -gt 0) {
  Write-Host ""
  Dim "可选依赖缺失，相关 skill 会在运行时报错提示："
  Dim "  whisper / ffmpeg → hearing (转写语音)   pip install openai-whisper; choco install ffmpeg"
  Dim "  doki             → dokidoki              npm i -g @tryjoy/dokidoki"
  Write-Host ""
}

# ─── Existing agent check ───────────────────────────────────────────────────
Step "2. 检查 agent 冲突"

if ((Test-Path $AgentWorkspace) -or (Test-Path $AgentDataDir)) {
  Warn "已存在 $AgentId 的 workspace 或数据目录"
  Dim "  workspace: $AgentWorkspace"
  Dim "  data:      $AgentDataDir"
  if ($NonInteractive -or $Force) {
    Info "继续 — 仅更新人设，保留 memory / custom.md / sessions"
  } else {
    $choice = AskChoice "怎么处理？" @(
      "升级现有 agent（保留聊天/记忆/custom.md）",
      "用别的 id 新装一份",
      "中止"
    )
    switch -Regex ($choice) {
      '^升级'  { Info "将保留用户数据" }
      '^用别的' {
        $new = Ask "新 agent id" "${AgentId}2"
        $AgentId = $new
        if ($Runtime -eq "qclaw") {
          $AgentWorkspace = Join-Path $QclawHome "workspace-$AgentId"
        } else {
          $AgentWorkspace = Join-Path $OpenclawHome "workspace\$AgentId"
        }
        $AgentDataDir = Join-Path $OpenclawHome "agents\$AgentId"
        $AgentConfigDir = Join-Path $AgentDataDir "agent"
      }
      '^中止' { ErrL "已中止"; exit 0 }
    }
  }
}

# ─── Model selection ────────────────────────────────────────────────────────
Step "3. 模型匹配"

function Get-AvailableModels {
  $cfg = Get-Content $OpenclawConfig -Raw | ConvertFrom-Json
  $models = $cfg.agents.defaults.models
  if (-not $models) { return @() }
  $names = @()
  foreach ($prop in $models.PSObject.Properties.Name) { $names += $prop }
  return $names
}

function Get-ModelMap {
  $yaml = Get-Content (Join-Path $PackRoot "config\model-map.yaml") -Raw
  # Lightweight YAML parser for our flat structure
  $caps = @{}; $current = $null; $inPref = $false
  foreach ($line in $yaml -split "`n") {
    if ($line -match '^  (\w+):\s*$') { $current = $Matches[1]; $caps[$current] = @(); $inPref = $false; continue }
    if ($line -match '^\s+preferred:\s*$') { $inPref = $true; continue }
    if ($inPref -and $line -match '^\s+-\s+(\S+)') { $caps[$current] += $Matches[1]; continue }
    if ($line -match '^\s{4}\w' -and $line -notmatch 'preferred') { $inPref = $false }
  }
  return $caps
}

$Primary = ""
if ($SkipModels) {
  $cfg = Get-Content $OpenclawConfig -Raw | ConvertFrom-Json
  $Primary = $cfg.agents.defaults.model.primary
  Info "跳过模型映射，继承 primary: $Primary"
} elseif ($Runtime -eq "qclaw") {
  try {
    $cfg = Get-Content $OpenclawConfig -Raw | ConvertFrom-Json
    $Primary = $cfg.agents.defaults.model.primary
  } catch {
    $Primary = ""
  }
  if (-not $Primary) { $Primary = "qclaw/modelroute" }
  Info "QClaw 主模型继承: $Primary"
} else {
  $avail = Get-AvailableModels
  Write-Host "已配置的 provider/model："
  foreach ($m in $avail) { Write-Host "  $m" }
  Write-Host ""
  $caps = Get-ModelMap
  $matches = @()
  if ($caps.ContainsKey("roleplay")) {
    $matches = $caps["roleplay"] | Where-Object { $avail -contains $_ }
  }
  if (-not $matches -or $matches.Count -eq 0) {
    Warn "roleplay 能力无匹配模型，退化到 general"
    if ($caps.ContainsKey("general")) {
      $matches = $caps["general"] | Where-Object { $avail -contains $_ }
    }
  }
  if (-not $matches -or $matches.Count -eq 0) {
    ErrL "未在 openclaw.json 中找到任何可用模型。请先添加模型后重跑。"
    exit 1
  }
  if ($matches.Count -eq 1) { $Primary = $matches[0] }
  else { $Primary = AskChoice "发现多个可用模型，选一个：" $matches }
  Info "主模型选定：$Primary"
}

# ─── Collect secrets ────────────────────────────────────────────────────────
Step "4. 收集凭据"
Dim "留空回车即跳过，对应能力会被标记 '未启用'。"
Dim "全跳过也行：装完后随时通过 openclaw.json 的 skills.entries.*.env 补；旧版 .env 仍兼容。"
Write-Host ""

function Set-EnvDefault($key, $value = "") {
  if ([string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($key, "Process"))) {
    [Environment]::SetEnvironmentVariable($key, $value, "Process")
  }
}

function Import-EnvFileIfUnset($path) {
  $reused = @()
  if (-not (Test-Path $path)) { return $reused }
  foreach ($line in (Get-Content $path)) {
    if ($line -notmatch '^\s*([A-Z_]+)\s*=\s*(.*)$') { continue }
    $key = $Matches[1]
    $value = $Matches[2].Trim()
    $value = $value.Trim('"').Trim("'")
    if (-not $value) { continue }
    if ([string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($key, "Process"))) {
      [Environment]::SetEnvironmentVariable($key, $value, "Process")
      $reused += $key
    }
  }
  return $reused
}

function Import-OpenclawSkillEnvIfUnset($path) {
  $reused = @()
  if (-not (Test-Path $path)) { return $reused }
  try {
    $cfg = Get-Content $path -Raw | ConvertFrom-Json
  } catch {
    return $reused
  }
  $skillKeys = @{
    voice = @(
      "MINIMAX_API_KEY", "MINIMAX_GROUP_ID", "VOLCENGINE_API_KEY",
      "VOLCENGINE_RESOURCE_ID", "VOICE_DEFAULT_MINIMAX",
      "VOICE_DEFAULT_VOLCENGINE", "VOICE_DEFAULT_SPEED",
      "OPENCLAW_GATEWAY_TOKEN"
    )
    selfie = @("FAL_KEY", "KIE_API_KEY", "OPENCLAW_GATEWAY_TOKEN")
  }
  foreach ($skill in $skillKeys.Keys) {
    $entry = $cfg.skills.entries.$skill
    if (-not $entry -or -not $entry.env) { continue }
    foreach ($key in $skillKeys[$skill]) {
      $value = $entry.env.$key
      if (-not $value) { continue }
      if ([string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($key, "Process"))) {
        [Environment]::SetEnvironmentVariable($key, [string]$value, "Process")
        $reused += $key
      }
    }
  }
  return $reused
}

$SharedEnv = Join-Path $OpenclawSkills ".env"
$AgentEnv = Join-Path $AgentWorkspace "skills\.env"
if (-not $ResetSecrets) {
  $reused = @()
  $reused += Import-OpenclawSkillEnvIfUnset $OpenclawConfig
  $reused += Import-EnvFileIfUnset $SharedEnv
  $reused += Import-EnvFileIfUnset $AgentEnv
  if ($reused.Count -gt 0) {
    Info "复用旧凭据/openclaw.json 配置 ($($reused.Count) 项): $($reused -join ' ')"
    Dim "  想重新输入跑 -ResetSecrets。"
    Write-Host ""
  }
}

try {
  $cfgForGatewayToken = Get-Content $OpenclawConfig -Raw | ConvertFrom-Json
  $cfgGatewayToken = $cfgForGatewayToken.gateway.auth.token
  if ($cfgGatewayToken) {
    [Environment]::SetEnvironmentVariable("OPENCLAW_GATEWAY_TOKEN", $cfgGatewayToken, "Process")
  }
} catch {}

Set-EnvDefault "FEISHU_APP_ID"
Set-EnvDefault "FEISHU_APP_SECRET"
Set-EnvDefault "MINIMAX_API_KEY"
Set-EnvDefault "MINIMAX_GROUP_ID"
Set-EnvDefault "VOLCENGINE_API_KEY"
Set-EnvDefault "VOLCENGINE_RESOURCE_ID" "seed-tts-1.0"
Set-EnvDefault "FAL_KEY"
Set-EnvDefault "KIE_API_KEY"
Set-EnvDefault "SELFIE_REFERENCE_IMAGE" "https://pulseact.lovappen.cn/test/act_ci_build/dlc-promotion/act-gengen/images/e.png"
Set-EnvDefault "SELFIE_CHARACTER_DESC"

if (-not $NonInteractive) {
  Dim "  飞书凭据 → 跳过（cc-connect QR 扫码绑定走 -WithFeishu；原生 Feishu 高级用户可装完后手填 skills\.env）"
  if (-not $env:MINIMAX_API_KEY) {
    $env:MINIMAX_API_KEY = AskSecret "MiniMax API Key (留空则禁用唱歌/TTS)"
  }
  if ($env:MINIMAX_API_KEY -and -not $env:MINIMAX_GROUP_ID) {
    $env:MINIMAX_GROUP_ID = Ask "MiniMax Group ID"
  }
  if ($env:VOLCENGINE_API_KEY -or (Confirm "配置火山引擎 TTS 作备选？")) {
    if (-not $env:VOLCENGINE_API_KEY) {
      $env:VOLCENGINE_API_KEY = AskSecret "Volcengine API Key"
    }
    if (-not $env:VOLCENGINE_RESOURCE_ID) {
      $env:VOLCENGINE_RESOURCE_ID = Ask "Volcengine Resource ID" "seed-tts-1.0"
    }
  } else {
    $env:VOLCENGINE_API_KEY = ""
    $env:VOLCENGINE_RESOURCE_ID = ""
  }
  if ($env:FAL_KEY -or $env:KIE_API_KEY -or (Confirm "启用 selfie？")) {
    if (-not $env:FAL_KEY -and -not $env:KIE_API_KEY) {
      $env:FAL_KEY = AskSecret "fal.ai API Key (推荐，留空则 fallback kie.ai)"
    }
    if (-not $env:FAL_KEY -and -not $env:KIE_API_KEY) {
      $env:KIE_API_KEY = AskSecret "kie.ai API Key"
    }
    if (-not $env:SELFIE_REFERENCE_IMAGE) {
      $env:SELFIE_REFERENCE_IMAGE = Ask "角色参考图 URL（保持相貌一致）" "https://pulseact.lovappen.cn/test/act_ci_build/dlc-promotion/act-gengen/images/e.png"
    }
    if (-not $env:SELFIE_CHARACTER_DESC) {
      $env:SELFIE_CHARACTER_DESC = Ask "角色文字描述" "野木奈子，19岁人类美少女，红瞳，金色及肩发，战斗女仆装"
    }
  } else {
    $env:FAL_KEY = ""
    $env:KIE_API_KEY = ""
    $env:SELFIE_REFERENCE_IMAGE = ""
    $env:SELFIE_CHARACTER_DESC = ""
  }
}

# ─── Install skills ─────────────────────────────────────────────────────────
function Safe-InstallFile($src, $dst) {
  $dstDir = Split-Path -Parent $dst
  if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
  if (-not (Test-Path $dst)) {
    Copy-Item $src $dst
    Dim "  + $dst"
    return
  }
  $same = (Get-FileHash $src).Hash -eq (Get-FileHash $dst).Hash
  if ($same) { Dim "  = $dst"; return }
  if ($Force) {
    $ts = Get-Date -Format "yyyyMMdd-HHmmss"
    Copy-Item $dst "$dst.bak-$ts"
    Copy-Item $src $dst -Force
    Dim "  ± $dst (backed up)"
  } else {
    if (Confirm "  $dst 已存在且不同。覆盖（会备份）？") {
      $ts = Get-Date -Format "yyyyMMdd-HHmmss"
      Copy-Item $dst "$dst.bak-$ts"
      Copy-Item $src $dst -Force
      Dim "  ± $dst"
    } else { Warn "  跳过 $dst" }
  }
}

function Env-Merge($src, $dst) {
  $dstDir = Split-Path -Parent $dst
  if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
  if (-not (Test-Path $dst)) { Copy-Item $src $dst; Dim "  + $dst (new)"; return }
  $existing = Get-Content $dst -Raw
  $added = 0
  foreach ($line in (Get-Content $src)) {
    if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
    $key = ($line -split '=', 2)[0]
    if (-not ($existing -match "(?m)^$([regex]::Escape($key))=")) {
      Add-Content -Path $dst -Value $line
      $added++
    }
  }
  Dim "  ± $dst (+$added new keys)"
}

function Write-EnvValues($envPath, [string[]]$keys) {
  if (-not (Test-Path $envPath)) { return }
  $data = Get-Content $envPath -Raw
  foreach ($k in $keys) {
    $v = [Environment]::GetEnvironmentVariable($k, "Process")
    if ($v) {
      if ($data -match "(?m)^$([regex]::Escape($k))=.*$") {
        $data = $data -replace "(?m)^$([regex]::Escape($k))=.*$", "$k=$v"
      } else { $data += "`n$k=$v`n" }
    }
  }
  Set-Content -Path $envPath -Value $data -NoNewline
}

if (-not $SkipSkills) {
  Step "5. 安装 skills → $OpenclawSkills"
  New-Item -ItemType Directory -Path $OpenclawSkills -Force | Out-Null
  Safe-InstallFile (Join-Path $PackRoot "skills\skill-log.sh") (Join-Path $OpenclawSkills "skill-log.sh")

  foreach ($sk in @("vision","hearing","voice","selfie","dokidoki")) {
    $src = Join-Path $PackRoot "skills\$sk"
    $dst = Join-Path $OpenclawSkills $sk
    New-Item -ItemType Directory -Path $dst -Force | Out-Null
    Safe-InstallFile (Join-Path $src "SKILL.md") (Join-Path $dst "SKILL.md")
    if (Test-Path (Join-Path $src "scripts")) {
      New-Item -ItemType Directory -Path (Join-Path $dst "scripts") -Force | Out-Null
      Get-ChildItem (Join-Path $src "scripts") -File | ForEach-Object {
        Safe-InstallFile $_.FullName (Join-Path $dst "scripts\$($_.Name)")
      }
    }
    if (Test-Path (Join-Path $src "_meta.json")) {
      Safe-InstallFile (Join-Path $src "_meta.json") (Join-Path $dst "_meta.json")
    }
    New-Item -ItemType Directory -Path (Join-Path $dst "logs") -Force | Out-Null
  }

  Env-Merge (Join-Path $PackRoot ".env.shared.example") (Join-Path $OpenclawSkills ".env")
  Write-EnvValues (Join-Path $OpenclawSkills ".env") @(
    "MINIMAX_API_KEY","MINIMAX_GROUP_ID","VOLCENGINE_API_KEY","VOLCENGINE_RESOURCE_ID",
    "FAL_KEY","KIE_API_KEY","OPENCLAW_GATEWAY_TOKEN",
    "VOICE_DEFAULT_MINIMAX","VOICE_DEFAULT_VOLCENGINE","VOICE_DEFAULT_SPEED"
  )
  Info "共享 .env 已写入"
}

# ─── Install persona ───────────────────────────────────────────────────────
Step "6. 安装 agent 人设 → $AgentWorkspace"
New-Item -ItemType Directory -Path $AgentWorkspace -Force | Out-Null
foreach ($f in @("AGENTS.md","IDENTITY.md","SOUL.md","USER.md","HEARTBEAT.md","TOOLS.md")) {
  Safe-InstallFile (Join-Path $PackRoot "agent\$f") (Join-Path $AgentWorkspace $f)
}

$memoryPath = Join-Path $AgentWorkspace "MEMORY.md"
if (-not (Test-Path $memoryPath)) {
  Copy-Item (Join-Path $PackRoot "agent\MEMORY.md") $memoryPath
  Dim "  + MEMORY.md (bootstrap 模板，运行时由 agent 自己滚动维护)"
} else {
  Dim "  = MEMORY.md (保留用户运行时累积的记忆)"
}
try {
  $memory = Get-Content $memoryPath -Raw
  $updated = $memory
  $updated = $updated.Replace('- **provider**：`MINIMAX_API_KEY` 优先，`VOLCENGINE_API_KEY` 备选',
                              '- **provider**：`MINIMAX_API_KEY` 优先，`VOLCENGINE_API_KEY` 备选；key 从 `openclaw.json -> skills.entries.voice.env` 读取，兼容旧 `.env`')
  $updated = $updated.Replace('- **provider**:`MINIMAX_API_KEY` 优先,`VOLCENGINE_API_KEY` 备选',
                              '- **provider**:`MINIMAX_API_KEY` 优先,`VOLCENGINE_API_KEY` 备选；key 从 `openclaw.json -> skills.entries.voice.env` 读取，兼容旧 `.env`')
  $updated = $updated.Replace('- **默认声音**：`female-tianmei`（可在 `<workspace>/skills/.env` 改 `VOICE_DEFAULT_MINIMAX`）',
                              '- **默认声音**：`female-tianmei`（可在 `openclaw.json -> skills.entries.voice.env` 改 `VOICE_DEFAULT_MINIMAX`）')
  $updated = $updated.Replace('- **默认声音**:`female-tianmei`(可在 `<workspace>/skills/.env` 改 `VOICE_DEFAULT_MINIMAX`)',
                              '- **默认声音**:`female-tianmei`(可在 `openclaw.json -> skills.entries.voice.env` 改 `VOICE_DEFAULT_MINIMAX`)')
  $updated = $updated.Replace('- **provider**：`FAL_KEY` 优先，`KIE_API_KEY` 备选',
                              '- **provider**：`FAL_KEY` 优先，`KIE_API_KEY` 备选；key 从 `openclaw.json -> skills.entries.selfie.env` 读取，兼容旧 `.env`')
  if ($updated -ne $memory) {
    Set-Content -Path $memoryPath -Value $updated -NoNewline -Encoding UTF8
  }
} catch {}

$customPath = Join-Path $AgentWorkspace "custom.md"
if (-not (Test-Path $customPath)) {
  $customStub = @"
# custom.md — 用户自定义扩展层（不会被升级覆盖）

此文件空的时候 agent 仅走默认人设。往里加内容即可覆盖任何默认行为。
示例见 custom.md.example。
"@
  $customStub | Set-Content -Path $customPath -Encoding UTF8
  Dim "  + custom.md (empty stub)"
} else {
  Dim "  = custom.md (保留用户原文件)"
}
Safe-InstallFile (Join-Path $PackRoot "agent\custom.md.example") (Join-Path $AgentWorkspace "custom.md.example")

Env-Merge (Join-Path $PackRoot ".env.agent.example") (Join-Path $AgentWorkspace "skills\.env")
Write-EnvValues (Join-Path $AgentWorkspace "skills\.env") @(
  "FEISHU_APP_ID","FEISHU_APP_SECRET","SELFIE_REFERENCE_IMAGE","SELFIE_CHARACTER_DESC"
)

if (Test-Path (Join-Path $PackRoot "agent\scripts")) {
  $WorkspaceScripts = Join-Path $AgentWorkspace "scripts"
  New-Item -ItemType Directory -Path $WorkspaceScripts -Force | Out-Null
  Get-ChildItem (Join-Path $PackRoot "agent\scripts") -File -Filter "*.sh" | ForEach-Object {
    Safe-InstallFile $_.FullName (Join-Path $WorkspaceScripts $_.Name)
  }
}

Dim "保护不动：memory\, sessions\, auth-*.json"

# ─── Merge openclaw.json ────────────────────────────────────────────────────
Step "7. 合并 openclaw.json"
$tsBak = Get-Date -Format "yyyyMMdd-HHmmss"
Copy-Item $OpenclawConfig "$OpenclawConfig.bak-$tsBak"

python -c @"
import json, sys, os
path = r'$OpenclawConfig'
cfg = json.load(open(path))
agent_id = '$AgentId'
primary = '$Primary'
workspace = r'$AgentWorkspace'
agent_data_dir = r'$AgentConfigDir'
skills_dir = r'$OpenclawSkills'

agents = cfg.setdefault('agents', {})
lst = agents.setdefault('list', [])
found = False
for a in lst:
    if a.get('id') == agent_id:
        a['workspace'] = workspace
        a['agentDir'] = agent_data_dir
        model = a.get('model')
        if not isinstance(model, dict):
            model = {}
            a['model'] = model
        model['primary'] = primary
        found = True; break
if not found:
    lst.append({'id': agent_id, 'name': agent_id, 'workspace': workspace,
                'agentDir': agent_data_dir, 'model': {'primary': primary}})

skills = cfg.setdefault('skills', {})
entries = skills.setdefault('entries', {})
def set_env(name, keys):
    e = entries.setdefault(name, {'enabled': True, 'env': {}})
    e.setdefault('enabled', True)
    env = e.setdefault('env', {})
    for k in keys:
        v = os.environ.get(k, '')
        if v: env[k] = v
set_env('voice', ['MINIMAX_API_KEY','MINIMAX_GROUP_ID','VOLCENGINE_API_KEY','VOLCENGINE_RESOURCE_ID',
                  'VOICE_DEFAULT_MINIMAX','VOICE_DEFAULT_VOLCENGINE','VOICE_DEFAULT_SPEED','OPENCLAW_GATEWAY_TOKEN'])
set_env('selfie', ['FAL_KEY','KIE_API_KEY','OPENCLAW_GATEWAY_TOKEN'])

load = skills.setdefault('load', {})
extras = load.setdefault('extraDirs', [])
gs = os.path.expanduser(skills_dir)
if gs not in extras: extras.append(gs)

open(path, 'w', encoding='utf-8').write(json.dumps(cfg, indent=2, ensure_ascii=False) + '\n')
print(f'merged: agent={agent_id}, primary={primary}')
"@
Info "openclaw.json 已合并"

function Copy-DirectoryContents($src, $dst) {
  if (-not (Test-Path $src)) { return }
  if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }
  Get-ChildItem -Path $src -Force | ForEach-Object {
    Copy-Item -Path $_.FullName -Destination $dst -Recurse -Force
  }
}

function Sync-HermesRuntime {
  $hermesWorkspace = Join-Path $HermesHome "workspace\$AgentId"
  $hermesSkills = Join-Path $HermesHome "skills\openclaw-imports"
  New-Item -ItemType Directory -Path $hermesWorkspace, $hermesSkills -Force | Out-Null
  Copy-DirectoryContents $AgentWorkspace $hermesWorkspace
  Copy-DirectoryContents $OpenclawSkills $hermesSkills
  Info "Hermes runtime 已同步: $hermesWorkspace"
}

function Sync-QClawRuntime {
  $qclawAppConfig = Join-Path $QclawHome "qclaw.json"
  if (-not (Test-Path $qclawAppConfig)) {
    ErrL "选择 QClaw runtime，但找不到 $qclawAppConfig。请先下载安装并启动一次 QClaw。"
    exit 1
  }

  $qclawWorkspace = Join-Path $QclawHome "workspace-$AgentId"
  $qclawAgentDir = Join-Path $QclawHome "agents\$AgentId\agent"
  $qclawSkills = Join-Path $QclawHome "skills"
  New-Item -ItemType Directory -Path $qclawWorkspace, $qclawAgentDir, $qclawSkills -Force | Out-Null
  if ($AgentWorkspace -ne $qclawWorkspace) { Copy-DirectoryContents $AgentWorkspace $qclawWorkspace }
  if ($OpenclawSkills -ne $qclawSkills) { Copy-DirectoryContents $OpenclawSkills $qclawSkills }

  $env:NAKO_PS_QCLAW_HOME = $QclawHome
  $env:NAKO_PS_QCLAW_CONFIG = $OpenclawConfig
  $env:NAKO_PS_OPENCLAW_CONFIG = $OpenclawConfig
  $env:NAKO_PS_AGENT_ID = $AgentId
  $env:NAKO_PS_PRIMARY = $Primary
  python -c @'
import json
import os
import time
from pathlib import Path

qclaw_home = Path(os.environ["NAKO_PS_QCLAW_HOME"])
qclaw_config = Path(os.environ["NAKO_PS_QCLAW_CONFIG"])
openclaw_config = Path(os.environ["NAKO_PS_OPENCLAW_CONFIG"])
agent_id = os.environ["NAKO_PS_AGENT_ID"]
primary = os.environ.get("NAKO_PS_PRIMARY", "")
config_path = qclaw_config
source_path = openclaw_config

def load(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except Exception:
        return {}

cfg = load(config_path)
source = load(source_path)
if not isinstance(cfg, dict):
    cfg = {}
agents = cfg.setdefault("agents", {})
if not isinstance(agents, dict):
    cfg["agents"] = agents = {}
agents.setdefault("defaults", {})
items = agents.setdefault("list", [])
if not isinstance(items, list):
    agents["list"] = items = []

source_item = {}
for item in ((source.get("agents") or {}).get("list") or []):
    if isinstance(item, dict) and item.get("id") == agent_id:
        source_item = item
        break

existing_item = {}
for item in items:
    if isinstance(item, dict) and item.get("id") == agent_id:
        existing_item = item
        break

def primary_model(value):
    if isinstance(value, str):
        return value
    if isinstance(value, dict):
        primary_value = value.get("primary")
        if isinstance(primary_value, str):
            return primary_value
    return ""

default_identity = {
    "name": "野木奈子",
    "emoji": "🎀",
    "theme": "核战后赛博世界专属战斗女仆",
}
identity = (
    existing_item.get("identity") if isinstance(existing_item.get("identity"), dict)
    else source_item.get("identity") if isinstance(source_item.get("identity"), dict)
    else default_identity
)
name = existing_item.get("name") or source_item.get("name") or ""
if not name or name == agent_id:
    name = identity.get("name") or agent_id

entry = {
    "id": agent_id,
    "name": name,
    "workspace": str(qclaw_home / f"workspace-{agent_id}"),
    "agentDir": str(qclaw_home / "agents" / agent_id / "agent"),
    "identity": identity,
}
qclaw_default_model = (((agents.get("defaults") or {}).get("model") or {}).get("primary"))
model = (
    primary_model(existing_item.get("model"))
    or qclaw_default_model
    or primary_model(source_item.get("model"))
    or primary
)
if model:
    entry["model"] = model

for idx, item in enumerate(items):
    if isinstance(item, dict) and item.get("id") == agent_id:
        merged = dict(item)
        merged.update(entry)
        items[idx] = merged
        break
else:
    items.append(entry)

old = config_path.read_text(encoding="utf-8", errors="ignore") if config_path.exists() else ""
new = json.dumps(cfg, ensure_ascii=False, indent=2) + "\n"
if old != new:
    if config_path.exists():
        backup = config_path.with_name(f"openclaw.json.bak-nako-qclaw-{time.strftime('%Y%m%d-%H%M%S')}")
        backup.write_text(old, encoding="utf-8")
    config_path.write_text(new, encoding="utf-8")
'@
  Info "QClaw runtime 已同步: $qclawWorkspace"
}

if ($Runtime -eq "hermes") {
  Step "7a. 同步 Hermes runtime"
  Sync-HermesRuntime
} elseif ($Runtime -eq "qclaw") {
  Step "7a. 同步 QClaw runtime"
  Sync-QClawRuntime
}

# ─── cc-connect 多平台 (可选) ──────────────────────────────────────────────
if ($WithCcConnect -or ((-not $NonInteractive) -and (Confirm "现在配置 cc-connect 接入飞书/微信等多平台？"))) {
  Step "8. cc-connect 多平台接入"
  $CcFlags = @("--agent-id", $AgentId, "--runtime", $Runtime)
  if ($NonInteractive) { $CcFlags += "--non-interactive" }
  if ($WithFeishu) { $CcFlags += "--with-feishu" }
  if ($WithWeixin) { $CcFlags += "--with-weixin" }
  $CcFlags += @("--cc-connect-source", $CcConnectSource)
  $rc = Invoke-CcSetup $CcFlags
  if ($rc -ne 0) {
    Warn "cc-connect 配置未完成（可后续手动跑 scripts/cc-connect-setup.sh）"
  }
}

# ─── Done ───────────────────────────────────────────────────────────────────
Write-Host ""
Info "安装完成！"
Dim "下一步："
if ($Runtime -eq "qclaw") {
  $qclawNextWorkspace = Join-Path $QclawHome "workspace-$AgentId"
  Dim "  1. QClaw workspace: $qclawNextWorkspace"
} elseif ($Runtime -eq "hermes") {
  $hermesNextWorkspace = Join-Path $HermesHome "workspace\$AgentId"
  Dim "  1. Hermes workspace: $hermesNextWorkspace"
} else {
  Dim "  1. 重启 openclaw gateway（Windows: 关闭进程后重开）"
}
Dim "  2. 在飞书/微信里找 $AgentId"
Dim "  3. 定制在 $AgentWorkspace\custom.md（升级不会动它；Hermes/QClaw 会从这里同步）"
Dim "  4. 文档在 $PackRoot\docs\"
