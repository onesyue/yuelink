<#
.SYNOPSIS
  Wintun bundle gate for Windows builds.

.DESCRIPTION
  Two modes:
    -Download    Fetch upstream Wintun zip, verify sha256 against the
                 pinned `windows/third_party/wintun/wintun.sha256`, then
                 extract amd64 + arm64 DLLs into the third_party tree
                 so CMake's install(FILES …) rule can pick them up.

    -Verify      Verify a built bundle — looks for wintun.dll next to
                 yuelink.exe and checks its sha256 matches one of the
                 pinned arch hashes. This is the release-gate's
                 trip-wire; if it fires, the Windows package would have
                 shipped without a working TUN driver.

  Exit codes match check_windows_wintun_bundle.sh:
    0  ok
    1  missing dll
    2  arch mismatch
    3  hash mismatch
    4  usage error / unrecoverable

.EXAMPLE
  ./scripts/check_windows_wintun_bundle.ps1 -Download
  ./scripts/check_windows_wintun_bundle.ps1 -Verify -BundleDir build/windows/x64/runner/Release
#>
[CmdletBinding(DefaultParameterSetName = 'Verify')]
param(
  [Parameter(ParameterSetName = 'Download')]
  [switch]$Download,

  [Parameter(ParameterSetName = 'Verify')]
  [switch]$Verify,

  [Parameter(ParameterSetName = 'Verify')]
  [string]$BundleDir,

  [switch]$Json
)

$ErrorActionPreference = 'Stop'

$RepoRoot      = (Resolve-Path "$PSScriptRoot/..").Path
$ThirdPartyDir = Join-Path $RepoRoot 'windows/third_party/wintun'
$HashFile      = Join-Path $ThirdPartyDir 'wintun.sha256'
$WintunUrl     = 'https://www.wintun.net/builds/wintun-0.14.1.zip'
$ZipName       = Split-Path -Leaf $WintunUrl

# Loaded from $HashFile. Two-column "<hash>  <relpath>" format.
function Get-PinnedHashes {
  if (-not (Test-Path $HashFile)) {
    throw "pinned hash file missing: $HashFile"
  }
  $map = @{}
  Get-Content $HashFile | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith('#')) { return }
    $parts = $line -split '\s+', 2
    if ($parts.Length -eq 2) {
      $map[$parts[1]] = $parts[0].ToLower()
    }
  }
  return $map
}

$Results = New-Object System.Collections.Generic.List[object]

function Add-Result($Status, $Arch, $Path, $Detail) {
  $Results.Add([pscustomobject]@{
    status = $Status
    arch   = $Arch
    path   = $Path
    detail = $Detail
  })
  if (-not $Json) {
    $line = "  [{0}] {1,-5} {2}" -f $Status, $Arch, $Path
    if ($Detail) { $line += " — $Detail" }
    Write-Host $line
  }
}

# ── Download mode ───────────────────────────────────────────────────────
if ($Download) {
  $hashes = Get-PinnedHashes
  $tmp    = New-TemporaryFile
  $tmpZip = "$tmp.zip"
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  try {
    Write-Host "↓ Downloading $WintunUrl"
    Invoke-WebRequest -Uri $WintunUrl -OutFile $tmpZip -UseBasicParsing
    $zipHash = (Get-FileHash -Algorithm SHA256 $tmpZip).Hash.ToLower()

    $expectedZip = $hashes[$ZipName]
    if (-not $expectedZip) {
      Add-Result 'fail' '-' $ZipName "no pinned hash for zip"
      exit 3
    }
    if ($zipHash -ne $expectedZip) {
      Add-Result 'fail' '-' $ZipName "sha256 mismatch (got $zipHash, want $expectedZip)"
      exit 3
    }
    Add-Result 'ok' '-' $ZipName 'zip hash matches'

    $extractDir = Join-Path ([System.IO.Path]::GetTempPath()) ("wintun-" + [System.Guid]::NewGuid())
    Expand-Archive -Path $tmpZip -DestinationPath $extractDir -Force
    foreach ($arch in 'amd64','arm64') {
      $src = Join-Path $extractDir "wintun/bin/$arch/wintun.dll"
      if (-not (Test-Path $src)) {
        Add-Result 'fail' $arch $src "missing in upstream archive"
        continue
      }
      $h = (Get-FileHash -Algorithm SHA256 $src).Hash.ToLower()
      $want = $hashes["$arch/wintun.dll"]
      if (-not $want) {
        Add-Result 'fail' $arch $src "no pinned hash for $arch/wintun.dll"
        continue
      }
      if ($h -ne $want) {
        Add-Result 'fail' $arch $src "sha256 mismatch (got $h, want $want)"
        continue
      }
      $destDir = Join-Path $ThirdPartyDir $arch
      New-Item -ItemType Directory -Force -Path $destDir | Out-Null
      Copy-Item $src (Join-Path $destDir 'wintun.dll') -Force
      Add-Result 'ok' $arch (Join-Path $destDir 'wintun.dll') 'installed'
    }
    Remove-Item -Recurse -Force $extractDir
  } finally {
    Remove-Item -Force $tmpZip -ErrorAction SilentlyContinue
  }
}

# ── Verify mode ─────────────────────────────────────────────────────────
if ($Verify) {
  if (-not $BundleDir) {
    throw "-Verify requires -BundleDir <path-to-Release-folder>"
  }
  if (-not (Test-Path $BundleDir)) {
    Add-Result 'fail' '-' $BundleDir 'bundle dir not found'
    exit 1
  }
  $hashes = Get-PinnedHashes
  $dlls = Get-ChildItem -Path $BundleDir -Recurse -Filter 'wintun.dll' -File `
    -ErrorAction SilentlyContinue
  if ($dlls.Count -eq 0) {
    Add-Result 'fail' '-' (Join-Path $BundleDir 'wintun.dll') `
      'missing — would assert false running on launch'
    exit 1
  }
  $bad = 0
  foreach ($dll in $dlls) {
    $h = (Get-FileHash -Algorithm SHA256 $dll.FullName).Hash.ToLower()
    if ($h -eq $hashes['amd64/wintun.dll']) {
      Add-Result 'ok' 'amd64' $dll.FullName ''
    } elseif ($h -eq $hashes['arm64/wintun.dll']) {
      Add-Result 'ok' 'arm64' $dll.FullName ''
    } else {
      Add-Result 'fail' '?' $dll.FullName `
        "hash $h matches neither pinned amd64/arm64 — possible substitution"
      $bad++
    }
  }
  if ($bad -gt 0) { exit 3 }
}

if ($Json) {
  $out = [pscustomobject]@{
    mode    = if ($Download) { 'download' } else { 'verify' }
    ok      = (-not ($Results | Where-Object status -eq 'fail'))
    results = $Results
  }
  $out | ConvertTo-Json -Depth 4
}
