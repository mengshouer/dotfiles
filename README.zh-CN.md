# Dotfiles

[English](README.md)

这是一个由 chezmoi 管理的个人 dotfiles 仓库，覆盖 macOS、Linux、WSL 和 Windows。

## 安装

Unix:

```sh
repo_url="<repo-url>"
source_dir="${XDG_DATA_HOME:-$HOME/.local/share}/chezmoi"

mkdir -p "$(dirname "$source_dir")"
git clone "$repo_url" "$source_dir"
cd "$source_dir"

bash scripts/bootstrap
```

Windows PowerShell:

```powershell
$repoUrl = "<repo-url>"
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

默认 layer 是 `terminal`；`dev` 只安装 `fnm` 和 `uv`。

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

`--update` / `-Update` 会运行 `git pull --ff-only` 和 `chezmoi apply`。
Unix `terminal` update 还会运行 `zimfw update`。

## 备注

- Unix `--set-shell` 显式允许 `chsh -s "$(command -v zsh)"`。
- Unix `DOTFILES_BOOTSTRAP_BIN_DIR` 只覆盖当次 installer 的 bin 目录。
- Unix bootstrap 会在新安装的 `chezmoi` 不在当前 shell 的 `PATH` 时，输出准确的 `export PATH=...` 命令。
- Local overrides 位于 `~/.config/dotfiles/`、`~/.gitconfig` 和 `~/.config/git/ignore.local`。
- Git baseline 配置由 `~/.config/git/base.gitconfig` 管理；`chezmoi apply` 会在缺少 include 时追加入口，不会替换已有本地 Git 配置。
