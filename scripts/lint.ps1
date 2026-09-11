<#
.SYNOPSIS
Runs PSScriptAnalyzer over the module, the dev scripts and the tests. Exits non-zero on any finding.

.DESCRIPTION
`task lint` and the CI workflow both call this, so the rule set (PSScriptAnalyzerSettings.psd1)
is applied identically everywhere. Needs the PSScriptAnalyzer module; on CI it is installed on
the fly, locally the script tells you how.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
    if ($env:CI) {
        Install-Module PSScriptAnalyzer -Scope CurrentUser -Force -SkipPublisherCheck
    }
    else {
        throw 'PSScriptAnalyzer is not installed. Run: Install-Module PSScriptAnalyzer -Scope CurrentUser'
    }
}
Import-Module PSScriptAnalyzer

$paths = @('src', 'scripts', 'tests') | ForEach-Object { Join-Path $root $_ }
$findings = @($paths | ForEach-Object {
        Invoke-ScriptAnalyzer -Path $_ -Recurse -Settings (Join-Path $root 'PSScriptAnalyzerSettings.psd1')
    })
if ($findings) {
    $findings | Format-Table RuleName, Severity, ScriptName, Line, Message -AutoSize -Wrap | Out-String -Width 200 | Write-Host
    throw "PSScriptAnalyzer reported $($findings.Count) finding(s)"
}
Write-Host 'PSScriptAnalyzer: clean' -ForegroundColor Green
