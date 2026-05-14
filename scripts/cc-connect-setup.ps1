# cc-connect setup for Windows PowerShell.
#
# This is the native PowerShell counterpart of cc-connect-setup.sh. It avoids
# requiring Git Bash/WSL for Windows installs while keeping the same config
# shape in ~/.cc-connect/config.toml.

[CmdletBinding()]
param(
  [string]$AgentId = "agent-nako",
  [ValidateSet("openclaw","hermes","qclaw")]
  [string]$Runtime = "openclaw",
  [string]$DisplayName = "",
  [string]$CcProjectId = "",
  [switch]$WithFeishu,
  [switch]$WithWeixin,
  [ValidateSet("auto","npm","lazycat","skip")]
  [string]$CcConnectSource = "lazycat",
  [switch]$NonInteractive,
  [switch]$Uninstall,
  [switch]$PurgeCcConnect,
  [switch]$UninstallAll
)

function Initialize-Utf8Console {
  $env:PYTHONIOENCODING = "utf-8"
  $env:PYTHONUTF8 = "1"
  try {
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
      $chcp = Get-Command chcp.com -ErrorAction SilentlyContinue
      if ($chcp) { & $chcp.Source 65001 > $null 2>&1 }
    }
    [Console]::InputEncoding = $utf8NoBom
    [Console]::OutputEncoding = $utf8NoBom
    $global:OutputEncoding = $utf8NoBom
  } catch {}
}
Initialize-Utf8Console

$ErrorActionPreference = "Stop"

if ($env:NAKO_AGENT_RUNTIME -and -not $PSBoundParameters.ContainsKey("Runtime")) {
  if ($env:NAKO_AGENT_RUNTIME -in @("openclaw","hermes","qclaw")) {
    $Runtime = $env:NAKO_AGENT_RUNTIME
  }
}
if ($env:CC_CONNECT_SOURCE -and -not $PSBoundParameters.ContainsKey("CcConnectSource")) {
  if ($env:CC_CONNECT_SOURCE -in @("auto","npm","lazycat","skip")) {
    $CcConnectSource = $env:CC_CONNECT_SOURCE
  }
}

function Info($m) { Write-Host "[OK] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[!] $m" -ForegroundColor Yellow }
function ErrL($m) { Write-Host "[ERR] $m" -ForegroundColor Red }
function Step($m) { Write-Host ""; Write-Host ">> $m" -ForegroundColor Cyan }
function Dim($m) { Write-Host $m -ForegroundColor DarkGray }

function Confirm-Choice($Question, $Default = "n") {
  $hint = if ($Default -eq "y") { "[Y/n]" } else { "[y/N]" }
  $reply = Read-Host "? $Question $hint"
  if ([string]::IsNullOrWhiteSpace($reply)) { $reply = $Default }
  return ($reply -match '^[Yy]')
}

function Resolve-InstallPath($PathValue) {
  if ([string]::IsNullOrWhiteSpace($PathValue)) { return $PathValue }
  $expanded = [Environment]::ExpandEnvironmentVariables($PathValue)
  if ($expanded -eq "~") { $expanded = $script:HomeDir }
  elseif ($expanded.StartsWith("~\")) { $expanded = Join-Path $script:HomeDir $expanded.Substring(2) }
  elseif ($expanded.StartsWith("~/")) { $expanded = Join-Path $script:HomeDir $expanded.Substring(2) }
  return [System.IO.Path]::GetFullPath($expanded)
}

function Get-JsonValue($PathValue, $Key) {
  if (-not (Test-Path $PathValue)) { return "" }
  try {
    $cur = Get-Content $PathValue -Raw | ConvertFrom-Json
    foreach ($part in $Key.Split(".")) {
      if ($null -eq $cur) { return "" }
      $prop = $cur.PSObject.Properties[$part]
      if ($null -eq $prop) { return "" }
      $cur = $prop.Value
    }
    if ($cur -is [string]) { return $cur }
  } catch {}
  return ""
}

function ConvertTo-TomlString($Value) {
  $text = [string]$Value
  return '"' + $text.Replace("\", "\\").Replace('"', '\"') + '"'
}

function ConvertTo-TomlArray([string[]]$Values) {
  return "[" + (($Values | ForEach-Object { ConvertTo-TomlString $_ }) -join ", ") + "]"
}

function ConvertTo-TomlInlineTable($Table) {
  $pairs = @()
  foreach ($entry in $Table.GetEnumerator()) {
    if ($null -ne $entry.Value -and [string]$entry.Value -ne "") {
      $pairs += ("{0} = {1}" -f $entry.Key, (ConvertTo-TomlString $entry.Value))
    }
  }
  return "{ " + ($pairs -join ", ") + " }"
}

function Resolve-OpenClawCommand {
  if ($env:OPENCLAW_BIN) {
    $candidate = Resolve-InstallPath $env:OPENCLAW_BIN
    if (Test-Path $candidate) {
      if ($candidate.EndsWith(".ps1", [StringComparison]::OrdinalIgnoreCase)) {
        $cmdShim = [IO.Path]::ChangeExtension($candidate, ".cmd")
        if (Test-Path $cmdShim) { return $cmdShim }
      }
      return $candidate
    }
    throw "OpenClaw runtime selected but OPENCLAW_BIN does not exist: $candidate"
  }
  $cmd = Get-Command openclaw -ErrorAction SilentlyContinue
  if ($cmd) {
    $source = $cmd.Source
    if ($source.EndsWith(".ps1", [StringComparison]::OrdinalIgnoreCase)) {
      $cmdShim = [IO.Path]::ChangeExtension($source, ".cmd")
      if (Test-Path $cmdShim) { return $cmdShim }
    }
    return $source
  }
  $candidates = @()
  $candidates += Join-Path $script:HomeDir ".local/bin/openclaw"
  if ($env:APPDATA) {
    $candidates += Join-Path $env:APPDATA "npm/openclaw.cmd"
    $candidates += Join-Path $env:APPDATA "npm/openclaw.exe"
    $candidates += Join-Path $env:APPDATA "npm/openclaw.ps1"
  }
  foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path $candidate)) { return $candidate }
  }
  throw "OpenClaw runtime selected but openclaw command was not found. Install OpenClaw or set OPENCLAW_BIN."
}

function Set-GlobalTomlOption($Text, $Section, $Key, $Value) {
  $projectMatch = [regex]::Match($Text, "(?m)^\[\[projects\]\]\s*$")
  $prefixEnd = if ($projectMatch.Success) { $projectMatch.Index } else { $Text.Length }
  $prefix = $Text.Substring(0, $prefixEnd)
  $rest = $Text.Substring($prefixEnd)
  $sectionPattern = "(?ms)(^\[$([regex]::Escape($Section))\]\s*\n)(.*?)(?=^\[|\z)"
  $match = [regex]::Match($prefix, $sectionPattern)
  if ($match.Success) {
    $body = $match.Groups[2].Value
    $keyPattern = "(?m)^$([regex]::Escape($Key))\s*=.*$"
    if ([regex]::IsMatch($body, $keyPattern)) {
      $body = [regex]::Replace($body, $keyPattern, "$Key = $Value")
    } else {
      $body = "$Key = $Value`n$body"
    }
    return $prefix.Substring(0, $match.Groups[2].Index) + $body + $prefix.Substring($match.Groups[2].Index + $match.Groups[2].Length) + $rest
  }
  if ($prefix -and -not $prefix.EndsWith("`n")) { $prefix += "`n" }
  return $prefix + "`n[$Section]`n$Key = $Value`n" + $rest
}

function Get-CcPlatform {
  $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
  switch ($arch) {
    "x64" { $arch = "amd64" }
    "arm64" { $arch = "arm64" }
    default { throw "unsupported architecture: $arch" }
  }
  if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
    return "windows-$arch"
  }
  if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)) {
    return "darwin-$arch"
  }
  if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Linux)) {
    return "linux-$arch"
  }
  throw "unsupported OS"
}

function Test-CcConnectNativeVideo {
  $cmd = Get-Command cc-connect -ErrorAction SilentlyContinue
  if (-not $cmd) { return $false }
  try {
    $version = (& $cmd.Source --version 2>&1 | Select-Object -First 1) -join " "
    return ($version -match 'lazycat/v1\.3\.3|v?1\.3\.[3-9]')
  } catch {
    return $false
  }
}

