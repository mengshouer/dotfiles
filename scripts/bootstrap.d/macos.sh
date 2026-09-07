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

if (( EUID == 0 )); then
  printf 'Homebrew cannot be used as root. Run macOS bootstrap as a normal user.\n' >&2
  exit 1
fi

bootstrap_prepare_path
update_source_repo "$repo_root"

ensure_brew() {
  if have_usable_brew; then
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

check_fnm_legacy_dir() {
  local fnm_dir legacy_fnm_dir

  fnm_dir="${FNM_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/fnm}"
  legacy_fnm_dir="$HOME/Library/Application Support/fnm"
  [[ "$fnm_dir" == "$legacy_fnm_dir" ]] && fnm_dir="${XDG_DATA_HOME:-$HOME/.local/share}/fnm"
  [[ -d "$legacy_fnm_dir" && ! -e "$fnm_dir" ]] || return 0

  printf 'Legacy fnm data directory found: %s\n' "$legacy_fnm_dir" >&2
  printf 'Move it before rerunning bootstrap:\n' >&2
  printf '  mkdir -p %q\n' "$(dirname "$fnm_dir")" >&2
  printf '  mv %q %q\n' "$legacy_fnm_dir" "$fnm_dir" >&2
  printf '  export FNM_DIR=%q\n' "$fnm_dir" >&2
  return 1
}

case "$layer" in
  terminal)
    brew_install git curl chezmoi zsh starship zoxide fzf
    ;;
  dev)
    check_fnm_legacy_dir
    brew_install fnm uv
    ;;
esac

apply_after_update

if [[ "$layer" == "terminal" ]]; then
  install_zimfw
fi

set_shell_if_requested
if (( ! update && ! set_shell )); then
  print_manual_chezmoi_steps
fi
