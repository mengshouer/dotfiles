# Optional fnm initialization (fast default PATH + on-demand multishell).

$dotfilesFnmCacheDir = [System.Environment]::GetFolderPath('LocalApplicationData')
if (-not $dotfilesFnmCacheDir) {
    $dotfilesFnmCacheDir = if ($env:XDG_CACHE_HOME) {
        $env:XDG_CACHE_HOME
    } elseif ($HOME) {
        Join-Path $HOME ".cache"
    } else {
        [System.IO.Path]::GetTempPath()
    }
}
$dotfilesFnmCacheFile = Join-Path (Join-Path $dotfilesFnmCacheDir "fnm") "path.cached.txt"

$dotfilesFnmPath = $null
$dotfilesFnmDefaultAlias = $null
$dotfilesFnmDirResolved = $null

$dotfilesFnmCacheInfo = [System.IO.FileInfo]::new($dotfilesFnmCacheFile)
if ($dotfilesFnmCacheInfo.Exists) {
    $dotfilesFnmCacheValid = $true
    $dotfilesFnmCacheTicks = $dotfilesFnmCacheInfo.LastWriteTimeUtc.Ticks
    $dotfilesFnmLocalEnv = if ($HOME) { Join-Path $HOME ".config\dotfiles\local.env" } else { $null }

    foreach ($dep in @($dotfilesFnmLocalEnv, $PSCommandPath)) {
        if (-not $dep) {
            continue
        }
        $depInfo = [System.IO.FileInfo]::new($dep)
        if ($depInfo.Exists -and ([Math]::Max($depInfo.LastWriteTimeUtc.Ticks, $depInfo.CreationTimeUtc.Ticks) -gt $dotfilesFnmCacheTicks)) {
            $dotfilesFnmCacheValid = $false
            break
        }
    }

    if ($dotfilesFnmCacheValid) {
        try {
            $cachedLines = [System.IO.File]::ReadAllLines($dotfilesFnmCacheFile)
            if ($cachedLines.Length -ge 1 -and $cachedLines[0] -and [System.IO.File]::Exists($cachedLines[0])) {
                $dotfilesFnmPath = $cachedLines[0]
                if ($cachedLines.Length -ge 2 -and $cachedLines[1] -and [System.IO.Directory]::Exists($cachedLines[1])) {
                    $dotfilesFnmDefaultAlias = $cachedLines[1]
                }
                if ($cachedLines.Length -ge 3 -and $cachedLines[2] -and [System.IO.Directory]::Exists($cachedLines[2])) {
                    $dotfilesFnmDirResolved = $cachedLines[2]
                }
            }
        } catch {}
    }
}

if (-not $dotfilesFnmPath) {
    $dotfilesFnmPath = if (Get-Command Resolve-DotfilesCommandPath -ErrorAction SilentlyContinue) {
        Resolve-DotfilesCommandPath -Name "fnm"
    } else {
        $cmd = Get-Command fnm -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) { $cmd.Source } else { $null }
    }
}

