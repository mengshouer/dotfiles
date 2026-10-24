# Python virtual environment helpers.

function global:Enable-DotfilesVenv {
    param(
        [string]$Path = ".venv"
    )

    $candidates = @(
        $Path,
        [System.IO.Path]::Combine($Path, "Scripts\Activate.ps1"),
        [System.IO.Path]::Combine($Path, ".venv\Scripts\Activate.ps1")
    )

    $activate = $null
    foreach ($candidate in $candidates) {
        if ($candidate -and [System.IO.File]::Exists($candidate)) {
            $activate = $candidate
            break
        }
    }

    if (-not $activate) {
        Write-Error "No PowerShell virtual environment activation script found for '$Path'."
        return
    }

    Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force
    . $activate
}

function global:venv { Enable-DotfilesVenv @args }
function global:va   { Enable-DotfilesVenv @args }

function global:Disable-DotfilesVenv {
    if (Get-Command deactivate -ErrorAction SilentlyContinue) {
        deactivate
        return
    }

    Write-Host "No active Python virtual environment."
}

function global:vde  { Disable-DotfilesVenv @args }
