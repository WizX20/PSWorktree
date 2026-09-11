# Pester 5+ suite for the PSWorktree module. Every git-backed test builds its own throwaway repo under
# $TestDrive (a bare "origin" plus a clone), so nothing here touches a real repository and the
# tests can run on a bare CI runner. `wt` prints through Write-Host, so output is captured by
# redirecting the information stream (6>&1).

BeforeAll {
    $script:ModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'src\PSWorktree\PSWorktree.psd1'
    Import-Module $script:ModulePath -Force

    # git needs an identity on a fresh runner; env vars keep it out of any config file.
    $env:GIT_AUTHOR_NAME = 'wt tests'; $env:GIT_AUTHOR_EMAIL = 'wt-tests@example.invalid'
    $env:GIT_COMMITTER_NAME = $env:GIT_AUTHOR_NAME; $env:GIT_COMMITTER_EMAIL = $env:GIT_AUTHOR_EMAIL

    function script:New-TestRepo {
        # A clone with one commit on main, tracking a bare origin next to it. Returns the clone path.
        param([string]$Name = 'repo')
        $base = Join-Path $TestDrive ([guid]::NewGuid().ToString('N').Substring(0, 8))
        $origin = Join-Path $base 'origin.git'
        $repo = Join-Path $base $Name
        New-Item -ItemType Directory -Path $base | Out-Null
        Invoke-Git init -q --bare -b main $origin
        Invoke-Git clone -q $origin $repo
        Invoke-Git -C $repo commit -q --allow-empty -m init
        Invoke-Git -C $repo push -q -u origin main
        $repo
    }

    function script:Invoke-Git {
        # Windows PowerShell 5.1 turns native stderr into ErrorRecords, and Pester runs with
        # ErrorActionPreference = Stop, so git's harmless chatter ("You appear to have cloned
        # an empty repository") would abort a test. Run setup-only git calls with Continue and
        # judge them by exit code instead. (The module itself is unaffected: its functions
        # see the global preference, not Pester's.)
        param([Parameter(ValueFromRemainingArguments)][string[]]$GitArgs)
        $ErrorActionPreference = 'Continue'
        & git @GitArgs 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed with exit code $LASTEXITCODE" }
    }

    function script:Get-WtOutput {
        # Runs the block (a real `wt ...` call line, switches included) and returns everything
        # it printed as one string.
        param([scriptblock]$Call)
        (& $Call 6>&1 | Out-String)
    }

    function script:Add-CommitIn {
        param([string]$Path, [string]$File)
        Set-Content -Path (Join-Path $Path $File) -Value "content of $File"
        Invoke-Git -C $Path add $File
        Invoke-Git -C $Path commit -q -m "add $File"
    }
}

Describe 'module surface' {
    It 'exports exactly one command: wt' {
        $m = Get-Module PSWorktree
        $m.ExportedFunctions.Keys | Should -Be @('wt')
        $m.ExportedAliases.Count | Should -Be 0
    }

    It 'resolves wt to the module function, not Windows Terminal' {
        (Get-Command wt).CommandType | Should -Be 'Function'
        (Get-Command wt).Source | Should -Be 'PSWorktree'
    }

    It 'prints help for --help, -h, help and /?' {
        Get-WtOutput { wt --help } | Should -Match 'USAGE:'
        Get-WtOutput { wt -h } | Should -Match 'USAGE:'
        Get-WtOutput { wt help } | Should -Match 'USAGE:'
        Get-WtOutput { wt /? } | Should -Match 'USAGE:'
    }

    It 'help documents every command' {
        $help = Get-WtOutput { wt --help }
        foreach ($cmd in 'wt list', 'wt add', 'wt checkout', 'wt rm', 'wt rename', 'wt clean', '-DryRun', '-Orphans') {
            $help | Should -Match ([regex]::Escape($cmd))
        }
    }

    It 'tab-completes the sub-commands' {
        $c = [System.Management.Automation.CommandCompletion]::CompleteInput('wt li', 5, $null)
        $c.CompletionMatches.CompletionText | Should -Contain 'list'
        $c = [System.Management.Automation.CommandCompletion]::CompleteInput('wt ', 3, $null)
        $c.CompletionMatches.CompletionText | Should -Contain 'clean'
    }
}