function Install-CcConnectBinary($SourcePath) {
  $suffix = if ($IsWindows) { ".exe" } else { "" }
  $dest = $env:CC_CONNECT_BIN
  if (-not $dest) {
    $localBin = Join-Path $script:HomeDir ".local/bin"
    New-Item -ItemType Directory -Path $localBin -Force | Out-Null
    $dest = Join-Path $localBin "cc-connect$suffix"
  } else {
    $localBin = Split-Path -Parent $dest
    New-Item -ItemType Directory -Path $localBin -Force | Out-Null
  }
  Copy-Item -Path $SourcePath -Destination $dest -Force
  if (-not $IsWindows -and (Get-Command chmod -ErrorAction SilentlyContinue)) {
    & chmod 0755 $dest 2>$null
  }
  if ($env:PATH -notlike "*$localBin*") {
    $env:PATH = "$localBin$([IO.Path]::PathSeparator)$env:PATH"
  }
  $script:CcConnectChanged = $true
  Info "cc-connect installed to $dest"
}

function Install-CcConnectRelease {
  if (-not (Get-Command curl -ErrorAction SilentlyContinue) -and -not (Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue)) {
    return $false
  }
  if (-not (Get-Command tar -ErrorAction SilentlyContinue)) {
    Warn "tar not found; cannot extract cc-connect release asset"
    return $false
  }
  $platform = Get-CcPlatform
  $asset = "cc-connect-$CcConnectLazycatVersion-$platform.tar.gz"
  $url = "$CcConnectLazycatReleaseBase/$asset"
  $tmp = Join-Path ([IO.Path]::GetTempPath()) ("cc-connect-" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Path $tmp -Force | Out-Null
  try {
    $archive = Join-Path $tmp $asset
    Info "download cc-connect release: $asset"
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $archive
    $checksumPath = Join-Path $tmp "$asset.sha256"
    try {
      Invoke-WebRequest -UseBasicParsing -Uri "$url.sha256" -OutFile $checksumPath
      $expected = ((Get-Content $checksumPath -Raw).Trim() -split '\s+')[0]
      $actual = (Get-FileHash -Algorithm SHA256 $archive).Hash.ToLowerInvariant()
      if ($expected.ToLowerInvariant() -ne $actual) { throw "sha256 mismatch for $asset" }
    } catch {
      if ($_.Exception.Message -match "sha256 mismatch") { throw }
    }
    & tar -C $tmp -xzf $archive
    if ($LASTEXITCODE -ne 0) { return $false }
    $bin = if ($platform.StartsWith("windows-")) {
      Join-Path $tmp "cc-connect-$platform.exe"
    } else {
      Join-Path $tmp "cc-connect-$platform"
    }
    if (-not (Test-Path $bin)) {
      $bin = (Get-ChildItem -Path $tmp -Recurse -File -Filter "cc-connect*" | Select-Object -First 1).FullName
    }
    if (-not $bin) { return $false }
    Install-CcConnectBinary $bin
    return $true
  } finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
  }
}

function Install-CcConnectNpm {
  if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    ErrL "npm required to install cc-connect from npm"
    return $false
  }
  & npm i -g cc-connect
  if ($LASTEXITCODE -ne 0) { return $false }
  $script:CcConnectChanged = $true
  return $true
}

function Get-QClawLayout {
  $base = Resolve-InstallPath ($(if ($env:QCLAW_HOME) { $env:QCLAW_HOME } else { Join-Path $script:HomeDir ".qclaw" }))
  $baseConfig = Join-Path $base "qclaw.json"
  $qclawHome = $base
  $stateDir = Get-JsonValue $baseConfig "stateDir"
  if ($stateDir) {
    $qclawHome = Resolve-InstallPath $stateDir
  }
  $stateConfig = Join-Path $qclawHome "qclaw.json"
  $configPath = Get-JsonValue $stateConfig "configPath"
  if (-not $configPath) { $configPath = Get-JsonValue $baseConfig "configPath" }
  if ($configPath) { $configPath = Resolve-InstallPath $configPath } else { $configPath = Join-Path $qclawHome "openclaw.json" }
  $nodeBin = if ($env:QCLAW_NODE_BIN) { $env:QCLAW_NODE_BIN } else { Get-JsonValue $stateConfig "cli.nodeBinary" }
  if (-not $nodeBin) { $nodeBin = Get-JsonValue $baseConfig "cli.nodeBinary" }
  $openclawMjs = if ($env:QCLAW_OPENCLAW_MJS) { $env:QCLAW_OPENCLAW_MJS } else { Get-JsonValue $stateConfig "cli.openclawMjs" }
  if (-not $openclawMjs) { $openclawMjs = Get-JsonValue $baseConfig "cli.openclawMjs" }
  [pscustomobject]@{
    Home = $qclawHome
    ConfigPath = $configPath
    Workspace = Join-Path $qclawHome "workspace-$AgentId"
    NodeBin = $nodeBin
    OpenClawMjs = $openclawMjs
  }
}

function Get-GatewayToken($ConfigPath) {
  if (-not (Test-Path $ConfigPath)) { return "" }
  try {
    $cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    $token = $cfg.gateway.auth.token
    if ($token) { return [string]$token }
  } catch {}
  return ""
}

function ConvertTo-CcPlainJsonValue($Value) {
  if ($null -eq $Value) { return $null }
  if ($Value -is [string]) { return $Value }
  if ($Value -is [System.Collections.IDictionary]) {
    $out = [ordered]@{}
    foreach ($key in $Value.Keys) {
      $out[$key] = ConvertTo-CcPlainJsonValue $Value[$key]
    }
    return $out
  }
  if ($Value -is [pscustomobject]) {
    $out = [ordered]@{}
    foreach ($prop in $Value.PSObject.Properties) {
      $out[$prop.Name] = ConvertTo-CcPlainJsonValue $prop.Value
    }
    return $out
  }
  if ($Value -is [System.Collections.IEnumerable]) {
    $items = @()
    foreach ($item in $Value) {
      $items += ,(ConvertTo-CcPlainJsonValue $item)
    }
    return $items
  }
  return $Value
}

function Read-CcJsonMap($PathValue) {
  if (-not (Test-Path $PathValue)) { return [ordered]@{} }
  try {
    $value = ConvertTo-CcPlainJsonValue (Get-Content $PathValue -Raw | ConvertFrom-Json)
    if ($value -is [System.Collections.IDictionary]) { return $value }
  } catch {}
  return [ordered]@{}
}

function Test-CcMapKey($Map, $Key) {
  return ($Map -is [System.Collections.IDictionary] -and $Map.Contains($Key))
}

function Copy-CcJsonMap($Map) {
  $out = [ordered]@{}
  if ($Map -is [System.Collections.IDictionary]) {
    foreach ($key in $Map.Keys) {
      $out[$key] = $Map[$key]
    }
  }
  return $out
}

function Get-CcMapString($Map, $Key) {
  if (-not (Test-CcMapKey $Map $Key)) { return "" }
  $value = $Map[$Key]
  if ($value -is [string]) { return $value }
  return ""
}

function ConvertTo-CcJsonBoolean($Value) {
  if ($Value -is [bool]) { return $Value }
  if ($Value -is [string]) { return ($Value -match '^(1|true|yes)$') }
  if ($null -eq $Value) { return $false }
  return [bool]$Value
}

function Write-CcJsonIfChanged($PathValue, $Data, $BackupPrefix) {
  $old = if (Test-Path $PathValue) { Get-Content $PathValue -Raw -ErrorAction SilentlyContinue } else { "" }
  $new = ($Data | ConvertTo-Json -Depth 80) + "`n"
  if ($old -eq $new) { return $false }
  $parent = Split-Path -Parent $PathValue
  New-Item -ItemType Directory -Path $parent -Force | Out-Null
  if (Test-Path $PathValue) {
    $backup = Join-Path $parent ("{0}-{1}" -f $BackupPrefix,(Get-Date -Format "yyyyMMdd-HHmmss"))
    Set-Content -Path $backup -Value $old -NoNewline -Encoding UTF8
  }
  Set-Content -Path $PathValue -Value $new -NoNewline -Encoding UTF8
  return $true
}

function Get-QClawIdentityFromWorkspace($Workspace) {
  $text = ""
  foreach ($name in @("IDENTITY.md", "AGENTS.md", "SOUL.md")) {
    $path = Join-Path $Workspace $name
    if (Test-Path $path) {
      try { $text += "`n" + (Get-Content $path -Raw -Encoding UTF8 -ErrorAction SilentlyContinue) } catch {}
    }
  }
  $identity = [ordered]@{}
  foreach ($line in ($text -split "`r?`n")) {
    if ($line.Trim() -match '^-?\s*(\w+)\s*:\s*(.+)$') {
      $label = $Matches[1].ToLowerInvariant()
      $value = $Matches[2].Trim()
      switch ($label) {
        "name" { $identity["name"] = $value }
        "emoji" { $identity["emoji"] = $value }
        "vibe" {
          if (-not (Test-CcMapKey $identity "theme")) { $identity["theme"] = $value }
        }
        "avatar" { $identity["avatar"] = $value }
      }
    }
  }
  if ($identity.Count -gt 0) { return $identity }
  foreach ($pattern in @("\*\*姓名\*\*[：:]\s*([^\n\r ]+)", "姓名[：:]\s*([^\n\r ]+)", "name[：:]\s*([^\n\r ]+)")) {
    $match = [regex]::Match($text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) {
      $identity["name"] = $match.Groups[1].Value.Trim()
      return $identity
    }
  }
  return [ordered]@{}
}

