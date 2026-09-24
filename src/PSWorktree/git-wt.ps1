# `git wt` entry point: the global git alias that `wt install git` sets up runs this file with
# the arguments after `git wt`. git starts an alias as a child process, and a child cannot
# change its parent shell's directory - so the module is told, and every place `wt` would cd
# prints the path instead.
$module = Import-Module (Join-Path $PSScriptRoot 'PSWorktree.psd1') -PassThru
& $module { $script:ViaGit = $true }
wt @args
