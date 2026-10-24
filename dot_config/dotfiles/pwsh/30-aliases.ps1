# Shared PowerShell aliases and lazy command stubs.

function global:Invoke-DotfilesAliasCommand {
    param(
        [string]$Command,
        [object[]]$Arguments
    )

    # Use Invoke-Expression to mimic bash-style alias (text substitution).
    # This ensures .ps1 wrappers (e.g. fnm's npm.ps1) that parse
    # $MyInvocation.Statement see the full command text with real arguments,
    # instead of the unexpanded literal "@args".
    if ($Arguments.Count) {
        $quoted = foreach ($arg in $Arguments) {
            $str = $arg.ToString()
            if ($str.Contains(' ')) {
                '"{0}"' -f ($str -replace '"', '\"')
            } else {
                $str
            }
        }
        Invoke-Expression ($Command + ' ' + ($quoted -join ' '))
    } else {
        Invoke-Expression $Command
    }
}

function global:Set-DotfilesAlias {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Command
    )

    $escaped = $Command.Replace("'", "''")
    $body = "Invoke-DotfilesAliasCommand '$escaped' `$args"

    if (Get-Alias -Name $Name -ErrorAction SilentlyContinue) {
        Remove-Item -LiteralPath "Alias:$Name" -Force -Confirm:$false -ErrorAction SilentlyContinue
    }
    Set-Item -LiteralPath "Function:global:$Name" -Value $body
}

function global:_al {
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Definition
    )

    $name, $command = $Definition -split "=", 2
    Set-DotfilesAlias -Name $name -Command $command
}

function global:j     { Invoke-DotfilesAliasCommand 'z' $args }
function global:ji    { Invoke-DotfilesAliasCommand 'zi' $args }

function global:..    { Invoke-DotfilesAliasCommand 'Set-Location ..' $args }
function global:...   { Invoke-DotfilesAliasCommand 'Set-Location ../..' $args }

function global:ll    { Invoke-DotfilesAliasCommand 'Get-ChildItem -Force' $args }
function global:la    { Invoke-DotfilesAliasCommand 'Get-ChildItem -Force -Hidden' $args }
function global:l     { Invoke-DotfilesAliasCommand 'Get-ChildItem' $args }

function global:g     { Invoke-DotfilesAliasCommand 'git' $args }
function global:gs    { Invoke-DotfilesAliasCommand 'git status' $args }
function global:gst   { Invoke-DotfilesAliasCommand 'git stash' $args }
function global:ga    { Invoke-DotfilesAliasCommand 'git add' $args }
function global:gaa   { Invoke-DotfilesAliasCommand 'git add .' $args }
function global:gct   { Invoke-DotfilesAliasCommand 'git commit' $args }
function global:gph   { Invoke-DotfilesAliasCommand 'git push' $args }
function global:gpl   { Invoke-DotfilesAliasCommand 'git pull' $args }
function global:gch   { Invoke-DotfilesAliasCommand 'git checkout' $args }
function global:gr1   { Invoke-DotfilesAliasCommand 'git reset --soft HEAD~1' $args }
function global:glg   { Invoke-DotfilesAliasCommand 'git log --oneline --graph' $args }

function global:nr    { Invoke-DotfilesAliasCommand 'npm run' $args }

function global:c     { Invoke-DotfilesAliasCommand 'code .' $args }

function global:d     { Invoke-DotfilesAliasCommand 'docker' $args }
function global:dc    { Invoke-DotfilesAliasCommand 'docker compose' $args }

function global:py    { Invoke-DotfilesAliasCommand 'python' $args }
function global:uvpy  { Invoke-DotfilesAliasCommand 'uv run python' $args }
function global:uvpip { Invoke-DotfilesAliasCommand 'uv pip' $args }

function global:ard   { Invoke-DotfilesAliasCommand 'aria2c --summary-interval=10 -x 3 --allow-overwrite=true -Z' $args }

function global:s     { Invoke-DotfilesAliasCommand 'scoop' $args }

# Lazy-load heavy interactive commands (opendir, toclip, elocal*) on first call.
function global:Import-DotfilesLazyCommands {
    . ([System.IO.Path]::Combine($HOME, ".config\dotfiles\pwsh\lazy-commands.ps1"))
}

function global:opendir {
    Import-DotfilesLazyCommands
    opendir @args
}

function global:toclip {
    Import-DotfilesLazyCommands
    if ($MyInvocation.ExpectingInput) {
        @($input) | toclip @args
    } else {
        toclip @args
    }
}

function global:elocal     { Import-DotfilesLazyCommands; elocal @args }
function global:elocalenv  { Import-DotfilesLazyCommands; elocalenv @args }
function global:egit       { Import-DotfilesLazyCommands; egit @args }
function global:egitignore { Import-DotfilesLazyCommands; egitignore @args }
