# PSWorktree - git worktree helper for PowerShell: list / cd / add / checkout / rm / rename / clean any
# git worktree, the ones Claude Code creates under .claude/worktrees/ included.
# Exports one command, `wt`, which must run in the caller's session (it cd's you around),
# hence a module rather than an executable. Commands:
#   wt                    interactive picker (up/down, ENTER cd, DEL remove, type to filter)
#   wt list               static table (Cur/Name/Branch/Head)
#   wt <name>             cd to worktree (exact or prefix match)
#   wt add <branch> [base] create a worktree (+ branch if new) and cd in
#   wt checkout <branch>  check out an existing local/origin branch into a worktree (alias: wt co)
#   wt rm <name> [-Force] remove worktree (refuses main/current)
#   wt rename <old> <new> rename worktree locally (alias: wt mv)
#   wt clean [base]       remove worktrees whose branch landed upstream (incl. squash-merges)
function Get-Worktrees {
    $wts = @(); $wt = $null
    git worktree list --porcelain 2>$null | ForEach-Object {
        if ($_ -like 'worktree *') { $wt = [ordered]@{ Path = $_.Substring(9); Branch = ''; Head = ''; Locked = $false } }
        elseif ($_ -like 'HEAD *') { $wt.Head = $_.Substring(5, 7) }
        elseif ($_ -like 'branch *') { $wt.Branch = ($_.Substring(7) -replace '^refs/heads/', '') }
        elseif ($_ -eq 'detached') { $wt.Branch = '(detached)' }
        elseif ($_ -like 'locked*') { $wt.Locked = $true }
        elseif ($_ -eq '' -and $wt) {
            $wts += [pscustomobject]@{ Name = Split-Path $wt.Path -Leaf; Branch = $wt.Branch; Head = $wt.Head; Path = $wt.Path; Locked = $wt.Locked }; $wt = $null
        }
    }
    if ($wt) { $wts += [pscustomobject]@{ Name = Split-Path $wt.Path -Leaf; Branch = $wt.Branch; Head = $wt.Head; Path = $wt.Path; Locked = $wt.Locked } }
    $wts
}
function Show-Worktrees {
    $cur = (git rev-parse --show-toplevel 2>$null) -replace '\\', '/'
    $rows = Get-Worktrees | ForEach-Object {
        $mark = if (($_.Path -replace '\\', '/') -eq $cur) { '*' } else { '' }
        [pscustomobject]@{ Cur = $mark; Name = $_.Name; Branch = $_.Branch; Head = $_.Head }
    }
    Write-WtTable @($rows) 'Cur', 'Name', 'Branch', 'Head'
}
function Test-WtPrefix {
    # Prefix match on typed text, taken literally. -like reads '[', ']', '*' and '?' as
    # pattern characters, so 'feat[1]' never matched and an unbalanced 'feat[' threw.
    param([string]$Text, [string]$Prefix)
    $Text.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)
}
function Resolve-Worktree {
    param([string]$Name)
    $wts = Get-Worktrees
    $m = $wts | Where-Object { $_.Name -eq $Name }
    if (-not $m) { $m = $wts | Where-Object { Test-WtPrefix $_.Name $Name } | Select-Object -First 1 }
    $m
}
function Remove-Worktree {
    param([string]$Name, [switch]$Force)
    if (-not $Name) { Write-Host 'usage: wt rm <name> [-Force]' -ForegroundColor Yellow; return }
    $m = Resolve-Worktree $Name
    if (-not $m) { Write-Host "no worktree '$Name'" -ForegroundColor Yellow; return }
    $mp = $m.Path -replace '\\', '/'
    $cur = (git rev-parse --show-toplevel 2>$null) -replace '\\', '/'
    $main = ((git worktree list --porcelain 2>$null | Select-Object -First 1) -replace '^worktree ', '') -replace '\\', '/'
    if ($mp -eq $cur) { Write-Host "refusing: '$($m.Name)' is the current worktree" -ForegroundColor Red; return }
    if ($mp -eq $main) { Write-Host "refusing: '$($m.Name)' is the main worktree" -ForegroundColor Red; return }
    if ($Force) {
        # Skip git's own delete: it uses Win32 paths and dies on deep node_modules/obj trees.
        if (Remove-WorktreePath $m.Path) {
            git worktree prune
            Write-Host "removed worktree '$($m.Name)'" -ForegroundColor Green
        }
        else { Write-Host "could not delete $($m.Path) - files still open in it?" -ForegroundColor Yellow }
        return
    }
    git worktree remove $m.Path
    if ($LASTEXITCODE -eq 0) { Write-Host "removed worktree '$($m.Name)'" -ForegroundColor Green }
    else {
        Write-Host "git refused (dirty/locked?) - retry with: wt rm $($m.Name) -Force" -ForegroundColor Yellow
        Write-Host "  on 'Filename too long': git deletes through Win32 paths and deep node_modules/obj" -ForegroundColor DarkGray
        Write-Host "  trees blow past MAX_PATH. Fix it for git everywhere with:" -ForegroundColor DarkGray
        Write-Host "      git config --global core.longpaths true" -ForegroundColor DarkGray
        Write-Host "  (-Force does not need it - it deletes the directory without git.)" -ForegroundColor DarkGray
    }
}
function Rename-Worktree {
    param([string]$OldName, [string]$NewName)
    if (-not $OldName -or -not $NewName) { Write-Host 'usage: wt rename <old> <new>' -ForegroundColor Yellow; return }
    $m = Resolve-Worktree $OldName
    if (-not $m) { Write-Host "no worktree '$OldName'" -ForegroundColor Yellow; return }
    $mp = $m.Path -replace '\\', '/'
    $main = ((git worktree list --porcelain 2>$null | Select-Object -First 1) -replace '^worktree ', '') -replace '\\', '/'
    if ($mp -eq $main) { Write-Host "refusing: '$($m.Name)' is the main worktree" -ForegroundColor Red; return }
    $newPath = Join-Path (Split-Path $m.Path -Parent) $NewName
    if (Test-Path -LiteralPath $newPath) { Write-Host "target already exists: $newPath" -ForegroundColor Red; return }
    $cur = (git rev-parse --show-toplevel 2>$null) -replace '\\', '/'
    $inside = ($mp -eq $cur)
    if ($inside) { Set-Location -LiteralPath (Split-Path $m.Path -Parent) }  # release dir so Windows can move it
    git worktree move $m.Path $newPath
    if ($LASTEXITCODE -eq 0) {
        Write-Host "renamed worktree '$($m.Name)' -> '$NewName'" -ForegroundColor Green
        if ($inside) { Set-Location -LiteralPath $newPath }
    }
    else {
        Write-Host "git worktree move failed (locked/dirty?)" -ForegroundColor Yellow
        if ($inside) { Set-Location -LiteralPath $m.Path }
    }
}
function Get-MainWorktreeRoot {
    ((git worktree list --porcelain 2>$null | Select-Object -First 1) -replace '^worktree ', '') -replace '/', '\'
}
function Get-WorktreeParent {
    # Where new worktrees go: .claude/worktrees/ in a Claude-enabled repo (gitignored,
    # matches `claude -w` and Claude's own worktrees), else a plain .worktrees/ sibling dir.
    param([string]$MainRoot)
    if (Test-Path -LiteralPath (Join-Path $MainRoot '.claude')) { Join-Path $MainRoot '.claude\worktrees' }
    else { Join-Path $MainRoot '.worktrees' }
}
function Test-WorktreeInit {
    # Repos that init worktrees from a post-checkout hook (e.g. a `task configure` step)
    # silently skip it when core.hooksPath isn't wired - the worktree then has no config.
    param([string]$MainRoot, [string]$Path)
    $want = Join-Path $MainRoot '.githooks'
    $hp = (git -C $MainRoot config core.hooksPath) 2>$null
    if ($hp -and -not [System.IO.Path]::IsPathRooted($hp)) { $hp = Join-Path $MainRoot $hp }
    $wired = $hp -and (($hp -replace '/', '\').TrimEnd('\') -ieq ($want -replace '/', '\').TrimEnd('\'))
    if ((Test-Path -LiteralPath $want) -and -not $wired) {
        Write-Host "warning: repo ships .githooks but core.hooksPath is not set - worktree init hook did not run" -ForegroundColor Yellow
        Write-Host "         fix: git config core.hooksPath .githooks   (then re-init this worktree)" -ForegroundColor DarkGray
    }
    $name = Split-Path $Path -Leaf
    if ($name.Length -gt 30) {
        Write-Host "warning: name is $($name.Length) chars - deep build paths (node_modules/obj) can blow past MAX_PATH; a shorter name is safer" -ForegroundColor Yellow
    }
}
function Add-Worktree {
    param([string]$Branch, [string]$Base)
    if (-not $Branch) { Write-Host 'usage: wt add <branch> [<base-ref>]' -ForegroundColor Yellow; return }
    $mainRoot = Get-MainWorktreeRoot
    if (-not $mainRoot) { Write-Host 'not in a git repo' -ForegroundColor Red; return }
    $dir = $Branch -replace '[/\\]', '-'
    $path = Join-Path (Get-WorktreeParent $mainRoot) $dir
    if (Test-Path -LiteralPath $path) { Write-Host "path already exists: $path" -ForegroundColor Red; return }
    git show-ref --verify --quiet "refs/heads/$Branch"; $localExists = ($LASTEXITCODE -eq 0)
    git show-ref --verify --quiet "refs/remotes/origin/$Branch"; $remoteExists = ($LASTEXITCODE -eq 0)
    if ($localExists -or $remoteExists) {
        git worktree add $path $Branch          # existing branch (DWIM creates tracking for remote-only)
    }
    elseif ($Base) { git worktree add -b $Branch $path $Base }
    else { git worktree add -b $Branch $path }  # new branch from current HEAD
    if ($LASTEXITCODE -eq 0) {
        Write-Host "created worktree '$dir' on branch '$Branch'" -ForegroundColor Green
        Test-WorktreeInit $mainRoot $path
        Set-Location -LiteralPath $path
    }
    else { Write-Host 'git worktree add failed' -ForegroundColor Yellow }
}
function Enter-BranchWorktree {
    # wt checkout <branch> [dir]: check out an EXISTING branch (local or on origin) into a
    # worktree under the repo's worktree dir and cd in. Never creates a branch - use `wt add`.
    param([string]$Branch, [string]$Dir)
    if (-not $Branch) { Write-Host 'usage: wt checkout <branch> [<dir-name>]' -ForegroundColor Yellow; return }
    $mainRoot = Get-MainWorktreeRoot
    if (-not $mainRoot) { Write-Host 'not in a git repo' -ForegroundColor Red; return }
    $Branch = $Branch -replace '^origin/', ''
    $existing = Get-Worktrees | Where-Object { $_.Branch -eq $Branch } | Select-Object -First 1
    if ($existing) {
        Write-Host "'$Branch' already checked out in '$($existing.Name)'" -ForegroundColor Cyan
        Set-Location -LiteralPath $existing.Path; return
    }
    git show-ref --verify --quiet "refs/heads/$Branch"; $localExists = ($LASTEXITCODE -eq 0)
    git show-ref --verify --quiet "refs/remotes/origin/$Branch"; $remoteExists = ($LASTEXITCODE -eq 0)
    if (-not $localExists -and -not $remoteExists) {
        Write-Host "fetching origin..." -ForegroundColor DarkGray
        git fetch origin --quiet 2>$null
        git show-ref --verify --quiet "refs/remotes/origin/$Branch"; $remoteExists = ($LASTEXITCODE -eq 0)
    }
    if (-not $localExists -and -not $remoteExists) {
        Write-Host "no branch '$Branch' locally or on origin - create it with: wt add $Branch [base]" -ForegroundColor Red
        return
    }
    $dirName = if ($Dir) { $Dir } else { $Branch -replace '[/\\]', '-' }
    $path = Join-Path (Get-WorktreeParent $mainRoot) $dirName
    if (Test-Path -LiteralPath $path) { Write-Host "path already exists: $path" -ForegroundColor Red; return }
    if ($localExists) { git worktree add $path $Branch }
    else { git worktree add --track -b $Branch $path "origin/$Branch" }
    if ($LASTEXITCODE -eq 0) {
        $src = if ($localExists) { 'local' } else { 'origin' }
        Write-Host "checked out '$Branch' ($src) at $path" -ForegroundColor Green
        Test-WorktreeInit $mainRoot $path
        Set-Location -LiteralPath $path
    }
    else { Write-Host 'git worktree add failed' -ForegroundColor Yellow }
}
function Test-FuzzyMatch {
    # Subsequence match, case-insensitive: every character of the filter must occur in the
    # text in order, not necessarily next to each other - so 'e94' finds 'EDU-9942-mailing'.
    # Whitespace in the filter is skipped, which lets 'edu 9942' hit a dash-separated name.
    param([string]$Text, [string]$Filter)
    if (-not $Filter) { return $true }
    $t = $Text.ToLowerInvariant()
    $i = 0
    foreach ($c in $Filter.ToLowerInvariant().ToCharArray()) {
        if ([char]::IsWhiteSpace($c)) { continue }
        $i = $t.IndexOf($c, $i)
        if ($i -lt 0) { return $false }
        $i++
    }
    return $true
}
function Get-WorktreeFilterMatches {
    # Name and branch are matched as one string, so a filter may straddle both. Rows that
    # carry the filter literally lead: a loose subsequence hit ('ipf' also matches ci-fix
    # through prefetch) must not outrank the branch that actually reads 'ipfilter'.
    # Emits the rows plainly: the caller wraps in @(), and a comma-returned array would
    # survive that wrap as a single nested element.
    param([object[]]$Worktrees, [string]$Filter)
    $hits = @($Worktrees | Where-Object { Test-FuzzyMatch "$($_.Name) $($_.Branch)" $Filter })
    $needle = $Filter.Replace(' ', '').ToLowerInvariant()
    if (-not $needle) { return $hits }
    $direct = @($hits | Where-Object { "$($_.Name) $($_.Branch)".ToLowerInvariant().Contains($needle) })
    $loose = @($hits | Where-Object { -not "$($_.Name) $($_.Branch)".ToLowerInvariant().Contains($needle) })
    $direct + $loose
}
function Get-WtConsoleWidth {
    # WindowWidth throws when stdout is redirected (no console handle); fall back so a row
    # still prints instead of taking the whole picker down.
    $w = try { [Console]::WindowWidth - 1 } catch { $Host.UI.RawUI.WindowSize.Width - 1 }
    if (-not $w -or $w -lt 1) { $w = 119 }
    $w
}
function Format-WtCell {
    # Pad or clip to an exact column width; '..' marks a cut, so a clipped branch cannot be
    # misread as a short one.
    param([string]$Text, [int]$Width)
    if ($Width -lt 1) { return '' }
    if ($Text.Length -le $Width) { return $Text.PadRight($Width) }
    if ($Width -le 2) { return $Text.Substring(0, $Width) }
    $Text.Substring(0, $Width - 2) + '..'
}
function Get-WtDirSize {
    # Sum of file lengths under a directory, walked with DirectoryInfo instead of
    # Get-ChildItem -Recurse: an order of magnitude faster on a node_modules tree in
    # Windows PowerShell 5.1, and a directory that cannot be read (access denied, or a
    # path past MAX_PATH on 5.1) is skipped rather than aborting the walk. Reparse points
    # are not followed - a junction would count its target twice, or loop.
    param([string]$Path)
    $total = [long]0
    $stack = New-Object System.Collections.Generic.Stack[string]
    $stack.Push($Path)
    while ($stack.Count -gt 0) {
        try {
            $dir = New-Object System.IO.DirectoryInfo ($stack.Pop())
            foreach ($f in $dir.EnumerateFiles()) { $total += $f.Length }
            foreach ($d in $dir.EnumerateDirectories()) {
                if (-not ($d.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) { $stack.Push($d.FullName) }
            }
        }
        catch { continue }   # unreadable directory: skip it, keep walking the rest
    }
    $total
}
function Format-WtSize {
    # Explorer-style units (1024-based), one decimal at most. Formatted invariant on
    # purpose: the -f operator follows the console culture and prints '2,4 GB' on a
    # Dutch box.
    param([long]$Bytes)
    $units = 'B', 'KB', 'MB', 'GB', 'TB'
    $v = [double]$Bytes; $u = 0
    while ($v -ge 1024 -and $u -lt $units.Count - 1) { $v /= 1024; $u++ }
    $n = if ($u -eq 0) { [string]$Bytes } else { $v.ToString('0.#', [System.Globalization.CultureInfo]::InvariantCulture) }
    "$n $($units[$u])"
}
function Write-WtTable {
    # Format-Table -AutoSize drops whole trailing columns once the wide ones fill the
    # console, and the trailing columns are the ones that say what happens (State, Dirty,
    # Action). Clip the branch first, then the name, so every column stays on screen.
    param([object[]]$Rows, [string[]]$Columns)
    if (-not $Rows) { return }
    $w = @{}
    foreach ($c in $Columns) {
        $max = ($Rows | ForEach-Object { ([string]$_.$c).Length } | Measure-Object -Maximum).Maximum
        $w[$c] = [Math]::Max([int]$max, $c.Length)
    }
    $gap = 2
    $over = ($Columns | ForEach-Object { $w[$_] } | Measure-Object -Sum).Sum + $gap * ($Columns.Count - 1) - (Get-WtConsoleWidth)
    foreach ($c in 'Branch', 'Name') {
        if ($over -le 0 -or -not $w.ContainsKey($c)) { continue }
        $min = if ($c -eq 'Name') { 8 } else { 12 }
        $take = [Math]::Max(0, [Math]::Min($over, $w[$c] - $min)); $w[$c] -= $take; $over -= $take
    }
    $sep = ' ' * $gap
    $head = @(); $rule = @()
    foreach ($c in $Columns) { $head += Format-WtCell $c $w[$c]; $rule += '-' * $w[$c] }
    Write-Host ''
    Write-Host (($head -join $sep).TrimEnd()) -ForegroundColor Green
    Write-Host (($rule -join $sep).TrimEnd()) -ForegroundColor Green
    foreach ($r in $Rows) {
        $cells = foreach ($c in $Columns) { Format-WtCell ([string]$r.$c) $w[$c] }
        Write-Host (($cells -join $sep).TrimEnd())
    }
    Write-Host ''
}
function Write-WtLine {
    # One row of the picker, written as coloured segments - @{ T = text; F = fg; B = bg } -
    # and then blanked out to the console width, so a shorter frame cannot leave the
    # previous one showing while the highlight bar still ends where the row ends.
    param([object[]]$Segments)
    $w = Get-WtConsoleWidth
    $used = 0
    foreach ($s in $Segments) {
        if ($used -ge $w) { break }
        $text = [string]$s.T
        if ($used + $text.Length -gt $w) { $text = $text.Substring(0, $w - $used) }
        $p = @{ Object = $text; NoNewline = $true }
        if ($s.F) { $p.ForegroundColor = $s.F }
        if ($s.B) { $p.BackgroundColor = $s.B }
        Write-Host @p
        $used += $text.Length
    }
    Write-Host (' ' * ($w - $used))
}
function Get-WtHintSegments {
    # The key bar. Keys are lit and the labels dim, so the line reads as controls rather
    # than as one more table row.
    param([string]$Filter, [int]$Shown, [int]$Total)
    $key = 'Yellow'; $dim = 'DarkGray'
    if ($Filter) {
        return @(
            @{ T = '  filter '; F = $dim },
            @{ T = " $Filter "; F = 'Black'; B = $key },
            @{ T = "  $Shown/$Total match   "; F = 'Gray' },
            @{ T = 'backspace'; F = $key }, @{ T = ' deletes   '; F = $dim },
            @{ T = 'esc'; F = $key }, @{ T = ' clears   '; F = $dim },
            @{ T = 'enter'; F = $key }, @{ T = ' open'; F = $dim }
        )
    }
    @(
        @{ T = '  up/down'; F = $key }, @{ T = ' move   '; F = $dim },
        @{ T = 'enter'; F = $key }, @{ T = ' open   '; F = $dim },
        @{ T = 'del'; F = $key }, @{ T = ' remove   '; F = $dim },
        @{ T = 'esc'; F = $key }, @{ T = ' cancel   '; F = $dim },
        @{ T = 'type'; F = $key }, @{ T = ' to filter'; F = $dim }
    )
}
function Show-WorktreePicker {
    # Draw the list and report what the user asked for: @{ Action; Worktree; Filter }.
    # Kept apart from Select-Worktree so a removal runs outside the drawn block, with the
    # console back under normal control, and the list redrawn from scratch afterwards.
    param([object[]]$All, [string]$Filter = '')
    $cur = ConvertTo-Slash (git rev-parse --show-toplevel 2>$null)
    $nameW = ($All | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum
    $brW = ($All | ForEach-Object { $_.Branch.Length } | Measure-Object -Maximum).Maximum
    # Keep the block inside the console: the branch column gives way first, the name after.
    $over = ($nameW + $brW + 15) - (Get-WtConsoleWidth)
    if ($over -gt 0) {
        $take = [Math]::Max(0, [Math]::Min($over, $brW - 12)); $brW -= $take; $over -= $take
    }
    if ($over -gt 0) { $nameW = [Math]::Max(8, $nameW - $over) }
    $wts = @(Get-WorktreeFilterMatches $All $Filter)
    $sel = 0
    for ($i = 0; $i -lt $wts.Count; $i++) { if ((ConvertTo-Slash $wts[$i].Path) -eq $cur) { $sel = $i } }
    $rule = '  ' + ('-' * ($nameW + $brW + 13))
    [Console]::CursorVisible = $false
    # Reserve the block's rows up-front so the buffer scrolls ONCE now; then anchor $top to
    # the top of the reserved region. Avoids a stale $top near the buffer bottom. Hint,
    # header and rule take a row each, and every worktree keeps its row even while the
    # filter hides it - the block must stay the height it reserved. The key bar gets a
    # blank row on either side so it reads as a header, not as the first list row.
    $rows = $All.Count + 5
    for ($i = 0; $i -lt $rows; $i++) { Write-Host '' }
    $top = [Console]::CursorTop - $rows
    if ($top -lt 0) { $top = 0 }
    $result = @{ Action = 'cancel'; Worktree = $null; Filter = $Filter }
    $done = $false
    try {
        while (-not $done) {
            [Console]::SetCursorPosition(0, $top)
            Write-WtLine @(@{ T = '' })
            Write-WtLine (Get-WtHintSegments $Filter $wts.Count $All.Count)
            Write-WtLine @(@{ T = '' })
            Write-WtLine @(
                @{ T = '  ' + (Format-WtCell 'NAME' $nameW) + '  '; F = 'DarkGray' },
                @{ T = (Format-WtCell 'BRANCH' $brW) + '  '; F = 'DarkGray' },
                @{ T = 'HEAD'; F = 'DarkGray' })
            Write-WtLine @(@{ T = $rule; F = 'DarkGray' })
            $shown = 0
            foreach ($w in $wts) {
                $isCur = (ConvertTo-Slash $w.Path) -eq $cur
                $mark = if ($isCur) { '*' } else { ' ' }
                $nameCell = (Format-WtCell $w.Name $nameW) + '  '
                $brCell = (Format-WtCell $w.Branch $brW) + '  '
                if ($shown -eq $sel) {
                    Write-WtLine @(
                        @{ T = "$mark "; F = 'Black'; B = 'Cyan' },
                        @{ T = $nameCell; F = 'Black'; B = 'Cyan' },
                        @{ T = $brCell; F = 'Black'; B = 'Cyan' },
                        @{ T = $w.Head; F = 'Black'; B = 'Cyan' })
                }
                else {
                    $nameColor = if ($isCur) { 'Green' } else { 'White' }
                    Write-WtLine @(
                        @{ T = "$mark "; F = 'Green' },
                        @{ T = $nameCell; F = $nameColor },
                        @{ T = $brCell; F = 'DarkGray' },
                        @{ T = $w.Head; F = 'DarkGray' })
                }
                $shown++
            }
            if ($shown -eq 0) { Write-WtLine @(@{ T = "  nothing matches '$Filter'"; F = 'Yellow' }); $shown = 1 }
            for ($i = $shown; $i -lt $All.Count; $i++) { Write-WtLine @(@{ T = '' }) }
            $k = [Console]::ReadKey($true)
            $before = $Filter
            switch ($k.Key) {
                'UpArrow' { if ($wts.Count) { $sel = ($sel - 1 + $wts.Count) % $wts.Count } }
                'DownArrow' { if ($wts.Count) { $sel = ($sel + 1) % $wts.Count } }
                'Home' { $sel = 0 }
                'End' { $sel = [Math]::Max(0, $wts.Count - 1) }
                'Enter' { if ($wts.Count) { $result.Action = 'open'; $result.Worktree = $wts[$sel]; $done = $true } }
                'Delete' { if ($wts.Count) { $result.Action = 'remove'; $result.Worktree = $wts[$sel]; $done = $true } }
                'Escape' { if ($Filter) { $Filter = '' } else { $done = $true } }
                'Backspace' { if ($Filter) { $Filter = $Filter.Substring(0, $Filter.Length - 1) } }
                default { if ($k.KeyChar -and -not [char]::IsControl($k.KeyChar)) { $Filter += $k.KeyChar } }
            }
            if ($Filter -ne $before) {
                # Keep the highlight on the worktree it was on while the set shrinks around it.
                $keep = if ($wts.Count) { $wts[$sel].Path } else { '' }
                $wts = @(Get-WorktreeFilterMatches $All $Filter)
                $sel = 0
                for ($i = 0; $i -lt $wts.Count; $i++) { if ($wts[$i].Path -eq $keep) { $sel = $i } }
            }
        }
    }
    finally {
        [Console]::CursorVisible = $true
        [Console]::SetCursorPosition(0, $top)
        $blank = ' ' * (Get-WtConsoleWidth)
        for ($i = 0; $i -lt $rows; $i++) { Write-Host $blank }
        [Console]::SetCursorPosition(0, $top)
    }
    $result.Filter = $Filter
    $result
}
function Remove-PickedWorktree {
    # DEL in the picker: name what is about to go, ask, then hand the work to 'wt rm'.
    param([object]$Worktree)
    $p = ConvertTo-Slash $Worktree.Path
    if ($p -eq (ConvertTo-Slash (git rev-parse --show-toplevel 2>$null))) {
        Write-Host "refusing: '$($Worktree.Name)' is the current worktree" -ForegroundColor Red
        return
    }
    if ($p -eq (ConvertTo-Slash (Get-MainWorktreeRoot))) {
        Write-Host "refusing: '$($Worktree.Name)' is the main worktree" -ForegroundColor Red
        return
    }
    Write-Host "remove worktree '$($Worktree.Name)'" -ForegroundColor Yellow
    Write-Host "  branch: $($Worktree.Branch)" -ForegroundColor DarkGray
    Write-Host "  path:   $($Worktree.Path)" -ForegroundColor DarkGray
    if ((Read-Host 'delete it? [y/N]').Trim().ToLower() -notin 'y', 'yes') {
        Write-Host 'kept' -ForegroundColor DarkGray
        return
    }
    Remove-Worktree $Worktree.Name
    if (Test-Path -LiteralPath $Worktree.Path) {
        # git kept it: uncommitted edits, untracked files or a lock. Say what -Force costs.
        Write-Host 'still there - it holds uncommitted or untracked files, or it is locked' -ForegroundColor Yellow
        if ((Read-Host 'force-delete it, losing whatever was not committed? [y/N]').Trim().ToLower() -in 'y', 'yes') {
            Remove-Worktree $Worktree.Name -Force
        }
        else {
            Write-Host 'kept' -ForegroundColor DarkGray
        }
    }
}
function Select-Worktree {
    $filter = ''
    while ($true) {
        $all = @(Get-Worktrees)
        if (-not $all) { return }
        if ($Host.Name -ne 'ConsoleHost') { Show-Worktrees; return }
        # Last object only: a stray write inside the picker must not turn this into an array.
        $r = Show-WorktreePicker $all $filter | Select-Object -Last 1
        if (-not $r) { return }
        $filter = $r.Filter
        if ($r.Action -eq 'open') { Set-Location -LiteralPath $r.Worktree.Path; return }
        if ($r.Action -ne 'remove') { return }
        Remove-PickedWorktree $r.Worktree   # then loop: the list is read fresh and redrawn
    }
}
function ConvertTo-Slash {
    # Normalise a Windows path for comparison. [char]92 avoids a literal backslash here.
    param([string]$Path)
    if ($Path) { $Path.Replace([char]92, '/') } else { '' }
}
function Get-CleanBaseRef {
    # Upstream branch that PRs land on. Prefer origin/acceptance (teams that PR into an integration branch),
    # then origin/HEAD, then the usual defaults. Never guesses 'main' first on purpose.
    param([string]$Base)
    if ($Base) {
        if ($Base -notlike 'origin/*') {
            git show-ref --verify --quiet "refs/remotes/origin/$Base"
            if ($LASTEXITCODE -eq 0) { return "origin/$Base" }
        }
        git rev-parse --verify --quiet "$Base^{commit}" > $null
        if ($LASTEXITCODE -eq 0) { return $Base }
        Write-Host "unknown base ref '$Base'" -ForegroundColor Red; return $null
    }
    foreach ($c in 'acceptance', 'main', 'master') {
        git show-ref --verify --quiet "refs/remotes/origin/$c"
        if ($LASTEXITCODE -eq 0) { return "origin/$c" }
    }
    $head = (git symbolic-ref --quiet --short refs/remotes/origin/HEAD) 2>$null
    if ($head) { return $head }
    Write-Host 'could not determine an upstream base ref - pass one: wt clean <base>' -ForegroundColor Red
    $null
}
function Get-BranchMergeState {
    # merged     : tip is already contained in base - its commits landed
    # no-commits : contained in base and never pushed, so it never had commits of its own
    # squashed   : branch content landed as a squash/rebase commit - patch-equivalent
    #              commit exists in base, so --merged/ancestor checks miss it. Detected by
    #              replaying the branch tree as one commit on the merge-base and asking
    #              git cherry whether base already has that patch.
    # gone       : upstream tracking branch was deleted, content not found in base
    # open       : still has work not in base
    param([string]$Branch, [string]$Base)
    $track = (git for-each-ref --format='%(upstream:track)' "refs/heads/$Branch") 2>$null
    $gone = ($track -eq '[gone]')
    git merge-base --is-ancestor $Branch $Base 2>$null
    if ($LASTEXITCODE -eq 0) {
        $upstream = (git for-each-ref --format='%(upstream)' "refs/heads/$Branch") 2>$null
        if (-not $upstream) { return @{ State = 'no-commits'; Gone = $false } }
        return @{ State = 'merged'; Gone = $gone }
    }
    $mb = (git merge-base $Base $Branch) 2>$null
    if ($LASTEXITCODE -eq 0 -and $mb) {
        $tree = (git rev-parse "$Branch^{tree}") 2>$null
        $fake = (git commit-tree $tree -p $mb -m squash-probe) 2>$null
        if ($fake) {
            $cherry = (git cherry $Base $fake) 2>$null
            if ($cherry -and ($cherry -join '') -like '-*') { return @{ State = 'squashed'; Gone = $gone } }
        }
    }
    if ($gone) { return @{ State = 'gone'; Gone = $true } }
    @{ State = 'open'; Gone = $false }
}
function Get-UntrackedFiles {
    # Untracked and NOT ignored: what would be lost with no way to get it back.
    param([string]$Path)
    , @((git -C $Path status --porcelain) 2>$null | Where-Object { $_ -like '??*' } | ForEach-Object { $_.Substring(3) })
}
function Get-WorktreeDirtyState {
    # clean | untracked (new files git does not track yet; ignored ones - node_modules,
    #                    generated config - do not show up here at all)
    #       | modified  (tracked edits or staged changes - real work, keep by default)
    param([string]$Path)
    $lines = @((git -C $Path status --porcelain) 2>$null)
    if (-not $lines) { return 'clean' }
    if ($lines | Where-Object { $_ -notlike '??*' }) { return 'modified' }
    'untracked'
}
function Remove-WorktreePath {
    # 'git worktree remove' deletes the tree through the Win32 API and dies on deep
    # node_modules/obj nesting with "Filename too long" - and then blocks the whole run on
    # git's interactive "Should I try again? (y/n)" prompt. PowerShell deletes it instead;
    # if even that balks, robocopy mirrors an empty dir over it - robocopy has no MAX_PATH limit.
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    # Left over: read-only bits, or a Windows PowerShell 5.1 host that is not long-path aware.
    $empty = Join-Path ([System.IO.Path]::GetTempPath()) ("wt-empty-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $empty -Force | Out-Null
    try {
        robocopy $empty $Path /MIR /NFL /NDL /NJH /NJS /NC /NS /NP | Out-Null
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
    finally { Remove-Item -LiteralPath $empty -Recurse -Force -ErrorAction SilentlyContinue }
    -not (Test-Path -LiteralPath $Path)
}
function Read-WithCompletion {
    # Read-Host cannot complete on Tab, so drive the console directly: printable keys append,
    # Backspace deletes, Tab cycles the candidates matching the token after the last separator.
    param([string]$Prompt, [string[]]$Candidates)
    if ($Host.Name -ne 'ConsoleHost') { return Read-Host ($Prompt.TrimEnd(': ')) }
    Write-Host $Prompt -NoNewline
    $buf = ''; $hits = @(); $hi = 0; $tabbed = $null
    while ($true) {
        $k = [Console]::ReadKey($true)
        if ($k.Key -eq 'Enter') { Write-Host ''; return $buf }
        if ($k.Key -eq 'Escape') { Write-Host ''; return '' }
        if ($k.Key -eq 'Backspace') {
            if ($buf.Length -gt 0) { $buf = $buf.Substring(0, $buf.Length - 1); [Console]::Write("`b `b") }
            $tabbed = $null
            continue
        }
        if ($k.Key -eq 'Tab') {
            $sep = $buf.LastIndexOfAny([char[]]@(',', ' '))
            $head = $buf.Substring(0, $sep + 1)
            $tok = $buf.Substring($sep + 1)
            if ($tabbed -ne $buf) { $hits = @($Candidates | Where-Object { Test-WtPrefix $_ $tok }); $hi = 0 }
            elseif ($hits.Count -gt 0) { $hi = ($hi + 1) % $hits.Count }
            if ($hits.Count -gt 0) {
                $new = $head + $hits[$hi]
                for ($i = 0; $i -lt $buf.Length; $i++) { [Console]::Write("`b `b") }
                [Console]::Write($new)
                $buf = $new; $tabbed = $buf
            }
            continue
        }
        if ($k.KeyChar -and -not [char]::IsControl($k.KeyChar)) {
            $buf += $k.KeyChar; [Console]::Write($k.KeyChar); $tabbed = $null
        }
    }
}
function Resolve-CleanSelection {
    # Turn a typed line into rows: exact name/branch match first, then prefix. Unknown tokens
    # are reported rather than silently dropped - a typo must not quietly shrink the set.
    param([object[]]$Doomed, [string]$Line)
    $picked = @(); $missed = @()
    foreach ($tok in ($Line -split '[, ]+' | Where-Object { $_ })) {
        $hit = @($Doomed | Where-Object { $_.Name -eq $tok -or $_.Branch -eq $tok })
        if (-not $hit) { $hit = @($Doomed | Where-Object { (Test-WtPrefix $_.Name $tok) -or (Test-WtPrefix $_.Branch $tok) }) }
        if ($hit) { $picked += $hit } else { $missed += $tok }
    }
    if ($missed) { Write-Host "  not a candidate: $($missed -join ', ')" -ForegroundColor Yellow }
    , @($picked | Sort-Object Path -Unique)
}
function Select-CleanTargets {
    # The confirmation step: rather than one y/N over everything, offer the groups the table
    # already shows, or a hand-picked list.
    param([object[]]$Doomed, [string]$What)
    $merged = @($Doomed | Where-Object { $_.State -in 'merged', 'squashed' })
    $fresh = @($Doomed | Where-Object { $_.State -eq 'no-commits' -or $_.Dirty -eq 'untracked' })
    $orphans = @($Doomed | Where-Object { $_.State -eq 'orphan' })
    Write-Host ''
    Write-Host "what should go? ($($Doomed.Count) candidates, $What)" -ForegroundColor Cyan
    Write-Host "  a  all $($Doomed.Count)"
    if ($merged) { Write-Host "  m  merged/squashed ($($merged.Count))" }
    if ($fresh) { Write-Host "  u  no-commits/untracked ($($fresh.Count))" }
    if ($orphans) { Write-Host "  o  orphan directories ($($orphans.Count))" }
    Write-Host '  s  pick by name or branch (Tab completes)'
    Write-Host '  q  cancel'
    $ans = (Read-Host 'choice').Trim().ToLower()
    switch ($ans) {
        { $_ -in 'a', 'y', 'all' } { return $Doomed }
        { $_ -in 'm', 'merged' } { return $merged }
        { $_ -in 'u', 'untracked' } { return $fresh }
        { $_ -in 'o', 'orphan', 'orphans' } { return $orphans }
        { $_ -in 's', 'select', 'pick' } {
            $cand = @($Doomed | ForEach-Object { $_.Name }) +
            @($Doomed | Where-Object { $_.Branch -ne '-' } | ForEach-Object { $_.Branch })
            $line = Read-WithCompletion 'names/branches (space or comma separated): ' (@($cand) | Sort-Object -Unique)
            return (Resolve-CleanSelection $Doomed $line)
        }
        default { return @() }
    }
}
function Clear-MergedWorktrees {
    param([string]$Base, [switch]$DryRun, [switch]$Yes, [switch]$IncludeGone,
        [switch]$KeepBranch, [switch]$NoFetch, [switch]$Force, [switch]$Orphans)
    $mainRoot = Get-MainWorktreeRoot
    if (-not $mainRoot) { Write-Host 'not in a git repo' -ForegroundColor Red; return }
    if (-not $NoFetch) {
        Write-Host 'fetching origin (--prune)...' -ForegroundColor DarkGray
        git fetch origin --prune --quiet 2>$null
    }
    $baseRef = Get-CleanBaseRef $Base
    if (-not $baseRef) { return }
    git worktree prune   # drop entries whose directory is already gone, before listing
    $cur = ConvertTo-Slash (git rev-parse --show-toplevel 2>$null)
    $mainP = ConvertTo-Slash $mainRoot
    $baseBranch = $baseRef -replace '^origin/', ''
    Write-Host "base: $baseRef" -ForegroundColor DarkGray

    $rows = @()
    foreach ($w in Get-Worktrees) {
        $p = ConvertTo-Slash $w.Path
        $skip = $null
        if ($p -eq $mainP) { $skip = 'main worktree' }
        elseif ($p -eq $cur) { $skip = 'current worktree' }
        elseif ($w.Branch -eq '(detached)') { $skip = 'detached' }
        elseif ($w.Branch -eq $baseBranch) { $skip = 'base branch' }
        if ($skip) {
            $rows += [pscustomobject]@{ Name = $w.Name; Branch = $w.Branch; State = '-'; Dirty = '-'; Action = "keep ($skip)"; Path = $w.Path; Remove = $false }
            continue
        }
        $m = Get-BranchMergeState $w.Branch $baseRef
        $state = $m.State
        $take = ($state -in 'merged', 'squashed', 'no-commits') -or ($state -eq 'gone' -and $IncludeGone)
        if (-not $take) {
            $why = if ($state -eq 'gone') { 'gone upstream, content not in base - use -IncludeGone' } else { 'not merged' }
            $rows += [pscustomobject]@{ Name = $w.Name; Branch = $w.Branch; State = $state; Dirty = '?'; Action = "keep ($why)"; Path = $w.Path; Remove = $false }
            continue
        }
        $dirty = Get-WorktreeDirtyState $w.Path
        if ($w.Locked -and -not $Force) {
            $rows += [pscustomobject]@{ Name = $w.Name; Branch = $w.Branch; State = $state; Dirty = 'locked'; Action = 'keep (locked - use -Force)'; Path = $w.Path; Remove = $false }
            continue
        }
        if ($dirty -ne 'clean' -and -not $Force) {
            # Untracked here means not tracked AND not ignored - generated config and
            # node_modules never reach this branch. So it is unsaved work until proven
            # otherwise: a new file nobody has added yet reads exactly like a stray one.
            $why = if ($dirty -eq 'modified') { 'uncommitted changes' }
            else { "$((Get-UntrackedFiles $w.Path).Count) untracked file(s)" }
            $rows += [pscustomobject]@{ Name = $w.Name; Branch = $w.Branch; State = $state; Dirty = $dirty; Action = "keep ($why - use -Force)"; Path = $w.Path; Remove = $false }
            continue
        }
        $rows += [pscustomobject]@{ Name = $w.Name; Branch = $w.Branch; State = $state; Dirty = $dirty; Action = 'remove'; Path = $w.Path; Remove = $true }
    }

    if ($Orphans) {
        # Directories sitting in the worktree parent that git does not know about: leftovers
        # from a half-finished removal, or from a 'git worktree prune' after one. They hold
        # no branch and no git state, so nothing here can tell you whether they matter.
        $known = @{}
        Get-Worktrees | ForEach-Object { $known[(ConvertTo-Slash $_.Path).TrimEnd('/')] = $true }
        $rows | ForEach-Object { $known[(ConvertTo-Slash $_.Path).TrimEnd('/')] = $true }
        $parent = Get-WorktreeParent $mainRoot
        if (Test-Path -LiteralPath $parent) {
            foreach ($dir in (Get-ChildItem -LiteralPath $parent -Directory -ErrorAction SilentlyContinue)) {
                if ($known[(ConvertTo-Slash $dir.FullName).TrimEnd('/')]) { continue }
                $rows += [pscustomobject]@{ Name = $dir.Name; Branch = '-'; State = 'orphan'; Dirty = 'unregistered'; Action = 'remove (directory only)'; Path = $dir.FullName; Remove = $true }
            }
        }
    }

    # Sizes are taken now, before anything goes: the table shows what a clean would buy,
    # and the summary what it actually freed. Rows that stay are not walked.
    $doomed = @($rows | Where-Object { $_.Remove })
    if ($doomed) { Write-Host "measuring $($doomed.Count) worktree(s)..." -ForegroundColor DarkGray }
    foreach ($r in $rows) {
        $bytes = 0; $size = '-'
        if ($r.Remove) { $bytes = Get-WtDirSize $r.Path; $size = Format-WtSize $bytes }
        $r | Add-Member -NotePropertyName Bytes -NotePropertyValue $bytes
        $r | Add-Member -NotePropertyName Size -NotePropertyValue $size
    }

    Write-WtTable @($rows | Sort-Object { -not $_.Remove }, Name) 'Name', 'Branch', 'State', 'Dirty', 'Size', 'Action'

    if (-not $doomed) { Write-Host 'nothing to clean' -ForegroundColor Green; return }
    # Ignored files (generated config, node_modules) are gone silently - they are
    # reproducible. Untracked-but-not-ignored ones are not, so name them first.
    foreach ($d in ($doomed | Where-Object { $_.Dirty -eq 'untracked' })) {
        $files = Get-UntrackedFiles $d.Path
        $head = ($files | Select-Object -First 5 | ForEach-Object { "'$_'" }) -join ', '
        if ($files.Count -gt 5) { $head += ", ... (+$($files.Count - 5))" }
        Write-Host "  $($d.Name): deletes $($files.Count) untracked file(s): $head" -ForegroundColor Yellow
    }
    $what = if ($KeepBranch) { 'worktree(s)' } else { 'worktree(s) + local branch(es)' }
    if ($DryRun) {
        $total = ($doomed | Measure-Object Bytes -Sum).Sum
        Write-Host "dry run: would remove $($doomed.Count) $what, would free $(Format-WtSize $total)" -ForegroundColor Cyan
        return
    }
    if (-not $Yes) {
        $doomed = @(Select-CleanTargets $doomed $what)
        if (-not $doomed) { Write-Host 'nothing selected' -ForegroundColor Yellow; return }
        Write-Host "removing $($doomed.Count) $what" -ForegroundColor Cyan
    }
    $removed = 0; $freed = [long]0
    foreach ($d in $doomed) {
        if ($d.Dirty -eq 'locked' -or (Get-Worktrees | Where-Object { $_.Path -eq $d.Path -and $_.Locked })) {
            git worktree unlock $d.Path 2>$null | Out-Null
        }
        if (-not (Remove-WorktreePath $d.Path)) {
            Write-Host "  failed to delete '$($d.Name)' - files still open in it? $($d.Path)" -ForegroundColor Yellow
            Write-Host "    a running dev server, IDE or docker mount holds a file; close it and re-run." -ForegroundColor DarkGray
            Write-Host "    if git itself complains 'Filename too long' elsewhere: git config --global core.longpaths true" -ForegroundColor DarkGray
            continue
        }
        git worktree prune   # drops the admin entry now that the directory is gone
        $removed++; $freed += $d.Bytes
        $msg = "removed '$($d.Name)'"
        if (-not $KeepBranch -and $d.Branch -ne '-') {
            git branch -D $d.Branch 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { $msg += " + branch '$($d.Branch)'" }
            else { $msg += " (branch '$($d.Branch)' kept - delete failed)" }
        }
        Write-Host "  $msg ($($d.Size))" -ForegroundColor Green
    }
    git worktree prune
    Write-Host "cleaned $removed of $($doomed.Count) $what, reclaimed $(Format-WtSize $freed)" -ForegroundColor Green
}
function Show-WtHelp {
    @"
wt - git worktree helper (works with git/Claude-created worktrees)

USAGE:
  wt                          interactive picker: Up/Down move, ENTER cd, DEL remove the
                              highlighted worktree (asks first), ESC cancel; type to
                              filter the list, ESC clears an active filter
  wt list                     print a static table (Cur/Name/Branch/Head)
  wt <name>                   cd to a worktree (exact or prefix match)
  wt add <branch> [base]      create a worktree under .claude/worktrees/ and cd in
                              (checks out existing local/remote branch, else creates it)
  wt checkout <branch> [dir]  check out an EXISTING branch - local or origin, fetched
                              if unknown - into .claude/worktrees/<dir> and cd in
                              (alias: wt co; never creates a branch, use 'wt add')
  wt rm <name> [-Force]       remove a worktree (refuses main/current; -Force if dirty/locked)
  wt rename <old> <new>       rename a worktree locally (alias: wt mv)
  wt clean [base]             remove every worktree whose branch already landed on the
                              upstream base - or never diverged from it - and delete that
                              local branch. Base defaults to origin/acceptance, else
                              origin/main|master, else origin/HEAD (alias: wt prune)
       -DryRun        only show what would go, and how much disk it would free
       -Yes           skip the menu and take everything listed
       -IncludeGone   also take branches whose upstream was deleted but whose
                      content was not found on the base (closed-unmerged PRs)
       -KeepBranch    remove the worktree, keep the local branch
       -NoFetch       skip the 'git fetch --prune' first
       -Force         also take locked worktrees, and ones holding uncommitted
                      changes or untracked files
       -Orphans       also delete directories in the worktree dir that git no longer
                      knows about (leftovers of a half-finished removal)
  wt --help | -h              show this help

NOTES:
  - <name> is the worktree directory basename; Tab-completion is available.
  - the picker filters as you type: the characters must appear in the name or branch
    in order, but not next to each other ('e94' finds EDU-9942-...), and spaces are
    ignored; rows carrying the filter literally are listed first. ESC clears an active
    filter, a second ESC closes the picker. DEL removes the highlighted worktree after
    a y/N confirmation - it refuses main and current, and offers -Force only when git
    keeps the directory back.
  - clean ends in a menu, not a y/N: take all of it, only the merged/squashed ones, only
    the no-commits/untracked ones, only the orphan dirs, or 's' to type names/branches
    (space or comma separated, Tab cycles the matching candidates). -Yes skips the menu.
  - worktrees land in <repo>/.claude/worktrees/ when the repo has a .claude dir,
    else in <repo>/.worktrees/. 'checkout' on an already-checked-out branch just cd's.
  - rm without -Force lets git do the delete, so it can hit MAX_PATH on deep
    node_modules/obj trees ("Filename too long"); git config --global core.longpaths true
    fixes that for git everywhere. rm -Force and clean bypass git and never hit it.
  - rename uses 'git worktree move': local only, leaves branch/remote untouched.
  - clean detects squash-merges (how PRs land on acceptance), not just fast-forward
    merges: it replays the branch as one commit on the merge-base and asks git cherry
    whether the base already carries that patch. Deletion goes through PowerShell, with
    robocopy as fallback - never git - so deep paths cannot trip MAX_PATH. Gitignored
    files (node_modules, generated config) never block a removal. Uncommitted edits and
    untracked-but-not-ignored files do: a file nobody has added yet reads the same as a
    stray one, so it is kept until -Force says otherwise, and -Force lists what it takes.
  - clean measures every candidate before it deletes anything: the Size column is the
    sum of the file sizes in that worktree (node_modules, bin/, obj/ included - what git
    ignores still takes up disk), junctions are not followed, and the closing line adds
    up only the removals that succeeded.
  - module: $PSScriptRoot
  - project: https://github.com/WizX20/PSWorktree
"@ | Write-Host
}
function wt {
    param([Parameter(Position = 0)][string]$Command, [Parameter(Position = 1)][string]$Arg, [Parameter(Position = 2)][string]$Arg2, [switch]$Force, [switch]$DryRun, [switch]$Yes, [switch]$IncludeGone,
        [switch]$KeepBranch, [switch]$NoFetch, [switch]$Orphans, [Alias('h')][switch]$Help)
    if ($Help -or $Command -in '--help', 'help', '-h', '/?') { Show-WtHelp; return }
    switch ($Command) {
        '' { Select-Worktree }
        'list' { Show-Worktrees }
        'add' { Add-Worktree $Arg $Arg2 }
        { $_ -in 'checkout', 'co' } { Enter-BranchWorktree $Arg $Arg2 }
        { $_ -in 'rm', 'remove' } { Remove-Worktree $Arg -Force:$Force }
        { $_ -in 'rename', 'mv' } { Rename-Worktree $Arg $Arg2 }
        { $_ -in 'clean', 'prune' } { Clear-MergedWorktrees -Base $Arg -DryRun:$DryRun -Yes:$Yes -IncludeGone:$IncludeGone -KeepBranch:$KeepBranch -NoFetch:$NoFetch -Force:$Force -Orphans:$Orphans }
        default {
            $m = Resolve-Worktree $Command
            if ($m) { Set-Location -LiteralPath $m.Path } else { Write-Host "no worktree '$Command'" -ForegroundColor Yellow }
        }
    }
}
Register-ArgumentCompleter -CommandName wt -ParameterName Command -ScriptBlock {
    param($c, $p, $word)
    @('list', 'add', 'checkout', 'rm', 'rename', 'clean', '--help') + (Get-Worktrees).Name | Where-Object { Test-WtPrefix $_ $word } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}
Register-ArgumentCompleter -CommandName wt -ParameterName Arg -ScriptBlock {
    param($c, $p, $word, $ast, $bound)
    if ($bound['Command'] -in 'add', 'checkout', 'co') {
        $taken = (Get-Worktrees).Branch
        $names = git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>$null |
            Where-Object { $_ -ne 'origin/HEAD' } | ForEach-Object { $_ -replace '^origin/', '' } | Sort-Object -Unique
        if ($bound['Command'] -ne 'add') { $names = $names | Where-Object { $_ -notin $taken } }
    }
    else { $names = (Get-Worktrees).Name }
    $names | Where-Object { Test-WtPrefix $_ $word } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}
Export-ModuleMember -Function wt
