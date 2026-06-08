# Shared PowerShell profile loader.

$dotfilesPwshDir = Join-Path $HOME ".config\dotfiles\pwsh"
$dotfilesProfileLoader = if ($PSCommandPath) {
    $PSCommandPath
} else {
    Join-Path $dotfilesPwshDir "00-profile-loader.ps1"
}

if (Test-Path -LiteralPath $dotfilesPwshDir -PathType Container) {
    Get-ChildItem -LiteralPath $dotfilesPwshDir -Filter "*.ps1" |
        Where-Object { (-not $dotfilesProfileLoader) -or ($_.FullName -ne $dotfilesProfileLoader) } |
        Sort-Object Name |
        ForEach-Object { . $_.FullName }
}

Remove-Variable dotfilesPwshDir, dotfilesProfileLoader -ErrorAction SilentlyContinue
