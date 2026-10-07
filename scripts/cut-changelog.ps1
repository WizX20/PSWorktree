<#
.SYNOPSIS
Stamps the release notes into CHANGELOG.md: the fragment files in changelog.d/ plus anything
under "## [Unreleased]" become "## [<version>] - <today>", the fragments are deleted, and the
notes go to dist/release-notes.md. Used by the Release workflow.

.DESCRIPTION
Why fragments: when every pull request adds its line under "## [Unreleased]", each merge puts
every other open pull request in conflict with main. A file of its own per pull request never
conflicts. A fragment is changelog.d/<anything>.<section>.md - section one of added, changed,
deprecated, removed, fixed, security (Keep a Changelog) - holding one or more "- " bullets.
changelog.d/README.md explains this to contributors and is left alone.

Entries are grouped per section in Keep a Changelog order; within a section, hand-written
Unreleased lines come first, then the fragments by file name. Fails on a misnamed fragment or
one that is not a bullet list, and when there is nothing to write unless -FallbackFromGit was
given: a release without notes is a mistake worth stopping. A fresh, empty "## [Unreleased]"
heading is left in place.

.PARAMETER Version
Semantic version without a leading "v", e.g. 1.2.0.

.PARAMETER FallbackFromGit
When there are no entries at all, use the commit subjects since the last v* tag (all commits
when there is no tag yet), skipping merge and release commits. The scheduled weekly release
uses this, so a week of small commits without an entry still gets readable notes.

.PARAMETER Check
Only validate the fragments in changelog.d/ and exit; changes nothing. The test suite runs
this on every pull request, so a misnamed fragment fails there instead of in the release.

.PARAMETER Root
The repository root; defaults to the folder above scripts/. Tests point it at a throwaway copy.
#>
[CmdletBinding(DefaultParameterSetName = 'Cut')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Cut')]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version,
    [Parameter(ParameterSetName = 'Cut')][switch]$FallbackFromGit,
    [Parameter(Mandatory, ParameterSetName = 'Check')][switch]$Check,
    [string]$Root
)
$ErrorActionPreference = 'Stop'
# Not a parameter default: under `powershell -File`, Windows PowerShell 5.1 leaves $PSScriptRoot
# empty while it binds parameters.
if (-not $Root) { $Root = Split-Path $PSScriptRoot -Parent }

# Keep a Changelog's sections, in its order; the key is how a fragment file spells it.
$sections = [ordered]@{ added = 'Added'; changed = 'Changed'; deprecated = 'Deprecated'; removed = 'Removed'; fixed = 'Fixed'; security = 'Security' }
$entries = [ordered]@{}
foreach ($name in $sections.Values) { $entries[$name] = [Collections.Generic.List[string]]::new() }

$fragmentDir = Join-Path $Root 'changelog.d'
$fragments = @(if (Test-Path -LiteralPath $fragmentDir) {
        Get-ChildItem -LiteralPath $fragmentDir -File | Where-Object Name -NE 'README.md' | Sort-Object Name
    })
$fragmentEntries = foreach ($file in $fragments) {
    $m = [regex]::Match($file.Name, '^[A-Za-z0-9][A-Za-z0-9._-]*\.(added|changed|deprecated|removed|fixed|security)\.md$')
    if (-not $m.Success) {
        throw "changelog.d/$($file.Name): name it <anything>.<section>.md, with section one of $($sections.Keys -join ', ')"
    }
    $body = ([IO.File]::ReadAllText($file.FullName) -replace "`r`n", "`n").Trim()
    if (-not $body.StartsWith('- ')) { throw "changelog.d/$($file.Name): write one or more '- ' bullets" }
    foreach ($line in $body -split "`n") {
        if ($line.Trim()) { [pscustomobject]@{ Section = $sections[$m.Groups[1].Value]; Line = $line.TrimEnd() } }
    }
}
if ($Check) {
    Write-Host "changelog.d: $($fragments.Count) fragment(s), all well-formed" -ForegroundColor Green
    return
}

$changelog = Join-Path $Root 'CHANGELOG.md'
$text = [IO.File]::ReadAllText($changelog) -replace "`r`n", "`n"
$section = [regex]::Match($text, '(?ms)^## \[Unreleased\][^\n]*\n(.*?)(?=^## |\z)')
if (-not $section.Success) { throw 'CHANGELOG.md has no "## [Unreleased]" section' }
if ($text -match "(?m)^## \[$([regex]::Escape($Version))\]") { throw "CHANGELOG.md already has a $Version section" }

# Hand-written lines under Unreleased still count; lines before any "### " heading are Changed.
$current = 'Changed'
foreach ($line in ($section.Groups[1].Value.Trim() -split "`n")) {
    if ($line -match '^### (.+?)\s*$') {
        $current = $sections[$Matches[1].ToLowerInvariant()]
        if (-not $current) { throw "CHANGELOG.md: unknown heading '### $($Matches[1])' under Unreleased - use one of $($sections.Values -join ', ')" }
    }
    elseif ($line.Trim()) { $entries[$current].Add($line.TrimEnd()) }
}
foreach ($entry in $fragmentEntries) { $entries[$entry.Section].Add($entry.Line) }

$notes = @(foreach ($name in $entries.Keys) {
        if ($entries[$name].Count) { "### $name`n`n" + ($entries[$name] -join "`n") }
    }) -join "`n`n"

if (-not $notes -and $FallbackFromGit) {
    # git writes UTF-8; read with the console's code page, an em-dash in a subject would garble.
    $savedEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
        $lastTag = (git -C $Root tag -l 'v*' --sort=-v:refname | Select-Object -First 1)
        $range = if ($lastTag) { "$lastTag..HEAD" } else { 'HEAD' }
        $subjects = @(git -C $Root log $range --no-merges --format='%s' |
                Where-Object { $_ -and $_ -notmatch '^chore: release v\d' })
    }
    finally { [Console]::OutputEncoding = $savedEncoding }
    if ($subjects) {
        $notes = "### Changed`n`n" + (($subjects | ForEach-Object { "- $_" }) -join "`n")
        Write-Host "CHANGELOG.md: no entries - using $($subjects.Count) commit subject(s) since $(if ($lastTag) { $lastTag } else { 'the first commit' })" -ForegroundColor Yellow
    }
}
if (-not $notes) { throw 'No release notes: add a fragment to changelog.d/ (see changelog.d/README.md) or an entry under "## [Unreleased]"' }

$today = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
# MatchEvaluator, not -replace: notes may contain '$' (e.g. $PROFILE), which a replacement
# string would read as a group reference.
$fresh = "## [Unreleased]`n`n## [$Version] - $today`n`n$notes`n`n"
$stamped = [regex]::Replace($text, '(?ms)^## \[Unreleased\][^\n]*\n.*?(?=^## |\z)', { param($m) $fresh }.GetNewClosure())
# One newline at the end, also when the new section is the last one in the file.
[IO.File]::WriteAllText($changelog, $stamped.TrimEnd("`n") + "`n", [Text.UTF8Encoding]::new($false))
foreach ($file in $fragments) { Remove-Item -LiteralPath $file.FullName }

$dist = Join-Path $Root 'dist'
[IO.Directory]::CreateDirectory($dist) | Out-Null
$notesFile = Join-Path $dist 'release-notes.md'
[IO.File]::WriteAllText($notesFile, $notes + "`n", [Text.UTF8Encoding]::new($false))
Write-Host "CHANGELOG.md: [Unreleased] + $($fragments.Count) fragment(s) -> [$Version] - $today; notes in $notesFile" -ForegroundColor Green
$notes
