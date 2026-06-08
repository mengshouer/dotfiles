param(
    [Parameter(Position = 0)]
    [ValidateSet("terminal", "dev")]
    [string]$Layer = "terminal",

    [switch]$Update
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

function Write-Usage {
    @"
Usage:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\bootstrap.ps1 [dev] [-Update]

Layers:
  terminal   git chezmoi starship zoxide fzf
  dev        fnm uv

PowerShell 7 is recommended, but terminal modules are compatible with Windows
PowerShell 5.1.

Flags:
  -Update   git pull --ff-only and apply dotfiles
"@ | Write-Host
}

function Invoke-Step {
    param(
        [string]$Label,
        [scriptblock]$Action
    )

    & $Action
}

function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-RepoRoot {
    return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).ProviderPath
}

function Invoke-SourceUpdate {
    if (-not $Update) {
        return
    }

    $repoRoot = Get-RepoRoot

    if (-not (Test-Command git)) {
        throw "git is required for -Update."
    }

    $isGitWorktree = $false
    try {
        & git -C $repoRoot rev-parse --is-inside-work-tree *> $null
        $isGitWorktree = $?
    } catch {
        $isGitWorktree = $false
    }

    if (-not $isGitWorktree) {
        Write-Host "Skipping source update: $repoRoot is not a git worktree."
        return
    }

    Invoke-Step "git -C $repoRoot pull --ff-only" {
        git -C $repoRoot pull --ff-only
    }
}

function Install-ScoopIfMissing {
    if (Test-Command scoop) {
        return
    }

    Write-Host "Scoop is required for Windows bootstrap: https://scoop.sh/"
    Write-Host "Install Scoop manually, then rerun this script."
}

function Test-ScoopPackageInstalled {
    param([string]$Package)

    $prefixSucceeded = $false
    try {
        & scoop prefix $Package *> $null
        $prefixSucceeded = $?
    } catch {
        $prefixSucceeded = $false
    }

    if ($prefixSucceeded) {
        return $true
    }

    $roots = @()
    if ($env:SCOOP) { $roots += $env:SCOOP }
    if ($env:SCOOP_GLOBAL) { $roots += $env:SCOOP_GLOBAL }
    if ($HOME) { $roots += (Join-Path $HOME "scoop") }
    if ($env:ProgramData) { $roots += (Join-Path $env:ProgramData "scoop") }

    foreach ($root in ($roots | Select-Object -Unique)) {
        if (-not $root) {
            continue
        }

        $appDir = Join-Path $root "apps\$Package\current"
        if (Test-Path -LiteralPath $appDir -PathType Container) {
            return $true
        }
    }

    return $false
}

function Install-ScoopPackage {
    param([string[]]$Packages)

    Install-ScoopIfMissing
    if (-not (Test-Command scoop)) {
        return
    }

    foreach ($package in $Packages) {
        if (-not (Test-ScoopPackageInstalled -Package $package)) {
            Invoke-Step "scoop install $package" {
                scoop install $package
            }
        }
    }
}

function Write-ManualChezmoiSteps {
    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "  chezmoi diff  # optional: review changes before apply"
    Write-Host "  chezmoi apply"
}

function Invoke-ChezmoiAfterUpdate {
    if (-not $Update) {
        return
    }

    if (-not (Test-Command chezmoi)) {
        throw "chezmoi is required for -Update."
    }

    Invoke-Step "chezmoi apply" { chezmoi apply }
}

Invoke-SourceUpdate

switch ($Layer) {
    "terminal" {
        Install-ScoopPackage -Packages @("git", "chezmoi", "starship", "zoxide", "fzf")
    }
    "dev" {
        Install-ScoopPackage -Packages @("fnm", "uv")
    }
}

Invoke-ChezmoiAfterUpdate
if (-not $Update) {
    Write-ManualChezmoiSteps
}
