# Pester 5+ suite for the PSWorktree module. Every git-backed test builds its own throwaway repo under
# $TestDrive (a bare "origin" plus a clone), so nothing here touches a real repository and the
# tests can run on a bare CI runner. `wt` prints through Write-Host, so output is captured by
# redirecting the information stream (6>&1). CI runs it on Windows (pwsh and 5.1) and on Linux
# (pwsh), so paths are built with Join-Path and matched with [\\/].

BeforeDiscovery {
    # -Skip needs it while Pester is still collecting the tests; BeforeAll comes later.
    $script:onWindows = [System.Environment]::OSVersion.Platform -eq 'Win32NT'
}

BeforeAll {
    $script:onWindows = [System.Environment]::OSVersion.Platform -eq 'Win32NT'
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
        foreach ($cmd in 'wt list', 'wt add', 'wt checkout', 'wt rm', 'wt rename', 'wt clean', '-DryRun', '-Orphans',
            'git wt', 'wt install git', 'wt install profile', 'wt install bash', 'wt uninstall', 'PSWORKTREE_CD_FILE') {
            $help | Should -Match ([regex]::Escape($cmd))
        }
    }

    It 'tab-completes the sub-commands' {
        $c = [System.Management.Automation.CommandCompletion]::CompleteInput('wt li', 5, $null)
        $c.CompletionMatches.CompletionText | Should -Contain 'list'
        $c = [System.Management.Automation.CommandCompletion]::CompleteInput('wt ', 3, $null)
        $c.CompletionMatches.CompletionText | Should -Contain 'clean'
        $c = [System.Management.Automation.CommandCompletion]::CompleteInput('wt install ', 11, $null)
        $c.CompletionMatches.CompletionText | Should -Be @('git', 'profile', 'bash')
    }

    It 'tab-completes the sub-commands outside a repo too, not file names' {
        # There Get-Worktrees has no names, and a $null completion used to throw. Under a
        # global 'Stop' (a profile's, or the CI runner's), Windows PowerShell 5.1 also made
        # git's "not a git repository" throw - set it here so every run checks that.
        $dir = Join-Path $TestDrive 'not-a-repo'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $savedPreference = $global:ErrorActionPreference
        Push-Location $dir
        try {
            $global:ErrorActionPreference = 'Stop'
            $c = [System.Management.Automation.CommandCompletion]::CompleteInput('wt ', 3, $null)
            $c.CompletionMatches.CompletionText | Should -Contain 'clean'
            $c = [System.Management.Automation.CommandCompletion]::CompleteInput('wt rm ', 6, $null)
            $c.CompletionMatches.Count | Should -Be 0
            { wt list 6>$null } | Should -Not -Throw
        }
        finally {
            $global:ErrorActionPreference = $savedPreference
            Pop-Location
        }
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

    It 'size formatting uses 1024-based units with at most one decimal, culture-independent' {
        InModuleScope PSWorktree {
            Format-WtSize 0 | Should -Be '0 B'
            Format-WtSize 1023 | Should -Be '1023 B'
            Format-WtSize 1024 | Should -Be '1 KB'
            Format-WtSize 1536 | Should -Be '1.5 KB'
            Format-WtSize (512 * 1MB) | Should -Be '512 MB'
            Format-WtSize ([long](2.44 * 1GB)) | Should -Be '2.4 GB'
            Format-WtSize (3 * 1TB) | Should -Be '3 TB'
            Format-WtSize (2048 * 1TB) | Should -Be '2048 TB'
        }
    }

    It 'directory size sums nested files and does not follow junctions' {
        InModuleScope PSWorktree {
            $root = Join-Path $TestDrive 'sized'
            New-Item -ItemType Directory -Path (Join-Path $root 'a\b') -Force | Out-Null
            [IO.File]::WriteAllBytes((Join-Path $root 'top.bin'), (New-Object byte[] 1000))
            [IO.File]::WriteAllBytes((Join-Path $root 'a\mid.bin'), (New-Object byte[] 200))
            [IO.File]::WriteAllBytes((Join-Path $root 'a\b\deep.bin'), (New-Object byte[] 34))
            $other = Join-Path $TestDrive 'elsewhere'
            New-Item -ItemType Directory -Path $other | Out-Null
            [IO.File]::WriteAllBytes((Join-Path $other 'big.bin'), (New-Object byte[] 5000))
            $link = if ($script:OnWindows) { 'Junction' } else { 'SymbolicLink' }
            New-Item -ItemType $link -Path (Join-Path $root 'link') -Target $other | Out-Null
            Get-WtDirSize $root | Should -Be 1234
            Get-WtDirSize (Join-Path $root 'a') | Should -Be 234
            Get-WtDirSize (Join-Path $TestDrive 'does-not-exist') | Should -Be 0
        }
    }

    It 'slash normalisation handles empty input' {
        InModuleScope PSWorktree {
            ConvertTo-Slash 'C:\x\y' | Should -Be 'C:/x/y'
            ConvertTo-Slash '' | Should -Be ''
            ConvertTo-Slash $null | Should -Be ''
        }
    }

    It 'reads a POSIX HOME from Git Bash as the Windows profile folder' -Skip:(-not $onWindows) {
        InModuleScope PSWorktree {
            $saved = $env:HOME
            try {
                $env:HOME = '/c/Users/someone'
                Get-WtBashrcPath | Should -Be (Join-Path $HOME '.bashrc')
                $env:HOME = 'C:\home\someone'
                Get-WtBashrcPath | Should -Be 'C:\home\someone\.bashrc'
            }
            finally { $env:HOME = $saved }
        }
    }

    It 'looks past a PSModulePath folder it may not read' {
        # GitHub's Linux runner lists /root/.local/share/powershell/Modules; Test-Path throws there.
        InModuleScope PSWorktree {
            $saved = $env:PSModulePath
            try {
                New-Item -ItemType Directory -Path (Join-Path $TestDrive 'modules\PSWorktree') -Force | Out-Null
                $env:PSModulePath = @((Join-Path $TestDrive 'unreadable'), (Join-Path $TestDrive 'modules')) -join [System.IO.Path]::PathSeparator
                # Pester wants a default mock next to the filtered one: the real Test-Path, called
                # as the cmdlet itself - by name it would find this mock again.
                Mock Test-Path { & (Get-Command Test-Path -CommandType Cmdlet) -LiteralPath $LiteralPath }
                Mock Test-Path { throw [System.UnauthorizedAccessException]::new('denied') } -ParameterFilter { $LiteralPath -like '*unreadable*' }
                Test-WtModuleOnPath | Should -BeTrue
            }
            finally { $env:PSModulePath = $saved }
        }
    }

    It 'native paths take backslashes on Windows only' {
        InModuleScope PSWorktree {
            # git's C:/x/y reads C:\x\y on Windows; turning /home/me into \home\me elsewhere
            # would hand git a relative name.
            $expected = if ($script:OnWindows) { 'C:\x\y' } else { 'C:/x/y' }
            ConvertTo-NativePath 'C:/x/y' | Should -Be $expected
            if (-not $script:OnWindows) { ConvertTo-NativePath '/home/me/repo' | Should -Be '/home/me/repo' }
            ConvertTo-NativePath '' | Should -Be ''
        }
    }

    It 'prefix match takes the typed text literally, ignoring case' {
        InModuleScope PSWorktree {
            Test-WtPrefix 'feature-three' 'FEAT' | Should -BeTrue
            Test-WtPrefix 'feature-three' 'three' | Should -BeFalse
            Test-WtPrefix 'feat[1]' 'feat[' | Should -BeTrue      # -like threw on the unbalanced '['
            Test-WtPrefix 'feat[1]' 'feat[1]' | Should -BeTrue    # -like read [1] as a character class
            Test-WtPrefix 'feat1' 'feat[1]' | Should -BeFalse
            Test-WtPrefix 'x*y' 'x*' | Should -BeTrue
            Test-WtPrefix 'anything' '' | Should -BeTrue
        }
    }

    It 'worktree parent is .claude/worktrees in a Claude-enabled repo, else .worktrees' {
        InModuleScope PSWorktree {
            $plain = Join-Path $TestDrive 'plain'; New-Item -ItemType Directory -Path $plain | Out-Null
            $claude = Join-Path $TestDrive 'claude'; New-Item -ItemType Directory -Path (Join-Path $claude '.claude') -Force | Out-Null
            Get-WorktreeParent $plain | Should -Be (Join-Path $plain '.worktrees')
            Get-WorktreeParent $claude | Should -Be (Join-Path $claude '.claude\worktrees')
            # A repo path with brackets: Test-Path without -LiteralPath read [po] as a character class.
            $odd = Join-Path $TestDrive 're[po]'; New-Item -ItemType Directory -Path (Join-Path $odd '.claude') -Force | Out-Null
            Get-WorktreeParent $odd | Should -Be (Join-Path $odd '.claude\worktrees')
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

    It 'list keeps the Head column on screen when a branch is wider than the console' {
        Get-WtOutput { wt add feature/a-branch-name-long-enough-to-crowd-out-the-columns-that-follow-it } | Out-Null
        Set-Location $script:repo
        Mock -ModuleName PSWorktree Get-WtConsoleWidth { 60 }
        $out = Get-WtOutput { wt list }
        $out | Should -Match 'Cur\s+Name\s+Branch\s+Head'
        $out | Should -Match '\*\s+repo\s+main\s+[0-9a-f]{7}'
        $out | Should -Match 'feature-a-branch\S*\.\.\s+feature/a-\S*\.\.\s+[0-9a-f]{7}'
        foreach ($line in ($out -split "`r?`n")) { $line.Length | Should -BeLessOrEqual 60 }
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

    It 'takes a directory name with [ and ] through checkout, cd, prefix, rename and rm' {
        # Git forbids '[' in a branch name, so this only comes in through a chosen directory
        # name - and PowerShell reads it as a wildcard unless every path call is literal.
        Invoke-Git branch bracketed
        Get-WtOutput { wt checkout bracketed 'feat[1]' } | Should -Match "checked out 'bracketed'"
        (Split-Path (Get-Location).Path -Leaf) | Should -Be 'feat[1]'
        Set-Location -LiteralPath $script:repo
        wt 'feat[1]'
        (Split-Path (Get-Location).Path -Leaf) | Should -Be 'feat[1]'
        Set-Location -LiteralPath $script:repo
        wt 'feat['                                            # used to throw: invalid wildcard pattern
        (Split-Path (Get-Location).Path -Leaf) | Should -Be 'feat[1]'
        Set-Location -LiteralPath $script:repo
        Get-WtOutput { wt checkout bracketed } | Should -Match 'already checked out'
        (Split-Path (Get-Location).Path -Leaf) | Should -Be 'feat[1]'
        Set-Location -LiteralPath $script:repo
        Get-WtOutput { wt rename 'feat[1]' 'feat[2]' } | Should -Match "renamed worktree 'feat\[1\]' -> 'feat\[2\]'"
        Get-WtOutput { wt rename 'feat[2]' 'feat[2]' } | Should -Match 'target already exists'
        Get-WtOutput { wt rm 'feat[2]' } | Should -Match "removed worktree 'feat\[2\]'"
        (git worktree list).Count | Should -Be 1
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
        # No 2>$null here: under Windows PowerShell 5.1 a redirected native stderr becomes an
        # ErrorRecord, and with ErrorActionPreference=Stop git's own 'fatal: ...' would abort
        # the test before wt prints its hint. Unredirected it just lands in the log.
        Get-WtOutput { wt rm dirty } | Should -Match 'git refused'
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
        $out | Should -Match 'feat-open\s+feat-open\s+open\s+\?\s+-\s+keep \(not merged\)'
        (git worktree list).Count | Should -Be 5
    }

    It 'keeps State, Dirty and Action on screen when a branch is wider than the console' {
        Get-WtOutput { wt add dependabot/npm_and_yarn/frontend/ProspectApp/acceptance/production-8691542a09 } | Out-Null
        Set-Location $script:repo
        Mock -ModuleName PSWorktree Get-WtConsoleWidth { 100 }
        $out = Get-WtOutput { wt clean -DryRun }
        $out | Should -Match 'Name\s+Branch\s+State\s+Dirty\s+Size\s+Action'
        $out | Should -Match 'dependabot-npm\S*\.\.\s+dependabot\S*\.\.\s+no-commits\s+clean\s+\d+ B\s+remove'
        $out | Should -Match 'feat-open\s+feat-open\s+open\s+\?\s+-\s+keep \(not merged\)'
        foreach ($line in ($out -split "`r?`n")) { $line.Length | Should -BeLessOrEqual 100 }
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

    It 'shows the size of each candidate, what a dry run would free, and what a clean reclaimed' {
        # Ignored, so it does not block the removal - node_modules never does either.
        Add-Content -Path (Join-Path $script:repo '.git\info\exclude') -Value '*.bin'
        [IO.File]::WriteAllBytes((Join-Path $script:repo '.worktrees\feat-merged\blob.bin'), (New-Object byte[] (3MB)))
        $out = Get-WtOutput { wt clean -DryRun }
        $out | Should -Match 'measuring 3 worktree\(s\)'
        $out | Should -Match 'feat-merged\s+feat-merged\s+merged\s+clean\s+3 MB\s+remove'
        $out | Should -Match 'feat-empty\s+feat-empty\s+no-commits\s+clean\s+\d+ B\s+remove'
        $out | Should -Match 'dry run: would remove 3 worktree\(s\) \+ local branch\(es\), would free 3 MB'
        $out = Get-WtOutput { wt clean -Yes }
        $out | Should -Match "removed 'feat-merged' \+ branch 'feat-merged' \(3 MB\)"
        $out | Should -Match 'cleaned 3 of 3 worktree\(s\) \+ local branch\(es\), reclaimed 3 MB'
    }

    It 'counts only the removals that succeeded towards the reclaimed total' {
        Add-Content -Path (Join-Path $script:repo '.git\info\exclude') -Value '*.bin'
        [IO.File]::WriteAllBytes((Join-Path $script:repo '.worktrees\feat-merged\blob.bin'), (New-Object byte[] (3MB)))
        # Pester needs a default mock next to the filtered one; a plain delete is enough here.
        Mock -ModuleName PSWorktree Remove-WorktreePath { Remove-Item -LiteralPath $Path -Recurse -Force; -not (Test-Path -LiteralPath $Path) }
        Mock -ModuleName PSWorktree Remove-WorktreePath { $false } -ParameterFilter { $Path -like '*feat-merged' }
        $out = Get-WtOutput { wt clean -Yes }
        $out | Should -Match "failed to delete 'feat-merged'"
        $out | Should -Match 'cleaned 2 of 3 worktree\(s\) \+ local branch\(es\), reclaimed \d+ B'
        $out | Should -Not -Match 'reclaimed 3 MB'
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
        $out | Should -Match 'leftover\s+-\s+orphan\s+unregistered\s+0 B\s+remove \(directory only\)'
        $out | Should -Match 'dry run: would remove 4 worktree'
    }
}

Describe 'git wt' {
    # `wt install git` writes the global git config, so every test gets a throwaway one
    # (GIT_CONFIG_GLOBAL, git 2.32+): the real ~/.gitconfig is neither read nor touched.
    BeforeAll {
        $script:RealGlobalConfig = $env:GIT_CONFIG_GLOBAL

        function script:Invoke-GitWt {
            # `git wt ...` through the real alias - a child pwsh or powershell - returning all
            # it printed. Continue, for the same reason as Invoke-Git.
            param([Parameter(ValueFromRemainingArguments)][string[]]$WtArgs)
            $ErrorActionPreference = 'Continue'
            (& git wt @WtArgs 2>&1 | Out-String)
        }
    }
    BeforeEach {
        $env:GIT_CONFIG_GLOBAL = Join-Path $TestDrive ('gitconfig-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:repo = New-TestRepo
        Push-Location $script:repo
    }
    AfterEach {
        Pop-Location
        $env:GIT_CONFIG_GLOBAL = $script:RealGlobalConfig
        InModuleScope PSWorktree { $script:ViaGit = $false }
    }

    It 'install git points a global alias at git-wt.ps1, and leaves it be the second time' {
        Get-WtOutput { wt install git } | Should -Match "set up 'git wt'"
        git config --global --get alias.wt |
            Should -Match "^!(pwsh|powershell) -NoLogo -NoProfile -ExecutionPolicy Bypass -File '[^']+/src/PSWorktree/git-wt\.ps1'$"
        Get-WtOutput { wt install git } | Should -Match 'already set up'
    }

    It 'install git keeps the wt alias of another tool unless -Force, and uninstall git never removes it' {
        Invoke-Git config --global alias.wt 'worktree list'
        Get-WtOutput { wt install git } | Should -Match 'refusing'
        Get-WtOutput { wt uninstall git } | Should -Match 'not PSWorktree'
        git config --global --get alias.wt | Should -Be 'worktree list'
        Get-WtOutput { wt install git -Force } | Should -Match "set up 'git wt'"
        Get-WtOutput { wt uninstall git } | Should -Match "removed 'git wt'"
        git config --global --get alias.wt | Should -BeNullOrEmpty
    }

    It 'runs wt in a child process with the arguments and switches intact' {
        Invoke-Git worktree add -b done (Join-Path $script:repo '.worktrees\done')   # never diverged: clean takes it
        Get-WtOutput { wt install git } | Out-Null
        $out = Invoke-GitWt clean -DryRun -NoFetch
        $out | Should -Match 'dry run: would remove 1 worktree'
        $out | Should -Not -Match 'fetching'
        (git worktree list).Count | Should -Be 2
        Invoke-GitWt help | Should -Match 'USAGE:'
    }

    It 'add creates the worktree and prints the way there; the calling shell stays put' {
        Get-WtOutput { wt install git } | Out-Null
        $out = Invoke-GitWt add feature/x
        $out | Should -Match "created worktree 'feature-x'"
        $out | Should -Match 'cd ".+[\\/]\.worktrees[\\/]feature-x"'
        $out | Should -Match 'git wt install profile'
        Test-Path -LiteralPath (Join-Path $script:repo '.worktrees\feature-x') | Should -BeTrue
        (Get-Location).Path | Should -Be $script:repo
    }

    It 'survives a module path with spaces, an ampersand and a quote' {
        # Documents often live in 'OneDrive - Contoso & Co', and a manual install sits below it.
        $odd = Join-Path $TestDrive "it's a & b\PSWorktree"
        New-Item -ItemType Directory -Path $odd -Force | Out-Null
        Copy-Item -Path (Join-Path (Split-Path $script:ModulePath -Parent) '*') -Destination $odd
        Invoke-Git config --global alias.wt (& (Get-Module PSWorktree) { param($r) Get-WtGitAlias $r } $odd)
        Invoke-GitWt list | Should -Match '\*\s+repo\s+main'
    }

    It 'wt NAME and checkout print the path instead of moving' {
        InModuleScope PSWorktree { $script:ViaGit = $true }
        Get-WtOutput { wt add feature-y } | Should -Match 'cd ".+[\\/]feature-y"'
        (Get-Location).Path | Should -Be $script:repo
        Get-WtOutput { wt feature-y } | Should -Match 'cd ".+[\\/]feature-y"'
        Get-WtOutput { wt co feature-y } | Should -Match '(?s)already checked out.+cd ".+[\\/]feature-y"'
        (Get-Location).Path | Should -Be $script:repo
    }

    It 'rename refuses the worktree you are in - your shell holds it - and renames the others' {
        Get-WtOutput { wt add here } | Out-Null                   # still in-process: this cd's in
        InModuleScope PSWorktree { $script:ViaGit = $true }
        Get-WtOutput { wt rename here there } | Should -Match "refusing: you are inside 'here'"
        Set-Location $script:repo
        Get-WtOutput { wt rename here there } | Should -Match "renamed worktree 'here' -> 'there'"
    }

    It 'hands the path to the file PSWORKTREE_CD_FILE names, and prints no cd line' {
        InModuleScope PSWorktree { $script:ViaGit = $true }
        $cdFile = Join-Path $TestDrive 'cd-target'
        $env:PSWORKTREE_CD_FILE = $cdFile
        try {
            $out = Get-WtOutput { wt add feature-z }
            $out | Should -Match "created worktree 'feature-z'"
            $out | Should -Not -Match 'cd "|cannot change'
            [IO.File]::ReadAllText($cdFile) | Should -Match '[\\/]\.worktrees[\\/]feature-z$'
            (Get-Location).Path | Should -Be $script:repo
        }
        finally { Remove-Item Env:PSWORKTREE_CD_FILE }
    }

    It 'shows the table when there is no console for the picker (output piped)' {
        Get-WtOutput { wt install git } | Out-Null
        Invoke-GitWt | Should -Match 'Cur\s+Name\s+Branch\s+Head'
    }
}

Describe 'wt install bash' {
    BeforeAll { $script:RealGlobalConfig = $env:GIT_CONFIG_GLOBAL }
    BeforeEach {
        $env:GIT_CONFIG_GLOBAL = Join-Path $TestDrive ('gitconfig-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:rcPath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N').Substring(0, 8) + '\.bashrc')
        Mock -ModuleName PSWorktree Get-WtBashrcPath ([scriptblock]::Create("'$script:rcPath'"))
        # Not wherever the suite was started: git refuses even --global config inside a
        # checkout it cannot read (a Windows worktree seen from WSL, say).
        Push-Location $TestDrive
    }
    AfterEach {
        Pop-Location
        $env:GIT_CONFIG_GLOBAL = $script:RealGlobalConfig
    }

    It 'adds one LF-ended line that sources wt.sh from the module folder, once' {
        Get-WtOutput { wt install git } | Out-Null
        $out = Get-WtOutput { wt install bash }
        $out | Should -Match 'added the wt function'
        $out | Should -Not -Match 'warning'
        Get-WtOutput { wt install bash } | Should -Match 'already in'
        $text = [IO.File]::ReadAllText($script:rcPath)
        $text | Should -Match "^\[ -f '[^']+/src/PSWorktree/wt\.sh' \] && \. '[^']+/src/PSWorktree/wt\.sh'  # wt: git worktree helper \(wt uninstall bash removes this\)\n$"
        $text | Should -Not -Match "`r"
    }

    It 'warns when git wt, which the function runs, is not set up' {
        Get-WtOutput { wt install bash } | Should -Match 'warning: .+wt install git'
    }

    It 'points the line of an older install at this module, and uninstall leaves the rest as it was' {
        New-Item -ItemType Directory -Path (Split-Path $script:rcPath -Parent) | Out-Null
        $old = "[ -f '/old/place/wt.sh' ] && . '/old/place/wt.sh'  # wt: git worktree helper (wt uninstall bash removes this)"
        [IO.File]::WriteAllText($script:rcPath, "export A=1`n$old`nalias ll='ls -l'`n")
        Get-WtOutput { wt install bash } | Should -Match 'added the wt function'
        $lines = [IO.File]::ReadAllText($script:rcPath) -split "`n"
        $lines[0] | Should -Be 'export A=1'
        $lines[1] | Should -Match '/src/PSWorktree/wt\.sh'
        $lines[2] | Should -Be "alias ll='ls -l'"
        Get-WtOutput { wt uninstall bash } | Should -Match 'removed the wt function'
        [IO.File]::ReadAllText($script:rcPath) | Should -BeExactly "export A=1`nalias ll='ls -l'`n"
        Get-WtOutput { wt uninstall bash } | Should -Match 'no wt line'
    }

}

Describe 'bash function (wt.sh)' {
    BeforeAll {
        $script:RealGlobalConfig = $env:GIT_CONFIG_GLOBAL
        # Git Bash on Windows: the bash.exe on PATH may well be WSL's launcher. git knows where
        # its own installation is.
        $script:bash = if ($onWindows) {
            $gitRoot = Split-Path (Split-Path (Split-Path (git --exec-path) -Parent) -Parent) -Parent
            @('bin\bash.exe', 'usr\bin\bash.exe') | ForEach-Object { Join-Path $gitRoot $_ } |
                Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        }
        else { (Get-Command bash -ErrorAction SilentlyContinue).Source }
    }
    BeforeEach {
        $env:GIT_CONFIG_GLOBAL = Join-Path $TestDrive ('gitconfig-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:repo = New-TestRepo
        Push-Location $script:repo
        Get-WtOutput { wt install git } | Out-Null
    }
    AfterEach {
        Pop-Location
        $env:GIT_CONFIG_GLOBAL = $script:RealGlobalConfig
    }

    It 'cd''s the calling bash where git wt would, and stays put when there is nowhere to go' {
        if (-not $script:bash) { Set-ItResult -Skipped -Because 'no bash found'; return }
        # Each step prints where the shell is afterwards; git wt's own output goes to a log.
        $steps = @(
            '. "$1" || exit 1'
            'cd "$2" || exit 1'
            'wt add feature/b >>"$3" 2>&1; echo "add: $(basename "$(pwd)")"'
            'cd "$2"; wt list >>"$3" 2>&1; echo "list: $(basename "$(pwd)")"'
            'wt feature-b >>"$3" 2>&1; echo "name: $(basename "$(pwd)")"'
            'wt --help 2>&1 | grep -q "USAGE:" && echo "help: ok"'
        ) -join "`n"
        $file = Join-Path $TestDrive 'wt-e2e.sh'
        [IO.File]::WriteAllText($file, "$steps`n")                  # LF: bash reads a CR as part of the command
        $wtsh = Join-Path (Split-Path $script:ModulePath -Parent) 'wt.sh'
        $log = Join-Path $TestDrive 'wt-e2e.log'
        $bashArgs = @($file, $wtsh, $script:repo, $log) | ForEach-Object { $_.Replace('\', '/') }
        $ErrorActionPreference = 'Continue'                         # see Invoke-Git
        $out = & $script:bash @bashArgs 2>&1 | Out-String
        $out | Should -Match 'add: feature-b'
        $out | Should -Match 'list: repo'
        $out | Should -Match 'name: feature-b'
        $out | Should -Match 'help: ok'
    }
}

Describe 'wt install profile' {
    BeforeEach {
        $script:profilePath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N').Substring(0, 8) + '\profile.ps1')
        Mock -ModuleName PSWorktree Get-WtProfilePath ([scriptblock]::Create("'$script:profilePath'"))
    }

    It 'adds the import line once, creating the profile and its folder when missing' {
        Get-WtOutput { wt install profile } | Should -Match 'added the wt command'
        Get-WtOutput { wt install profile } | Should -Match 'already in your profile'
        $lines = @(Get-Content -LiteralPath $script:profilePath)
        $lines.Count | Should -Be 1
        $lines[0] | Should -Match '^Import-Module PSWorktree -ErrorAction SilentlyContinue\b'
    }

    It 'knows the line an older Scoop install wrote, and uninstall takes only that out' {
        New-Item -ItemType Directory -Path (Split-Path $script:profilePath -Parent) | Out-Null
        Set-Content -LiteralPath $script:profilePath -Value @(
            'Import-Module posh-git',
            '# Import-Module PSWorktree   (commented out: not ours to touch)',
            'Import-Module PSWorktree -ErrorAction SilentlyContinue  # wt: git worktree helper (scoop install psworktree)',
            'Set-Alias ll Get-ChildItem')
        Get-WtOutput { wt install profile } | Should -Match 'already in your profile'
        Get-WtOutput { wt uninstall profile } | Should -Match 'removed the wt command'
        Get-Content -LiteralPath $script:profilePath |
            Should -Be @('Import-Module posh-git', '# Import-Module PSWorktree   (commented out: not ours to touch)', 'Set-Alias ll Get-ChildItem')
        Get-WtOutput { wt uninstall profile } | Should -Match "no 'Import-Module PSWorktree' line"
    }

    It 'leaves the rest of a <Name> profile as it was, byte for byte' -ForEach @(
        @{ Name = 'UTF-8 with BOM'; Kind = 'utf8bom' }
        @{ Name = 'UTF-8'; Kind = 'utf8' }
        @{ Name = 'UTF-16'; Kind = 'utf16' }
        @{ Name = 'ANSI'; Kind = 'ansi' }
    ) {
        $enc = switch ($Kind) {
            'utf8bom' { New-Object System.Text.UTF8Encoding $true }
            'utf8' { New-Object System.Text.UTF8Encoding $false }
            'utf16' { [System.Text.Encoding]::Unicode }
            'ansi' { [System.Text.Encoding]::GetEncoding(28591) }
        }
        # Non-ASCII on purpose: an UTF-8 round trip would mangle the ANSI byte, and a default
        # write would drop the BOM or the UTF-16.
        $text = "# caf$([char]0xE9) profile`r`nSet-Alias ll Get-ChildItem`r`n"
        $before = [byte[]]($enc.GetPreamble() + $enc.GetBytes($text))
        New-Item -ItemType Directory -Path (Split-Path $script:profilePath -Parent) | Out-Null
        [IO.File]::WriteAllBytes($script:profilePath, $before)
        Get-WtOutput { wt install profile } | Out-Null
        [IO.File]::ReadAllText($script:profilePath, $enc) | Should -Match "caf$([char]0xE9) profile\r\nSet-Alias ll Get-ChildItem\r\nImport-Module PSWorktree"
        Get-WtOutput { wt uninstall profile } | Should -Match 'removed the wt command'
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($script:profilePath)) | Should -Be ([Convert]::ToBase64String($before))
    }
}
