# Pester suite for the dev scripts in scripts/ (the module's own suite is PSWorktree.Tests.ps1).
# Nothing here touches the real repository or machine: each script is pointed at a scratch
# folder under $TestDrive. Runs on Windows PowerShell 5.1 as well, like the rest of tests/.

Describe 'cut-changelog' {
    BeforeAll {
        $script:CutChangelog = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/cut-changelog.ps1'

        function script:New-ChangelogRepo {
            # A throwaway repository root: CHANGELOG.md with an Unreleased and a released section,
            # and the given fragments in changelog.d/ (name -> content).
            param([string]$Unreleased = '', [hashtable]$Fragments = @{})
            $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N').Substring(0, 8))
            New-Item -ItemType Directory -Path (Join-Path $root 'changelog.d') | Out-Null
            Set-Content -LiteralPath (Join-Path $root 'changelog.d/README.md') -Value '# how to'
            foreach ($name in $Fragments.Keys) {
                [IO.File]::WriteAllText((Join-Path $root "changelog.d/$name"), $Fragments[$name])
            }
            [IO.File]::WriteAllText((Join-Path $root 'CHANGELOG.md'),
                "# Changelog`n`n## [Unreleased]`n`n$Unreleased`n## [1.0.0] - 2026-09-11`n`n### Added`n`n- first`n")
            $root
        }
    }

    It 'merges the fragments and the Unreleased lines into one section, in Keep a Changelog order' {
        $root = New-ChangelogRepo -Unreleased "### Fixed`n`n- hand-written fix`n" -Fragments @{
            'b-clean.fixed.md'     = "- clean fix`n"
            'a-install.changed.md' = "- install docs`r`n- second line`r`n"
            'c-new.added.md'       = '- a new flag'
        }
        $notes = & $script:CutChangelog -Version 1.1.0 -Root $root 6>$null
        $expected = "### Added`n`n- a new flag`n`n### Changed`n`n- install docs`n- second line`n`n### Fixed`n`n- hand-written fix`n- clean fix"
        $notes | Should -Be $expected
        $changelog = [IO.File]::ReadAllText((Join-Path $root 'CHANGELOG.md'))
        $today = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
        $changelog.Contains("## [Unreleased]`n`n## [1.1.0] - $today`n`n$expected`n`n## [1.0.0] - 2026-09-11") | Should -BeTrue
        $changelog | Should -Not -Match "`n`n\z"
        @(Get-ChildItem -LiteralPath (Join-Path $root 'changelog.d')).Name | Should -Be @('README.md')
        [IO.File]::ReadAllText((Join-Path $root 'dist/release-notes.md')) | Should -Be "$expected`n"
    }

    It 'refuses a fragment that is <Case>' -ForEach @(
        @{ Case = 'misnamed'; Name = 'oops.fix.md'; Content = '- x'; Message = '*changelog.d/oops.fix.md: name it*' }
        @{ Case = 'not a bullet list'; Name = 'oops.fixed.md'; Content = 'Fixed a thing'; Message = "*changelog.d/oops.fixed.md: write one or more '- ' bullets*" }
    ) {
        $root = New-ChangelogRepo -Fragments @{ $Name = $Content }
        { & $script:CutChangelog -Check -Root $root 6>$null } | Should -Throw $Message
        { & $script:CutChangelog -Version 1.1.0 -Root $root 6>$null } | Should -Throw $Message
        Test-Path -LiteralPath (Join-Path $root "changelog.d/$Name") | Should -BeTrue
    }

    It 'refuses to release without notes' {
        $root = New-ChangelogRepo
        { & $script:CutChangelog -Version 1.1.0 -Root $root 6>$null } | Should -Throw '*No release notes*'
    }

    It 'falls back to the commit subjects, non-ASCII intact' {
        $dash = [char]0x2014   # an em-dash; spelled as a char code to keep this file ASCII
        $root = New-ChangelogRepo
        # Windows PowerShell 5.1 turns git's stderr chatter into errors under Pester's Stop
        # preference; judge these setup calls by exit code instead.
        $ErrorActionPreference = 'Continue'
        git -C $root init -q 2>&1 | Out-Null
        git -C $root -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m "Make wt clean faster $dash twice as fast" 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0
        $ErrorActionPreference = 'Stop'
        $notes = & $script:CutChangelog -Version 1.1.0 -Root $root -FallbackFromGit 6>$null
        $notes | Should -Be "### Changed`n`n- Make wt clean faster $dash twice as fast"
    }

    It "accepts this repository's own fragments" {
        # Runs on every pull request, so a misnamed fragment fails here rather than in the release.
        { & $script:CutChangelog -Check 6>$null } | Should -Not -Throw
    }

    It 'finds the repository on its own when run with -File' {
        # A fresh process of this same edition: Windows PowerShell 5.1 binds parameters under
        # -File before $PSScriptRoot is set, so a default derived from it came out empty.
        $exe = (Get-Process -Id $PID).Path
        $ErrorActionPreference = 'Continue'
        $out = & $exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script:CutChangelog -Check 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $out
        $out | Should -Match 'all well-formed'
    }
}
