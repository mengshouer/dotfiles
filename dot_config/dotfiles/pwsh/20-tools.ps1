# Terminal tool initialization.

function script:Get-DotfilesToolCacheDir {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $baseDir = [System.Environment]::GetFolderPath('LocalApplicationData')
    if (-not $baseDir) {
        $baseDir = if ($env:XDG_CACHE_HOME) {
            $env:XDG_CACHE_HOME
        } elseif ($HOME) {
            Join-Path $HOME ".cache"
        } else {
            [System.IO.Path]::GetTempPath()
        }
    }

    $cacheDir = Join-Path $baseDir $Name
    if (-not [System.IO.Directory]::Exists($cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }

    return $cacheDir
}

function script:Test-DotfilesToolCacheStale {
    param(
        [Parameter(Mandatory)]
        [string]$CachePath,

        [string[]]$DependencyPaths = @(),

        [int]$MinBytes = 256
    )

    $cacheInfo = [System.IO.FileInfo]::new($CachePath)
    if ((-not $cacheInfo.Exists) -or ($cacheInfo.Length -lt $MinBytes)) {
        return $true
    }

    $cacheTicks = $cacheInfo.LastWriteTimeUtc.Ticks
    foreach ($depPath in $DependencyPaths) {
        if (-not $depPath) {
            continue
        }

        $depInfo = [System.IO.FileInfo]::new($depPath)
        if ($depInfo.Exists) {
            $depTicks = [Math]::Max($depInfo.LastWriteTimeUtc.Ticks, $depInfo.CreationTimeUtc.Ticks)
            if ($depTicks -gt $cacheTicks) {
                return $true
            }
        }
    }

    return $false
}

function script:Resolve-DotfilesCachedToolPath {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$CachePath
    )

    if ([System.IO.File]::Exists($CachePath)) {
        try {
            $reader = [System.IO.File]::OpenText($CachePath)
            try {
                $line = $reader.ReadLine()
            } finally {
                $reader.Dispose()
            }
            if ($line -and $line.StartsWith("# DOTFILES_SOURCE_BINARY: ", [System.StringComparison]::Ordinal)) {
                $cachedBinary = $line.Substring(26).Trim()
                if ($cachedBinary -and [System.IO.File]::Exists($cachedBinary)) {
                    return $cachedBinary
                }
            }
        } catch {}
    }

    if (Get-Command Resolve-DotfilesCommandPath -ErrorAction SilentlyContinue) {
        return (Resolve-DotfilesCommandPath -Name $Name)
    }

    $cmd = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) {
        return $cmd.Source
    }

    return $null
}

function script:Write-DotfilesToolCacheFile {
    param(
        [Parameter(Mandatory)]
        [string]$CachePath,

        [Parameter(Mandatory)]
        [string]$Content
    )

    $tempPath = "$CachePath.$PID.tmp"
    try {
        [System.IO.File]::WriteAllText($tempPath, $Content, [System.Text.UTF8Encoding]::new($true))
        Move-Item -LiteralPath $tempPath -Destination $CachePath -Force -ErrorAction Stop
    } catch {
        try {
            [System.IO.File]::WriteAllText($CachePath, $Content, [System.Text.UTF8Encoding]::new($true))
        } catch {}
    } finally {
        if ([System.IO.File]::Exists($tempPath)) {
            try { [System.IO.File]::Delete($tempPath) } catch {}
        }
    }
}

