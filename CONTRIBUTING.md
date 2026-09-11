# Contributing

Thanks for taking the time to contribute to PSWorktree (`wt`).

This document covers how to file issues, propose changes, and get a pull request merged. For running from source, the tests, and the release pipeline, see [DEVGUIDE.md](DEVGUIDE.md).

By participating in this project you agree to abide by the [Code of Conduct](CODE_OF_CONDUCT.md).

## Reporting bugs

Open a [GitHub issue](https://github.com/WizX20/PSWorktree/issues/new/choose) with:

- What you did (the exact `wt` command line, numbered steps)
- What you expected
- What happened — full console output as text, plus `git worktree list --porcelain` if the worktree layout matters
- Your PowerShell edition/version and host, git version, and how you installed `wt`

If you can reproduce on the latest release from [Releases](https://github.com/WizX20/PSWorktree/releases/latest), say so.

## Suggesting features

Open an issue describing the use case before writing code. Small fixes can go straight to a PR, but anything that changes what `clean` considers safe to delete, the picker's key handling, or where worktrees are created benefits from a short design discussion first so the PR doesn't bounce on that.

## Security issues

Do **not** open a public issue for security-sensitive bugs. Use GitHub's [private security advisory](https://github.com/WizX20/PSWorktree/security/advisories/new) on this repo instead.

## Submitting a pull request

1. Fork the repo and create a topic branch off `main`.
2. Make your change. Keep the diff focused — one concern per PR.
3. Run `task check` (PSScriptAnalyzer + Pester). Add or extend a test in `tests/PSWorktree.Tests.ps1` for behaviour you changed; the suite builds real throwaway git repos, so most things can be tested for real.
4. Try it in a real repo with a few worktrees. The picker and the `clean` menu are interactive and not covered by Pester.
5. Update [`CHANGELOG.md`](CHANGELOG.md) — add a line under **Unreleased** for any user-visible change. Never edit released sections.
6. Update `Show-WtHelp` in `src/PSWorktree/PSWorktree.psm1` if a command, flag or behaviour changed, and paste the new `task help` output into the README's `wt --help` block.
7. Push and open a PR against `main`. Reference any related issue (`Fixes #123`).

CI runs lint + tests on PowerShell 7 and Windows PowerShell 5.1 for every PR — make sure both pass before requesting review.

### Branch naming

- `feature/<short-description>` — new functionality
- `fix/<short-description>` — bug fixes
- `chore/<short-description>` — refactors, build/CI, docs, dependency bumps

### Commit messages

- Imperative subject, ≤72 characters, no trailing period (`Add -Orphans to clean`, not `Added -Orphans to clean.`).
- Optional `feat:` / `fix:` / `chore:` prefix when it adds clarity — match the existing `git log` style.
- Body (when needed): wrap at 72 columns, explain **why** more than what.
- Create new commits — do not amend or force-push published commits.
- Do not skip hooks (`--no-verify`) or signing.

### Code style

- The module is a single file, `src/PSWorktree/PSWorktree.psm1`: private helpers first, `Show-WtHelp`, then the `wt` dispatcher and its argument completers at the bottom. Only `wt` is exported.
- Must run on Windows PowerShell 5.1 as well as PowerShell 7: no ternaries, no `??`, no `-Parallel`, nothing that needs .NET Core.
- No dependencies beyond git and PowerShell. `wt` is meant to be one small module you can read in a sitting.
- Console output goes through `Write-Host` with the existing colour conventions: green for done, yellow for refused/needs attention, red for errors, dark gray for hints.
- Anything that deletes files must stay on the PowerShell/robocopy path (`Remove-WorktreePath`) — `git worktree remove` hits `MAX_PATH` on deep trees.
- Comments explain *why*, not what; keep them terse.
- 4-space indentation, `PascalCase` Verb-Noun helpers, `$camelCase` locals. `task lint` must stay clean; rule exclusions live in `PSScriptAnalyzerSettings.psd1` with a reason each.

## Releasing

Maintainers only. See [DEVGUIDE.md → Release process](DEVGUIDE.md#release-process).

## Licence

By contributing you agree that your contribution is licensed under the [Business Source License 1.1](LICENSE) (BUSL-1.1), and that the [NOTICE](NOTICE) file is preserved in any redistribution.