Describe 'pure helpers' {
    It 'fuzzy match: subsequence, case-insensitive, whitespace ignored' {
        InModuleScope PSWorktree {
            Test-FuzzyMatch 'EDU-9942-mailing' 'e94' | Should -BeTrue
            Test-FuzzyMatch 'EDU-9942-mailing' 'edu 9942' | Should -BeTrue
            Test-FuzzyMatch 'EDU-9942-mailing' 'MAIL' | Should -BeTrue
            Test-FuzzyMatch 'EDU-9942-mailing' 'xyz' | Should -BeFalse
            Test-FuzzyMatch 'EDU-9942-mailing' '' | Should -BeTrue
        }
    }

    It 'filter matches: literal hits are listed before loose subsequence hits' {
        InModuleScope PSWorktree {
            $rows = @(
                [pscustomobject]@{ Name = 'ci-fix'; Branch = 'chore/prefetch-ci'; Path = 'a' },
                [pscustomobject]@{ Name = 'ipfilter'; Branch = 'feature/ipfilter'; Path = 'b' },
                [pscustomobject]@{ Name = 'other'; Branch = 'main'; Path = 'c' }
            )
            $hits = @(Get-WorktreeFilterMatches $rows 'ipf')
            $hits.Count | Should -Be 2
            $hits[0].Name | Should -Be 'ipfilter'
            $hits[1].Name | Should -Be 'ci-fix'
            @(Get-WorktreeFilterMatches $rows '').Count | Should -Be 3
        }
    }

    It 'cell formatting pads, clips with .., and survives tiny widths' {
        InModuleScope PSWorktree {
            Format-WtCell 'abc' 5 | Should -Be 'abc  '
            Format-WtCell 'abcdefgh' 5 | Should -Be 'abc..'
            Format-WtCell 'abcdefgh' 2 | Should -Be 'ab'
            Format-WtCell 'abc' 0 | Should -Be ''
        }
    }

    It 'slash normalisation handles empty input' {
        InModuleScope PSWorktree {
            ConvertTo-Slash 'C:\x\y' | Should -Be 'C:/x/y'
            ConvertTo-Slash '' | Should -Be ''
            ConvertTo-Slash $null | Should -Be ''
        }
    }

    It 'worktree parent is .claude/worktrees in a Claude-enabled repo, else .worktrees' {
        InModuleScope PSWorktree {
            $plain = Join-Path $TestDrive 'plain'; New-Item -ItemType Directory -Path $plain | Out-Null
            $claude = Join-Path $TestDrive 'claude'; New-Item -ItemType Directory -Path (Join-Path $claude '.claude') -Force | Out-Null
            Get-WorktreeParent $plain | Should -Be (Join-Path $plain '.worktrees')
            Get-WorktreeParent $claude | Should -Be (Join-Path $claude '.claude\worktrees')
        }
    }
}

