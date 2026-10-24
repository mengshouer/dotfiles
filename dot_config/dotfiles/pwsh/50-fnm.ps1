# Optional fnm initialization (fast default PATH + on-demand multishell).

function script:Register-DotfilesFnm {
    $dotfilesFnmPath = $null
    $dotfilesFnmDefaultAlias = $null
    $dotfilesFnmDirResolved = $null

    if ($global:__dotfiles_fnm_precached -and $global:__dotfiles_fnm_bin) {
        $global:__dotfiles_fnm_precached = $false
        $dotfilesFnmPath = $global:__dotfiles_fnm_bin
        $dotfilesFnmDefaultAlias = $global:__dotfiles_fnm_default_alias
        $dotfilesFnmDirResolved = $global:__dotfiles_fnm_dir_resolved
    } else {
        $global:__dotfiles_fnm_bin = $null
        $global:__dotfiles_fnm_default_alias = $null
        $global:__dotfiles_fnm_dir_resolved = $null

        $dotfilesFnmCacheDir = if ($env:LOCALAPPDATA) {
            $env:LOCALAPPDATA
        } else {
            $dir = [System.Environment]::GetFolderPath('LocalApplicationData')
            if ($dir) { $dir }
            elseif ($env:XDG_CACHE_HOME) { $env:XDG_CACHE_HOME }
            elseif ($HOME) { [System.IO.Path]::Combine($HOME, ".cache") }
            else { [System.IO.Path]::GetTempPath() }
        }
        $dotfilesFnmCacheFile = [System.IO.Path]::Combine($dotfilesFnmCacheDir, "fnm\path.cached.txt")

        $dotfilesFnmCacheInfo = [System.IO.FileInfo]::new($dotfilesFnmCacheFile)
        if ($dotfilesFnmCacheInfo.Exists) {
            $dotfilesFnmCacheValid = $true
            $dotfilesFnmCacheTicks = $dotfilesFnmCacheInfo.LastWriteTimeUtc.Ticks
            $dotfilesFnmLocalEnv = if ($HOME) { [System.IO.Path]::Combine($HOME, ".config\dotfiles\local.env") } else { $null }

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
    }

    if (-not $dotfilesFnmPath) {
        $dotfilesFnmPath = if ($null -ne ${function:Resolve-DotfilesCommandPath}) {
            Resolve-DotfilesCommandPath -Name "fnm"
        } else {
            $cmds = @(Get-Command fnm -CommandType Application -ErrorAction SilentlyContinue)
            if ($cmds.Count -gt 0) { $cmds[0].Source } else { $null }
        }
    }

    if (-not $dotfilesFnmPath) {
        return
    }

    $global:__dotfiles_fnm_bin = $dotfilesFnmPath
    $global:__dotfiles_fnm_initialized = $false
    $global:__dotfiles_fnm_last_dir = $null
    $global:__dotfiles_fnm_startup_checked = $false

    if (-not $dotfilesFnmDefaultAlias) {
        $dotfilesFnmCandidates = @()
        if ($env:FNM_DIR) {
            $dotfilesFnmCandidates += $env:FNM_DIR
        }
        $dotfilesFnmBinDir = [System.IO.Path]::GetDirectoryName($dotfilesFnmPath)
        if ($dotfilesFnmBinDir) {
            $dotfilesFnmCandidates += $dotfilesFnmBinDir
        }
        if ($env:APPDATA) {
            $dotfilesFnmCandidates += [System.IO.Path]::Combine($env:APPDATA, "fnm")
        }
        if ($env:LOCALAPPDATA) {
            $dotfilesFnmCandidates += [System.IO.Path]::Combine($env:LOCALAPPDATA, "fnm")
        }
        if ($HOME) {
            $dotfilesFnmCandidates += [System.IO.Path]::Combine($HOME, ".local\share\fnm")
            $dotfilesFnmCandidates += [System.IO.Path]::Combine($HOME, ".fnm")
        }

        foreach ($candidate in $dotfilesFnmCandidates) {
            if (-not $candidate) {
                continue
            }
            $aliasDir = [System.IO.Path]::Combine($candidate, "aliases\default")
            $aliasBinDir = [System.IO.Path]::Combine($aliasDir, "bin")
            if ([System.IO.Directory]::Exists($aliasBinDir)) {
                $dotfilesFnmDefaultAlias = $aliasBinDir
                $dotfilesFnmDirResolved = $candidate
                break
            } elseif ([System.IO.Directory]::Exists($aliasDir)) {
                $dotfilesFnmDefaultAlias = $aliasDir
                $dotfilesFnmDirResolved = $candidate
                break
            }
        }

        try {
            $cacheParent = [System.IO.Path]::GetDirectoryName($dotfilesFnmCacheFile)
            if ($cacheParent -and (-not [System.IO.Directory]::Exists($cacheParent))) {
                [void][System.IO.Directory]::CreateDirectory($cacheParent)
            }
            $tempCacheFile = "$dotfilesFnmCacheFile.$PID.tmp"
            try {
                [System.IO.File]::WriteAllLines(
                    $tempCacheFile,
                    @([string]$dotfilesFnmPath, [string]$dotfilesFnmDefaultAlias, [string]$dotfilesFnmDirResolved),
                    [System.Text.UTF8Encoding]::new($true)
                )
                if ($PSVersionTable.PSVersion.Major -ge 6) {
                    [System.IO.File]::Move($tempCacheFile, $dotfilesFnmCacheFile, $true)
                } else {
                    if ([System.IO.File]::Exists($dotfilesFnmCacheFile)) {
                        [System.IO.File]::Delete($dotfilesFnmCacheFile)
                    }
                    [System.IO.File]::Move($tempCacheFile, $dotfilesFnmCacheFile)
                }
            } finally {
                if ([System.IO.File]::Exists($tempCacheFile)) {
                    try { [System.IO.File]::Delete($tempCacheFile) } catch {}
                }
            }
        } catch {}
    }

    $global:__dotfiles_fnm_dir_resolved = $dotfilesFnmDirResolved
    if ($dotfilesFnmDirResolved -and (-not $env:FNM_DIR)) {
        $env:FNM_DIR = $dotfilesFnmDirResolved
    }

    $global:__dotfiles_fnm_default_alias = $dotfilesFnmDefaultAlias
    if ($dotfilesFnmDefaultAlias) {
        if ($env:PATH) {
            if ($env:PATH.IndexOf("fnm_multishells", [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
                if ($env:PATH.IndexOf($dotfilesFnmDefaultAlias, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
                    $env:PATH = "$dotfilesFnmDefaultAlias;$env:PATH"
                }
            } else {
                $env:FNM_MULTISHELL_PATH = $null
                $pathSep = [System.IO.Path]::PathSeparator
                $pathList = [System.Collections.Generic.List[string]]::new()
                $pathList.Add($dotfilesFnmDefaultAlias)
                foreach ($part in $env:PATH.Split($pathSep)) {
                    if ($part -and
                        (-not [string]::Equals($part, $dotfilesFnmDefaultAlias, [System.StringComparison]::OrdinalIgnoreCase)) -and
                        ($part.IndexOf("fnm_multishells", [System.StringComparison]::OrdinalIgnoreCase) -lt 0)) {
                        $pathList.Add($part)
                    }
                }
                $env:PATH = [string]::Join($pathSep, $pathList)
            }
        } else {
            $env:PATH = $dotfilesFnmDefaultAlias
        }
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
            [string]$DirectoryPath = $ExecutionContext.SessionState.Path.CurrentFileSystemLocation.ProviderPath
        )

        $dir = $DirectoryPath
        while ($dir) {
            if ([System.IO.File]::Exists([System.IO.Path]::Combine($dir, ".nvmrc")) -or
                [System.IO.File]::Exists([System.IO.Path]::Combine($dir, ".node-version"))) {
                return $true
            }

            $pkgJson = [System.IO.Path]::Combine($dir, "package.json")
            if ([System.IO.File]::Exists($pkgJson)) {
                try {
                    $raw = [System.IO.File]::ReadAllText($pkgJson)
                    if ($raw.IndexOf('"engines"', [System.StringComparison]::Ordinal) -ge 0) {
                        return $true
                    }
                } catch {}
            }

            $parent = [System.IO.Path]::GetDirectoryName($dir)
            if ((-not $parent) -or [string]::Equals($parent, $dir, [System.StringComparison]::OrdinalIgnoreCase)) {
                break
            }
            $dir = $parent
        }

        return $false
    }

    function global:Set-FnmOnLoad {
        $global:__dotfiles_fnm_startup_checked = $true
        $currentDir = $ExecutionContext.SessionState.Path.CurrentFileSystemLocation.ProviderPath
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
            $prevStrategy = $env:FNM_VERSION_FILE_STRATEGY
            try {
                $env:FNM_VERSION_FILE_STRATEGY = "recursive"
                & $global:__dotfiles_fnm_bin use --silent-if-unchanged | Out-Host
            } finally {
                $env:FNM_VERSION_FILE_STRATEGY = $prevStrategy
            }
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

    function global:cd_with_fnm { Set-LocationWithFnm @args }

    # Hook LocationChangedAction on PowerShell 7+ so cd, zoxide (z/j), .., ...,
    # and Push-Location/Pop-Location all trigger Set-FnmOnLoad without calling
    # Set-Alias at startup (which would autoload Microsoft.PowerShell.Utility).
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        if (-not $global:__dotfiles_fnm_location_hooked) {
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
    } else {
        Set-Alias -Option AllScope -Scope Global -Name cd -Value Set-LocationWithFnm
    }

    # Defer initial directory version check until the first prompt render
    # (before Starship renders the prompt) so $PROFILE startup is never blocked.
    function global:Invoke-Starship-PreCommand {
        if (-not $global:__dotfiles_fnm_startup_checked) {
            $global:__dotfiles_fnm_startup_checked = $true
            if (-not $global:__dotfiles_fnm_default_alias) {
                Initialize-DotfilesFnm
            } else {
                Set-FnmOnLoad
            }
        }
    }

    if (-not $env:STARSHIP_SHELL) {
        Invoke-Starship-PreCommand
    }
}

Register-DotfilesFnm
