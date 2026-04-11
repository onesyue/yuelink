# Force-refresh Windows icon cache so Explorer / taskbar / Start menu pick
# up the new YueLink icon. Use this if you upgraded YueLink but the old
# square icon is still showing on a pinned taskbar shortcut.
#
# Equivalent of refresh_macos_icon.sh — same root cause (Explorer caches
# every icon it has ever seen in IconCache.db, and pinned shortcuts freeze
# the icon at the time of pin).
#
# Run from PowerShell (no admin needed for current user, admin recommended
# to also clear the system cache):
#
#     pwsh scripts/refresh_windows_icon.ps1
#
# What this does, in order:
#   1. Quits any running YueLink instance
#   2. Stops Explorer (so it releases the cache files)
#   3. Deletes per-user IconCache.db / iconcache_*.db / thumbcache_*.db
#   4. Restarts Explorer
#   5. Calls SHChangeNotify so Explorer rebuilds the cache from disk

$ErrorActionPreference = 'SilentlyContinue'

Write-Host "→ 1/5  Quitting any running YueLink..." -ForegroundColor Cyan
Get-Process -Name yuelink -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host "→ 2/5  Stopping Explorer..." -ForegroundColor Cyan
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

Write-Host "→ 3/5  Deleting per-user icon caches..." -ForegroundColor Cyan
$cacheDir = "$env:LocalAppData\Microsoft\Windows\Explorer"
$patterns = @(
    "$cacheDir\IconCache.db",
    "$cacheDir\iconcache_*.db",
    "$cacheDir\thumbcache_*.db"
)
foreach ($pattern in $patterns) {
    Get-ChildItem -Path $pattern -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Remove-Item $_.FullName -Force
            Write-Host "    removed $($_.Name)"
        } catch {
            Write-Host "    skipped $($_.Name) (in use)" -ForegroundColor Yellow
        }
    }
}

Write-Host "→ 4/5  Restarting Explorer..." -ForegroundColor Cyan
Start-Process explorer.exe
Start-Sleep -Milliseconds 800

Write-Host "→ 5/5  Notifying Explorer to refresh icons..." -ForegroundColor Cyan
# SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_FLUSH, NULL, NULL)
$signature = @'
[DllImport("shell32.dll", CharSet = CharSet.Auto, SetLastError = true)]
public static extern void SHChangeNotify(uint wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);
'@
$shell32 = Add-Type -MemberDefinition $signature -Name 'Shell32Helper' -Namespace 'Win32' -PassThru
$shell32::SHChangeNotify(0x08000000, 0x1000, [IntPtr]::Zero, [IntPtr]::Zero)

Write-Host ""
Write-Host "✓ Done. Taskbar / Start menu / Desktop should now show the new icon." -ForegroundColor Green
Write-Host ""
Write-Host "  If a pinned taskbar shortcut still shows the old icon:" -ForegroundColor Yellow
Write-Host "    1. Right-click the icon → Unpin from taskbar" -ForegroundColor Yellow
Write-Host "    2. Open YueLink from Start menu" -ForegroundColor Yellow
Write-Host "    3. Right-click the running app on the taskbar → Pin to taskbar" -ForegroundColor Yellow
