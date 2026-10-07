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
Write-Host "PSScriptAnalyzer $((Get-Module PSScriptAnalyzer).Version) on $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion)" -ForegroundColor DarkGray

$settings = Join-Path $root 'PSScriptAnalyzerSettings.psd1'
$findings = @(foreach ($path in @('src', 'scripts', 'tests') | ForEach-Object { Join-Path $root $_ }) {
        # PSScriptAnalyzer itself crashes now and then on the Linux runners ("Object reference not
        # set to an instance of an object", "more than one dynamic module in each dynamic
        # assembly"): a race in its parallel rule runs, not a finding about our code. A crash is
        # retried; findings never are. Each attempt is collected whole, so a crash halfway
        # through cannot report findings twice.
        for ($attempt = 1; ; $attempt++) {
            try {
                $result = @(Invoke-ScriptAnalyzer -Path $path -Recurse -Settings $settings -ErrorAction Stop)
                break
            }
            catch {
                if ($attempt -ge 3) { throw }
                Write-Warning "PSScriptAnalyzer crashed on ${path} (attempt $attempt of 3): $($_.Exception.Message) - retrying"
            }
        }
        $result
    })
if ($findings) {
    $findings | Format-Table RuleName, Severity, ScriptName, Line, Message -AutoSize -Wrap | Out-String -Width 200 | Write-Host
    throw "PSScriptAnalyzer reported $($findings.Count) finding(s)"
}
Write-Host 'PSScriptAnalyzer: clean' -ForegroundColor Green
