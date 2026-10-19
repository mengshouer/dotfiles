# Shared PowerShell profile loader.

$dotfilesPwshDir = Join-Path $HOME ".config\dotfiles\pwsh"
$dotfilesProfileLoader = if ($PSCommandPath) {
    $PSCommandPath
} else {
    Join-Path $dotfilesPwshDir "00-profile-loader.ps1"
}

if ([System.IO.Directory]::Exists($dotfilesPwshDir)) {
    $dotfilesScripts = [System.IO.Directory]::GetFiles($dotfilesPwshDir, "*.ps1")
    [System.Array]::Sort($dotfilesScripts, [System.StringComparer]::OrdinalIgnoreCase)
    foreach ($dotfilesScript in $dotfilesScripts) {
        if ((-not $dotfilesProfileLoader) -or (-not [string]::Equals($dotfilesScript, $dotfilesProfileLoader, [System.StringComparison]::OrdinalIgnoreCase))) {
            . $dotfilesScript
        }
    }
}

Remove-Variable dotfilesPwshDir, dotfilesProfileLoader, dotfilesScripts, dotfilesScript -ErrorAction SilentlyContinue
