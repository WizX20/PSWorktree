<#
.SYNOPSIS
Builds the release zip: dist/PSWorktree-<version>.zip with a single top-level PSWorktree/ folder inside.

.DESCRIPTION
The zip is what a GitHub Release carries and what the Scoop manifest downloads. Scoop's
`extract_dir: "PSWorktree"` strips the top-level folder, so the install dir IS the module folder
(PSWorktree.psd1 at its root) and the `psmodule` junction ~/scoop/modules/PSWorktree points straight at it.
The version comes from src/PSWorktree/PSWorktree.psd1 - stamp it first with scripts/set-version.ps1.
Prints the zip path and its SHA256 (the value bucket/psworktree.json needs).
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$src = Join-Path $root 'src\PSWorktree'
$version = (Test-ModuleManifest (Join-Path $src 'PSWorktree.psd1')).Version.ToString()

$dist = Join-Path $root 'dist'
$stage = Join-Path $dist 'PSWorktree'
if (Test-Path $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item (Join-Path $src '*') $stage
Copy-Item (Join-Path $root 'LICENSE'), (Join-Path $root 'NOTICE') $stage

$zip = Join-Path $dist "PSWorktree-$version.zip"
if (Test-Path $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path $stage -DestinationPath $zip
$hash = (Get-FileHash $zip -Algorithm SHA256).Hash
Write-Host "packed $zip" -ForegroundColor Green
Write-Host "sha256 $hash"
[pscustomobject]@{ Version = $version; Zip = $zip; Sha256 = $hash }
