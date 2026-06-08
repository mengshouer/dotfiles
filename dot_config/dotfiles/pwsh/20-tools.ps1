# Terminal tool initialization.

function Initialize-DotfilesZoxide {
    if (Get-Command zoxide -CommandType Application -ErrorAction SilentlyContinue) {
        Invoke-Expression (& { (zoxide init powershell | Out-String) })
    }
}

function Initialize-DotfilesStarship {
    $starship = Get-Command starship -CommandType Application -ErrorAction SilentlyContinue
    if (-not $starship) {
        return
    }

    $localAppData = [System.Environment]::GetFolderPath('LocalApplicationData')
    if (-not $localAppData) {
        $localAppData = if ($env:HOME) { Join-Path $env:HOME '.cache' } else { [System.IO.Path]::GetTempPath() }
    }
    $cacheRoot = Join-Path $localAppData "starship"
    $cachePath = Join-Path $cacheRoot "init.cached.ps1"

    if (-not (Test-Path -LiteralPath $cacheRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $cacheRoot -Force | Out-Null
    }

    $needsRefresh = -not (Test-Path -LiteralPath $cachePath -PathType Leaf)
    $starshipPath = $starship.Source
    if (-not $starshipPath) {
        $starshipPath = $starship.Path
    }

    if ((-not $needsRefresh) -and $starshipPath -and (Test-Path -LiteralPath $starshipPath)) {
        $cache = Get-Item -LiteralPath $cachePath
        $binary = Get-Item -LiteralPath $starshipPath
        $needsRefresh = $binary.LastWriteTimeUtc -gt $cache.LastWriteTimeUtc
    }

    if ($needsRefresh) {
        starship init powershell | Out-File -LiteralPath $cachePath -Encoding utf8
    }

    . $cachePath
}

Initialize-DotfilesStarship
Initialize-DotfilesZoxide
