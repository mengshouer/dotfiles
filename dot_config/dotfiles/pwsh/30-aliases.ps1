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

# toclip helpers: shared probe and I/O pieces for the toclip command below.

function script:Test-DotfilesWindowsHost {
    # Same probe opendir uses, so both commands in this file agree.
    return ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)
}

# The device that reaches the terminal in front of the user, regardless of
# where stdout points.
function script:Get-DotfilesTerminalDevicePath {
    if (Test-DotfilesWindowsHost) {
        return 'CONOUT$'
    }

    return '/dev/tty'
}

# Open the terminal device for writing, or $null when it is not reachable.
function script:Open-DotfilesTerminalDevice {
    try {
        return [System.IO.File]::Open(
            (Get-DotfilesTerminalDevicePath),
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::ReadWrite
        )
    } catch {
        return $null
    }
}

function script:Test-DotfilesTerminalDevice {
    $stream = Open-DotfilesTerminalDevice
    if ($null -eq $stream) {
        return $false
    }

    $stream.Dispose()
    return $true
}

# Check whether this session came in over sshd. Environment variables first,
# then the process tree, because nested shells may have dropped SSH_*.
function script:Test-DotfilesRemoteSession {
    if ($env:SSH_CONNECTION -or $env:SSH_CLIENT -or $env:SSH_TTY) {
        return $true
    }

    $cimAvailable = Get-Command -Name Get-CimInstance -ErrorAction SilentlyContinue
    if (-not $cimAvailable) {
        return $false
    }

    $currentId = $PID
    for ($hop = 0; $hop -lt 10; $hop++) {
        $process = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $currentId" -ErrorAction SilentlyContinue
        if ($null -eq $process) {
            return $false
        }

        if ($process.Name -like 'sshd*') {
            return $true
        }

        $currentId = $process.ParentProcessId
        if (($null -eq $currentId) -or ($currentId -le 0)) {
            return $false
        }
    }

    return $false
}

function script:Get-DotfilesClipboardBackend {
    if (Get-Command -Name Set-Clipboard -ErrorAction SilentlyContinue) {
        return 'Set-Clipboard'
    }

    return $null
}

# Write raw bytes to the terminal, falling back to stdout only when stdout is a
# terminal so that redirections stay untouched.
function script:Write-DotfilesTerminalSequence {
    param(
        [Parameter(Mandatory)]
        [string]$Sequence
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Sequence)

    $stream = Open-DotfilesTerminalDevice
    if ($null -ne $stream) {
        try {
            try {
                $stream.Write($bytes, 0, $bytes.Length)
                $stream.Flush()
                return $true
            } finally {
                $stream.Dispose()
            }
        } catch {
        }
    }

    if (-not [Console]::IsOutputRedirected) {
        try {
            $stdout = [Console]::OpenStandardOutput()
            $stdout.Write($bytes, 0, $bytes.Length)
            $stdout.Flush()
            return $true
        } catch {
        }
    }

    return $false
}

# $Payload is single line base64. Inside tmux the bare sequence is swallowed by
# the default set-clipboard=external, so the DCS passthrough form (which needs
# allow-passthrough on) is sent first, followed by the bare sequence that applies
# when set-clipboard=on. Both carry the same payload, so whichever one the
# terminal honours is correct.
function script:Get-DotfilesOsc52Sequence {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Payload
    )

    $escape = [char]27
    $bell = [char]7
    $sequences = ''

    if ($env:TMUX) {
        $sequences += "$escape" + "Ptmux;$escape$escape]52;c;$Payload$bell$escape\"
    }

    return $sequences + "$escape]52;c;$Payload$bell"
}

function script:Format-DotfilesByteSize {
    param(
        [Parameter(Mandatory)]
        [long]$Bytes
    )

    if ($Bytes -ge 1048576) {
        return ('{0:0.0} MiB' -f ($Bytes / 1048576))
    }

    if ($Bytes -ge 1024) {
        return ('{0:0.0} KiB' -f ($Bytes / 1024))
    }

    return "$Bytes B"
}

# Decode clipboard bytes as text. UTF-8 is assumed unless a BOM says otherwise.
function script:ConvertFrom-DotfilesClipboardBytes {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [byte[]]$Bytes
    )

    if (($Bytes.Length -ge 3) -and ($Bytes[0] -eq 0xEF) -and ($Bytes[1] -eq 0xBB) -and ($Bytes[2] -eq 0xBF)) {
        return [System.Text.Encoding]::UTF8.GetString($Bytes, 3, $Bytes.Length - 3)
    }

    if (($Bytes.Length -ge 2) -and ($Bytes[0] -eq 0xFF) -and ($Bytes[1] -eq 0xFE)) {
        return [System.Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2)
    }

    return [System.Text.Encoding]::UTF8.GetString($Bytes)
}

