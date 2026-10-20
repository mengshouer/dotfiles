# Shared PowerShell helpers and early environment import.

function Import-DotfilesEnvFile {
    param(
        [string]$Path
    )

    if ((-not $Path) -or (-not [System.IO.File]::Exists($Path))) {
        return
    }

    foreach ($rawLine in [System.IO.File]::ReadAllLines($Path)) {
        $line = $rawLine.Trim()
        if ((-not $line) -or $line.StartsWith("#", [System.StringComparison]::Ordinal)) {
            continue
        }

        if ($line -match '^export\s+(.*)$') {
            $line = $Matches[1].TrimStart()
        }

        $separator = $line.IndexOf("=")
        if ($separator -lt 1) {
            continue
        }

        $key = $line.Substring(0, $separator).Trim()
        $value = $line.Substring($separator + 1).Trim()

        if ($key -notmatch "^[A-Za-z_][A-Za-z0-9_]*$") {
            continue
        }

        if ($value.Length -ge 2) {
            if (($value.StartsWith('"', [System.StringComparison]::Ordinal) -and $value.EndsWith('"', [System.StringComparison]::Ordinal)) -or
                ($value.StartsWith("'", [System.StringComparison]::Ordinal) -and $value.EndsWith("'", [System.StringComparison]::Ordinal))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
        }

        [System.Environment]::SetEnvironmentVariable($key, $value, "Process")
    }
}

function Add-DotfilesPathPrepend {
    param(
        [string]$Path
    )

    if ((-not $Path) -or (-not [System.IO.Directory]::Exists($Path))) {
        return
    }

    $pathSep = [System.IO.Path]::PathSeparator
    $result = [System.Collections.Generic.List[string]]::new()
    $result.Add($Path)

    if ($env:PATH) {
        foreach ($part in $env:PATH.Split($pathSep)) {
            if ($part -and (-not [string]::Equals($part, $Path, [System.StringComparison]::OrdinalIgnoreCase))) {
                $result.Add($part)
            }
        }
    }

    $env:PATH = [string]::Join($pathSep, $result)
}

function Resolve-DotfilesCommandPath {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $commandPath = $null
    $isWindowsHost = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
    $candidateNames = if ($isWindowsHost -and (-not [System.IO.Path]::HasExtension($Name))) {
        @("$Name.exe", "$Name.cmd", "$Name.bat")
    } else {
        @($Name)
    }

    if ($env:PATH) {
        foreach ($dir in $env:PATH.Split([System.IO.Path]::PathSeparator)) {
            $trimmedDir = $dir.Trim().Trim('"')
            if (-not $trimmedDir) {
                continue
            }
            foreach ($fileName in $candidateNames) {
                try {
                    $fullPath = [System.IO.Path]::Combine($trimmedDir, $fileName)
                    if ([System.IO.File]::Exists($fullPath)) {
                        $commandPath = $fullPath
                        break
                    }
                } catch {}
            }
            if ($commandPath) {
                break
            }
        }
    }

    if (-not $commandPath) {
        $command = Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $command) {
            return $null
        }
        $commandPath = if ($command.Source) { $command.Source } else { $command.Path }
        if (-not $commandPath) {
            return $null
        }
    }

    if ($commandPath.EndsWith(".exe", [System.StringComparison]::OrdinalIgnoreCase)) {
        $shimFile = [System.IO.Path]::ChangeExtension($commandPath, ".shim")
        if ([System.IO.File]::Exists($shimFile)) {
            $targetPath = $null
            $hasCustomArgs = $false
            foreach ($line in [System.IO.File]::ReadAllLines($shimFile)) {
                $trimmed = $line.Trim()
                if ($trimmed -match '^path\s*=\s*"?([^"]+)"?$') {
                    $targetPath = $Matches[1]
                } elseif ($trimmed -match '^args\s*=\s*\S+') {
                    $hasCustomArgs = $true
                }
            }

            if ((-not $hasCustomArgs) -and $targetPath -and [System.IO.File]::Exists($targetPath)) {
                return $targetPath
            }
        }
    }

    return $commandPath
}

Import-DotfilesEnvFile -Path (Join-Path $HOME ".config\dotfiles\local.env")
