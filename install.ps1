# install.ps1 — Nako agent pack installer for Windows PowerShell 7+
#
# Usage:
#   iex (iwr -UseBasicParsing https://cdn.jsdelivr.net/gh/Lovappen/MetaPact@main/install.ps1).Content
#   # or: pwsh install.ps1 [-Force] [-AgentId agent-nako] [-NonInteractive] [-SkipSkills] [-SkipModels] [-ResetSecrets] [-WithFeishu] [-WithWeixin] [-CcConnectSource auto|npm|lazycat|skip]

[CmdletBinding()]
param(
  [switch]$Force,
  [string]$Agent = "nako",
  [string]$AgentId = "agent-nako",
  [switch]$NonInteractive,
  [switch]$SkipSkills,
  [switch]$SkipModels,
  [switch]$ResetSecrets,
  [switch]$WithCcConnect,
  [switch]$WithFeishu,
  [switch]$WithWeixin,
  [ValidateSet("auto","npm","lazycat","skip")]
  [string]$CcConnectSource = "lazycat"
)

$ErrorActionPreference = "Stop"

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

$OpenclawHome = Join-Path $env:USERPROFILE ".openclaw"
$OpenclawConfig = Join-Path $OpenclawHome "openclaw.json"
$OpenclawSkills = Join-Path $OpenclawHome "skills"
$AgentWorkspace = Join-Path $OpenclawHome "workspace\$AgentId"
$AgentDataDir = Join-Path $OpenclawHome "agents\$AgentId"

if ($WithFeishu -or $WithWeixin) { $WithCcConnect = $true }

Write-Host ""
Write-Host "野木奈子 Agent Pack - 安装器 (Windows)" -ForegroundColor White -BackgroundColor DarkBlue
Dim "  Repo:  github.com/Lovappen/MetaPact"
Dim "  Agent: $AgentId"
Dim "  Pack:  $PackRoot"
Write-Host ""

# ─── Preflight ──────────────────────────────────────────────────────────────
Step "1. 前置检查"

$MissingHard = @()
foreach ($b in @("python", "jq", "curl")) {
  if (Get-Command $b -ErrorAction SilentlyContinue) { Info $b }
  else { ErrL $b; $MissingHard += $b }
}

if (-not (Test-Path $OpenclawHome)) {
  ErrL "$OpenclawHome 不存在 — 请先 npm i -g openclaw"; exit 1
}
Info "openclaw 目录 $OpenclawHome"

if (-not (Test-Path $OpenclawConfig)) { ErrL "openclaw.json 不存在"; exit 1 }
Info "openclaw.json"

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
        $AgentWorkspace = Join-Path $OpenclawHome "workspace\$AgentId"
        $AgentDataDir = Join-Path $OpenclawHome "agents\$AgentId"
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
  $updated = $updated.Replace("- **provider**：`MINIMAX_API_KEY` 优先，`VOLCENGINE_API_KEY` 备选",
                              "- **provider**：`MINIMAX_API_KEY` 优先，`VOLCENGINE_API_KEY` 备选；key 从 `openclaw.json -> skills.entries.voice.env` 读取，兼容旧 `.env`")
  $updated = $updated.Replace("- **provider**:`MINIMAX_API_KEY` 优先,`VOLCENGINE_API_KEY` 备选",
                              "- **provider**:`MINIMAX_API_KEY` 优先,`VOLCENGINE_API_KEY` 备选；key 从 `openclaw.json -> skills.entries.voice.env` 读取，兼容旧 `.env`")
  $updated = $updated.Replace("- **默认声音**：`female-tianmei`（可在 `<workspace>/skills/.env` 改 `VOICE_DEFAULT_MINIMAX`）",
                              "- **默认声音**：`female-tianmei`（可在 `openclaw.json -> skills.entries.voice.env` 改 `VOICE_DEFAULT_MINIMAX`）")
  $updated = $updated.Replace("- **默认声音**:`female-tianmei`(可在 `<workspace>/skills/.env` 改 `VOICE_DEFAULT_MINIMAX`)",
                              "- **默认声音**:`female-tianmei`(可在 `openclaw.json -> skills.entries.voice.env` 改 `VOICE_DEFAULT_MINIMAX`)")
  $updated = $updated.Replace("- **provider**：`FAL_KEY` 优先，`KIE_API_KEY` 备选",
                              "- **provider**：`FAL_KEY` 优先，`KIE_API_KEY` 备选；key 从 `openclaw.json -> skills.entries.selfie.env` 读取，兼容旧 `.env`")
  if ($updated -ne $memory) {
    Set-Content -Path $memoryPath -Value $updated -NoNewline -Encoding UTF8
  }
} catch {}

