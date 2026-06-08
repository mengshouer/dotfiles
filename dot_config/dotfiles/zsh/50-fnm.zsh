# Optional fnm initialization.

zsh_init_fnm() {
  (( ${+commands[fnm]} )) || return 0

  if [[ -z "${XDG_RUNTIME_DIR:-}" || ! -d "$XDG_RUNTIME_DIR" || ! -w "$XDG_RUNTIME_DIR" ]]; then
    export XDG_RUNTIME_DIR="/tmp"
  fi

  zsh_optional_eval fnm env --use-on-cd --shell zsh
}

zsh_defer_or_run zsh_init_fnm
