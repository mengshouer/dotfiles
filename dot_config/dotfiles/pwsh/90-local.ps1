# Final local override. This file is intentionally ignored by git/chezmoi.

if ([System.IO.File]::Exists([System.IO.Path]::Combine($HOME, ".config\dotfiles\local.ps1"))) {
    . ([System.IO.Path]::Combine($HOME, ".config\dotfiles\local.ps1"))
}