function ConvertTo-QClawIdentityMap($Value) {
  $identity = [ordered]@{}
  if (-not ($Value -is [System.Collections.IDictionary])) { return $identity }
  foreach ($key in @("name", "emoji", "theme", "avatar")) {
    $item = Get-CcMapString $Value $key
    if ($item) { $identity[$key] = $item }
  }
  if (-not (Test-CcMapKey $identity "theme")) {
    $vibe = Get-CcMapString $Value "vibe"
    if ($vibe) { $identity["theme"] = $vibe }
  }
  return $identity
}

function Get-QClawAgentPaths($Layout) {
  $agentsRoot = Join-Path $Layout.Home "agents"
  $agentRoot = Join-Path $agentsRoot $AgentId
  [pscustomobject]@{
    Root = $agentRoot
    AgentDir = Join-Path $agentRoot "agent"
    SessionsDir = Join-Path $agentRoot "sessions"
  }
}

function Ensure-QClawAgentRegistration {
  $layout = Get-QClawLayout
  $paths = Get-QClawAgentPaths $layout
  New-Item -ItemType Directory -Path $layout.Workspace,$paths.AgentDir -Force | Out-Null

  $cfg = Read-CcJsonMap $layout.ConfigPath
  $agents = if (Test-CcMapKey $cfg "agents" -and $cfg["agents"] -is [System.Collections.IDictionary]) {
    $cfg["agents"]
  } else {
    [ordered]@{}
  }
  $cfg["agents"] = $agents

  $items = @()
  if (Test-CcMapKey $agents "list" -and -not ($null -eq $agents["list"])) {
    $items = @($agents["list"])
  }
  $existing = [ordered]@{}
  $existingIndex = -1
  for ($i = 0; $i -lt $items.Count; $i++) {
    if ($items[$i] -is [System.Collections.IDictionary] -and (Get-CcMapString $items[$i] "id") -eq $AgentId) {
      $existing = $items[$i]
      $existingIndex = $i
      break
    }
  }

  $identity = ConvertTo-QClawIdentityMap $(if (Test-CcMapKey $existing "identity") { $existing["identity"] } else { $null })
  if ($identity.Count -eq 0) {
    $identity = Get-QClawIdentityFromWorkspace $layout.Workspace
  }
  if ($AgentId.StartsWith("agent-nako", [StringComparison]::Ordinal)) {
    $legacyAvatars = @(
      "assets/nako-avatar.svg",
      "https://pulseact.lovappen.cn/test/act_ci_build/dlc-promotion/act-gengen/images/e.png"
    )
    if ((Get-CcMapString $identity "avatar") -in $legacyAvatars) {
      $identity["avatar"] = "assets/nako-avatar-head.png"
    }
    foreach ($pair in @(
      @("name", "野木奈子"),
      @("emoji", "🎀"),
      @("theme", "核战后赛博世界专属战斗女仆"),
      @("avatar", "assets/nako-avatar-head.png")
    )) {
      if (-not (Get-CcMapString $identity $pair[0])) { $identity[$pair[0]] = $pair[1] }
    }
  }

  $entry = Copy-CcJsonMap $existing
  $name = Get-CcMapString $existing "name"
  if (-not $name -or $name -eq $AgentId) { $name = Get-CcMapString $identity "name" }
  if (-not $name) {
    $fallback = $DisplayName.Trim()
    if ($fallback.StartsWith("QClaw ", [StringComparison]::Ordinal)) {
      $fallback = $fallback.Substring(6)
    }
    $name = if ($fallback) { $fallback } else { $AgentId }
  }

  $entry["id"] = $AgentId
  $entry["name"] = $name
  $entry["workspace"] = $layout.Workspace
  $entry["agentDir"] = $paths.AgentDir
  if ($identity.Count -gt 0) { $entry["identity"] = $identity }

  $model = Get-CcMapString $existing "model"
  if (-not $model -and (Test-CcMapKey $agents "defaults") -and $agents["defaults"] -is [System.Collections.IDictionary]) {
    $defaults = $agents["defaults"]
    if (Test-CcMapKey $defaults "model" -and $defaults["model"] -is [System.Collections.IDictionary]) {
      $model = Get-CcMapString $defaults["model"] "primary"
    }
  }
  if ($model) { $entry["model"] = $model }

  if ($AgentId.StartsWith("agent-nako", [StringComparison]::Ordinal)) {
    $tools = if (Test-CcMapKey $entry "tools" -and $entry["tools"] -is [System.Collections.IDictionary]) {
      Copy-CcJsonMap $entry["tools"]
    } else {
      [ordered]@{}
    }
    $deny = if (Test-CcMapKey $tools "deny") { @($tools["deny"]) } else { @() }
    foreach ($toolName in @("image_generate", "video_generate", "tts")) {
      if ($deny -notcontains $toolName) { $deny += $toolName }
    }
    $tools["deny"] = $deny
    $entry["tools"] = $tools
  }

  if ($existingIndex -ge 0) {
    $items[$existingIndex] = $entry
  } else {
    $items += ,$entry
  }
  $agents["list"] = $items

  if (Write-CcJsonIfChanged $layout.ConfigPath $cfg "openclaw.json.bak-cc-connect-qclaw") {
    return "changed"
  }
  return "ok"
}

function Ensure-QClawCcSession {
  $layout = Get-QClawLayout
  $paths = Get-QClawAgentPaths $layout
  New-Item -ItemType Directory -Path $paths.SessionsDir -Force | Out-Null

  $sessionLabel = "cc-connect 飞书/微信"
  $sessionsPath = Join-Path $paths.SessionsDir "sessions.json"
  $sessions = Read-CcJsonMap $sessionsPath
  $key = "agent:${AgentId}:session-cc-connect"
  $entry = if (Test-CcMapKey $sessions $key -and $sessions[$key] -is [System.Collections.IDictionary]) {
    Copy-CcJsonMap $sessions[$key]
  } else {
    [ordered]@{}
  }

  $resetExisting = $false
  if ($entry.Count -gt 0 -and $env:QCLAW_PERSONA_CHANGED -eq "1") {
    $oldSessionFile = Get-CcMapString $entry "sessionFile"
    if ($oldSessionFile -and (Test-Path $oldSessionFile)) {
      $backup = "$oldSessionFile.bak-cc-connect-stale-$(Get-Date -Format "yyyyMMdd-HHmmss")"
      Move-Item -Path $oldSessionFile -Destination $backup -Force -ErrorAction SilentlyContinue
    }
    $entry = [ordered]@{}
    $resetExisting = $true
  }

  foreach ($otherKey in @($sessions.Keys)) {
    if ($otherKey -eq $key -or -not ([string]$otherKey).StartsWith("agent:${AgentId}:", [StringComparison]::Ordinal)) {
      continue
    }
    $other = $sessions[$otherKey]
    if (-not ($other -is [System.Collections.IDictionary])) { continue }
    $origin = if (Test-CcMapKey $other "origin" -and $other["origin"] -is [System.Collections.IDictionary]) { $other["origin"] } else { [ordered]@{} }
    $delivery = if (Test-CcMapKey $other "deliveryContext" -and $other["deliveryContext"] -is [System.Collections.IDictionary]) { $other["deliveryContext"] } else { [ordered]@{} }
    $staleCc = (
      (Get-CcMapString $other "label") -in @("ACP", "cc-connect", "cc-connect 飞书/微信") -or
      (Get-CcMapString $origin "provider") -eq "acp" -or
      (Get-CcMapString $origin "surface") -eq "cc-connect" -or
      (Get-CcMapString $delivery "channel") -eq "cc-connect" -or
      (Get-CcMapString $other "lastChannel") -eq "cc-connect"
    )
    if ($staleCc) {
      $sessions.Remove($otherKey)
    }
  }

  $sessionId = Get-CcMapString $entry "sessionId"
  if (-not $sessionId) { $sessionId = [guid]::NewGuid().ToString() }
  $sessionFile = Get-CcMapString $entry "sessionFile"
  if (-not $sessionFile) { $sessionFile = Join-Path $paths.SessionsDir "$sessionId.jsonl" }
  try { $updatedAt = [int64]$entry["updatedAt"] } catch { $updatedAt = 0 }
  if ($updatedAt -le 0) { $updatedAt = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }

  $entry["sessionId"] = $sessionId
  $entry["updatedAt"] = $updatedAt
  $entry["label"] = $sessionLabel
  $entry["systemSent"] = ConvertTo-CcJsonBoolean $(if (Test-CcMapKey $entry "systemSent") { $entry["systemSent"] } else { $false })
  $entry["abortedLastRun"] = ConvertTo-CcJsonBoolean $(if (Test-CcMapKey $entry "abortedLastRun") { $entry["abortedLastRun"] } else { $false })
  $entry["chatType"] = $(if (Get-CcMapString $entry "chatType") { Get-CcMapString $entry "chatType" } else { "direct" })
  $entry["deliveryContext"] = [ordered]@{ channel = "webchat" }
  $entry["lastChannel"] = "webchat"
  $entry["origin"] = [ordered]@{
    label = $sessionLabel
    provider = "webchat"
    surface = "webchat"
    chatType = "direct"
  }
  $entry["sessionFile"] = $sessionFile
  $sessions[$key] = $entry

  New-Item -ItemType Directory -Path (Split-Path -Parent $sessionFile) -Force | Out-Null
  if (-not (Test-Path $sessionFile)) {
    $header = [ordered]@{
      type = "session"
      version = 3
      id = $sessionId
      timestamp = [DateTimeOffset]::UtcNow.ToString("o").Replace("+00:00", "Z")
      cwd = $layout.Workspace
    }
    Set-Content -Path $sessionFile -Value (($header | ConvertTo-Json -Compress -Depth 20) + "`n") -NoNewline -Encoding UTF8
  }

  [void](Write-CcJsonIfChanged $sessionsPath $sessions "sessions.json.bak-cc-connect")
  if ($resetExisting) { return "reset" }
  return "ok"
}

