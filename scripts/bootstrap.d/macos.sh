#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/bootstrap [dev] [--set-shell] [--update]

Layers:
  terminal   git curl chezmoi zsh starship zoxide fzf zimfw
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

ensure_brew() {
  if have brew; then
    return 0
  fi

  printf 'Homebrew is required for macOS bootstrap: https://brew.sh/\n' >&2
  return 1
}

brew_install() {
  ensure_brew || return 1
  local package
  for package in "$@"; do
    if brew list --formula "$package" >/dev/null 2>&1; then
      continue
    fi
    run brew install "$package"
  done
}

case "$layer" in
  terminal)
    brew_install git curl chezmoi zsh starship zoxide fzf
    ;;
  dev)
    brew_install fnm uv
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
