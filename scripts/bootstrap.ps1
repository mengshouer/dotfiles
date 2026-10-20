Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$bootstrap = Join-Path $PSScriptRoot "bootstrap.d\windows.ps1"

$global:LASTEXITCODE = 0
& $bootstrap @args
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