function Initialize-QClawRuntimeForCcConnect {
  if ($Runtime -ne "qclaw") { return }
  $registrationStatus = Ensure-QClawAgentRegistration
  if ($registrationStatus -eq "changed") {
    Info "QClaw agent registered: $AgentId"
    $script:CcConnectChanged = $true
  }
  $sessionStatus = Ensure-QClawCcSession
  if ($sessionStatus -eq "reset" -or $registrationStatus -eq "changed" -or $env:QCLAW_PERSONA_CHANGED -eq "1") {
    Remove-CcConnectSessions
    $script:CcConnectChanged = $true
  }
}

function New-AgentSection($RuntimeName) {
  $homeDir = $script:HomeDir
  $ccData = Join-Path $homeDir ".cc-connect"
  $ccEnv = [ordered]@{
    CC_CONNECT_DATA_DIR = $ccData
    CC_CONNECT_API_DATA_DIR = $ccData
    CC_CONNECT_SESSION_DIR = (Join-Path $ccData "sessions")
    CC_CONNECT_CONFIG = (Join-Path $ccData "config.toml")
  }
  if ($RuntimeName -eq "hermes") {
    $hermesHome = Resolve-InstallPath ($(if ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-Path $homeDir ".hermes" }))
    $hermesCmd = if ($env:HERMES_BIN) { $env:HERMES_BIN } else { (Get-Command hermes -ErrorAction SilentlyContinue).Source }
    if (-not $hermesCmd) { throw "Hermes runtime selected but hermes command was not found" }
    $workspace = Join-Path $hermesHome "workspace/$AgentId"
    $envMap = [ordered]@{
      HOME = $homeDir
      HERMES_HOME = $hermesHome
      PATH = $env:PATH
    }
    foreach ($entry in $ccEnv.GetEnumerator()) { $envMap[$entry.Key] = $entry.Value }
    $envMap["NAKO_OUTPUT_MODE"] = "acp"
    $envMap["NAKO_CCCONNECT_PROJECT"] = $CcProjectId
    $envMap["NAKO_AGENT_WORKSPACE"] = $workspace
    $envMap["NAKO_SKILLS_DIR"] = Join-Path $hermesHome "skills/nako"
    $envMap["NAKO_MEDIA_HOME"] = Join-Path $hermesHome "media"
    $envMap["NAKO_AGENT_RUNTIME"] = "hermes"
    return [pscustomobject]@{ WorkDir = $workspace; Command = $hermesCmd; Args = @("acp"); Env = $envMap }
  }
  if ($RuntimeName -eq "qclaw") {
    $layout = Get-QClawLayout
    if (-not $layout.NodeBin -or -not $layout.OpenClawMjs) {
      throw "QClaw runtime selected but qclaw.json does not provide cli.nodeBinary/openclawMjs"
    }
    New-Item -ItemType Directory -Path $layout.Workspace -Force | Out-Null
    $envMap = [ordered]@{
      HOME = $homeDir
      QCLAW_HOME = $layout.Home
      OPENCLAW_STATE_DIR = $layout.Home
      OPENCLAW_CONFIG = $layout.ConfigPath
      OPENCLAW_CONFIG_PATH = $layout.ConfigPath
      PATH = $env:PATH
    }
    foreach ($entry in $ccEnv.GetEnumerator()) { $envMap[$entry.Key] = $entry.Value }
    $envMap["OPENCLAW_OUTPUT_MODE"] = "acp"
    $envMap["OPENCLAW_CCCONNECT_PROJECT"] = $CcProjectId
    $envMap["NAKO_OUTPUT_MODE"] = "acp"
    $envMap["NAKO_CCCONNECT_PROJECT"] = $CcProjectId
    $envMap["NAKO_AGENT_WORKSPACE"] = $layout.Workspace
    $envMap["NAKO_SKILLS_DIR"] = Join-Path $layout.Home "skills"
    $envMap["NAKO_MEDIA_HOME"] = Join-Path $layout.Home "media"
    $envMap["NAKO_AGENT_RUNTIME"] = "qclaw"
    $token = Get-GatewayToken $layout.ConfigPath
    if ($token) { $envMap["OPENCLAW_GATEWAY_TOKEN"] = $token }
    return [pscustomobject]@{
      WorkDir = $layout.Workspace
      Command = $layout.NodeBin
      Args = @($layout.OpenClawMjs, "acp", "--session", "agent:${AgentId}:session-cc-connect")
      Env = $envMap
    }
  }

  $openclawHome = Join-Path $homeDir ".openclaw"
  $workspace = Join-Path $openclawHome "workspace/$AgentId"
  $openclawCmd = Resolve-OpenClawCommand
  $envMap = [ordered]@{
    HOME = $homeDir
    OPENCLAW_HOME = $openclawHome
    PATH = $env:PATH
  }
  foreach ($entry in $ccEnv.GetEnumerator()) { $envMap[$entry.Key] = $entry.Value }
  $envMap["OPENCLAW_OUTPUT_MODE"] = "acp"
  $envMap["OPENCLAW_CCCONNECT_PROJECT"] = $CcProjectId
  $envMap["NAKO_OUTPUT_MODE"] = "acp"
  $envMap["NAKO_CCCONNECT_PROJECT"] = $CcProjectId
  $envMap["NAKO_AGENT_WORKSPACE"] = $workspace
  $envMap["NAKO_SKILLS_DIR"] = Join-Path $openclawHome "skills"
  $envMap["NAKO_MEDIA_HOME"] = Join-Path $openclawHome "media"
  $envMap["NAKO_AGENT_RUNTIME"] = "openclaw"
  $token = Get-GatewayToken (Join-Path $openclawHome "openclaw.json")
  if ($token) { $envMap["OPENCLAW_GATEWAY_TOKEN"] = $token }
  [pscustomobject]@{ WorkDir = $openclawHome; Command = $openclawCmd; Args = @("acp", "--session", "agent:${AgentId}:main"); Env = $envMap }
}

function Write-CcLogTail($PathValue, $Label) {
  if (-not (Test-Path $PathValue)) { return }
  $lines = @(Get-Content $PathValue -Tail 40 -ErrorAction SilentlyContinue)
  if ($lines.Count -eq 0) { return }
  ErrL "$Label ($PathValue):"
  foreach ($line in $lines) {
    Write-Host $line -ForegroundColor Red
  }
}

function Get-CcApiSocketPaths {
  @(
    (Join-Path $script:CcHome "run/api.sock"),
    (Join-Path $script:CcHome ".cc-connect/run/api.sock")
  )
}

function Test-CcApiSocketReady {
  foreach ($socketPath in (Get-CcApiSocketPaths)) {
    if (Test-Path $socketPath) { return $true }
  }
  return $false
}

function Write-CcConnectStartDiagnostics {
  ErrL "cc-connect API socket not ready."
  ErrL "expected socket paths:"
  foreach ($socketPath in (Get-CcApiSocketPaths)) {
    ErrL "  - $socketPath"
  }
  $statusLog = Join-Path $script:CcHome "daemon-status.log"
  try {
    & cc-connect daemon status --work-dir $script:CcHome > $statusLog 2>&1
  } catch {}
  Write-CcLogTail $statusLog "daemon status"
  Write-CcLogTail (Join-Path $script:CcHome "cc-connect.err.log") "stderr"
  Write-CcLogTail (Join-Path $script:CcHome "cc-connect.log") "stdout"
}

