<#
.SYNOPSIS
Links src/PSWorktree into your CurrentUser module path so `Import-Module PSWorktree` loads the working copy.

.DESCRIPTION
Creates <CurrentUser modules>/PSWorktree -> <repo>/src/PSWorktree: a directory junction on Windows
(no admin rights needed), a symbolic link elsewhere. Edits in the checkout are live after
`Import-Module PSWorktree -Force`. A link that points at another checkout - a removed worktree,
say - is pointed at this one. Refuses to replace a real directory; a Scoop install lives in
~/scoop/modules, so the two do not collide, but the link shadows it while present. -Remove takes
the link away again.

.PARAMETER Remove
Remove the link instead of creating it.

.PARAMETER ModulesPath
The module folder to link into. Defaults to the CurrentUser module path of the PowerShell running
the script: Documents\PowerShell\Modules for PowerShell 7 on Windows (what `task link` uses),
Documents\WindowsPowerShell\Modules for Windows PowerShell 5.1, ~/.local/share/powershell/Modules
elsewhere. Tests point it into a scratch folder.
#>
[CmdletBinding()]
param(
    [switch]$Remove,
    [string]$ModulesPath
)
$ErrorActionPreference = 'Stop'
# $IsWindows does not exist in Windows PowerShell 5.1.
$onWindows = [System.Environment]::OSVersion.Platform -eq 'Win32NT'
$src = Join-Path (Split-Path $PSScriptRoot -Parent) 'src/PSWorktree'
if (-not $ModulesPath) {
    # On Linux and macOS the profile lives in ~/.config/powershell, but modules do not.
    $ModulesPath = if ($onWindows) { Join-Path (Split-Path $PROFILE.CurrentUserAllHosts -Parent) 'Modules' }
    else { Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'powershell/Modules' }
}
$link = Join-Path $ModulesPath 'PSWorktree'
# -Force: Get-Item also finds a link whose target is gone; Test-Path alone says True or False
# for it depending on the platform.
$item = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue

if ($Remove) {
    if (-not $item) { Write-Host "no link at $link" -ForegroundColor DarkGray; return }
    if (-not $item.LinkType) { throw "$link is a real directory, not a link - not touching it" }
    $item.Delete()
    Write-Host "removed $link" -ForegroundColor Green
    return
}
if ($item) {
    if (-not $item.LinkType) { throw "$link already exists as a real directory - remove it first" }
    $target = @($item.Target)[0]
    if ($target -and (Test-Path -LiteralPath $target) -and
        (Resolve-Path -LiteralPath $target).ProviderPath.TrimEnd('\', '/') -eq (Resolve-Path -LiteralPath $src).ProviderPath.TrimEnd('\', '/')) {
        Write-Host "already linked: $link -> $src" -ForegroundColor DarkGray
        return
    }
    # Another checkout, or one that no longer exists: point it here.
    $item.Delete()
    Write-Host "re-pointing $link (was -> $target)" -ForegroundColor Yellow
}
New-Item -ItemType Directory -Force -Path $ModulesPath | Out-Null
$linkType = if ($onWindows) { 'Junction' } else { 'SymbolicLink' }
New-Item -ItemType $linkType -Path $link -Target $src | Out-Null
Write-Host "linked $link -> $src" -ForegroundColor Green
Write-Host 'now: Import-Module PSWorktree -Force' -ForegroundColor DarkGray
