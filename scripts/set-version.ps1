<#
.SYNOPSIS
Stamps a version into src/PSWorktree/PSWorktree.psd1 (ModuleVersion). Used by the Release workflow.

.PARAMETER Version
Semantic version without a leading "v", e.g. 1.2.0.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version
)
$ErrorActionPreference = 'Stop'
$manifest = Join-Path (Split-Path $PSScriptRoot -Parent) 'src\PSWorktree\PSWorktree.psd1'
$text = [IO.File]::ReadAllText($manifest)
if ($text -notmatch "(?m)^\s*ModuleVersion\s*=\s*'[^']*'") { throw "no ModuleVersion line found in $manifest" }
$new = [regex]::Replace($text, "(?m)^(\s*ModuleVersion\s*=\s*')[^']*(')", "`${1}$Version`${2}")
# Same version is fine: the first release ships the version the manifest already carries.
if ($new -ne $text) { [IO.File]::WriteAllText($manifest, $new, [Text.UTF8Encoding]::new($false)) }
$check = Test-ModuleManifest $manifest
if ($check.Version.ToString() -ne $Version) { throw "manifest reads back as $($check.Version), expected $Version" }
Write-Host "PSWorktree.psd1 ModuleVersion = $Version" -ForegroundColor Green
