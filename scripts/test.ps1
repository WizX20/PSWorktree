<#
.SYNOPSIS
Runs the Pester suite in tests/. Exits non-zero when a test fails.

.DESCRIPTION
`task test` and the CI workflow both call this. Needs Pester 5 or newer (the built-in Pester
3.4 that ships with Windows PowerShell cannot run these tests); on CI it is installed on the
fly, locally the script tells you how. Extra arguments are passed to Invoke-Pester's -Path
filter, so `task test -- tests/PSWorktree.Tests.ps1` runs a single file.

.PARAMETER Path
Test file(s) or folder(s) to run. Defaults to the whole tests/ folder.

.PARAMETER CI
Also write an NUnit XML report to dist/test-results.xml, for the CI job to upload.
#>
[CmdletBinding()]
param(
    [string[]]$Path,
    [switch]$CI
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (-not $Path) { $Path = @(Join-Path $root 'tests') }

$pester = Get-Module -ListAvailable Pester | Where-Object { $_.Version -ge [version]'5.0' } |
    Sort-Object Version -Descending | Select-Object -First 1
if (-not $pester) {
    if ($env:CI) {
        Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser -Force -SkipPublisherCheck
    }
    else {
        throw 'Pester 5+ is not installed. Run: Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser -Force -SkipPublisherCheck'
    }
}
Import-Module Pester -MinimumVersion 5.0
Write-Host "Pester $((Get-Module Pester).Version) on $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion)" -ForegroundColor DarkGray

$config = New-PesterConfiguration
$config.Run.Path = $Path
$config.Run.Exit = $true
$config.Output.Verbosity = 'Detailed'
if ($CI) {
    $out = Join-Path $root 'dist'
    New-Item -ItemType Directory -Force -Path $out | Out-Null
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputFormat = 'NUnitXml'
    $config.TestResult.OutputPath = Join-Path $out 'test-results.xml'
}
Invoke-Pester -Configuration $config
