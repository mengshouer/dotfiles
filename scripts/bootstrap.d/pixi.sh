#!/usr/bin/env bash
# Optional Linux-only, home-persistent pixi setup.

install_pixi() (
  set -euo pipefail

  # Do not reintroduce inherited locations excluded by root's PATH policy.
  if (( EUID == 0 )); then
    case "${PIXI_HOME:-}" in
      [!/]*|/home|/home/*|/Users|/Users/*|/tmp|/tmp/*|/var/tmp|/var/tmp/*|/opt/homebrew|/opt/homebrew/*)
        unset PIXI_HOME ;;
    esac
  fi

  # Keep this layout in sync with dot_config/dotfiles/zsh/06-pixi-path.zsh.
  local home_dir="${PIXI_HOME:-$HOME/.pixi}"
  local bin_dir="$home_dir/bin"
  local executable="$bin_dir/pixi"
  local platform tmp_dir=""

  case "$(uname -m)" in
    x86_64|amd64) platform=x86_64 ;;
    aarch64|arm64) platform=aarch64 ;;
    *) say "pixi bootstrap supports Linux x86_64 and aarch64 only."; return 1 ;;
  esac

  # Never replace a symlink that may point outside the persistent home.
  if [[ -L "$executable" ]]; then
    say "Refusing to reuse a symlink at $executable; a home-local executable is required."
    return 1
  fi
  if [[ ! -x "$executable" ]]; then
    if [[ -e "$executable" ]]; then
      say "Refusing to overwrite the existing non-executable path: $executable"
      return 1
    fi
    mkdir -p "$bin_dir"
    tmp_dir="$(mktemp -d "$bin_dir/.pixi-install.XXXXXX")"
    trap 'rm -rf -- "$tmp_dir"' EXIT
    # The musl build is a static binary: no glibc or archive tooling required.
    say "Installing pixi from the official $platform release into $bin_dir."
    curl -fsSL --retry 3 -o "$tmp_dir/pixi" \
      "https://github.com/prefix-dev/pixi/releases/latest/download/pixi-${platform}-unknown-linux-musl"
    chmod 0755 "$tmp_dir/pixi"
    "$tmp_dir/pixi" --version
    mv "$tmp_dir/pixi" "$executable"
  fi
  "$executable" --version

  say "pixi is ready at $executable."
  say "After chezmoi apply, open a new zsh terminal: its fixed pixi installation path is detected and $bin_dir is added to PATH without activation."
  if ! getconf GNU_LIBC_VERSION >/dev/null 2>&1; then
    say "Note: pixi itself is a static musl build, but conda-forge packages still need glibc to run."
  fi
  say "Install the tools each machine needs with: pixi global install <package> (or the pxi shortcut after chezmoi apply)."
)
