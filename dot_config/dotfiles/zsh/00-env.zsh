# Shared zsh helpers and basic interactive options.

setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS
setopt SHARE_HISTORY

HISTSIZE="${HISTSIZE:-10000}"
SAVEHIST="${SAVEHIST:-10000}"

bindkey -e
WORDCHARS=${WORDCHARS//[\/]}

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
        ${~pattern}) continue 2 ;;
      esac
    done
    filtered+=("$entry")
  done

  path=("${filtered[@]}")
  typeset -gU path PATH
}
