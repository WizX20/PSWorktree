@{
    # Information-level rules (comment help, positional parameters) are style advice for
    # published cmdlets; `wt` is a console tool with its own --help.
    Severity     = @('Error', 'Warning')

    ExcludeRules = @(
        # `wt` is an interactive console tool: coloured Write-Host lines ARE its output.
        'PSAvoidUsingWriteHost',
        # The internal Remove-/Rename-/Clear- helpers are driven by `wt rm` / `wt clean`, which
        # carry their own confirmation flow (-Force, -Yes, y/N prompts) instead of ShouldProcess.
        'PSUseShouldProcessForStateChangingFunctions',
        'PSUseSingularNouns',
        # Argument-completer script blocks must declare the leading positions of the
        # ($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        # signature to reach the later ones, so the first two are unused by design.
        'PSReviewUnusedParameter',
        # False positive on `if ($x -eq (git ... 2>$null))`: the rule sees the '>' of a
        # stderr redirection inside a condition and suspects a mistyped comparison.
        'PSPossibleIncorrectUsageOfRedirectionOperator'
    )
}
