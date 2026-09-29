# PSWorktree for bash (Git Bash, WSL) and zsh: `wt` runs `git wt` and then does the one thing
# a git alias cannot - cd this shell. `wt install bash` sources this file from ~/.bashrc.
#
# git starts `git wt` as a child process, and a child cannot change its parent's directory.
# So `git wt` writes the directory it would cd into to the file named in PSWORKTREE_CD_FILE,
# and the function goes there once it is done. The terminal is never captured: the picker
# stays interactive, and messages show as they come.
wt() {
    local wt_file wt_dir wt_rc
    if [ "$1" = "--help" ]; then shift; set -- help "$@"; fi    # git would answer --help itself
    wt_file=$(mktemp) || return 1
    # Git Bash: git and PowerShell are Windows programs and want C:\... paths.
    PSWORKTREE_CD_FILE=$(cygpath -w "$wt_file" 2>/dev/null || printf '%s' "$wt_file") git wt "$@"
    wt_rc=$?
    wt_dir=$(cat "$wt_file" 2>/dev/null)
    rm -f "$wt_file"
    if [ -n "$wt_dir" ]; then cd "$wt_dir" || wt_rc=$?; fi
    return $wt_rc
}
