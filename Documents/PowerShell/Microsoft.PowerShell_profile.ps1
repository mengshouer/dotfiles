# PowerShell 7 profile managed by chezmoi.

$dotfilesProfileLoader = Join-Path $HOME ".config\dotfiles\pwsh\00-profile-loader.ps1"

if (Test-Path -LiteralPath $dotfilesProfileLoader -PathType Leaf) {
    . $dotfilesProfileLoader
}

Remove-Variable dotfilesProfileLoader -ErrorAction SilentlyContinue
