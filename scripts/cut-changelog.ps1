<#
.SYNOPSIS
Turns the "## [Unreleased]" section of CHANGELOG.md into "## [<version>] - <today>" and writes
that section's body to dist/release-notes.md. Used by the Release workflow.

.DESCRIPTION
Fails when there is no Unreleased section, or when it is empty and -FallbackFromGit was not
given: a release without notes is a mistake worth stopping. A fresh, empty "## [Unreleased]"
heading is left in place for the next cycle.

.PARAMETER Version
Semantic version without a leading "v", e.g. 1.2.0.

.PARAMETER FallbackFromGit
When the Unreleased section is empty, fill it with the commit subjects since the last v* tag
(all commits when there is no tag yet), skipping merge and release commits. This is what the
scheduled weekly release uses, so a week of small commits without a hand-written entry still
gets readable notes.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version,
    [switch]$FallbackFromGit
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$changelog = Join-Path $root 'CHANGELOG.md'
$text = [IO.File]::ReadAllText($changelog) -replace "`r`n", "`n"

$section = [regex]::Match($text, '(?ms)^## \[Unreleased\][^\n]*\n(.*?)(?=^## |\z)')
if (-not $section.Success) { throw 'CHANGELOG.md has no "## [Unreleased]" section' }
$notes = $section.Groups[1].Value.Trim()
if ($text -match "(?m)^## \[$([regex]::Escape($Version))\]") { throw "CHANGELOG.md already has a $Version section" }

if (-not $notes -and $FallbackFromGit) {
    $lastTag = (git -C $root tag -l 'v*' --sort=-v:refname | Select-Object -First 1)
    $range = if ($lastTag) { "$lastTag..HEAD" } else { 'HEAD' }
    $subjects = @(git -C $root log $range --no-merges --format='%s' |
            Where-Object { $_ -and $_ -notmatch '^chore: release v\d' })
    if ($subjects) {
        $notes = "### Changed`n`n" + (($subjects | ForEach-Object { "- $_" }) -join "`n")
        Write-Host "CHANGELOG.md: Unreleased was empty - using $($subjects.Count) commit subject(s) since $(if ($lastTag) { $lastTag } else { 'the first commit' })" -ForegroundColor Yellow
    }
}
if (-not $notes) { throw 'The "## [Unreleased]" section of CHANGELOG.md is empty - write the release notes first' }

$today = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
# MatchEvaluator, not -replace: notes may contain '$' (e.g. $PROFILE), which a replacement
# string would read as a group reference.
$fresh = "## [Unreleased]`n`n## [$Version] - $today`n`n$notes`n`n"
$stamped = [regex]::Replace($text, '(?ms)^## \[Unreleased\][^\n]*\n.*?(?=^## |\z)', { param($m) $fresh }.GetNewClosure())
[IO.File]::WriteAllText($changelog, $stamped, [Text.UTF8Encoding]::new($false))

$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$notesFile = Join-Path $dist 'release-notes.md'
[IO.File]::WriteAllText($notesFile, $notes + "`n", [Text.UTF8Encoding]::new($false))
Write-Host "CHANGELOG.md: [Unreleased] -> [$Version] - $today; notes in $notesFile" -ForegroundColor Green
$notes
