$ErrorActionPreference = "SilentlyContinue"

$Started = Get-Date
$Controller = if ($env:YUELINK_CONTROLLER) { $env:YUELINK_CONTROLLER } else { "127.0.0.1:9090" }
$Secret = $env:YUELINK_SECRET
$AppVersion = if ($env:YUELINK_APP_VERSION) { $env:YUELINK_APP_VERSION } else { "unknown" }
$TunStack = if ($env:YUELINK_TUN_STACK) { $env:YUELINK_TUN_STACK } else { "mixed" }
if ($env:YUELINK_START_CMD) {
  powershell -NoProfile -Command $env:YUELINK_START_CMD | Out-Null
  Start-Sleep -Seconds $(if ($env:YUELINK_START_SETTLE_SECONDS) { [int]$env:YUELINK_START_SETTLE_SECONDS } else { 3 })
}

function Invoke-ControllerVersion {
  $headers = @{}
  if ($Secret) { $headers["Authorization"] = "Bearer $Secret" }
  try {
    Invoke-RestMethod -Uri "http://$Controller/version" -Headers $headers -TimeoutSec 3
  } catch { $null }
}

function Test-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($id)
  $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Wintun {
  $paths = @(
    "$PSScriptRoot\..\build\windows\x64\runner\Release\wintun.dll",
    "$PSScriptRoot\..\windows\libs\amd64\wintun.dll",
    "$PSScriptRoot\..\windows\libs\arm64\wintun.dll",
    "$env:ProgramData\YueLink\Service\wintun.dll"
  )
  ($paths | Where-Object { Test-Path $_ } | Select-Object -First 1) -ne $null
}

function Test-TunInterface {
  try {
    (Get-NetAdapter | Where-Object {
      $_.Name -match "^Meta$|YueLink|mihomo|Wintun|Clash" -or
      $_.InterfaceDescription -match "Meta Tunnel|Wintun|YueLink|mihomo|Clash"
    } | Select-Object -First 1) -ne $null
  } catch { $false }
}

function Test-Route {
  try {
    $route = route print | Out-String
    $route -match "\bMeta\b|Meta Tunnel|YueLink|mihomo|Wintun|Clash"
  } catch { $false }
}

function Test-Dns {
  $headers = @{}
  if ($Secret) { $headers["Authorization"] = "Bearer $Secret" }
  try {
    Invoke-RestMethod -Uri "http://$Controller/dns/query?name=www.gstatic.com&type=A" -Headers $headers -TimeoutSec 4 | Out-Null
    $true
  } catch { $false }
}

function Test-Https($Url) {
  try {
    $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 8
    [int]$r.StatusCode -lt 500
  } catch { $false }
}

function Get-Status($Url) {
  try {
    $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 8 -MaximumRedirection 0
    [string]$r.StatusCode
  } catch {
    if ($_.Exception.Response) {
      [string][int]$_.Exception.Response.StatusCode
    } else {
      "timeout"
    }
  }
}

$version = Invoke-ControllerVersion
$controllerOk = $null -ne $version
$coreVersion = if ($controllerOk -and $version.version) { $version.version } else { "unknown" }
$transportOk = Test-Https "https://www.gstatic.com/generate_204"
$githubOk = Test-Https "https://github.com/"
$googleOk = $transportOk
$claudeStatus = Get-Status "https://claude.ai/"
$chatgptStatus = Get-Status "https://chatgpt.com/"

$errorClass = "ok"
if (-not (Test-Wintun)) { $errorClass = "missing_driver" }
elseif (-not (Test-Admin)) { $errorClass = "missing_permission" }
elseif (-not $controllerOk) { $errorClass = "controller_failed" }
elseif (-not (Test-TunInterface)) { $errorClass = "tun_interface_missing" }
elseif (-not (Test-Route)) { $errorClass = "route_not_applied" }
elseif (-not (Test-Dns)) { $errorClass = "dns_hijack_failed" }
elseif (-not $transportOk -and -not $githubOk) { $errorClass = "node_timeout" }

if ($env:YUELINK_STOP_CMD) {
  powershell -NoProfile -Command $env:YUELINK_STOP_CMD | Out-Null
  Start-Sleep -Seconds $(if ($env:YUELINK_STOP_SETTLE_SECONDS) { [int]$env:YUELINK_STOP_SETTLE_SECONDS } else { 3 })
}

$elapsed = [int]((Get-Date) - $Started).TotalMilliseconds
[ordered]@{
  platform = "windows"
  app_version = $AppVersion
  core_version = $coreVersion
  tun_stack = $TunStack
  has_admin = Test-Admin
  driver_present = Test-Wintun
  interface_present = Test-TunInterface
  controller_ok = $controllerOk
  route_ok = Test-Route
  dns_ok = Test-Dns
  transport_ok = $transportOk
  google_ok = $googleOk
  github_ok = $githubOk
  claude_status = $claudeStatus
  chatgpt_status = $chatgptStatus
  cleanup_ok = -not (Test-TunInterface)
  error_class = $errorClass
  elapsed_ms = $elapsed
} | ConvertTo-Json -Depth 3
