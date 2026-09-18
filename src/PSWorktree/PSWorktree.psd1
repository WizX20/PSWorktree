@{
    RootModule        = 'PSWorktree.psm1'
    ModuleVersion     = '1.1.0'
    GUID              = '8a143b3e-9f1a-4613-aeb5-85994128ed15'
    Author            = 'WizX20'
    CompanyName       = 'WizX20'
    Copyright         = '(c) 2026 WizX20. Business Source License 1.1.'
    Description       = 'wt - git worktree helper for PowerShell: an interactive picker plus list / cd / add / checkout / rename / remove / clean for any git worktree, including the ones Claude Code creates under .claude/worktrees/.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport = @('wt')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('git', 'worktree', 'claude-code', 'windows', 'cli')
            LicenseUri = 'https://github.com/WizX20/PSWorktree/blob/main/LICENSE'
            ProjectUri = 'https://github.com/WizX20/PSWorktree'
            ReleaseNotes = 'https://github.com/WizX20/PSWorktree/blob/main/CHANGELOG.md'
        }
    }
}