function Initialize-DotfilesZoxide {
    $cachePath = Join-Path (Get-DotfilesToolCacheDir -Name "zoxide") "init.cached.ps1"
    $zoxidePath = Resolve-DotfilesCachedToolPath -Name "zoxide" -CachePath $cachePath
    if (-not $zoxidePath) {
        return
    }

    $localEnvPath = if ($HOME) { Join-Path $HOME ".config\dotfiles\local.env" } else { $null }
    $needsRefresh = Test-DotfilesToolCacheStale `
        -CachePath $cachePath `
        -DependencyPaths @($zoxidePath, $localEnvPath, $PSCommandPath) `
        -MinBytes 256

    if ($needsRefresh) {
        if (Get-Command Resolve-DotfilesCommandPath -ErrorAction SilentlyContinue) {
            $resolvedZoxide = Resolve-DotfilesCommandPath -Name "zoxide"
            if ($resolvedZoxide) {
                $zoxidePath = $resolvedZoxide
            }
        }

        $prevEncoding = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
            $initScript = (& $zoxidePath init powershell) -join [Environment]::NewLine
        } finally {
            [Console]::OutputEncoding = $prevEncoding
        }

        $escapedZoxidePath = $zoxidePath.Replace("'", "''")
        $initScript = [regex]::Replace(
            $initScript,
            '(?m)^(\s*\$result\s*=\s*)zoxide(\s+@args\b)',
            "`$1& '$escapedZoxidePath'`$2"
        )
        $initScript = [regex]::Replace(
            $initScript,
            '(?m)^(\s*)zoxide(\s+add\b)',
            "`$1& '$escapedZoxidePath'`$2"
        )
        $content = "# DOTFILES_SOURCE_BINARY: $zoxidePath" + [Environment]::NewLine + $initScript
        Write-DotfilesToolCacheFile -CachePath $cachePath -Content $content
    }

    # Reset zoxide hook guard before sourcing so re-sourcing $PROFILE re-attaches
    # the zoxide prompt hook after starship redefines global:prompt.
    Remove-Variable -Scope Global -Name __zoxide_hooked -ErrorAction SilentlyContinue
    . $cachePath
}

function Initialize-DotfilesStarship {
    $cachePath = Join-Path (Get-DotfilesToolCacheDir -Name "starship") "init.cached.ps1"
    $starshipPath = Resolve-DotfilesCachedToolPath -Name "starship" -CachePath $cachePath
    if (-not $starshipPath) {
        return
    }

    $configPath = if ($env:STARSHIP_CONFIG) {
        $env:STARSHIP_CONFIG
    } elseif ($HOME) {
        Join-Path $HOME ".config\starship.toml"
    } else {
        $null
    }

    $localEnvPath = if ($HOME) { Join-Path $HOME ".config\dotfiles\local.env" } else { $null }
    $needsRefresh = Test-DotfilesToolCacheStale `
        -CachePath $cachePath `
        -DependencyPaths @($starshipPath, $configPath, $localEnvPath, $PSCommandPath) `
        -MinBytes 512

    if ($needsRefresh) {
        if (Get-Command Resolve-DotfilesCommandPath -ErrorAction SilentlyContinue) {
            $resolvedStarship = Resolve-DotfilesCommandPath -Name "starship"
            if ($resolvedStarship) {
                $starshipPath = $resolvedStarship
            }
        }

        $prevEncoding = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
            $initScript = (& $starshipPath init powershell --print-full-init) -join [Environment]::NewLine
            $continuation = ((& $starshipPath prompt --continuation) -join "`n").TrimEnd("`r", "`n")
        } finally {
            [Console]::OutputEncoding = $prevEncoding
        }

        $escapedStarshipPath = $starshipPath.Replace("'", "''")
        $initScript = [regex]::Replace(
            $initScript,
            "(-Executable\s+)'[^']*'",
            "`$1'$escapedStarshipPath'"
        )

        if ($continuation) {
            $escapedContinuation = $continuation.Replace("'", "''")
            $initScript = [regex]::Replace(
                $initScript,
                'Invoke-Native\s+-Executable\s+''[^'']+''\s+-Arguments\s+@\(\s*"prompt",\s*"--continuation"\s*\)',
                "'$escapedContinuation'"
            )
        }

        # Replace slow Get-Random pipeline (~16ms) with fast GUID slice (<0.1ms).
        $initScript = $initScript.Replace(
            '$ENV:STARSHIP_SESSION_KEY = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 16 | ForEach-Object { [char]$_ })',
            '$ENV:STARSHIP_SESSION_KEY = [guid]::NewGuid().ToString("N").Substring(0, 16)'
        )

        # Defer PSReadLine option hooks until the first prompt render so profile
        # startup does not pay the cost of scanning PSModulePath to autoload PSReadLine.
        $initScript = $initScript.Replace(
            "`$script:DoesUseLists = (Get-PSReadLineOption).PredictionViewStyle -eq 'ListView'",
            '$script:DoesUseLists = $false'
        )
        $psReadLinePattern = '(?s)(# Invoke Starship and set continuation prompt.*?)(\r?\n\s*Export-ModuleMember)'
        if ($initScript -match $psReadLinePattern) {
            $initScript = [regex]::Replace(
                $initScript,
                $psReadLinePattern,
                '$script:PSReadLineInitialized = $false
    function Initialize-StarshipPSReadLine {
        if ($script:PSReadLineInitialized -or (-not (Get-Module PSReadLine))) {
            return
        }
        $script:PSReadLineInitialized = $true
        $script:DoesUseLists = (Get-PSReadLineOption).PredictionViewStyle -eq ''ListView''
        $1
    }$2'
            )
            $initScript = $initScript.Replace(
                'function global:prompt {',
                "function global:prompt {`n        if (-not `$script:PSReadLineInitialized) { Initialize-StarshipPSReadLine }"
            ).Replace(
                'function Enable-TransientPrompt {',
                "function Enable-TransientPrompt {`n        if (-not `$script:PSReadLineInitialized) { Initialize-StarshipPSReadLine }"
            )
        }

        $content = "# DOTFILES_SOURCE_BINARY: $starshipPath" + [Environment]::NewLine + $initScript
        Write-DotfilesToolCacheFile -CachePath $cachePath -Content $content
    }

    . $cachePath
}

Initialize-DotfilesStarship
Initialize-DotfilesZoxide
