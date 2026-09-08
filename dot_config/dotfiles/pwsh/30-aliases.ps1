# Shared PowerShell aliases.

function global:Set-DotfilesAlias {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Command
    )

    # Use Invoke-Expression to mimic bash-style alias (text substitution).
    # This ensures .ps1 wrappers (e.g. fnm's npm.ps1) that parse
    # $MyInvocation.Statement see the full command text with real arguments,
    # instead of the unexpanded literal "@args".
    $body = @'
if ($args.Count) {
    $q = @($args) | ForEach-Object {
        if ($_.ToString().Contains(' ')) { '"{0}"' -f ($_ -replace '"', '\"') }
        else { $_ }
    }
    Invoke-Expression ('__CMD__ ' + ($q -join ' '))
} else {
    Invoke-Expression '__CMD__'
}
'@.Replace('__CMD__', $Command.Replace("'", "''"))

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
    Set-DotfilesAlias -Name $alias.Key -Command $alias.Value
}

Remove-Variable aliases

function script:Start-DotfilesDetachedProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [string[]]$Arguments = @()
    )

    $actualFilePath = $FilePath
    $actualArguments = @($Arguments)
    $isWindowsPlatform = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT

    if (-not $isWindowsPlatform) {
        $nohup = Get-Command nohup -CommandType Application -ErrorAction SilentlyContinue
        if ($null -ne $nohup) {
            $actualArguments = @($actualFilePath) + $actualArguments
            $actualFilePath = $nohup.Source
        }
    }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $actualFilePath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    # ArgumentList is unavailable on Windows PowerShell 5.1/.NET Framework.
    $argumentListProperty = $startInfo.PSObject.Properties["ArgumentList"]
    if ($null -ne $argumentListProperty) {
        foreach ($argument in $actualArguments) {
            [void]$startInfo.ArgumentList.Add([string]$argument)
        }
    } else {
        $escapedArguments = @()
        foreach ($argument in $actualArguments) {
            $value = [string]$argument
            if (($value.Length -gt 0) -and ($value -notmatch '[\s"]')) {
                $escapedArguments += $value
                continue
            }

            $value = [regex]::Replace($value, '(\\*)"', '$1$1\"')
            $value = [regex]::Replace($value, '(\\+)$', '$1$1')
            $escapedArguments += '"' + $value + '"'
        }
        $startInfo.Arguments = $escapedArguments -join " "
    }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw "Failed to start '$actualFilePath'."
    }

    # Only process creation is synchronous; discard later launcher output.
    try { $process.StandardInput.Close() } catch {}
    try { [void]$process.StandardOutput.ReadToEndAsync() } catch {}
    try { [void]$process.StandardError.ReadToEndAsync() } catch {}
}

