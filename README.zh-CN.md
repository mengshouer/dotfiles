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

可选的 `mise` layer 仅支持 Linux（`bash scripts/bootstrap mise`），只安装 mise 官方默认的按用户布局：二进制在 `~/.local/bin/mise`，工具和 shims 在 `~/.local/share/mise`。
工具、安装目录和 lockfile 属于各机器的本地状态，不由 chezmoi 管理。
zsh 集成会把 shims 加入 `PATH`（`~/.local/bin` 本身已在 PATH 中），并提供 `mise_activate`/`mise_deactivate` 以及 `mise_*` 相关快捷函数。
交互 shell 会在首个提示符之后通过 `zsh-defer` 自动激活，启动速度不受影响（没有 `zsh-defer` 时退回立即激活）；`mise_deactivate` 可让当前 shell 退出激活。
mise 当前只作为 Linux layer，其他平台有更好的选择。

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

- Unix `--set-shell` 显式允许把 zsh 设为默认 shell（`chsh`，缺少 `chsh` 时改用 `usermod -s`）；已经是登录 shell 时会跳过。
- 无 Homebrew 时，系统包走 apt 或 dnf/yum；发行版仓库里没有 `fzf` 时，改用官方 release 二进制（Linux `amd64`/`arm64`）。
- Unix `DOTFILES_BOOTSTRAP_BIN_DIR` 只覆盖当次 installer 的 bin 目录。
- macOS 由 Homebrew 安装 `fnm`；其数据目录默认为 `${XDG_DATA_HOME:-$HOME/.local/share}/fnm`，且不能包含空白字符。如果只有旧的 `~/Library/Application Support/fnm` 目录存在，`bootstrap dev` 会停止并打印手动迁移命令。
- Unix bootstrap 会在新安装的 `chezmoi` 不在当前 shell 的 `PATH` 时，输出准确的 `export PATH=...` 命令。
- Local overrides 位于 `~/.config/dotfiles/`、`~/.gitconfig` 和 `~/.config/git/ignore`；后者由 chezmoi 仅播种一次、之后归用户所有，改完即生效。
- Git baseline 配置由 `~/.config/git/base.gitconfig` 管理；`chezmoi apply` 会在缺少 include 时追加入口，不会替换已有本地 Git 配置。
