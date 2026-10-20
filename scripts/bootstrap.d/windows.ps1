Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

function Write-Usage {
    @"
Usage:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\bootstrap.ps1 [terminal|dev] [-Update]

Layers:
  terminal   git chezmoi starship zoxide fzf
  dev        fnm uv

PowerShell 7 is recommended, but terminal modules are compatible with Windows
PowerShell 5.1.

Flags:
  -Update   git pull --ff-only and apply dotfiles
"@ | Write-Host
}

$Layer = "terminal"
$Update = $false

$argIndex = 0
if ($args.Count -gt 0) {
    $firstArg = [string]$args[0]
    switch -Exact ($firstArg) {
        "terminal" { $Layer = "terminal"; $argIndex = 1 }
        "dev"      { $Layer = "dev"; $argIndex = 1 }
        "-h"       { Write-Usage; exit 0 }
        "--help"   { Write-Usage; exit 0 }
        "-Help"    { Write-Usage; exit 0 }
        "-?"       { Write-Usage; exit 0 }
    }
}

for ($i = $argIndex; $i -lt $args.Count; $i++) {
    $arg = [string]$args[$i]
    switch -Exact ($arg) {
        "-Layer" {
            if (($i + 1) -ge $args.Count) {
                [Console]::Error.WriteLine("Missing value for -Layer.")
                Write-Usage
                exit 2
            }
            $i++
            $layerValue = [string]$args[$i]
            if ($layerValue -notin @("terminal", "dev")) {
                [Console]::Error.WriteLine("Unknown layer: $layerValue")
                Write-Usage
                exit 2
            }
            $Layer = $layerValue.ToLowerInvariant()
        }
        "-Update"  { $Update = $true }
        "-update"  { $Update = $true }
        "--update" { $Update = $true }
        "-h"       { Write-Usage; exit 0 }
        "--help"   { Write-Usage; exit 0 }
        "-Help"    { Write-Usage; exit 0 }
        "-?"       { Write-Usage; exit 0 }
        default {
            [Console]::Error.WriteLine("Unknown argument: $arg")
            Write-Usage
            exit 2
        }
    }
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

function Ensure-Scoop {
    if (Test-Command scoop) {
        return
    }

    [Console]::Error.WriteLine("Scoop is required for Windows bootstrap: https://scoop.sh/")
    [Console]::Error.WriteLine("Install Scoop manually, then rerun this script.")
    exit 1
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

    Ensure-Scoop

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
