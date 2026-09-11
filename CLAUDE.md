# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

**PSWorktree** — a PowerShell module (`src/PSWorktree/`) exporting one command, `wt`: an interactive git worktree picker plus `list`/`add`/`checkout`/`rename`/`rm`/`clean`. It targets Windows, PowerShell 7 **and** Windows PowerShell 5.1, and knows the `.claude/worktrees/` layout Claude Code uses. Read [DEVGUIDE.md](DEVGUIDE.md) for layout, tests and the release pipeline; [CONTRIBUTING.md](CONTRIBUTING.md) for conventions.

## GitHub account — always WizX20

This repo is published under the **WizX20** account from a machine whose active `gh` account is a work account. Never run `gh auth switch`. Inside this clone:

- `git push` / `git fetch` already authenticate as WizX20 through the included [`.gitconfig`](.gitconfig) (`task setup` once per clone — check with `git config user.name`, it must print `WizX20`).
- Use **`git gh …`** (or `task gh -- …`) instead of `gh …` for PRs, releases, workflow runs, API calls. Plain `gh` acts as the wrong account.
- Commits must be authored as `WizX20 <nerdsonwaves@outlook.com>`; if `git config user.email` shows anything else, run `task setup` before committing.

## Commands

```powershell
task check        # lint + test — run before every push
task test         # Pester (needs Pester 5+); `task test -- tests/PSWorktree.Tests.ps1`
task lint         # PSScriptAnalyzer; exclusions + reasons in PSScriptAnalyzerSettings.psd1
task help         # `wt --help` from the working copy — README quotes it, keep both in sync
task link         # dev junction into the CurrentUser module path; `task unlink` undoes
task pack         # dist/PSWorktree-<version>.zip + sha256
task release [VERSION=x.y.z] # dispatch the Release workflow now; it also runs weekly (Tuesday 06:00 UTC) and auto-bumps the patch version
```

## Rules

- **Behaviour changes need a Pester test.** The suite builds real git repos per test (`New-TestRepo`); private helpers are reachable via `InModuleScope PSWorktree`. Call `wt` with real switches inside `Get-WtOutput { wt clean -DryRun }` — never splat `'-DryRun'` as a string, it binds positionally.
- **5.1-compatible only**: no ternary, no `??`, no `.ForEach{}` on null, nothing .NET-Core-only.
- **Never delete through git** on Windows: `Remove-WorktreePath` (PowerShell → robocopy) exists because `git worktree remove` dies on `MAX_PATH`.
- **Changelog**: add a line under `## [Unreleased]`; the release workflow stamps the version (an empty section falls back to commit subjects, so keep subjects readable). Do not touch released sections.
- **Versions**: patch bumps are automatic. For a minor/major, raise `ModuleVersion` in `src/PSWorktree/PSWorktree.psd1` in the PR; the next release ships that version.
- **Help is the contract**: change `Show-WtHelp` and paste `task help` into the README block.
- **Commits**: imperative subject ≤72 chars, new commits (no amend), no `--no-verify`. Branches `feature/…`, `fix/…`, `chore/…` off `main`.
- **Do not commit or push without asking**; never push to `main` directly — open a PR.