# 0 = continue, 1 = cancelled, -1 = no terminal to ask on.
function script:Read-DotfilesConfirmation {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt
    )

    if ([Console]::IsInputRedirected) {
        return -1
    }

    try {
        $reply = Read-Host -Prompt $Prompt
    } catch {
        return -1
    }

    if ($reply -match '^(?i)\s*(y|yes)\s*$') {
        return 0
    }

    return 1
}

# Copy text into the clipboard of the machine whose terminal you are looking at.
# A local session uses the native clipboard; an SSH session emits OSC 52 so the
# terminal emulator in front of you sets its own clipboard.
function global:toclip {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments)]
        [string[]]$Path,

        # Declared so that objects can be piped in; the body reads them from $input.
        [Parameter(ValueFromPipeline)]
        [object]$InputObject,

        [switch]$Local,

        [switch]$Osc52,

        [switch]$PrintBase64,

        [switch]$Which,

        [switch]$Yes,

        [int]$MaxKiB = -1
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

    $mode = 'auto'
    if ($env:TOCLIP_MODE) {
        $mode = $env:TOCLIP_MODE.Trim().ToLowerInvariant()
    }
    if ($Local) {
        $mode = 'local'
    }
    if ($Osc52) {
        $mode = 'osc52'
    }

    if ($mode -notin @('auto', 'local', 'osc52')) {
        & $reportError `
            -Message "toclip: TOCLIP_MODE must be auto|local|osc52: '$mode'" `
            -ErrorId "ToClipboard.InvalidMode" `
            -Category InvalidArgument `
            -TargetObject $mode
        return
    }

    # Note: PowerShell variable names are case-insensitive, so this must not be
    # called $maxKiB - that would be the same variable as the -MaxKiB parameter.
    $effectiveMaxKiB = 64
    if ($MaxKiB -ge 0) {
        $effectiveMaxKiB = $MaxKiB
    } elseif ($env:TOCLIP_MAX_KIB) {
        $parsedMaxKiB = 0
        if ((-not [int]::TryParse($env:TOCLIP_MAX_KIB.Trim(), [ref]$parsedMaxKiB)) -or ($parsedMaxKiB -lt 0)) {
            & $reportError `
                -Message "toclip: TOCLIP_MAX_KIB must be an integer >= 0: '$($env:TOCLIP_MAX_KIB)'" `
                -ErrorId "ToClipboard.InvalidMaxKiB" `
                -Category InvalidArgument `
                -TargetObject $env:TOCLIP_MAX_KIB
            return
        }

        $effectiveMaxKiB = $parsedMaxKiB
    }

    $isRemote = Test-DotfilesRemoteSession
    $backend = Get-DotfilesClipboardBackend

    # A same-named external command (toclip.exe) is shadowed by this function.
    $otherCommands = @(
        Get-Command -Name 'toclip' -All -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandType -ne 'Function' }
    )

    $effective = $mode
    if ($effective -eq 'auto') {
        if ($backend -and ($isRemote -eq $false)) {
            $effective = 'local'
        } else {
            $effective = 'osc52'
        }
    }

    if ($Which) {
        if ($isRemote) {
            if ($env:SSH_CONNECTION -or $env:SSH_CLIENT -or $env:SSH_TTY) {
                "session        : remote (SSH_* environment variables)"
            } else {
                "session        : remote (sshd found in the process tree)"
            }
        } else {
            "session        : local"
        }

        "mode           : $mode -> $effective"
        if ($backend) {
            "native backend : $backend (native)"
        } else {
            "native backend : (none)"
        }
        "max-kib        : $effectiveMaxKiB"

        $terminalDevice = Get-DotfilesTerminalDevicePath
        if (Test-DotfilesTerminalDevice) {
            "controlling tty: available ($terminalDevice)"
        } elseif (-not [Console]::IsOutputRedirected) {
            "controlling tty: unavailable, falling back to stdout"
        } else {
            "controlling tty: unavailable"
        }

        if ($env:TMUX) {
            "tmux           : inside tmux, DCS passthrough is sent as well"
        }
        "self           : function toclip (PowerShell profile)"
        foreach ($other in $otherCommands) {
            "other toclip   : $($other.Source)"
        }

        return
    }

    foreach ($other in $otherCommands) {
        Write-Warning "toclip: another toclip is also available: $($other.Source); this function wins inside PowerShell"
    }

    if ($effective -eq 'local' -and (-not $backend)) {
        & $reportError `
            -Message "toclip: no clipboard backend on this machine; use -Osc52" `
            -ErrorId "ToClipboard.NoBackend" `
            -Category ObjectNotFound `
            -TargetObject $null
        return
    }

    $buffer = New-Object System.IO.MemoryStream
    try {
        if (($null -ne $Path) -and ($Path.Count -gt 0)) {
            foreach ($item in $Path) {
                if ($item -eq '-') {
                    $stdin = [Console]::OpenStandardInput()
                    $stdin.CopyTo($buffer)
                    continue
                }

                try {
                    $fileItem = Get-Item -LiteralPath $item -Force -ErrorAction Stop
                } catch {
                    & $reportError `
                        -Message "toclip: no such file: '$item'" `
                        -ErrorId "ToClipboard.FileNotFound" `
                        -Category ObjectNotFound `
                        -TargetObject $item
                    return
                }

                if (($fileItem.PSProvider.Name -ne "FileSystem") -or $fileItem.PSIsContainer) {
                    & $reportError `
                        -Message "toclip: not a file: '$item'" `
                        -ErrorId "ToClipboard.NotFile" `
                        -Category InvalidArgument `
                        -TargetObject $item
                    return
                }

                try {
                    $fileBytes = [System.IO.File]::ReadAllBytes($fileItem.FullName)
                } catch {
                    & $reportError `
                        -Message "toclip: cannot read '$item': $($_.Exception.Message)" `
                        -ErrorId "ToClipboard.ReadFailed" `
                        -Category ReadError `
                        -TargetObject $item
                    return
                }

                $buffer.Write($fileBytes, 0, $fileBytes.Length)
            }
        } elseif (@($input).Count -gt 0) {
            $text = (@($input) | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
            $pipelineBytes = [System.Text.Encoding]::UTF8.GetBytes($text)
            $buffer.Write($pipelineBytes, 0, $pipelineBytes.Length)
        } elseif ([Console]::IsInputRedirected) {
            $stdin = [Console]::OpenStandardInput()
            $stdin.CopyTo($buffer)
        } else {
            & $reportError `
                -Message "toclip: no input; pass a file, pipe text in, or use -Path" `
                -ErrorId "ToClipboard.NoInput" `
                -Category InvalidArgument `
                -TargetObject $null
            return
        }

        $bytes = $buffer.ToArray()
    } finally {
        $buffer.Dispose()
    }

    $contentSize = $bytes.Length
    $payload = [System.Convert]::ToBase64String($bytes)

    if ($PrintBase64) {
        $payload
        return
    }

    if ($effective -eq 'local') {
        $text = ConvertFrom-DotfilesClipboardBytes -Bytes $bytes

        try {
            Set-Clipboard -Value $text -ErrorAction Stop
            return
        } catch {
            if ($mode -ne 'auto') {
                & $reportError `
                    -Message "toclip: copying to the clipboard failed: $($_.Exception.Message)" `
                    -ErrorId "ToClipboard.CopyFailed" `
                    -Category WriteError `
                    -TargetObject $backend
                return
            }

            Write-Warning "toclip: $backend failed ($($_.Exception.Message)); falling back to OSC 52"
            $effective = 'osc52'
        }
    }

    if (($effectiveMaxKiB -gt 0) -and ($contentSize -gt ($effectiveMaxKiB * 1024)) -and (-not $Yes)) {
        $sizeText = Format-DotfilesByteSize -Bytes $contentSize
        $reply = Read-DotfilesConfirmation -Prompt "toclip: content is $sizeText, above the $effectiveMaxKiB KiB threshold; some terminals truncate or drop long OSC 52 sequences. Continue? [y/N]"

        if ($reply -lt 0) {
            & $reportError `
                -Message "toclip: content is $sizeText, above the $effectiveMaxKiB KiB threshold and there is no terminal to confirm on; use -Yes to continue or -MaxKiB 0 to lift the limit" `
                -ErrorId "ToClipboard.SizeLimitWithoutConfirmation" `
                -Category InvalidOperation `
                -TargetObject $contentSize
            return
        }

        if ($reply -ne 0) {
            & $reportError `
                -Message "toclip: cancelled" `
                -ErrorId "ToClipboard.Cancelled" `
                -Category OperationStopped `
                -TargetObject $null
            return
        }
    }

    if ((Test-DotfilesWindowsHost) -and (-not $Host.UI.SupportsVirtualTerminal)) {
        Write-Warning "toclip: this console does not support virtual terminal sequences; the clipboard was probably not set"
    }

    $sequence = Get-DotfilesOsc52Sequence -Payload $payload
    if (-not (Write-DotfilesTerminalSequence -Sequence $sequence)) {
        & $reportError `
            -Message "toclip: cannot write the OSC 52 sequence to the terminal" `
            -ErrorId "ToClipboard.WriteFailed" `
            -Category WriteError `
            -TargetObject $null
        return
    }
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