function Wait-CcConnectApiSocket {
  $timeout = 15
  if ($env:CC_CONNECT_SOCKET_TIMEOUT -and [int]::TryParse($env:CC_CONNECT_SOCKET_TIMEOUT, [ref]$timeout)) {}
  for ($i = 0; $i -lt $timeout; $i++) {
    if (Test-CcApiSocketReady) { return $true }
    Start-Sleep -Seconds 1
  }
  Write-CcConnectStartDiagnostics
  return $false
}

function ConvertTo-CcProcessArgument($Value) {
  $text = [string]$Value
  if ($text -eq "") { return '""' }
  if ($text -notmatch '[\s"]') { return $text }
  $quoted = '"'
  $slashes = 0
  foreach ($ch in $text.ToCharArray()) {
    if ($ch -eq '\') {
      $slashes += 1
      continue
    }
    if ($ch -eq '"') {
      $quoted += ('\' * ($slashes * 2 + 1)) + '"'
      $slashes = 0
      continue
    }
    if ($slashes -gt 0) {
      $quoted += ('\' * $slashes)
      $slashes = 0
    }
    $quoted += $ch
  }
  if ($slashes -gt 0) {
    $quoted += ('\' * ($slashes * 2))
  }
  return $quoted + '"'
}

function Add-CcProcessArguments($StartInfo, [string[]]$Arguments) {
  $argList = $null
  try { $argList = $StartInfo.ArgumentList } catch {}
  if ($null -ne $argList) {
    foreach ($argument in $Arguments) {
      [void]$argList.Add([string]$argument)
    }
    return
  }
  $StartInfo.Arguments = (($Arguments | ForEach-Object { ConvertTo-CcProcessArgument $_ }) -join " ")
}

function Start-CcRuntimeCheckProcess($Agent, $Stdout, $Stderr) {
  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = $Agent.Command
  $psi.WorkingDirectory = $Agent.WorkDir
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  Add-CcProcessArguments $psi $Agent.Args
  foreach ($entry in $Agent.Env.GetEnumerator()) {
    $psi.Environment[$entry.Key] = [string]$entry.Value
  }
  $proc = [System.Diagnostics.Process]::Start($psi)
  $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
  $stderrTask = $proc.StandardError.ReadToEndAsync()
  [pscustomobject]@{
    Process = $proc
    StdoutTask = $stdoutTask
    StderrTask = $stderrTask
    StdoutPath = $Stdout
    StderrPath = $Stderr
  }
}

function Save-CcRuntimeCheckOutput($RuntimeProcess) {
  try {
    $stdout = $RuntimeProcess.StdoutTask.GetAwaiter().GetResult()
    $stderr = $RuntimeProcess.StderrTask.GetAwaiter().GetResult()
    Set-Content -Path $RuntimeProcess.StdoutPath -Value $stdout -NoNewline -Encoding UTF8
    Set-Content -Path $RuntimeProcess.StderrPath -Value $stderr -NoNewline -Encoding UTF8
  } catch {}
}

function Get-CcRuntimePreflightTimeoutMs {
  $timeout = 2000
  if ($Runtime -eq "qclaw") { $timeout = 8000 }
  if ($env:CC_CONNECT_RUNTIME_CHECK_TIMEOUT_MS) {
    $parsed = 0
    if ([int]::TryParse($env:CC_CONNECT_RUNTIME_CHECK_TIMEOUT_MS, [ref]$parsed) -and $parsed -gt 0) {
      $timeout = $parsed
    }
  }
  return $timeout
}

function Test-CcAgentRuntimeLaunch {
  $agent = New-AgentSection $Runtime
  $label = switch ($Runtime) {
    "hermes" { "Hermes" }
    "qclaw" { "QClaw" }
    default { "OpenClaw" }
  }
  New-Item -ItemType Directory -Path $agent.WorkDir -Force | Out-Null
  New-Item -ItemType Directory -Path $script:CcHome -Force | Out-Null
  $stdout = Join-Path $script:CcHome ("runtime-check-{0}-{1}.out.log" -f $AgentId,$Runtime)
  $stderr = Join-Path $script:CcHome ("runtime-check-{0}-{1}.err.log" -f $AgentId,$Runtime)
  Remove-Item -Force $stdout,$stderr -ErrorAction SilentlyContinue

  try {
    $runtimeProcess = Start-CcRuntimeCheckProcess $agent $stdout $stderr
    $proc = $runtimeProcess.Process
  } catch {
    ErrL "$label runtime failed during setup preflight: $($_.Exception.Message)"
    throw
  }

  $timeoutMs = Get-CcRuntimePreflightTimeoutMs
  if (-not $proc.WaitForExit($timeoutMs)) {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    Save-CcRuntimeCheckOutput $runtimeProcess
    Info "$label runtime preflight stayed alive for ${timeoutMs}ms"
    return
  }
  Save-CcRuntimeCheckOutput $runtimeProcess
  if ($proc.ExitCode -eq 0) {
    Info "$label runtime preflight exited cleanly"
    return
  }

  ErrL "$label runtime failed during setup preflight (exit $($proc.ExitCode))."
  Write-CcLogTail $stderr "stderr"
  Write-CcLogTail $stdout "stdout"
  ErrL "Fix the runtime error above, then rerun scripts/cc-connect-setup.ps1 -AgentId $AgentId -Runtime $Runtime"
  throw "$label runtime failed during setup preflight"
}

function Update-CcConnectConfig {
  New-Item -ItemType Directory -Path (Split-Path -Parent $script:CcConfig) -Force | Out-Null
  $agent = New-AgentSection $Runtime
  $agentSection = @(
    "[projects.agent]",
    'type = "acp"',
    "",
    "[projects.agent.options]",
    "work_dir = $(ConvertTo-TomlString $agent.WorkDir)",
    "command = $(ConvertTo-TomlString $agent.Command)",
    "args = $(ConvertTo-TomlArray $agent.Args)",
    "display_name = $(ConvertTo-TomlString $DisplayName)",
    "env = $(ConvertTo-TomlInlineTable $agent.Env)",
    ""
  ) -join "`n"

  if (Test-Path $script:CcConfig) {
    $text = Get-Content $script:CcConfig -Raw
  } else {
    $text = "language = `"en`"`n`n[stream_preview]`nenabled = true`n`n[display]`ntool_messages = false`n`n[log]`nlevel = `"info`"`n"
  }
  $original = $text
  $text = Set-GlobalTomlOption $text "stream_preview" "enabled" "true"
  $text = Set-GlobalTomlOption $text "display" "tool_messages" "false"

  $parts = [regex]::Split($text, "(?m)(?=^\[\[projects\]\]\s*$)")
  $kept = New-Object System.Collections.Generic.List[string]
  $found = $false
  foreach ($part in $parts) {
    if (-not $part.StartsWith("[[projects]]")) {
      $kept.Add($part)
      continue
    }
    $nameMatch = [regex]::Match($part, '(?m)^name\s*=\s*"([^"]+)"\s*$')
    $projectName = if ($nameMatch.Success) { $nameMatch.Groups[1].Value } else { "" }
    $runtimeMatch = [regex]::Match($part, 'NAKO_AGENT_RUNTIME\s*=\s*"([^"]+)"')
    $projectRuntime = if ($runtimeMatch.Success) { $runtimeMatch.Groups[1].Value } else { "" }
    $isTarget = $projectName -eq $CcProjectId
    $isLegacySameRuntime = (
      $CcProjectId -ne $AgentId -and
      $projectName -eq $AgentId -and
      $projectRuntime -eq $Runtime
    )
    if (-not $isTarget -and -not $isLegacySameRuntime) {
      $kept.Add($part)
      continue
    }
    $found = $true
    $platformMatch = [regex]::Match($part, "(?m)^\[\[projects\.platforms\]\]\s*$")
    $platforms = if ($platformMatch.Success) { $part.Substring($platformMatch.Index).TrimStart("`r","`n") } else { "" }
    $newPart = "[[projects]]`nname = $(ConvertTo-TomlString $CcProjectId)`n`n$agentSection"
    if ($platforms) { $newPart += "`n$platforms" }
    $kept.Add($newPart)
  }
  if (-not $found) {
    if ($kept.Count -gt 0 -and $kept[$kept.Count - 1] -and -not $kept[$kept.Count - 1].EndsWith("`n")) {
      $kept[$kept.Count - 1] += "`n"
    }
    $kept.Add("`n[[projects]]`nname = $(ConvertTo-TomlString $CcProjectId)`n`n$agentSection")
  }
  $newText = ($kept -join "")
  if ($newText -ne $original -or -not (Test-Path $script:CcConfig)) {
    if (Test-Path $script:CcConfig) {
      $backup = Join-Path (Split-Path -Parent $script:CcConfig) ("config.toml.bak-runtime-{0}-{1}-{2}" -f $CcProjectId,$Runtime,(Get-Date -Format "yyyyMMdd-HHmmss"))
      Set-Content -Path $backup -Value $original -NoNewline -Encoding UTF8
    }
    Set-Content -Path $script:CcConfig -Value $newText -NoNewline -Encoding UTF8
    $script:CcConnectChanged = $true
  }
}

function Remove-CcConnectProject {
  if (-not (Test-Path $script:CcConfig)) { return $false }
  $text = Get-Content $script:CcConfig -Raw
  $parts = [regex]::Split($text, "(?m)(?=^\[\[projects\]\]\s*$)")
  $kept = New-Object System.Collections.Generic.List[string]
  $removed = $false
  foreach ($part in $parts) {
    if (-not $part.StartsWith("[[projects]]")) { $kept.Add($part); continue }
    $nameMatch = [regex]::Match($part, '(?m)^name\s*=\s*"([^"]+)"\s*$')
    if ($nameMatch.Success -and $nameMatch.Groups[1].Value -eq $CcProjectId) {
      $removed = $true
      continue
    }
    $kept.Add($part)
  }
  if (-not $removed) { return $false }
  $backup = Join-Path (Split-Path -Parent $script:CcConfig) ("config.toml.bak-uninstall-{0}-{1}" -f $CcProjectId,(Get-Date -Format "yyyyMMdd-HHmmss"))
  Set-Content -Path $backup -Value $text -NoNewline -Encoding UTF8
  Set-Content -Path $script:CcConfig -Value (($kept -join "").TrimEnd() + "`n") -NoNewline -Encoding UTF8
  return $true
}

function Disable-CcBlockingProjects {
  if (-not (Test-Path $script:CcConfig)) { return @() }
  $text = Get-Content $script:CcConfig -Raw
  $parts = [regex]::Split($text, "(?m)(?=^\[\[projects\]\]\s*$)")
  $kept = New-Object System.Collections.Generic.List[string]
  $disabled = New-Object System.Collections.Generic.List[string]
  $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue

  foreach ($part in $parts) {
    if (-not $part.StartsWith("[[projects]]")) {
      $kept.Add($part)
      continue
    }
    $nameMatch = [regex]::Match($part, '(?m)^name\s*=\s*"([^"]+)"\s*$')
    $name = if ($nameMatch.Success) { $nameMatch.Groups[1].Value } else { "" }
    if ($name -eq $CcProjectId) {
      $kept.Add($part)
      continue
    }
    $typeMatch = [regex]::Match($part, '(?ms)^\[projects\.agent\]\s*\n.*?^type\s*=\s*"([^"]+)"\s*$')
    $agentType = if ($typeMatch.Success) { $typeMatch.Groups[1].Value } else { "" }
    if ($agentType -ne "claudecode") {
      $kept.Add($part)
      continue
    }

    $commandMatch = [regex]::Match($part, '(?m)^command\s*=\s*"([^"]+)"\s*$')
    $commandValue = if ($commandMatch.Success) { $commandMatch.Groups[1].Value } else { "" }
    $missing = $false
    if ($commandValue) {
      $expanded = [Environment]::ExpandEnvironmentVariables($commandValue)
      if ($expanded.StartsWith("~\")) { $expanded = Join-Path $script:HomeDir $expanded.Substring(2) }
      elseif ($expanded.StartsWith("~/")) { $expanded = Join-Path $script:HomeDir $expanded.Substring(2) }
      if ([IO.Path]::IsPathRooted($expanded) -and -not (Test-Path $expanded)) { $missing = $true }
      elseif (-not [IO.Path]::IsPathRooted($expanded) -and -not (Get-Command $expanded -ErrorAction SilentlyContinue)) { $missing = $true }
    } elseif (-not $claudeCmd) {
      $missing = $true
    }

    if ($missing) {
      $disabled.Add($(if ($name) { $name } else { "<unnamed>" }))
      continue
    }
    $kept.Add($part)
  }

  if ($disabled.Count -gt 0) {
    $backup = Join-Path (Split-Path -Parent $script:CcConfig) ("config.toml.bak-disabled-blocking-projects-{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
    Set-Content -Path $backup -Value $text -NoNewline -Encoding UTF8
    Set-Content -Path $script:CcConfig -Value ((($kept -join "").TrimEnd()) + "`n") -NoNewline -Encoding UTF8
    $script:CcConnectChanged = $true
    Warn "disabled cc-connect projects that block startup: $($disabled -join ', ')"
    Dim "  backup: $backup"
  }
  return @($disabled)
}

function Remove-CcConnectSessions {
  $sessionDir = Join-Path $script:CcHome "sessions"
  if (-not (Test-Path $sessionDir)) { return }
  Get-ChildItem -Path $sessionDir -Filter "$CcProjectId`_*.json" -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
}

function Get-CcConnectPids {
  @(Get-Process -Name "cc-connect" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
}

function Stop-CcConnectProcesses {
  $pids = Get-CcConnectPids
  if ($pids.Count -eq 0) { return }
  Warn "stopping cc-connect processes: $($pids -join ' ')"
  foreach ($pidValue in $pids) {
    Stop-Process -Id $pidValue -Force -ErrorAction SilentlyContinue
  }
}

function Test-CcConnectHasStartableProjects {
  if (-not (Test-Path $script:CcConfig)) { return $false }
  $text = Get-Content $script:CcConfig -Raw
  return [regex]::IsMatch($text, "(?m)^\[\[projects\.platforms\]\]\s*$")
}

function Ensure-CcConnectRunning {
  param([string]$Reason = "cc-connect config changed")
  if ($script:CcConnectChanged) {
    Stop-CcConnectProcesses
    $script:CcConnectChanged = $false
  }
  if (-not (Test-CcConnectHasStartableProjects)) {
    & cc-connect daemon stop --work-dir $script:CcHome *> $null
    Stop-CcConnectProcesses
    Dim "cc-connect has no bound platform yet; skipping start"
    return
  }
  if ((Get-CcConnectPids).Count -gt 0) {
    if (Wait-CcConnectApiSocket) {
      Info "cc-connect is already running"
      return
    }
    $oldPids = Get-CcConnectPids
    Warn "cc-connect process exists but API socket is not ready; restarting: $($oldPids -join ' ')"
    foreach ($pidValue in $oldPids) {
      Stop-Process -Id $pidValue -Force -ErrorAction SilentlyContinue
    }
  }
  & cc-connect daemon install --work-dir $script:CcHome --force *> $null
  $installRc = $LASTEXITCODE
  & cc-connect daemon start --work-dir $script:CcHome *> $null
  $startRc = $LASTEXITCODE
  if ($installRc -eq 0 -and $startRc -eq 0) {
    Info "cc-connect daemon started"
    if (-not (Wait-CcConnectApiSocket)) {
      throw "cc-connect API socket not ready after daemon start"
    }
    return
  }
  $cmd = (Get-Command cc-connect -ErrorAction Stop).Source
  $stdout = Join-Path $script:CcHome "cc-connect.log"
  $stderr = Join-Path $script:CcHome "cc-connect.err.log"
  $proc = Start-Process -FilePath $cmd -WorkingDirectory $script:CcHome -RedirectStandardOutput $stdout -RedirectStandardError $stderr -WindowStyle Hidden -PassThru
  Info "cc-connect started in background (PID $($proc.Id)); log: $stdout"
  if (-not (Wait-CcConnectApiSocket)) {
    throw "cc-connect API socket not ready after start"
  }
}

function Test-CcPlatformConfigured($Platform) {
  if (-not (Test-Path $script:CcConfig)) { return $false }
  $text = Get-Content $script:CcConfig -Raw
  $parts = [regex]::Split($text, "(?m)(?=^\[\[projects\]\]\s*$)")
  foreach ($part in $parts) {
    if (-not $part.StartsWith("[[projects]]")) { continue }
    if ($part -notmatch "(?m)^name\s*=\s*`"$([regex]::Escape($CcProjectId))`"\s*$") { continue }
    if ($part -match "(?m)^type\s*=\s*`"$([regex]::Escape($Platform))`"\s*$") { return $true }
  }
  return $false
}

function Remove-CcPlatformBinding($Platform) {
  if (-not (Test-Path $script:CcConfig)) { return $false }
  $text = Get-Content $script:CcConfig -Raw
  $targets = if ($Platform -eq "feishu") { @("feishu", "lark") } else { @($Platform) }
  $parts = [regex]::Split($text, "(?m)(?=^\[\[projects\]\]\s*$)")
  $changed = $false
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($part in $parts) {
    if (-not $part.StartsWith("[[projects]]")) {
      $out.Add($part)
      continue
    }
    if ($part -notmatch "(?m)^name\s*=\s*`"$([regex]::Escape($CcProjectId))`"\s*$") {
      $out.Add($part)
      continue
    }

    $blocks = [regex]::Split($part, "(?m)(?=^\[\[projects\.platforms\]\]\s*$)")
    $fixed = New-Object System.Collections.Generic.List[string]
    $fixed.Add($blocks[0])
    for ($i = 1; $i -lt $blocks.Count; $i++) {
      $block = $blocks[$i]
      $typeMatch = [regex]::Match($block, '(?m)^type\s*=\s*"([^"]+)"\s*$')
      $blockType = if ($typeMatch.Success) { $typeMatch.Groups[1].Value } else { "" }
      if ($targets -contains $blockType) {
        $changed = $true
        continue
      }
      $fixed.Add($block)
    }
    $out.Add(($fixed -join ""))
  }
  if ($changed) {
    $backup = Join-Path (Split-Path -Parent $script:CcConfig) ("config.toml.bak-rebind-{0}-{1}-{2}" -f $CcProjectId,$Platform,(Get-Date -Format "yyyyMMdd-HHmmss"))
    Set-Content -Path $backup -Value $text -NoNewline -Encoding UTF8
    Set-Content -Path $script:CcConfig -Value ((($out -join "").TrimEnd()) + "`n") -NoNewline -Encoding UTF8
    $script:CcConnectChanged = $true
  }
  return $changed
}

function Normalize-CcPlatformOptions {
  if (-not (Test-Path $script:CcConfig)) { return $false }
  $text = Get-Content $script:CcConfig -Raw
  $parts = [regex]::Split($text, "(?m)(?=^\[\[projects\]\]\s*$)")
  $changed = $false
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($part in $parts) {
    if (-not $part.StartsWith("[[projects]]") -or $part -notmatch "(?m)^name\s*=\s*`"$([regex]::Escape($CcProjectId))`"\s*$") {
      $out.Add($part)
      continue
    }
    $blocks = [regex]::Split($part, "(?m)(?=^\[\[projects\.platforms\]\]\s*$)")
    $fixed = New-Object System.Collections.Generic.List[string]
    $fixed.Add($blocks[0])
    for ($i = 1; $i -lt $blocks.Count; $i++) {
      $block = $blocks[$i]
      if ($block -match '(?m)^type\s*=\s*"(feishu|lark)"\s*$') {
        $newBlock = [regex]::Replace($block, "(?m)^(enable_feishu_card|reply_to_trigger)\s*=.*\r?\n?", "").TrimEnd()
        if ($newBlock -notmatch "\[projects\.platforms\.options\]") {
          $newBlock += "`n`n[projects.platforms.options]"
        }
        $newBlock += "`nenable_feishu_card = false`nreply_to_trigger = false`n"
        if ($newBlock -ne $block) { $changed = $true }
        $block = $newBlock
      }
      $fixed.Add($block)
    }
    $out.Add(($fixed -join ""))
  }
  if ($changed) {
    $backup = Join-Path (Split-Path -Parent $script:CcConfig) ("config.toml.bak-platform-options-{0}-{1}" -f $CcProjectId,(Get-Date -Format "yyyyMMdd-HHmmss"))
    Set-Content -Path $backup -Value $text -NoNewline -Encoding UTF8
    Set-Content -Path $script:CcConfig -Value ($out -join "") -NoNewline -Encoding UTF8
    $script:CcConnectChanged = $true
  }
  return $changed
}

function Test-CcIsWindows {
  $var = Get-Variable IsWindows -ErrorAction SilentlyContinue
  if ($var) { return [bool]$var.Value }
  return [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
}

function Test-CcIsMacOS {
  $var = Get-Variable IsMacOS -ErrorAction SilentlyContinue
  if ($var) { return [bool]$var.Value }
  try {
    return [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
      [System.Runtime.InteropServices.OSPlatform]::OSX
    )
  } catch {
    return $false
  }
}

function Open-CcQrImage($Path, $Label) {
  try {
    if (Test-CcIsWindows) {
      Start-Process -FilePath $Path | Out-Null
    } elseif (Test-CcIsMacOS) {
      & open $Path *> $null
    } else {
      $opener = Get-Command xdg-open -ErrorAction SilentlyContinue
      if ($opener) {
        Start-Process -FilePath $opener.Source -ArgumentList @($Path) | Out-Null
      } else {
        Warn "QR image saved but no image opener was found: $Path"
        return
      }
    }
    Info "$Label QR image opened: $Path"
  } catch {
    Warn "QR image saved but could not be opened automatically: $Path"
  }
}

function Invoke-CcPlatformSetupWithQr($Platform, $Label, $QrPath) {
  $cmd = (Get-Command cc-connect -ErrorAction Stop).Source
  $args = @($Platform, "setup", "--project", $CcProjectId, "--timeout", "600", "--qr-image", $QrPath)
  if ($Platform -eq "weixin") {
    $args += "--set-allow-from-empty"
  }
  $proc = Start-Process -FilePath $cmd -ArgumentList $args -NoNewWindow -PassThru

  $opened = $false
  while (-not $proc.HasExited) {
    if (-not $opened -and (Test-Path $QrPath)) {
      $item = Get-Item $QrPath -ErrorAction SilentlyContinue
      if ($item -and $item.Length -gt 0) {
        Open-CcQrImage $QrPath $Label
        $opened = $true
      }
    }
    Start-Sleep -Milliseconds 500
  }
  $proc.WaitForExit()

  if (-not $opened -and (Test-Path $QrPath)) {
    $item = Get-Item $QrPath -ErrorAction SilentlyContinue
    if ($item -and $item.Length -gt 0) {
      Open-CcQrImage $QrPath $Label
    }
  }
  return $proc.ExitCode
}

function Setup-CcPlatform($Platform, $Label) {
  if (Test-CcPlatformConfigured $Platform) {
    if ($NonInteractive) {
      Info "$Label already configured"
      if ($Platform -eq "feishu") { [void](Normalize-CcPlatformOptions) }
      return
    }
    if (-not (Confirm-Choice "$Label is already configured. Unbind and rescan QR?" "n")) {
      Info "$Label already configured"
      if ($Platform -eq "feishu") { [void](Normalize-CcPlatformOptions) }
      return
    }
    if (Remove-CcPlatformBinding $Platform) {
      Warn "$Label unbound; starting QR onboarding"
    } else {
      Warn "$Label unbind failed; skipping QR onboarding"
      return
    }
  }
  if ($NonInteractive) {
    Dim "missing $Label; run manually: cc-connect $Platform setup --project $CcProjectId"
    return
  }
  Warn "$Label is not configured; starting QR onboarding"
  $qrDir = Join-Path $script:CcHome "qr"
  New-Item -ItemType Directory -Path $qrDir -Force | Out-Null
  $qrPath = Join-Path $qrDir "$CcProjectId-$Platform.png"
  Remove-Item -Force $qrPath -ErrorAction SilentlyContinue
  Dim "QR image will be saved to: $qrPath"
  $rc = Invoke-CcPlatformSetupWithQr $Platform $Label $qrPath
  if ($rc -eq 0) {
    $script:CcConnectChanged = $true
    if ($Platform -eq "feishu") { [void](Normalize-CcPlatformOptions) }
    Ensure-CcConnectRunning "$Label onboarding finished"
  } else {
    Warn "$Label onboarding failed or timed out"
  }
}

function Sync-HermesFeishuEnv {
  if ($Runtime -ne "hermes" -or -not (Test-Path $script:CcConfig)) { return }
  $text = Get-Content $script:CcConfig -Raw
  $appId = ""; $appSecret = ""
  $parts = [regex]::Split($text, "(?m)(?=^\[\[projects\]\]\s*$)")
  foreach ($part in $parts) {
    if (-not $part.StartsWith("[[projects]]") -or $part -notmatch "(?m)^name\s*=\s*`"$([regex]::Escape($CcProjectId))`"\s*$") { continue }
    $blocks = [regex]::Split($part, "(?m)(?=^\[\[projects\.platforms\]\]\s*$)")
    foreach ($block in $blocks) {
      if ($block -notmatch '(?m)^type\s*=\s*"(feishu|lark)"\s*$') { continue }
      $idMatch = [regex]::Match($block, '(?m)^app_id\s*=\s*"([^"]+)"\s*$')
      $secretMatch = [regex]::Match($block, '(?m)^app_secret\s*=\s*"([^"]+)"\s*$')
      if ($idMatch.Success -and $secretMatch.Success) {
        $appId = $idMatch.Groups[1].Value
        $appSecret = $secretMatch.Groups[1].Value
        break
      }
    }
  }
  if (-not $appId -or -not $appSecret) { return }
  $hermesHome = Resolve-InstallPath ($(if ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-Path $script:HomeDir ".hermes" }))
  $envPath = Join-Path $hermesHome "workspace/$AgentId/skills/.env"
  New-Item -ItemType Directory -Path (Split-Path -Parent $envPath) -Force | Out-Null
  $data = if (Test-Path $envPath) { Get-Content $envPath -Raw } else { "" }
  foreach ($pair in @(@("FEISHU_APP_ID",$appId), @("FEISHU_APP_SECRET",$appSecret))) {
    $key = $pair[0]; $value = $pair[1]
    $pattern = "(?m)^#?\s*$([regex]::Escape($key))=.*$"
    if ([regex]::IsMatch($data, $pattern)) {
      $data = [regex]::Replace($data, $pattern, "$key=$value")
    } else {
      if ($data -and -not $data.EndsWith("`n")) { $data += "`n" }
      $data += "$key=$value`n"
    }
  }
  Set-Content -Path $envPath -Value $data -NoNewline -Encoding UTF8
}

function Invoke-CcUninstall {
  Step "uninstall cc-connect project: $CcProjectId"
  & cc-connect daemon stop --work-dir $script:CcHome *> $null
  if ($PurgeCcConnect) { & cc-connect daemon uninstall --work-dir $script:CcHome *> $null }
  Stop-CcConnectProcesses
  if (Remove-CcConnectProject) { Info "removed project: $CcProjectId" } else { Dim "project not found: $CcProjectId" }
  Remove-CcConnectSessions
  if ($PurgeCcConnect) { Invoke-CcPurgeBinary }
}

function Invoke-CcPurgeBinary {
  $cmd = Get-Command cc-connect -ErrorAction SilentlyContinue
  if ($cmd) {
    Remove-Item -Force $cmd.Source -ErrorAction SilentlyContinue
    Info "removed cc-connect binary: $($cmd.Source)"
  }
}

function Backup-PathToDir($PathValue, $BackupRoot, $Label) {
  if (-not (Test-Path $PathValue)) { return }
  New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
  Move-Item -Path $PathValue -Destination (Join-Path $BackupRoot $Label) -Force
}

function Remove-AgentFromJsonConfig($PathValue, $BackupRoot, $Label) {
  if (-not (Test-Path $PathValue)) { return }
  try {
    $text = Get-Content $PathValue -Raw
    $cfg = $text | ConvertFrom-Json
    $items = @($cfg.agents.list | Where-Object { $_.id -ne $AgentId })
    if ($items.Count -eq @($cfg.agents.list).Count) { return }
    New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
    Copy-Item $PathValue (Join-Path $BackupRoot "$Label-openclaw.json")
    $cfg.agents.list = $items
    $cfg | ConvertTo-Json -Depth 80 | Set-Content -Path $PathValue -Encoding UTF8
  } catch {}
}

function Invoke-CcUninstallAll {
  Step "uninstall cc-connect and agent: $AgentId"
  & cc-connect daemon stop --work-dir $script:CcHome *> $null
  & cc-connect daemon uninstall --work-dir $script:CcHome *> $null
  Stop-CcConnectProcesses
  Invoke-CcPurgeBinary
  if (Test-Path $script:CcHome) {
    Move-Item $script:CcHome "$script:CcHome.bak-uninstall-all-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force
  }
  $backupRoot = Join-Path $script:HomeDir ".nako-agent.bak-uninstall-all-$AgentId-$(Get-Date -Format yyyyMMdd-HHmmss)"
  Remove-AgentFromJsonConfig (Join-Path $script:HomeDir ".openclaw/openclaw.json") $backupRoot "openclaw"
  Backup-PathToDir (Join-Path $script:HomeDir ".openclaw/workspace/$AgentId") $backupRoot "openclaw-workspace-$AgentId"
  Backup-PathToDir (Join-Path $script:HomeDir ".openclaw/agents/$AgentId") $backupRoot "openclaw-agent-$AgentId"
  $hermesHome = Resolve-InstallPath ($(if ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-Path $script:HomeDir ".hermes" }))
  Backup-PathToDir (Join-Path $hermesHome "workspace/$AgentId") $backupRoot "hermes-workspace-$AgentId"
  $qclaw = Get-QClawLayout
  Remove-AgentFromJsonConfig $qclaw.ConfigPath $backupRoot "qclaw"
  Backup-PathToDir $qclaw.Workspace $backupRoot "qclaw-workspace-$AgentId"
  Backup-PathToDir (Join-Path $qclaw.Home "agents/$AgentId") $backupRoot "qclaw-agent-$AgentId"
}

$homeSeed = if ($env:NAKO_HOME) {
  $env:NAKO_HOME
} elseif ($env:USERPROFILE) {
  $env:USERPROFILE
} elseif ($HOME) {
  $HOME
} elseif ($env:HOME) {
  $env:HOME
} else {
  [Environment]::GetFolderPath("UserProfile")
}
$script:HomeDir = Resolve-InstallPath $homeSeed
$script:CcHome = Join-Path $script:HomeDir ".cc-connect"
$script:CcConfig = Join-Path $script:CcHome "config.toml"
$script:CcConnectChanged = $false
$CcConnectLazycatVersion = if ($env:CC_CONNECT_LAZYCAT_VERSION) { $env:CC_CONNECT_LAZYCAT_VERSION } else { "v1.3.3" }
$CcConnectLazycatReleaseBase = if ($env:CC_CONNECT_LAZYCAT_RELEASE_BASE) { $env:CC_CONNECT_LAZYCAT_RELEASE_BASE } else { "https://github.com/CodeEagle/cc-connect/releases/download/$CcConnectLazycatVersion" }

if (-not $DisplayName) {
  $DisplayName = switch ($Runtime) {
    "hermes" { "Hermes $AgentId" }
    "qclaw" { "QClaw $AgentId" }
    default { "OpenClaw $AgentId" }
  }
}
if (-not $CcProjectId) {
  if ($env:CC_PROJECT_ID) {
    $CcProjectId = $env:CC_PROJECT_ID
  } elseif ($env:CC_CONNECT_PROJECT_ID) {
    $CcProjectId = $env:CC_CONNECT_PROJECT_ID
  } elseif ($Runtime -eq "openclaw") {
    $CcProjectId = $AgentId
  } else {
    $CcProjectId = "$AgentId-$Runtime"
  }
}

if ($UninstallAll) { Invoke-CcUninstallAll; exit 0 }
if ($Uninstall) { Invoke-CcUninstall; exit 0 }

Step "1. check cc-connect"
if ($CcConnectSource -eq "skip") {
  if (-not (Get-Command cc-connect -ErrorAction SilentlyContinue)) {
    ErrL "-CcConnectSource skip but cc-connect is not in PATH"
    exit 1
  }
} elseif ($CcConnectSource -in @("lazycat","auto")) {
  if (Test-CcConnectNativeVideo) {
    Info "current cc-connect supports native video"
  } elseif (-not (Install-CcConnectRelease)) {
    if ($CcConnectSource -eq "auto") {
      Warn "release install failed; fallback to npm"
      if (-not (Install-CcConnectNpm)) { exit 1 }
    } else {
      ErrL "CodeEagle/cc-connect release install failed"
      exit 1
    }
  }
} elseif (-not (Get-Command cc-connect -ErrorAction SilentlyContinue)) {
  if (-not (Install-CcConnectNpm)) { exit 1 }
}
Info (& cc-connect --version 2>&1 | Select-Object -First 1)

Step "2. configure cc-connect project: $CcProjectId"
try {
  Initialize-QClawRuntimeForCcConnect
  Update-CcConnectConfig
  [void](Disable-CcBlockingProjects)
  Test-CcAgentRuntimeLaunch
} catch {
  ErrL $_.Exception.Message
  exit 1
}
Info "cc-connect project configured: $CcProjectId -> $Runtime"

Step "3. platform QR onboarding"
if ($WithFeishu) { Setup-CcPlatform "feishu" "Feishu" }
if ($WithWeixin) { Setup-CcPlatform "weixin" "Weixin" }
if (-not $WithFeishu -and -not $WithWeixin) {
  if ($NonInteractive) {
    Dim "no -WithFeishu/-WithWeixin; skip onboarding"
  } else {
    if (Confirm-Choice "QR onboarding Feishu now?" "n") { Setup-CcPlatform "feishu" "Feishu" }
    if (Confirm-Choice "QR onboarding Weixin now?" "n") { Setup-CcPlatform "weixin" "Weixin" }
  }
}
[void](Normalize-CcPlatformOptions)
Sync-HermesFeishuEnv

Step "4. start cc-connect"
Ensure-CcConnectRunning "cc-connect config or binary changed"
Info "ready"
exit 0
