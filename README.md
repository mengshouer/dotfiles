# dotfiles

[中文](README.zh-CN.md)

Personal dotfiles for macOS, Linux, WSL, and Windows, managed with chezmoi.

## Install

Unix:

```sh
repo_url="https://github.com/mengshouer/dotfiles.git"
source_dir="${XDG_DATA_HOME:-$HOME/.local/share}/chezmoi"

mkdir -p "$(dirname "$source_dir")"
git clone "$repo_url" "$source_dir"
cd "$source_dir"

bash scripts/bootstrap
```

Windows PowerShell:

```powershell
$repoUrl = "https://github.com/mengshouer/dotfiles.git"
$sourceDir = Join-Path $HOME ".local\share\chezmoi"

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $sourceDir) | Out-Null
git clone $repoUrl $sourceDir
Set-Location $sourceDir

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\bootstrap.ps1
```

## Bootstrap

Unix:

```sh
bash scripts/bootstrap
bash scripts/bootstrap dev
```

Windows PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\bootstrap.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\bootstrap.ps1 dev
```

Default layer is `terminal`; `dev` installs `fnm` and `uv`.

## Update

Unix:

```sh
cd "${XDG_DATA_HOME:-$HOME/.local/share}/chezmoi"
bash scripts/bootstrap --update
bash scripts/bootstrap dev --update
```

Windows PowerShell:

```powershell
Set-Location "$HOME\.local\share\chezmoi"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\bootstrap.ps1 -Update
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\bootstrap.ps1 dev -Update
```

`--update` / `-Update` runs `git pull --ff-only` and `chezmoi apply`.
Unix `terminal` update also runs `zimfw update`.

## Notes

- Unix `--set-shell` opts in to `chsh -s "$(command -v zsh)"`.
- Unix `DOTFILES_BOOTSTRAP_BIN_DIR` overrides the installer bin directory for that run.
- Unix bootstrap prints the exact `export PATH=...` command when a newly installed `chezmoi` is outside the current shell's `PATH`.
- Local overrides live under `~/.config/dotfiles/`, `~/.gitconfig`, and `~/.config/git/ignore.local`.
- Git baseline settings are managed in `~/.config/git/base.gitconfig`; `chezmoi apply` adds a missing include without replacing existing local Git settings.
