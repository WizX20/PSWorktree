<p align="center">
  <a href="https://github.com/WizX20">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="docs/wizx20.png">
      <img src="docs/wizx20-transparent.png" alt="WizX20" height="140">
    </picture>
  </a>
</p>

# PSWorktree

[![CI](https://github.com/WizX20/PSWorktree/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/WizX20/PSWorktree/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/WizX20/PSWorktree?label=release)](https://github.com/WizX20/PSWorktree/releases/latest)

A git worktree helper for PowerShell. One command — `git wt` out of the box, or plain `wt` once you add it to your profile — gives you an interactive picker to jump between worktrees, plus `list`, `add`, `checkout`, `rename`, `rm` and a `clean` that knows which branches already landed upstream — squash-merges included.

It understands the worktrees that **Claude Code** creates (`claude -w`, the `EnterWorktree` tool, `--worktree` sessions) under `<repo>/.claude/worktrees/`: they show up in the picker like any other worktree, `wt add` puts new ones in the same place, and `wt clean` sweeps them up once their PR is merged.

> See the [Changelog](CHANGELOG.md) for updates.

## License

This project is licensed under the [Business Source License 1.1](LICENSE) (BUSL-1.1). Free for personal, internal, academic, and non-commercial redistribution use; resale or paid commercial distribution is not permitted. Converts to Apache 2.0 on the Change Date (2030-09-01). All copies and forks must retain the [NOTICE](NOTICE) file.

## Requirements

- **Windows** 10 / 11
- **PowerShell 7** (recommended) or **Windows PowerShell 5.1**
- **git** 2.17 or newer on `PATH`

## Install

### Windows — Scoop (recommended)

```powershell
scoop bucket add psworktree https://github.com/WizX20/PSWorktree
scoop install psworktree
```

(This repo doubles as its own Scoop bucket. The first `psworktree` is just the local name you give that bucket; the second is the app, from `bucket/psworktree.json`.)

That is the whole setup. The install:

1. drops the `PSWorktree` module in `~/scoop/modules/` and adds that folder to your `PSModulePath`;
2. sets up **`git wt`**: a global git alias (`git config --global alias.wt`) that runs the module in a child PowerShell. It works **right away**, from any shell — PowerShell 7, Windows PowerShell, cmd, Git Bash.

Your PowerShell profile is not touched. For plain `wt`, which can also cd, see [the `wt` command](#optional-the-wt-command) below.

Update with `scoop update psworktree`; `scoop uninstall psworktree` takes the alias away again.

Upgrading from 1.1 or older? Those versions put the `Import-Module PSWorktree` line in your profile themselves. It stays, so `wt` keeps working, and the update adds `git wt` next to it.

### Optional: the `wt` command

`git wt` has one limit: git runs an alias in a child process, and a child process cannot change the directory of the shell that started it. So where `wt` would cd — Enter in the picker, `add`, `checkout`, `wt <name>` — `git wt` prints the way there instead:

```text
cd "C:\src\app\.claude\worktrees\feature-login"
```

To actually jump around, add the `wt` command to your PowerShell profile:

```powershell
git wt install profile
```

That appends one line to `$PROFILE.CurrentUserAllHosts` — `Import-Module PSWorktree -ErrorAction SilentlyContinue  # wt: git worktree helper (wt uninstall profile removes this)` — so every new PowerShell session has `wt`; in the current one, run `Import-Module PSWorktree`. `git wt` keeps working alongside, and both take the same commands.

- The profile is the one of the PowerShell that runs the command, and `git wt` uses PowerShell 7 when it is installed. To get `wt` in Windows PowerShell 5.1, run `Import-Module PSWorktree; wt install profile` from a 5.1 prompt.
- Why a profile line rather than auto-loading: `wt` is also the name of Windows Terminal's launcher (`wt.exe`), and PowerShell prefers the function over the executable only once the module is imported. Windows Terminal stays reachable as `wt.exe`.
- `wt uninstall profile` takes the line out again.

### Windows — winget

Coming later. Until then use Scoop or the manual install.

### Manual

1. Download `PSWorktree-<version>.zip` from [GitHub Releases](https://github.com/WizX20/PSWorktree/releases/latest).
2. Extract the `PSWorktree` folder into a directory on your `PSModulePath` — for PowerShell 7 that is `$HOME\Documents\PowerShell\Modules\`, for Windows PowerShell 5.1 `$HOME\Documents\WindowsPowerShell\Modules\`.
3. Set up `git wt`, [the `wt` command](#optional-the-wt-command), or both:

   ```powershell
   Import-Module PSWorktree
   wt install git        # git wt: a global git alias to the folder you extracted to
   wt install profile    # wt: an Import-Module line in your profile
   ```

   The alias names that folder; extract a new version somewhere else and run `wt install git` again.

### From a checkout

```powershell
git clone https://github.com/WizX20/PSWorktree.git
cd PSWorktree
task link          # junctions src/PSWorktree into your CurrentUser module path
Import-Module PSWorktree -Force
wt install git     # optional: git wt, running this checkout
```

## Getting started

```powershell
git wt                       # pick a worktree: Up/Down, Enter to go there, Del to remove, type to filter
git wt add feature/login     # new branch + worktree
git wt co EDU-1234-fix       # existing branch (local or on origin) into a worktree
git wt list                  # who's where
git wt clean                 # remove worktrees whose branch already landed on origin/main|acceptance
```

With [the `wt` command](#optional-the-wt-command), drop the `git`: `wt add feature/login` also cd's you into the new worktree, and Enter in the picker takes you there. Help is `git wt help` — `git wt --help` is answered by git itself, with what the alias runs.

`wt clean` ends in a menu rather than a blunt y/N: take everything, only the merged/squashed ones, only the never-diverged ones, only orphan directories, or pick by name with Tab completion. Nothing with uncommitted or untracked work is removed unless you say `-Force`, and `-Force` tells you what it is about to delete. Every candidate is measured first, so the table shows what each one holds, `-DryRun` says how much a clean would free, and the closing line reports what it reclaimed — `node_modules`, `bin/` and `obj/` included.

## Help: `git wt help`

```text
wt - git worktree helper (works with git/Claude-created worktrees)

Two ways in, same commands: 'git wt ...', a global git alias that works from any shell,
and 'wt ...', the PowerShell command your profile can import ('git wt install profile').
Only 'wt' can cd: git runs an alias in a child process, which cannot move your shell, so
wherever the usage below says cd, 'git wt' prints the path instead.

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
  wt install git [-Force]     set up 'git wt': a global git alias to this module
  wt install profile          set up the 'wt' command: an Import-Module line in your
                              PowerShell profile, so every new session has it
  wt uninstall git|profile    take either one out again
  wt help | -h | --help       show this help ('git wt --help' is answered by git itself)

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
  - 'git wt' runs git-wt.ps1 from the module folder in pwsh (powershell.exe when there is
    no pwsh) without your profile. git starts it at the top of the worktree you are in.
    'install git' will not replace a 'wt' alias of another tool unless -Force. Under
    'git wt', rename refuses the worktree you are in: your shell holds that directory.
  - 'install profile' writes $PROFILE.CurrentUserAllHosts of the PowerShell running it -
    via 'git wt' that is pwsh; from Windows PowerShell 5.1 run it as 'wt install profile'.
    The line imports PSWorktree by name, so the module must sit on PSModulePath (Scoop,
    'task link' and the manual install all put it there).
  - module: C:\Users\you\scoop\apps\psworktree\current
  - project: https://github.com/WizX20/PSWorktree
```

## Claude Code worktrees

Claude Code isolates parallel sessions in git worktrees under `<repo>/.claude/worktrees/<name>` (`claude --worktree`, the `EnterWorktree` tool, background jobs). Those directories are ordinary worktrees as far as git is concerned, which is exactly what `wt` operates on:

- **Find them** — the picker lists every worktree git knows about, Claude's included; type a few characters of the branch to filter.
- **Same layout for your own** — `wt add` and `wt checkout` put new worktrees in `.claude/worktrees/` whenever the repo has a `.claude` directory, so Claude's and yours sit side by side. Repos without one get `.worktrees/` instead.
- **Sweep after the merge** — `wt clean` recognises branches that landed as a squash-merge (the usual way a PR lands), not only fast-forwards, and removes the worktree plus the local branch, reporting the disk space that freed. `-Orphans` also removes leftover directories from a removal that died halfway.
- **Hooks that never ran** — repos that initialise a worktree from a `post-checkout` hook silently skip it when `core.hooksPath` is not wired up; `wt add` warns when it sees a `.githooks` folder without that setting.
- **Long names** — `wt add` warns when a worktree name is over 30 characters: deep build trees (`node_modules`, `obj`) under a long path blow past `MAX_PATH` on Windows.

## Uninstall

- **Scoop:** `scoop uninstall psworktree` — the `git wt` alias goes with it. If you added the `wt` command, run `wt uninstall profile` first; a leftover `Import-Module PSWorktree` line is harmless (it carries `-ErrorAction SilentlyContinue`), so deleting it later is fine too.
- **Manual:** `wt uninstall git` and `wt uninstall profile`, then delete the `PSWorktree` folder from your modules directory.

## Contributing

Bug reports, feature ideas, and pull requests welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) to get started. Running from source, tests, and the release pipeline are documented in [DEVGUIDE.md](DEVGUIDE.md). All participants are expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
