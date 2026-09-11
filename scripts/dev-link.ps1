<#
.SYNOPSIS
Links src/PSWorktree into your CurrentUser module path so `Import-Module PSWorktree` loads the working copy.

.DESCRIPTION
Creates a directory junction <CurrentUser modules>\PSWorktree -> <repo>\src\PSWorktree (no admin rights
needed). Edits in the checkout are live after `Import-Module PSWorktree -Force`. Refuses to replace a
real directory; a Scoop install lives in ~/scoop/modules, so the two do not collide, but the
junction shadows it while present. -Remove takes the junction away again.

.PARAMETER Remove
Remove the junction instead of creating it.
#>
[CmdletBinding()]
param([switch]$Remove)
$ErrorActionPreference = 'Stop'
$src = Join-Path (Split-Path $PSScriptRoot -Parent) 'src\PSWorktree'
$modules = Join-Path (Split-Path $PROFILE.CurrentUserAllHosts -Parent) 'Modules'
$link = Join-Path $modules 'PSWorktree'

if ($Remove) {
    if (-not (Test-Path $link)) { Write-Host "no link at $link" -ForegroundColor DarkGray; return }
    $item = Get-Item $link
    if (-not $item.LinkType) { throw "$link is a real directory, not a junction - not touching it" }
    $item.Delete()
    Write-Host "removed $link" -ForegroundColor Green
    return
}

if (Test-Path $link) {
    $item = Get-Item $link
    if (-not $item.LinkType) { throw "$link already exists as a real directory - remove it first" }
    Write-Host "already linked: $link -> $($item.Target)" -ForegroundColor DarkGray
    return
}
New-Item -ItemType Directory -Force -Path $modules | Out-Null
New-Item -ItemType Junction -Path $link -Target $src | Out-Null
Write-Host "linked $link -> $src" -ForegroundColor Green
Write-Host 'now: Import-Module PSWorktree -Force' -ForegroundColor DarkGray
