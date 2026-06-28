# Optional fnm initialization.

zsh_init_fnm() {
  if (( ! ${+commands[fnm]} )); then
    local fnm_dir fnm_home

    fnm_home="${dotfiles_home:-$HOME}"
    if (( EUID == 0 && ! ${+dotfiles_home} )); then
      fnm_home=~root
    fi

    if (( EUID == 0 )); then
      case "$OSTYPE" in
        darwin*) fnm_dir="$fnm_home/Library/Application Support/fnm" ;;
        *)       fnm_dir="$fnm_home/.local/share/fnm" ;;
      esac
    elif [[ "$OSTYPE" == darwin* ]]; then
      fnm_dir="${XDG_DATA_HOME:-$fnm_home/Library/Application Support}/fnm"
    else
      fnm_dir="${XDG_DATA_HOME:-$fnm_home/.local/share}/fnm"
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