$customPath = Join-Path $AgentWorkspace "custom.md"
if (-not (Test-Path $customPath)) {
  @"
# custom.md — 用户自定义扩展层（不会被升级覆盖）

此文件空的时候 agent 仅走默认人设。往里加内容即可覆盖任何默认行为。
示例见 custom.md.example。
"@ | Set-Content -Path $customPath -Encoding UTF8
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
agent_data_dir = r'$AgentDataDir\agent'

agents = cfg.setdefault('agents', {})
lst = agents.setdefault('list', [])
found = False
for a in lst:
    if a.get('id') == agent_id:
        a['workspace'] = workspace
        a['agentDir'] = agent_data_dir
        a.setdefault('model', {})['primary'] = primary
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
gs = os.path.expanduser('~/.openclaw/skills')
if gs not in extras: extras.append(gs)

open(path, 'w', encoding='utf-8').write(json.dumps(cfg, indent=2, ensure_ascii=False) + '\n')
print(f'merged: agent={agent_id}, primary={primary}')
"@
Info "openclaw.json 已合并"

# ─── cc-connect 多平台 (可选) ──────────────────────────────────────────────
if ($WithCcConnect -or ((-not $NonInteractive) -and (Confirm "现在配置 cc-connect 接入飞书/微信等多平台？"))) {
  Step "8. cc-connect 多平台接入"
  $CcFlags = @("--agent-id", $AgentId)
  if ($NonInteractive) { $CcFlags += "--non-interactive" }
  if ($WithFeishu) { $CcFlags += "--with-feishu" }
  if ($WithWeixin) { $CcFlags += "--with-weixin" }
  $CcFlags += @("--cc-connect-source", $CcConnectSource)

  $RepoRoot = Split-Path -Parent $PackRoot
  $CcSetup = Join-Path $RepoRoot "scripts\cc-connect-setup.sh"
  if (-not (Test-Path $CcSetup)) {
    $CcSetup = Join-Path $ScriptDir "cc-connect-setup.sh"
  }

  if (-not (Get-Command bash -ErrorAction SilentlyContinue)) {
    Warn "未发现 bash，跳过 cc-connect 自动接入。可在 Git Bash / WSL 中运行 scripts/cc-connect-setup.sh。"
  } elseif (-not (Test-Path $CcSetup)) {
    Warn "未找到 cc-connect-setup.sh，跳过 cc-connect 自动接入。"
  } else {
    & bash $CcSetup @CcFlags
    if ($LASTEXITCODE -ne 0) {
      Warn "cc-connect 配置未完成（可后续手动跑 scripts/cc-connect-setup.sh）"
    }
  }
}

# ─── Done ───────────────────────────────────────────────────────────────────
Write-Host ""
Info "安装完成！"
Dim "下一步："
Dim "  1. 重启 openclaw gateway（Windows: 关闭进程后重开）"
Dim "  2. 在飞书里 @ $AgentId 或私聊它"
Dim "  3. 定制在 $AgentWorkspace\custom.md（升级不会动它）"
Dim "  4. 文档在 $PackRoot\docs\"
