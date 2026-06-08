Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$bootstrap = Join-Path $PSScriptRoot "bootstrap.d\windows.ps1"

& $bootstrap @args
