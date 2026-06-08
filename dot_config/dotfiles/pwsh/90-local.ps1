# Final local override. This file is intentionally ignored by git/chezmoi.

$localPs1 = Join-Path $HOME ".config\dotfiles\local.ps1"
if (Test-Path -LiteralPath $localPs1 -PathType Leaf) {
    . $localPs1
}

Remove-Variable localPs1 -ErrorAction SilentlyContinue
