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

可选的 `mise` layer（`bash scripts/bootstrap mise`，支持 Linux 和 macOS）用 mise 官方安装脚本（不是 Homebrew）安装官方默认的按用户布局：二进制在 `~/.local/bin/mise`，工具和 shims 在 `~/.local/share/mise`。
工具、安装目录和 lockfile 属于各机器的本地状态，不由 chezmoi 管理。
zsh/bash 集成会把 shims 加入 `PATH`（`~/.local/bin` 本身已在 PATH 中），并提供 `mise_activate`/`mise_deactivate` 以及 `mise_*` 相关快捷函数；布局是固定的，因此安装在其它位置（例如 Homebrew 版）的 mise 不会被识别。
交互 shell 会在首个提示符之后通过 `zsh-defer` 自动激活（在 bash 或无 `zsh-defer` 时退回立即激活）；`mise_deactivate` 可让当前 shell 退出激活。
macOS 上 mise shims 和 `~/.local/bin` 位于 Homebrew 之前，因此 mise 安装的同名工具会覆盖 Homebrew 的同名命令。

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

- Unix `--set-shell` 显式允许把所选 shell（默认 zsh，传入 `--bash` 时为 bash）设为默认 shell（`chsh`，缺少 `chsh` 时改用 `usermod -s`）；已经是登录 shell 时会跳过。
- 在不便安装 zsh 的环境可传入 `--bash`（`bash scripts/bootstrap --bash`；推荐首选 zsh，bash 仅作为降级兜底方案，不建议作为主力首选）：跳过 `zsh`/`zimfw`，安装 `bash-completion` 并启用 `~/.bashrc`（`~/.config/dotfiles/bash/entry.bash`）。单独执行 `chezmoi apply` 时，只有显式请求 bash 模式（`DOTFILES_ENABLE_BASH=1 chezmoi apply`）、托管块已存在、或未安装 zsh，才会改动 `~/.bashrc`；只要装了 zsh，`~/.zshrc` 仍会照常更新。
- bash 集成复用与 zsh 相同的模块，要求 bash 4.2+（macOS 自带 bash 3.2 会静默跳过）；它只管理 `~/.bashrc`，因此只读 `~/.bash_profile` 的登录 shell 不会被桥接。交互体验有降级（无语法高亮、行内自动建议与异步延迟加载；`fnm` 在首次调用 `fnm` 时初始化且无 `cd` 钩子；mise 在启动时激活，而不是首个提示符之后）。
- 无 Homebrew 时，系统包走 apt 或 dnf/yum；发行版仓库里没有 `fzf` 时，改用官方 release 二进制（Linux `amd64`/`arm64`）。
- Unix `DOTFILES_BOOTSTRAP_BIN_DIR` 只覆盖当次 installer 的 bin 目录。
- macOS 由 Homebrew 安装 `fnm`；其数据目录默认为 `${XDG_DATA_HOME:-$HOME/.local/share}/fnm`，且不能包含空白字符。如果只有旧的 `~/Library/Application Support/fnm` 目录存在，`bootstrap dev` 会停止并打印手动迁移命令。
- Unix bootstrap 会在新安装的 `chezmoi` 不在当前 shell 的 `PATH` 时，输出准确的 `export PATH=...` 命令。
- Local overrides 位于 `~/.config/dotfiles/`、`~/.gitconfig` 和 `~/.config/git/ignore`；后者由 chezmoi 仅播种一次、之后归用户所有，改完即生效。`elocal` 会按当前 shell 打开 `local.zsh` 或 `local.bash`。
- Git baseline 配置由 `~/.config/git/base.gitconfig` 管理；`chezmoi apply` 会在缺少 include 时追加入口，不会替换已有本地 Git 配置。