Describe 'worktree lifecycle' {
    BeforeEach {
        $script:repo = New-TestRepo
        Push-Location $script:repo
    }
    AfterEach {
        Pop-Location
    }

    It 'list shows the main worktree marked as current' {
        Get-WtOutput { wt list } | Should -Match '\*\s+repo\s+main'
    }

    It 'add creates a worktree under .worktrees, on a new branch, and cd''s into it' {
        Get-WtOutput { wt add feature/one } | Should -Match "created worktree 'feature-one'"
        (Get-Location).Path | Should -Be (Join-Path $script:repo '.worktrees\feature-one')
        git rev-parse --abbrev-ref HEAD | Should -Be 'feature/one'
    }

    It 'add lands in .claude/worktrees when the repo has a .claude directory' {
        New-Item -ItemType Directory -Path (Join-Path $script:repo '.claude') | Out-Null
        Get-WtOutput { wt add feature-two } | Out-Null
        (Get-Location).Path | Should -Be (Join-Path $script:repo '.claude\worktrees\feature-two')
    }

    It 'add refuses a path that already exists' {
        Get-WtOutput { wt add dup } | Out-Null
        Set-Location $script:repo
        Get-WtOutput { wt add dup } | Should -Match 'path already exists'
    }

    It 'wt NAME cd''s by exact name and by prefix' {
        Get-WtOutput { wt add feature-three } | Out-Null
        Set-Location $script:repo
        wt feature-three
        (Split-Path (Get-Location).Path -Leaf) | Should -Be 'feature-three'
        Set-Location $script:repo
        wt feat
        (Split-Path (Get-Location).Path -Leaf) | Should -Be 'feature-three'
        Set-Location $script:repo
        Get-WtOutput { wt nope } | Should -Match "no worktree 'nope'"
    }

    It 'checkout takes an origin-only branch into a worktree, and just cd''s when it is already out' {
        Invoke-Git push -q origin main:remote-only
        Get-WtOutput { wt checkout remote-only } | Should -Match "checked out 'remote-only' \(origin\)"
        git rev-parse --abbrev-ref HEAD | Should -Be 'remote-only'
        (git rev-parse --abbrev-ref '@{upstream}') | Should -Be 'origin/remote-only'
        Set-Location $script:repo
        Get-WtOutput { wt co remote-only } | Should -Match 'already checked out'
        (Split-Path (Get-Location).Path -Leaf) | Should -Be 'remote-only'
    }

    It 'checkout never creates a branch' {
        Get-WtOutput { wt checkout does-not-exist } | Should -Match "no branch 'does-not-exist'"
        (git worktree list).Count | Should -Be 1
    }

    It 'rename moves the worktree directory and keeps the branch' {
        Get-WtOutput { wt add old-name } | Out-Null
        Set-Location $script:repo
        Get-WtOutput { wt rename old-name new-name } | Should -Match "renamed worktree 'old-name' -> 'new-name'"
        Test-Path (Join-Path $script:repo '.worktrees\new-name') | Should -BeTrue
        Test-Path (Join-Path $script:repo '.worktrees\old-name') | Should -BeFalse
        git -C (Join-Path $script:repo '.worktrees\new-name') rev-parse --abbrev-ref HEAD | Should -Be 'old-name'
    }

    It 'rename follows you when you are inside the renamed worktree' {
        Get-WtOutput { wt add inside } | Out-Null
        Get-WtOutput { wt mv inside outside } | Out-Null
        (Split-Path (Get-Location).Path -Leaf) | Should -Be 'outside'
    }

    It 'rm removes a clean worktree and refuses main and current' {
        Get-WtOutput { wt add gone-soon } | Out-Null
        Get-WtOutput { wt rm gone-soon } | Should -Match 'is the current worktree'
        Set-Location $script:repo
        Get-WtOutput { wt rm repo } | Should -Match 'is the (main|current) worktree'
        Get-WtOutput { wt rm gone-soon } | Should -Match "removed worktree 'gone-soon'"
        (git worktree list).Count | Should -Be 1
    }

    It 'rm keeps a dirty worktree unless -Force' {
        Get-WtOutput { wt add dirty } | Out-Null
        Set-Content -Path 'untracked.txt' -Value 'x'
        Set-Location $script:repo
        Get-WtOutput { wt rm dirty 2>$null } | Should -Match 'git refused'
        Test-Path (Join-Path $script:repo '.worktrees\dirty') | Should -BeTrue
        Get-WtOutput { wt rm dirty -Force } | Should -Match "removed worktree 'dirty'"
        Test-Path (Join-Path $script:repo '.worktrees\dirty') | Should -BeFalse
    }
}

