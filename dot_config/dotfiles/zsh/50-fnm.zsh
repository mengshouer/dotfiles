# Optional fnm initialization.

zsh_init_fnm() {
  if (( ! ${+commands[fnm]} )); then
    local fnm_dir
    if [[ "$OSTYPE" == darwin* ]]; then
      fnm_dir="${XDG_DATA_HOME:-$HOME/Library/Application Support}/fnm"
    else
      fnm_dir="${XDG_DATA_HOME:-$HOME/.local/share}/fnm"
    fi
    [[ -d "$fnm_dir" ]] && zsh_path_prepend "$fnm_dir"
    (( ${+commands[fnm]} )) || return 0
  fi

  if [[ -z "${XDG_RUNTIME_DIR:-}" || ! -d "$XDG_RUNTIME_DIR" || ! -w "$XDG_RUNTIME_DIR" ]]; then
    export XDG_RUNTIME_DIR="/tmp"
  fi

  zsh_optional_eval fnm env --use-on-cd --shell zsh
}

zsh_defer_or_run zsh_init_fnm

