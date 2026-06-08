# Python virtual environment helpers.

function Enable-DotfilesVenv {
    param(
        [string]$Path = ".venv"
    )

    $candidates = @(
        $Path,
        (Join-Path $Path "Scripts\Activate.ps1"),
        (Join-Path $Path ".venv\Scripts\Activate.ps1")
    )

    $activate = $candidates |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1

    if (-not $activate) {
        Write-Error "No PowerShell virtual environment activation script found for '$Path'."
        return
    }

    Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force
    . $activate
}

Set-Alias -Name venv -Value Enable-DotfilesVenv
Set-Alias -Name va -Value Enable-DotfilesVenv

function Disable-DotfilesVenv {
    if (Get-Command deactivate -ErrorAction SilentlyContinue) {
        deactivate
        return
    }

    Write-Host "No active Python virtual environment."
}

Set-Alias -Name vde -Value Disable-DotfilesVenv
