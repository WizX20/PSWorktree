# Developer Guide

Contributor reference for PSWorktree (`wt`). End-user install and usage live in [README.md](README.md).

## Layout

```
src/PSWorktree/PSWorktree.psm1                the module: all helpers + the `wt` dispatcher + completers
src/PSWorktree/PSWorktree.psd1                module manifest (ModuleVersion is the release version)
tests/PSWorktree.Tests.ps1            Pester 5+ suite; builds throwaway git repos under $TestDrive
scripts/                      lint / test / pack / set-version / cut-changelog / dev-link
bucket/psworktree.json                Scoop manifest; this repo doubles as the Scoop bucket
.github/workflows/ci.yml      lint + test on pwsh and Windows PowerShell 5.1, then pack
.github/workflows/release.yml manual release: stamp, test, pack, bump bucket, tag, GitHub Release
.gitconfig                    maintainer-only: makes this clone talk to GitHub as WizX20
Taskfile.yml                  `task --list`
```

## Running from source

```powershell
task link                   # junction src/PSWorktree into your CurrentUser module path
Import-Module PSWorktree -Force     # after every edit
task unlink                 # remove the junction
```

Or skip the junction and load by path: `Import-Module ./src/PSWorktree -Force`.

Requires PowerShell 7 or Windows PowerShell 5.1, git, and [Task](https://taskfile.dev) for the `task` shortcuts (every task is a one-liner you can also run by hand).

## Tests and lint

```powershell
task check                  # lint + test, what CI runs
task lint                   # PSScriptAnalyzer over src/, scripts/, tests/
task test                   # Pester; `task test -- tests/PSWorktree.Tests.ps1` for one file
task help                   # print `wt --help` (the README quotes it verbatim)
```

- Tests need **Pester 5+** (`Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser -Force -SkipPublisherCheck`) and lint needs **PSScriptAnalyzer** (`Install-Module PSScriptAnalyzer -Scope CurrentUser`). On CI both are installed on the fly when missing. The Pester 3.4 that ships with Windows cannot run the suite.
- The suite creates a bare `origin` plus a clone per test, so `add`, `checkout`, `rename`, `rm` and every `clean` classification (merged / squashed / open / no-commits / orphan) run against real git. Private helpers are reached with `InModuleScope PSWorktree`.
- `wt` prints through `Write-Host`; tests capture it with `6>&1` (the `Get-WtOutput { wt ... }` helper). Call `wt` with real switches inside the block — splatting `'-Force'` as a string would bind it positionally.
- The interactive picker and the `clean` menu read the console directly and are not under test; try them by hand in a repo with a few worktrees.

## GitHub account: everything as WizX20

This repo is published from a machine that also has a work GitHub account logged in to `gh`. Rather than `gh auth switch` back and forth, the repo carries a [`.gitconfig`](.gitconfig) that a maintainer includes once per clone:

```powershell
task setup      # = git config --local include.path ../.gitconfig
```

From then on, inside this clone:

- commits are authored as `WizX20 <…>`;
- `git push` / `git fetch` authenticate as WizX20 — the credential helper obtains that account's token from the keyring at call time via `gh auth token --user WizX20` and hands it to `gh auth git-credential` through `GH_TOKEN` (the CLI's helper otherwise only serves the *active* account);
- `git gh <anything>` (or `task gh -- <anything>`) runs the GitHub CLI the same way: `git gh pr create`, `git gh run watch`, …

Nothing is written to disk and the active `gh` account is untouched. Plain `gh` still uses whatever account is active — use `git gh` in this repo. Contributors never need any of this; without the include the file is inert.

## Release process

Releases are cut by `.github/workflows/release.yml`. It runs **once a week, Tuesday 06:00 UTC**, and on manual dispatch — nothing else triggers it:

```powershell
task release                    # release now: next patch version (or the manifest's version if that was never released)
task release VERSION=1.1.0      # release now with an explicit version
```

The `check` job decides first, on `main`:

1. **Anything to release?** If `main` is exactly the commit of the latest `v*` tag, stop quietly (the weekly run is a no-op on a quiet week).
2. **Which version?** The dispatch input if given; else the manifest's `ModuleVersion` when no tag for it exists yet (first release, or a bump made in a PR); else the next patch of it. For a **minor/major** bump, raise `ModuleVersion` in `src/PSWorktree/PSWorktree.psd1` in your PR — the next release ships exactly that.
3. **Validate** — plain `x.y.z`, no such tag yet, not below the manifest version.
4. **Gate on CI** — the latest completed CI run on `main` must be `success`.

Then the `release` job:

