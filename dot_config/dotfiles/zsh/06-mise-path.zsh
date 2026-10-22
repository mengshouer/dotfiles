# Early optional mise PATH integration, before zimfw/compinit.
# Uses mise's official per-user layout: the binary lives in ~/.local/bin and
# installs/shims live under ~/.local/share/mise, inside the current user's HOME.

zsh_mise_check() {
  local mise_home="$HOME"
  (( EUID == 0 )) && mise_home=~root
  [[ -x "$mise_home/.local/bin/mise" ]] || return 1

  export MISE_DATA_DIR="${MISE_DATA_DIR:-$mise_home/.local/share/mise}"
  export MISE_CONFIG_DIR="${MISE_CONFIG_DIR:-$mise_home/.config/mise}"
  export MISE_STATE_DIR="${MISE_STATE_DIR:-$mise_home/.local/state/mise}"
  if [[ "$OSTYPE" == darwin* ]]; then
    export MISE_CACHE_DIR="${MISE_CACHE_DIR:-$mise_home/Library/Caches/mise}"
  else
    export MISE_CACHE_DIR="${MISE_CACHE_DIR:-$mise_home/.cache/mise}"
  fi
}

zsh_mise_prepare() {
  zsh_mise_check || return 1

  zsh_path_prepend "$MISE_DATA_DIR/shims"

  local completions_dir="$MISE_DATA_DIR/completions/${dotfiles_shell:-zsh}"
  if [[ -d "$completions_dir" ]]; then
    zsh_fpath_prepend "$completions_dir"
  fi
}

zsh_mise_prepare || return 0