# Open a directory in the platform's default graphical file manager.
function global:opendir {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [AllowEmptyString()]
        [string]$Path = ".",

        [Parameter(ValueFromRemainingArguments)]
        [object[]]$RemainingArguments
    )

    $reportError = {
        param(
            [string]$Message,
            [string]$ErrorId,
            [System.Management.Automation.ErrorCategory]$Category,
            [object]$TargetObject
        )

        $record = [System.Management.Automation.ErrorRecord]::new(
            [System.InvalidOperationException]::new($Message),
            $ErrorId,
            $Category,
            $TargetObject
        )
        $PSCmdlet.WriteError($record)
    }

    if (($null -ne $RemainingArguments) -and ($RemainingArguments.Count -gt 0)) {
        & $reportError `
            -Message "Usage: opendir [directory]" `
            -ErrorId "OpenDirectory.InvalidArgumentCount" `
            -Category InvalidArgument `
            -TargetObject $RemainingArguments
        return
    }

    try {
        $directoryItem = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    } catch {
        & $reportError `
            -Message "opendir: not a directory: '$Path'" `
            -ErrorId "OpenDirectory.NotDirectory" `
            -Category ObjectNotFound `
            -TargetObject $Path
        return
    }

    if (($directoryItem.PSProvider.Name -ne "FileSystem") -or (-not $directoryItem.PSIsContainer)) {
        & $reportError `
            -Message "opendir: not a directory: '$Path'" `
            -ErrorId "OpenDirectory.NotDirectory" `
            -Category InvalidArgument `
            -TargetObject $Path
        return
    }

    # FullName makes relative paths absolute without resolving directory links.
    $directory = $directoryItem.FullName
    $dotfilesIsWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
    $dotfilesIsWsl = $false
    $dotfilesIsMacOS = $false
    $dotfilesIsLinux = $false

    if (-not $dotfilesIsWindows) {
        if ($env:WSL_DISTRO_NAME -or $env:WSL_INTEROP) {
            $dotfilesIsWsl = $true
        } elseif (Test-Path -LiteralPath "/proc/version" -PathType Leaf) {
            try {
                $dotfilesIsWsl = (Get-Content -LiteralPath "/proc/version" -Raw -ErrorAction Stop) -match "microsoft"
            } catch {
                $dotfilesIsWsl = $false
            }
        }

        $platformFlag = Get-Variable -Name IsMacOS -ErrorAction SilentlyContinue
        if ($null -ne $platformFlag) {
            $dotfilesIsMacOS = [bool]$platformFlag.Value
        }

        $platformFlag = Get-Variable -Name IsLinux -ErrorAction SilentlyContinue
        if ($null -ne $platformFlag) {
            $dotfilesIsLinux = [bool]$platformFlag.Value
        }
    }

    if ($dotfilesIsWindows) {
        try {
            $null = Invoke-Item -LiteralPath $directory -ErrorAction Stop
            return
        } catch {}

        $explorer = Get-Command explorer.exe -CommandType Application -ErrorAction SilentlyContinue
        if ($null -ne $explorer) {
            try {
                Start-DotfilesDetachedProcess -FilePath $explorer.Source -Arguments @($directory)
                return
            } catch {}
        }

        & $reportError `
            -Message "opendir: failed to open directory: '$directory'" `
            -ErrorId "OpenDirectory.LaunchFailed" `
            -Category OpenError `
            -TargetObject $directory
        return
    }

    $platformName = $null
    $openerCandidates = @()

    if ($dotfilesIsWsl) {
        $platformName = "WSL"
        $explorer = Get-Command explorer.exe -CommandType Application -ErrorAction SilentlyContinue
        $wslpath = Get-Command wslpath -CommandType Application -ErrorAction SilentlyContinue

        if (($null -ne $explorer) -and ($null -ne $wslpath)) {
            try {
                $convertedPaths = @(& $wslpath.Source -w $directory 2>$null)
                if (($LASTEXITCODE -eq 0) -and ($convertedPaths.Count -gt 0)) {
                    $openerCandidates += [pscustomobject]@{
                        FilePath  = $explorer.Source
                        Arguments = @([string]$convertedPaths[0])
                    }
                }
            } catch {}
        }

        $wslview = Get-Command wslview -CommandType Application -ErrorAction SilentlyContinue
        if ($null -ne $wslview) {
            $openerCandidates += [pscustomobject]@{
                FilePath  = $wslview.Source
                Arguments = @($directory)
            }
        }
    } elseif ($dotfilesIsMacOS) {
        $platformName = "macOS"
        $open = Get-Command open -CommandType Application -ErrorAction SilentlyContinue
        if ($null -ne $open) {
            $openerCandidates += [pscustomobject]@{
                FilePath  = $open.Source
                Arguments = @($directory)
            }
        }
    } elseif ($dotfilesIsLinux) {
        $platformName = "Linux"
        $xdgOpen = Get-Command xdg-open -CommandType Application -ErrorAction SilentlyContinue
        if ($null -ne $xdgOpen) {
            $openerCandidates += [pscustomobject]@{
                FilePath  = $xdgOpen.Source
                Arguments = @($directory)
            }
        }

        $gio = Get-Command gio -CommandType Application -ErrorAction SilentlyContinue
        if ($null -ne $gio) {
            $openerCandidates += [pscustomobject]@{
                FilePath  = $gio.Source
                Arguments = @("open", $directory)
            }
        }
    } else {
        & $reportError `
            -Message "opendir: unsupported platform" `
            -ErrorId "OpenDirectory.UnsupportedPlatform" `
            -Category NotImplemented `
            -TargetObject $directory
        return
    }

    foreach ($candidate in $openerCandidates) {
        try {
            Start-DotfilesDetachedProcess `
                -FilePath $candidate.FilePath `
                -Arguments $candidate.Arguments
            return
        } catch {}
    }

    $message = if ($openerCandidates.Count -eq 0) {
        "opendir: no supported directory opener found for $platformName"
    } else {
        "opendir: failed to open directory on ${platformName}: '$directory'"
    }
    $category = if ($openerCandidates.Count -eq 0) { "ObjectNotFound" } else { "OpenError" }

    & $reportError `
        -Message $message `
        -ErrorId "OpenDirectory.LaunchFailed" `
        -Category $category `
        -TargetObject $directory
}

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
