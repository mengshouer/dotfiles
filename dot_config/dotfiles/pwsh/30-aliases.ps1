# Shared PowerShell aliases.

$aliases = [ordered]@{
    j     = "z"
    ji    = "zi"

    ".."  = "Set-Location .."
    "..." = "Set-Location ../.."

    ll    = "Get-ChildItem -Force"
    la    = "Get-ChildItem -Force -Hidden"
    l     = "Get-ChildItem"

    g     = "git"
    gs    = "git status"
    gst   = "git stash"
    ga    = "git add"
    gaa   = "git add ."
    gct   = "git commit"
    gp    = "git push"
    gpl   = "git pull"
    gch   = "git checkout"
    gr1   = "git reset --soft HEAD~1"
    gl    = "git log --oneline --graph"

    nr    = "npm run"

    c     = "code ."

    d     = "docker"
    dc    = "docker compose"

    py    = "python"
    uvpy  = "uv run python"
    uvpip = "uv pip"

    ard   = "aria2c --summary-interval=10 -x 3 --allow-overwrite=true -Z"

    s     = "scoop"
}

foreach ($alias in $aliases.GetEnumerator()) {
    Set-Item -LiteralPath "Function:global:$($alias.Key)" -Value "& $($alias.Value) @args"
}

Remove-Variable aliases

# Quick-edit local override files (machine-specific, not in repo).
function script:Invoke-DotfilesEditor {
    param([string]$Path)

    $editor = $env:VISUAL
    if (-not $editor) { $editor = $env:EDITOR }
    if (-not $editor) {
        if (Get-Command code -ErrorAction SilentlyContinue) { $editor = "code" }
        elseif (Get-Command notepad -ErrorAction SilentlyContinue) { $editor = "notepad" }
        else { $editor = "vi" }
    }

    & $editor $Path
}

function global:elocal       { Invoke-DotfilesEditor (Join-Path $HOME ".config\dotfiles\local.ps1") }
function global:elocalenv    { Invoke-DotfilesEditor (Join-Path $HOME ".config\dotfiles\local.env") }
function global:egit         { Invoke-DotfilesEditor (Join-Path $HOME ".gitconfig") }
function global:egitignore   {
    $target = Join-Path $HOME ".config\git\ignore.local"
    Invoke-DotfilesEditor $target
    # ignore.local is included into ~/.config/git/ignore via chezmoi template.
    # Re-apply so edits take effect immediately. GUI editors that detach
    # (e.g. `code` without -w) may run apply before you save; re-run
    # `chezmoi apply ~/.config/git/ignore` after saving in that case.
    if (Get-Command chezmoi -ErrorAction SilentlyContinue) {
        chezmoi apply (Join-Path $HOME ".config\git\ignore") 2>$null
    }
}
