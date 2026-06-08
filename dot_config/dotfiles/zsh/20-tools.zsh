# Terminal tool initialization.

if [[ -z "${STARSHIP_SESSION_KEY:-}" ]]; then
  zsh_optional_eval starship init zsh
fi

zsh_defer_or_run zsh_optional_eval zoxide init zsh
zsh_defer_or_run zsh_optional_eval fzf --zsh
