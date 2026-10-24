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
            [System.IO.Path]::Combine($HOME, ".cache")
        } else {
            [System.IO.Path]::GetTempPath()
        }
    }

    $cacheDir = [System.IO.Path]::Combine($baseDir, $Name)
    if (-not [System.IO.Directory]::Exists($cacheDir)) {
        [void][System.IO.Directory]::CreateDirectory($cacheDir)
    }

    return $cacheDir
}

function script:Get-DotfilesBinarySignature {
    param(
        [Parameter(Mandatory)]
        [string]$BinaryPath
    )

    try {
        $info = [System.IO.FileInfo]::new($BinaryPath)
        if ($info.Exists) {
            return "$BinaryPath|$($info.LastWriteTimeUtc.Ticks):$($info.Length)"
        }
    } catch {}

    return $BinaryPath
}

function script:Get-DotfilesCacheHeaderLine {
    param(
        [Parameter(Mandatory)]
        [string]$CachePath
    )

    if (-not [System.IO.File]::Exists($CachePath)) {
        return $null
    }

    try {
        $reader = [System.IO.File]::OpenText($CachePath)
        try {
            return $reader.ReadLine()
        } finally {
            $reader.Dispose()
        }
    } catch {
        return $null
    }
}

function script:Test-DotfilesToolCacheStale {
    param(
        [Parameter(Mandatory)]
        [string]$CachePath,

        [string]$HeaderLine = $null,

        [string]$ExpectedSignature = "",

        [string[]]$DependencyPaths = @(),

        [int]$MinBytes = 256
    )

    $cacheInfo = [System.IO.FileInfo]::new($CachePath)
    if ((-not $cacheInfo.Exists) -or ($cacheInfo.Length -lt $MinBytes)) {
        return $true
    }

    if ($ExpectedSignature) {
        $firstLine = if ($null -ne $HeaderLine) { $HeaderLine } else { Get-DotfilesCacheHeaderLine -CachePath $CachePath }
        if ($firstLine -ne "# DOTFILES_SOURCE_BINARY: $ExpectedSignature") {
            return $true
        }
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

        [string]$HeaderLine = $null
    )

    if ($HeaderLine -and $HeaderLine.StartsWith("# DOTFILES_SOURCE_BINARY: ", [System.StringComparison]::Ordinal)) {
        $cachedHeader = $HeaderLine.Substring(26).Trim()
        $pipeIndex = $cachedHeader.IndexOf('|')
        $cachedBinary = if ($pipeIndex -ge 0) { $cachedHeader.Substring(0, $pipeIndex) } else { $cachedHeader }
        if ($cachedBinary -and [System.IO.File]::Exists($cachedBinary)) {
            return $cachedBinary
        }
    }

    if ($null -ne ${function:Resolve-DotfilesCommandPath}) {
        return (Resolve-DotfilesCommandPath -Name $Name)
    }

    $cmds = @(Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue)
    if ($cmds.Count -gt 0) {
        return $cmds[0].Source
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
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            [System.IO.File]::Move($tempPath, $CachePath, $true)
        } else {
            if ([System.IO.File]::Exists($CachePath)) {
                [System.IO.File]::Delete($CachePath)
            }
            [System.IO.File]::Move($tempPath, $CachePath)
        }
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
    $global:__dotfiles_zoxide_bin = $null
    $global:__dotfiles_zoxide_cache = $null
    $cachePath = [System.IO.Path]::Combine((Get-DotfilesToolCacheDir -Name "zoxide"), "init.cached.ps1")
    $headerLine = Get-DotfilesCacheHeaderLine -CachePath $cachePath
    $zoxidePath = Resolve-DotfilesCachedToolPath -Name "zoxide" -HeaderLine $headerLine
    if (-not $zoxidePath) {
        return
    }

    $localEnvPath = if ($HOME) { [System.IO.Path]::Combine($HOME, ".config\dotfiles\local.env") } else { $null }
    $localPs1Path = if ($HOME) { [System.IO.Path]::Combine($HOME, ".config\dotfiles\local.ps1") } else { $null }
    $zoxideSig = Get-DotfilesBinarySignature -BinaryPath $zoxidePath
    $needsRefresh = Test-DotfilesToolCacheStale `
        -CachePath $cachePath `
        -HeaderLine $headerLine `
        -ExpectedSignature $zoxideSig `
        -DependencyPaths @($zoxidePath, $localEnvPath, $localPs1Path, $PSCommandPath) `
        -MinBytes 256

    if ($needsRefresh) {
        if ($null -ne ${function:Resolve-DotfilesCommandPath}) {
            $resolvedZoxide = Resolve-DotfilesCommandPath -Name "zoxide"
            if ($resolvedZoxide) {
                $zoxidePath = $resolvedZoxide
                $zoxideSig = Get-DotfilesBinarySignature -BinaryPath $zoxidePath
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
        $content = "# DOTFILES_SOURCE_BINARY: $zoxideSig" + [Environment]::NewLine + $initScript
        Write-DotfilesToolCacheFile -CachePath $cachePath -Content $content
    }

    $global:__dotfiles_zoxide_bin = $zoxidePath
    $global:__dotfiles_zoxide_cache = $cachePath

    # Reset zoxide hook guard before sourcing so re-sourcing $PROFILE re-attaches
    # the zoxide prompt hook after starship redefines global:prompt.
    Remove-Variable -Scope Global -Name __zoxide_hooked -ErrorAction SilentlyContinue
    . $cachePath
}

function Initialize-DotfilesStarship {
    $global:__dotfiles_starship_bin = $null
    $global:__dotfiles_starship_cache = $null
    $cachePath = [System.IO.Path]::Combine((Get-DotfilesToolCacheDir -Name "starship"), "init.cached.ps1")
    $headerLine = Get-DotfilesCacheHeaderLine -CachePath $cachePath
    $starshipPath = Resolve-DotfilesCachedToolPath -Name "starship" -HeaderLine $headerLine
    if (-not $starshipPath) {
        return
    }

    $configPath = if ($env:STARSHIP_CONFIG) {
        $env:STARSHIP_CONFIG
    } elseif ($HOME) {
        [System.IO.Path]::Combine($HOME, ".config\starship.toml")
    } else {
        $null
    }

    $localEnvPath = if ($HOME) { [System.IO.Path]::Combine($HOME, ".config\dotfiles\local.env") } else { $null }
    $localPs1Path = if ($HOME) { [System.IO.Path]::Combine($HOME, ".config\dotfiles\local.ps1") } else { $null }
    $starshipSig = Get-DotfilesBinarySignature -BinaryPath $starshipPath
    $needsRefresh = Test-DotfilesToolCacheStale `
        -CachePath $cachePath `
        -HeaderLine $headerLine `
        -ExpectedSignature $starshipSig `
        -DependencyPaths @($starshipPath, $configPath, $localEnvPath, $localPs1Path, $PSCommandPath) `
        -MinBytes 512

    if ($needsRefresh) {
        if ($null -ne ${function:Resolve-DotfilesCommandPath}) {
            $resolvedStarship = Resolve-DotfilesCommandPath -Name "starship"
            if ($resolvedStarship) {
                $starshipPath = $resolvedStarship
                $starshipSig = Get-DotfilesBinarySignature -BinaryPath $starshipPath
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
        $psReadLinePattern = '(?s)(# Invoke Starship and set continuation prompt.*?)(\r?\n\s*Export-ModuleMember)'
        if ($initScript -match $psReadLinePattern) {
            $initScript = $initScript.Replace(
                "`$script:DoesUseLists = (Get-PSReadLineOption).PredictionViewStyle -eq 'ListView'",
                '$script:DoesUseLists = $false'
            )
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
            ).Replace(
                'if ([Microsoft.PowerShell.PSConsoleReadLine]::InViCommandMode()) {',
                'if ($script:PSReadLineInitialized -and [Microsoft.PowerShell.PSConsoleReadLine]::InViCommandMode()) {'
            )
        }

        $content = "# DOTFILES_SOURCE_BINARY: $starshipSig" + [Environment]::NewLine + $initScript
        Write-DotfilesToolCacheFile -CachePath $cachePath -Content $content
    }

    $global:__dotfiles_starship_bin = $starshipPath
    $global:__dotfiles_starship_cache = $cachePath
    . $cachePath
}

Initialize-DotfilesStarship
Initialize-DotfilesZoxide
