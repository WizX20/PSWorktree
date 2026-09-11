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

A git worktree helper for PowerShell. One command, `wt`, gives you an interactive picker to jump between worktrees, plus `list`, `add`, `checkout`, `rename`, `rm` and a `clean` that knows which branches already landed upstream — squash-merges included.

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
2. adds one line to your PowerShell profile (`$PROFILE.CurrentUserAllHosts`) — `Import-Module PSWorktree -ErrorAction SilentlyContinue  # wt: git worktree helper (scoop install psworktree)`;
3. imports the module into the shell you ran `scoop install` from, so `wt` works **right away**, no restart.

Step 2 is needed because `wt` is also the name of Windows Terminal's launcher (`wt.exe`): PowerShell prefers a function over an executable only once the function exists, so the module must be imported rather than left to auto-loading. Windows Terminal stays reachable as `wt.exe`.

Update with `scoop update psworktree`.

### Windows — winget

Coming later. Until then use Scoop or the manual install.

### Manual

1. Download `PSWorktree-<version>.zip` from [GitHub Releases](https://github.com/WizX20/PSWorktree/releases/latest).
2. Extract the `PSWorktree` folder into a directory on your `PSModulePath` — for PowerShell 7 that is `$HOME\Documents\PowerShell\Modules\`, for Windows PowerShell 5.1 `$HOME\Documents\WindowsPowerShell\Modules\`.
3. Add `Import-Module PSWorktree` to your profile (`notepad $PROFILE`).

### From a checkout

```powershell
git clone https://github.com/WizX20/PSWorktree.git
cd PSWorktree
task link          # junctions src/PSWorktree into your CurrentUser module path
Import-Module PSWorktree -Force
```

## Getting started

```powershell
wt                       # pick a worktree: Up/Down, Enter to cd, Del to remove, type to filter
wt add feature/login     # new branch + worktree, cd in
wt co EDU-1234-fix       # existing branch (local or on origin) into a worktree, cd in
wt list                  # who's where
wt clean                 # remove worktrees whose branch already landed on origin/main|acceptance
```

`wt clean` ends in a menu rather than a blunt y/N: take everything, only the merged/squashed ones, only the never-diverged ones, only orphan directories, or pick by name with Tab completion. Nothing with uncommitted or untracked work is removed unless you say `-Force`, and `-Force` tells you what it is about to delete.

## `wt --help`

```text
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
       -DryRun        only show what would go
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
  - module: C:\Users\you\scoop\apps\psworktree\current
  - project: https://github.com/WizX20/PSWorktree
```

## Claude Code worktrees

Claude Code isolates parallel sessions in git worktrees under `<repo>/.claude/worktrees/<name>` (`claude --worktree`, the `EnterWorktree` tool, background jobs). Those directories are ordinary worktrees as far as git is concerned, which is exactly what `wt` operates on:

- **Find them** — the picker lists every worktree git knows about, Claude's included; type a few characters of the branch to filter.
- **Same layout for your own** — `wt add` and `wt checkout` put new worktrees in `.claude/worktrees/` whenever the repo has a `.claude` directory, so Claude's and yours sit side by side. Repos without one get `.worktrees/` instead.
- **Sweep after the merge** — `wt clean` recognises branches that landed as a squash-merge (the usual way a PR lands), not only fast-forwards, and removes the worktree plus the local branch. `-Orphans` also removes leftover directories from a removal that died halfway.
- **Hooks that never ran** — repos that initialise a worktree from a `post-checkout` hook silently skip it when `core.hooksPath` is not wired up; `wt add` warns when it sees a `.githooks` folder without that setting.
- **Long names** — `wt add` warns when a worktree name is over 30 characters: deep build trees (`node_modules`, `obj`) under a long path blow past `MAX_PATH` on Windows.

## Uninstall

- **Scoop:** `scoop uninstall psworktree`. The `Import-Module PSWorktree` line in your profile is harmless afterwards (it carries `-ErrorAction SilentlyContinue`); delete it when convenient.
- **Manual:** delete the `PSWorktree` folder from your modules directory and remove the `Import-Module PSWorktree` line from your profile.

## Contributing

Bug reports, feature ideas, and pull requests welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) to get started. Running from source, tests, and the release pipeline are documented in [DEVGUIDE.md](DEVGUIDE.md). All participants are expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
