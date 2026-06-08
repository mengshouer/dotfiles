# Shared zsh helpers and basic interactive options.

setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS
setopt SHARE_HISTORY

HISTSIZE="${HISTSIZE:-10000}"
SAVEHIST="${SAVEHIST:-10000}"

bindkey -e
WORDCHARS=${WORDCHARS//[\/]}

if (( $+functions[history-substring-search-up] )); then
  zmodload -F zsh/terminfo +p:terminfo 2>/dev/null || true

  for key in '^[[A' '^P' "${terminfo[kcuu1]}"; do
    [[ -n "$key" ]] && bindkey "$key" history-substring-search-up
  done

  for key in '^[[B' '^N' "${terminfo[kcud1]}"; do
    [[ -n "$key" ]] && bindkey "$key" history-substring-search-down
  done

  unset key
fi

zsh_path_prepend() {
  [[ -d "$1" ]] || return 0
  path=("$1" "${path[@]:#$1}")
  typeset -U path PATH
}

zsh_defer_or_run() {
  if (( $+functions[zsh-defer] )); then
    zsh-defer "$@"
  else
    "$@"
  fi
}

zsh_optional_eval() {
  local init_script

  init_script="$("$@" 2>/dev/null)" || return 0
  [[ -n "$init_script" ]] && eval "$init_script"
}

zsh_filter_path_patterns() {
  local entry pattern
  local -a filtered patterns

  patterns=("$@")
  for entry in "${path[@]}"; do
    for pattern in "${patterns[@]}"; do
      case "$entry" in
        $pattern) continue 2 ;;
      esac
    done
    filtered+=("$entry")
  done

  path=("${filtered[@]}")
  typeset -U path PATH
}
