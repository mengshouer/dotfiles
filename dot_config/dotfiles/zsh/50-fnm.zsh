# Optional fnm initialization.

zsh_init_fnm() {
  local fnm_dir fnm_home

  fnm_home="$HOME"
  (( EUID == 0 )) && fnm_home=~root

  if [[ "$OSTYPE" == darwin* ]]; then
    fnm_dir="${FNM_DIR:-${XDG_DATA_HOME:-$fnm_home/.local/share}/fnm}"
    if [[ "$fnm_dir" == *[[:space:]]* ]]; then
      print -u2 -- "Skipping fnm: FNM_DIR must not contain whitespace: $fnm_dir"
      return 0
    fi
    export FNM_DIR="$fnm_dir"
  elif (( ! ${+commands[fnm]} )); then
    fnm_dir="${XDG_DATA_HOME:-$fnm_home/.local/share}/fnm"
    [[ -d "$fnm_dir" ]] && zsh_path_prepend "$fnm_dir"
  fi

  (( ${+commands[fnm]} )) || return 0

  if [[ -z "${XDG_RUNTIME_DIR:-}" || ! -d "$XDG_RUNTIME_DIR" || ! -w "$XDG_RUNTIME_DIR" ]]; then
    export XDG_RUNTIME_DIR="/tmp"
  fi

  zsh_optional_eval fnm env --use-on-cd --shell zsh
}

zsh_defer_or_run zsh_init_fnm
