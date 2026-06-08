# Shared PowerShell helpers and early environment import.

function Import-DotfilesEnvFile {
    param(
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }

    Get-Content -LiteralPath $Path | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith("#")) {
            return
        }

        $separator = $line.IndexOf("=")
        if ($separator -lt 1) {
            return
        }

        $key = $line.Substring(0, $separator).Trim()
        $value = $line.Substring($separator + 1)

        if ($key -notmatch "^[A-Za-z_][A-Za-z0-9_]*$") {
            return
        }

        Set-Item -LiteralPath "Env:$key" -Value $value
    }
}

function Add-DotfilesPathPrepend {
    param(
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return
    }

    $parts = @()
    if ($env:PATH) {
        $parts = $env:PATH -split [IO.Path]::PathSeparator
    }

    $filtered = @($parts | Where-Object { $_ -and ($_ -ne $Path) })
    $env:PATH = (@($Path) + $filtered) -join [IO.Path]::PathSeparator
}

Import-DotfilesEnvFile -Path (Join-Path $HOME ".config\dotfiles\local.env")