Describe 'clean' {
    BeforeEach {
        $script:repo = New-TestRepo
        Push-Location $script:repo

        # merged: fast-forwarded into main and pushed
        Get-WtOutput { wt add feat-merged } | Out-Null
        Add-CommitIn (Get-Location).Path 'merged.txt'
        Invoke-Git push -q -u origin feat-merged
        Set-Location $script:repo
        Invoke-Git merge -q --ff-only feat-merged
        Invoke-Git push -q origin main

        # squashed: landed on main as one squash commit, as a squash-merged PR would
        Get-WtOutput { wt add feat-squashed } | Out-Null
        Add-CommitIn (Get-Location).Path 'squashed-a.txt'
        Add-CommitIn (Get-Location).Path 'squashed-b.txt'
        Invoke-Git push -q -u origin feat-squashed
        Set-Location $script:repo
        Invoke-Git merge -q --squash feat-squashed
        Invoke-Git commit -q -m 'squash feat-squashed'
        Invoke-Git push -q origin main

        # open: has work main does not have
        Get-WtOutput { wt add feat-open } | Out-Null
        Add-CommitIn (Get-Location).Path 'open.txt'
        Invoke-Git push -q -u origin feat-open
        Set-Location $script:repo

        # no-commits: branched off main, never diverged, never pushed
        Get-WtOutput { wt add feat-empty } | Out-Null
        Set-Location $script:repo
    }
    AfterEach {
        Pop-Location
    }

    It 'classifies merged, squashed, open and no-commits branches' {
        InModuleScope PSWorktree {
            (Get-BranchMergeState 'feat-merged' 'origin/main').State | Should -Be 'merged'
            (Get-BranchMergeState 'feat-squashed' 'origin/main').State | Should -Be 'squashed'
            (Get-BranchMergeState 'feat-open' 'origin/main').State | Should -Be 'open'
            (Get-BranchMergeState 'feat-empty' 'origin/main').State | Should -Be 'no-commits'
        }
    }

    It 'falls back to origin/main as the base when there is no origin/acceptance' {
        InModuleScope PSWorktree {
            Get-CleanBaseRef '' | Should -Be 'origin/main'
            Get-CleanBaseRef 'main' | Should -Be 'origin/main'
            Get-CleanBaseRef 'nope' 6>&1 | Out-String | Should -Match 'unknown base ref'
        }
    }

    It '-DryRun reports what would go and removes nothing' {
        $out = Get-WtOutput { wt clean -DryRun }
        $out | Should -Match 'dry run: would remove 3 worktree'
        $out | Should -Match 'feat-open\s+feat-open\s+open\s+\?\s+keep \(not merged\)'
        (git worktree list).Count | Should -Be 5
    }

    It '-Yes removes the landed worktrees plus their local branches and keeps the open one' {
        $out = Get-WtOutput { wt clean -Yes }
        $out | Should -Match 'cleaned 3 of 3'
        $names = @(git worktree list --porcelain | Where-Object { $_ -like 'worktree *' } | ForEach-Object { Split-Path $_.Substring(9) -Leaf })
        $names | Should -Contain 'feat-open'
        $names | Should -Not -Contain 'feat-merged'
        $names | Should -Not -Contain 'feat-squashed'
        $names | Should -Not -Contain 'feat-empty'
        $branches = @(git for-each-ref --format='%(refname:short)' refs/heads)
        $branches | Should -Contain 'feat-open'
        $branches | Should -Not -Contain 'feat-merged'
        $branches | Should -Not -Contain 'feat-squashed'
    }

    It '-KeepBranch removes the worktree but leaves the local branch' {
        Get-WtOutput { wt clean -Yes -KeepBranch } | Should -Match 'cleaned 3 of 3'
        @(git for-each-ref --format='%(refname:short)' refs/heads) | Should -Contain 'feat-merged'
    }

    It 'keeps a worktree with untracked files unless -Force, and names them' {
        Set-Content -Path (Join-Path $script:repo '.worktrees\feat-merged\draft.md') -Value 'wip'
        $out = Get-WtOutput { wt clean -DryRun }
        $out | Should -Match 'keep \(1 untracked file\(s\) - use -Force\)'
        $out = Get-WtOutput { wt clean -DryRun -Force }
        $out | Should -Match "feat-merged: deletes 1 untracked file\(s\): 'draft.md'"
    }

    It '-Orphans picks up directories git no longer knows about' {
        New-Item -ItemType Directory -Path (Join-Path $script:repo '.worktrees\leftover') | Out-Null
        $out = Get-WtOutput { wt clean -DryRun -Orphans }
        $out | Should -Match 'leftover\s+-\s+orphan\s+unregistered\s+remove \(directory only\)'
        $out | Should -Match 'dry run: would remove 4 worktree'
    }
}