5. **Stamp** — `scripts/set-version.ps1` writes `ModuleVersion`; `scripts/cut-changelog.ps1 -FallbackFromGit` turns `## [Unreleased]` into `## [x.y.z] - <date>` and extracts that section as the release notes. An empty section is filled from the commit subjects since the last tag, so write readable subjects even when you skip the changelog.
6. **Lint + test** the stamped module.
7. **Pack** — `scripts/pack.ps1` builds `dist/PSWorktree-x.y.z.zip` (top-level `PSWorktree/` folder with `PSWorktree.psd1`, `PSWorktree.psm1`, `LICENSE`, `NOTICE`) and prints its SHA256.
8. **Bump the bucket** — `bucket/psworktree.json` gets the new `version`, `url` and `hash`, edited in place.
9. **Commit + tag** `chore: release vx.y.z` on `main` (as `github-actions[bot]`), push with the `vx.y.z` tag.
10. **GitHub Release** `vx.y.z` with the zip attached and the changelog section as body.

If step 10 fails after step 9 pushed, create the release by hand with `git gh release create vx.y.z dist/PSWorktree-x.y.z.zip` from a fresh checkout of the tag — the tag check in step 3 refuses a re-run.

### First release

`bucket/psworktree.json` ships with a placeholder hash until the first release has run; `scoop install psworktree` fails with a hash mismatch before that. Run `task release` once the repo is on GitHub and CI is green — it ships the manifest's `1.0.0`.

### Required secret: `PSWORKTREE_RELEASE_TOKEN`

`main` is protected by a ruleset (pull requests only, squash merges only, CI checks required, no force-push; only the repository admin may bypass). `GITHUB_TOKEN` cannot bypass rulesets on a user-owned repository, so the release commit is pushed with a maintainer token:

1. GitHub → Settings → Developer settings → Personal access tokens → **Fine-grained tokens** → Generate. Resource owner `WizX20`, repository access: only `PSWorktree` (ActionsMonitor has its own token, `ACTIONSMONITOR_RELEASE_TOKEN`), permissions: **Contents: Read and write** (Metadata: Read is added automatically). Expiry: one year at most — note the date.
2. `git gh secret set PSWORKTREE_RELEASE_TOKEN -R WizX20/PSWorktree` and paste the token.

The `check` job fails early with a clear message when the secret is missing. A push with this token also triggers CI on `main` for the release commit — expected, one extra run per release. Without expiry the same can be done with a GitHub App added to the ruleset's bypass list; not worth it for one maintainer.

### Branch rules (ruleset `main`)

Managed on GitHub: **Settings → Rules → Rulesets → main**. Pull request required, `squash` the only merge method, required checks `lint + test (pwsh)`, `lint + test (powershell)` and `pack module zip`, deletion and force-push blocked; bypass list: repository admin only. Direct pushes to `main` are therefore impossible for everyone but the owner, and a PR cannot be squash-merged before CI is green.

### Repo visibility

Scoop fetches release assets over unauthenticated HTTPS. `WizX20/PSWorktree` must stay **public** for `scoop install` to work.

## Scoop bucket maintenance

- Manifest: `bucket/psworktree.json`. The release workflow bumps `version`/`url`/`hash`; `checkver: github` + `autoupdate` let `scoop update` find new releases.
- Users subscribe to the bucket straight from this repo: `scoop bucket add psworktree https://github.com/WizX20/PSWorktree`. The bucket name is a local alias for the repo URL — Scoop keys buckets by that alias, one repo each, so a second WizX20 project needs its own alias (ActionsMonitor's README uses `wizx20` for *its* repo). If the number of tools grows, the manifests belong together in one `WizX20/scoop-bucket` repo that the release workflows push into; until then, per-repo buckets keep each release self-contained.
- `psmodule.name: PSWorktree` makes Scoop junction `~/scoop/modules/PSWorktree` to the install dir and put `~/scoop/modules` on the user's `PSModulePath` (registry). `post_install` then patches `PSModulePath` in the running process, appends a guarded `Import-Module PSWorktree` line to `$PROFILE.CurrentUserAllHosts` (once; `wt.exe` = Windows Terminal would otherwise shadow the function until something imports the module), and imports the module into the current session. `post_uninstall` unloads it and leaves the profile line, which is harmless thanks to `-ErrorAction SilentlyContinue`.
- To try a manifest change before a release, test the hook script on its own: load `bucket/psworktree.json`, `[scriptblock]::Create($m.post_install -join "`r`n")`, and invoke it with `$dir`, `$global` and a throwaway `$PROFILE` object defined.

## winget

Not yet. winget has no notion of PowerShell modules; publishing `wt` there means wrapping the module in an installer or a portable that also wires the profile. Tracked as a later addition — the README says so.

## Conventions

- **Changelog** — add a line under `## [Unreleased]` for user-visible changes; the release workflow stamps the version. Never edit released sections.
- **Help text** — `Show-WtHelp` is the contract; the README quotes it. Change both.
- **Commits** — new commits, no amends of published commits, no skipped hooks.
- **Deleting directories** — always through `Remove-WorktreePath`, never through `git worktree remove` on Windows.
