# Changelog

All notable changes to PSWorktree (`wt`) are listed here, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions are [semantic](https://semver.org/).
Write new entries under **Unreleased** — the Release workflow stamps the version and date.

## [Unreleased]

### Added

- First public release of `wt`, the PowerShell git worktree helper that lived in a profile script until now.
- Interactive picker (`wt`): Up/Down move, Enter cd, Del remove (asks first), Esc cancel; type to filter with a
  fuzzy subsequence match — `e94` finds `EDU-9942-…` — where literal hits are listed first.
- `wt list`, `wt <name>` (exact or prefix cd), `wt add <branch> [base]`, `wt checkout <branch> [dir]` (alias `co`),
  `wt rm <name> [-Force]`, `wt rename <old> <new>` (alias `mv`).
- `wt clean [base]` (alias `prune`): removes worktrees whose branch already landed on the upstream base — fast-forward
  **and squash-merged** — or never diverged from it, and deletes the local branch. Ends in a menu (all / merged /
  no-commits / orphans / pick by name with Tab completion); `-DryRun`, `-Yes`, `-IncludeGone`, `-KeepBranch`,
  `-NoFetch`, `-Force`, `-Orphans`.
- New worktrees land in `<repo>/.claude/worktrees/` when the repo has a `.claude` directory (the same place
  Claude Code's `claude -w` and `EnterWorktree` put theirs), else in `<repo>/.worktrees/`.
- Deletion never goes through git on Windows, so deep `node_modules`/`obj` trees cannot trip `MAX_PATH`
  (PowerShell first, robocopy as fallback).
- Tab completion for sub-commands, worktree names and branch names.
- Packaged as the `PSWorktree` PowerShell module; installable with Scoop from this repo's bucket.
