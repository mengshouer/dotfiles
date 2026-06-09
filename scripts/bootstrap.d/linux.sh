#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/bootstrap [dev] [--set-shell] [--update]

Layers:
  terminal   git curl ca-certificates chezmoi zsh starship zoxide fzf zimfw
  dev        fnm uv

Flags:
  --set-shell   opt in to chsh -s "$(command -v zsh)"
  --update      git pull --ff-only, apply dotfiles, update zimfw
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
source "$script_dir/lib.sh"
bootstrap_parse_args "$@"
bootstrap_prepare_path
update_source_repo "$repo_root"

apt_updated=0

is_debian_like() {
  command -v apt-get >/dev/null 2>&1
}

apt_package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
}

apt_update_once() {
  (( apt_updated )) && return 0
  run_as_root apt-get update
  apt_updated=1
}

apt_install() {
  local packages=("$@")
  local missing=()
  local package

  is_debian_like || {
    say "apt-get not found. Install manually: ${packages[*]}"
    return 0
  }

  for package in "${packages[@]}"; do
    apt_package_installed "$package" || missing+=("$package")
  done

  if ((${#missing[@]})); then
    apt_update_once
    run_as_root apt-get install -y "${missing[@]}"
  fi
}

brew_formula_installed() {
  have brew && brew list --formula "$1" >/dev/null 2>&1
}

brew_install_formula() {
  local package="$1"

  brew_formula_installed "$package" && return 0
  run brew install "$package"
}

install_brew_or_apt_package() {
  local command_name="$1"
  local package="${2:-$command_name}"

  have "$command_name" && return 0

  if have brew; then
    brew_install_formula "$package"
    return 0
  fi

  apt_install "$package"
}

install_chezmoi() {
  have chezmoi && return 0

  if have brew; then
    brew_install_formula chezmoi
    return 0
  fi

  if is_debian_like && apt-cache show chezmoi >/dev/null 2>&1; then
    apt_install chezmoi
    return 0
  fi

  local bin_dir
  bin_dir="$(bootstrap_bin_dir)"
  say "Installing chezmoi with the official installer."
  run mkdir -p "$bin_dir"
  run sh -c 'sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$1"' sh "$bin_dir"
}

install_starship() {
  have starship && return 0

  if have brew; then
    brew_install_formula starship
    return 0
  fi

  local bin_dir
  bin_dir="$(bootstrap_bin_dir)"
  say "Installing starship with the official installer."
  run mkdir -p "$bin_dir"
  run sh -c 'curl -sS https://starship.rs/install.sh | sh -s -- -y -b "$1"' sh "$bin_dir"
}

install_zoxide() {
  have zoxide && return 0

  if have brew; then
    brew_install_formula zoxide
    return 0
  fi

  if is_debian_like && apt-cache show zoxide >/dev/null 2>&1; then
    apt_install zoxide
    return 0
  fi

  local bin_dir
  bin_dir="$(bootstrap_bin_dir)"
  say "Installing zoxide with the official installer."
  run mkdir -p "$bin_dir"
  run sh -c 'curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh -s -- --bin-dir "$1"' sh "$bin_dir"
}

install_fnm() {
  have fnm && return 0

  if have brew; then
    brew_install_formula fnm
    return 0
  fi

  if is_debian_like && apt-cache show fnm >/dev/null 2>&1; then
    apt_install fnm
    return 0
  fi

  say ""
  say "fnm is not installed. Run the following command to install it:"
  say "  curl -fsSL https://fnm.vercel.app/install | bash"
  say ""
}

install_uv() {
  have uv && return 0

  if have brew; then
    brew_install_formula uv
    return 0
  fi

  if is_debian_like && apt-cache show uv >/dev/null 2>&1; then
    apt_install uv
    return 0
  fi

  say ""
  say "uv is not installed. Run the following command to install it:"
  say "  curl -LsSf https://astral.sh/uv/install.sh | sh"
  say ""
}

case "$layer" in
  terminal)
    install_brew_or_apt_package curl
    install_brew_or_apt_package git
    if ! have brew && is_debian_like; then
      apt_install ca-certificates
    fi
    install_chezmoi
    install_brew_or_apt_package zsh
    install_starship
    install_zoxide
    install_brew_or_apt_package fzf
    ;;
  dev)
    install_fnm
    install_uv
    ;;
esac

apply_after_update

if [[ "$layer" == "terminal" ]]; then
  install_zimfw
fi

set_shell_if_requested
if (( ! update )); then
  print_manual_chezmoi_steps
fi