if ($dotfilesFnmPath) {
    $global:__dotfiles_fnm_bin = $dotfilesFnmPath
    $global:__dotfiles_fnm_initialized = $false
    $global:__dotfiles_fnm_last_dir = $null

    if (-not $dotfilesFnmDefaultAlias) {
        $dotfilesFnmCandidates = @()
        if ($env:FNM_DIR) {
            $dotfilesFnmCandidates += $env:FNM_DIR
        }
        $dotfilesFnmBinDir = Split-Path -Parent $dotfilesFnmPath
        if ($dotfilesFnmBinDir) {
            $dotfilesFnmCandidates += $dotfilesFnmBinDir
        }
        if ($env:APPDATA) {
            $dotfilesFnmCandidates += (Join-Path $env:APPDATA "fnm")
        }
        if ($env:LOCALAPPDATA) {
            $dotfilesFnmCandidates += (Join-Path $env:LOCALAPPDATA "fnm")
        }
        if ($HOME) {
            $dotfilesFnmCandidates += (Join-Path $HOME ".local\share\fnm")
            $dotfilesFnmCandidates += (Join-Path $HOME ".fnm")
        }

        foreach ($candidate in $dotfilesFnmCandidates) {
            if (-not $candidate) {
                continue
            }
            $aliasDir = Join-Path $candidate "aliases\default"
            if ([System.IO.Directory]::Exists($aliasDir)) {
                $dotfilesFnmDefaultAlias = $aliasDir
                $dotfilesFnmDirResolved = $candidate
                break
            }
        }

        try {
            $cacheParent = Split-Path -Parent $dotfilesFnmCacheFile
            if (-not [System.IO.Directory]::Exists($cacheParent)) {
                New-Item -ItemType Directory -Path $cacheParent -Force | Out-Null
            }
            $tempCacheFile = "$dotfilesFnmCacheFile.$PID.tmp"
            try {
                [System.IO.File]::WriteAllLines(
                    $tempCacheFile,
                    @([string]$dotfilesFnmPath, [string]$dotfilesFnmDefaultAlias, [string]$dotfilesFnmDirResolved),
                    [System.Text.UTF8Encoding]::new($true)
                )
                Move-Item -LiteralPath $tempCacheFile -Destination $dotfilesFnmCacheFile -Force -ErrorAction Stop
            } finally {
                if ([System.IO.File]::Exists($tempCacheFile)) {
                    try { [System.IO.File]::Delete($tempCacheFile) } catch {}
                }
            }
        } catch {}
    }

    if ($dotfilesFnmDirResolved -and (-not $env:FNM_DIR)) {
        $env:FNM_DIR = $dotfilesFnmDirResolved
    }

    $global:__dotfiles_fnm_default_alias = $dotfilesFnmDefaultAlias
    if ($dotfilesFnmDefaultAlias) {
        $pathSep = [System.IO.Path]::PathSeparator
        $pathList = [System.Collections.Generic.List[string]]::new()
        $pathList.Add($dotfilesFnmDefaultAlias)
        if ($env:PATH) {
            foreach ($part in $env:PATH.Split($pathSep)) {
                if ($part -and
                    (-not [string]::Equals($part, $dotfilesFnmDefaultAlias, [System.StringComparison]::OrdinalIgnoreCase)) -and
                    ($part.IndexOf("fnm_multishells", [System.StringComparison]::OrdinalIgnoreCase) -lt 0)) {
                    $pathList.Add($part)
                }
            }
        }
        $env:PATH = [string]::Join($pathSep, $pathList)
    }

    function global:Initialize-DotfilesFnm {
        if ($global:__dotfiles_fnm_initialized) {
            return
        }
        $global:__dotfiles_fnm_initialized = $true

        if ($global:__dotfiles_fnm_default_alias -and $env:PATH) {
            $sep = [System.IO.Path]::PathSeparator
            $cleaned = [System.Collections.Generic.List[string]]::new()
            foreach ($entry in $env:PATH.Split($sep)) {
                if ($entry -and (-not [string]::Equals($entry, $global:__dotfiles_fnm_default_alias, [System.StringComparison]::OrdinalIgnoreCase))) {
                    $cleaned.Add($entry)
                }
            }
            $env:PATH = [string]::Join($sep, $cleaned)
        }

        $prevEncoding = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
            $fnmEnv = (& $global:__dotfiles_fnm_bin env --shell powershell) -join [Environment]::NewLine
        } finally {
            [Console]::OutputEncoding = $prevEncoding
        }

        if ($fnmEnv) {
            Invoke-Expression $fnmEnv
        }
    }

    function global:fnm {
        if (-not $global:__dotfiles_fnm_initialized) {
            Initialize-DotfilesFnm
        }
        & $global:__dotfiles_fnm_bin @args
    }

    function global:Test-DotfilesFnmVersionFile {
        param(
            [string]$DirectoryPath = (Get-Location).ProviderPath
        )

        if (-not $DirectoryPath) {
            return $false
        }

        if ([System.IO.File]::Exists((Join-Path $DirectoryPath ".nvmrc")) -or
            [System.IO.File]::Exists((Join-Path $DirectoryPath ".node-version"))) {
            return $true
        }

        $pkgJson = Join-Path $DirectoryPath "package.json"
        if ([System.IO.File]::Exists($pkgJson)) {
            try {
                $raw = [System.IO.File]::ReadAllText($pkgJson)
                if ($raw.IndexOf('"engines"', [System.StringComparison]::Ordinal) -ge 0) {
                    return $true
                }
            } catch {}
        }

        return $false
    }

    function global:Set-FnmOnLoad {
        $currentDir = (Get-Location).ProviderPath
        if (-not $currentDir) {
            return
        }

        if ([string]::Equals($currentDir, $global:__dotfiles_fnm_last_dir, [System.StringComparison]::OrdinalIgnoreCase)) {
            return
        }
        $global:__dotfiles_fnm_last_dir = $currentDir

        if (Test-DotfilesFnmVersionFile -DirectoryPath $currentDir) {
            if (-not $global:__dotfiles_fnm_initialized) {
                Initialize-DotfilesFnm
            }
            & $global:__dotfiles_fnm_bin use --silent-if-unchanged | Out-Host
        }
    }

    function global:Set-LocationWithFnm {
        param($path)
        if ($null -eq $path) {
            Set-Location
        } else {
            Set-Location $path
        }
        Set-FnmOnLoad
    }

    Set-Alias -Scope Global -Name cd_with_fnm -Value Set-LocationWithFnm
    Set-Alias -Option AllScope -Scope Global -Name cd -Value Set-LocationWithFnm

    # Hook LocationChangedAction on PowerShell 7+ so zoxide (z/j), .., ..., and
    # Push-Location/Pop-Location also trigger Set-FnmOnLoad automatically.
    $locationChangedProp = $ExecutionContext.SessionState.InvokeCommand.PSObject.Properties["LocationChangedAction"]
    if (($null -ne $locationChangedProp) -and (-not $global:__dotfiles_fnm_location_hooked)) {
        $global:__dotfiles_fnm_location_hooked = $true
        $existingAction = $ExecutionContext.SessionState.InvokeCommand.LocationChangedAction
        if ($null -ne $existingAction) {
            $ExecutionContext.SessionState.InvokeCommand.LocationChangedAction = {
                param($sender, $eventArgs)
                & $existingAction $sender $eventArgs
                Set-FnmOnLoad
            }.GetNewClosure()
        } else {
            $ExecutionContext.SessionState.InvokeCommand.LocationChangedAction = {
                param($sender, $eventArgs)
                Set-FnmOnLoad
            }
        }
    }

    if (-not $dotfilesFnmDefaultAlias) {
        Initialize-DotfilesFnm
    } else {
        Set-FnmOnLoad
    }

    Remove-Variable dotfilesFnmCandidates, dotfilesFnmBinDir, candidate, aliasDir, cacheParent, tempCacheFile, pathSep, pathList, part, locationChangedProp, existingAction -ErrorAction SilentlyContinue
}

Remove-Variable dotfilesFnmCacheDir, dotfilesFnmCacheFile, dotfilesFnmCacheInfo, dotfilesFnmCacheValid, dotfilesFnmCacheTicks, dotfilesFnmLocalEnv, dep, depInfo, dotfilesFnmPath, dotfilesFnmDefaultAlias, dotfilesFnmDirResolved, cachedLines -ErrorAction SilentlyContinue
