# Optional fnm initialization (fast default PATH + on-demand multishell).

zsh_fnm_has_version_file() {
  local dir="${1:-$PWD}"
  [[ -n "$dir" ]] || return 1

  local parent pkg_json line
  while true; do
    if [[ -f "$dir/.nvmrc" || -f "$dir/.node-version" ]]; then
      return 0
    fi

    pkg_json="$dir/package.json"
    if [[ -f "$pkg_json" && -r "$pkg_json" ]]; then
      while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" == *'"engines"'* ]] && return 0
      done < "$pkg_json"
    fi

    parent="${dir:h}"
    [[ -z "$parent" || "$parent" == "$dir" ]] && break
    dir="$parent"
  done

  return 1
}

zsh_init_fnm() {
  (( ${__dotfiles_fnm_initialized:-0} )) && return 0
  typeset -g __dotfiles_fnm_initialized=1

  unfunction fnm 2>/dev/null || true
  if (( $+functions[add-zsh-hook] )); then
    add-zsh-hook -D chpwd _dotfiles_fnm_lazy_chpwd 2>/dev/null || true
  fi
  unfunction _dotfiles_fnm_lazy_chpwd 2>/dev/null || true

  if [[ -n "${__dotfiles_fnm_default_bin:-}" ]]; then
    path=("${path[@]:#$__dotfiles_fnm_default_bin}")
    typeset -gU path PATH
  fi

  if [[ -z "${XDG_RUNTIME_DIR:-}" || ! -d "$XDG_RUNTIME_DIR" || ! -w "$XDG_RUNTIME_DIR" ]]; then
    local fnm_home="$HOME"
    (( EUID == 0 )) && fnm_home=~root
    local fallback_runtime_dir="${XDG_CACHE_HOME:-$fnm_home/.cache}/fnm-runtime"
    command mkdir -p -m 0700 "$fallback_runtime_dir" 2>/dev/null || return 0
    export XDG_RUNTIME_DIR="$fallback_runtime_dir"
  fi

  zsh_optional_eval command fnm env --use-on-cd --shell zsh

  if (( $+functions[_fnm_autoload_hook] )); then
    _fnm_autoload_hook() {
      if zsh_fnm_has_version_file "$PWD"; then
        FNM_VERSION_FILE_STRATEGY=recursive command fnm use --silent-if-unchanged
      fi
    }
  fi
}

_dotfiles_fnm_lazy_chpwd() {
  [[ "$PWD" == "${__dotfiles_fnm_last_dir:-}" ]] && return 0
  typeset -g __dotfiles_fnm_last_dir="$PWD"

  if zsh_fnm_has_version_file "$PWD"; then
    zsh_init_fnm
    if (( $+functions[_fnm_autoload_hook] )); then
      _fnm_autoload_hook
    else
      FNM_VERSION_FILE_STRATEGY=recursive command fnm use --silent-if-unchanged
    fi
  fi
}

zsh_setup_fnm() {
  local fnm_dir fnm_home default_alias_bin

  fnm_home="$HOME"
  (( EUID == 0 )) && fnm_home=~root

  fnm_dir="${FNM_DIR:-${XDG_DATA_HOME:-$fnm_home/.local/share}/fnm}"
  if [[ "$OSTYPE" == darwin* ]]; then
    if [[ "$fnm_dir" == *[[:space:]]* ]]; then
      print -u2 -- "Skipping fnm: FNM_DIR must not contain whitespace: $fnm_dir"
      return 0
    fi
    export FNM_DIR="$fnm_dir"
  else
    if [[ -z "${FNM_DIR:-}" && ! -d "$fnm_dir" && -d "$fnm_home/.fnm" ]]; then
      fnm_dir="$fnm_home/.fnm"
    fi
    if (( ! ${+commands[fnm]} )); then
      [[ -d "$fnm_dir" ]] && zsh_path_prepend "$fnm_dir"
    fi
  fi

  (( ${+commands[fnm]} )) || return 0
  [[ -z "${FNM_DIR:-}" && -d "$fnm_dir" ]] && export FNM_DIR="$fnm_dir"

  # Drop inherited multishell state before setting up this shell.
  unset FNM_MULTISHELL_PATH
  zsh_filter_path_patterns "*/fnm_multishells/*"
  autoload -Uz add-zsh-hook
  add-zsh-hook -D chpwd _fnm_autoload_hook 2>/dev/null || true
  unfunction _fnm_autoload_hook 2>/dev/null || true

  typeset -g __dotfiles_fnm_initialized=0
  typeset -g __dotfiles_fnm_last_dir=""
  typeset -g __dotfiles_fnm_default_bin=""

  default_alias_bin="$fnm_dir/aliases/default/bin"
  if [[ -d "$default_alias_bin" ]]; then
    typeset -g __dotfiles_fnm_default_bin="$default_alias_bin"
    zsh_path_prepend "$default_alias_bin"

    fnm() {
      zsh_init_fnm
      command fnm "$@"
    }

    add-zsh-hook -D chpwd _dotfiles_fnm_lazy_chpwd
    add-zsh-hook chpwd _dotfiles_fnm_lazy_chpwd
    zsh_defer_or_run _dotfiles_fnm_lazy_chpwd
  else
    zsh_defer_or_run zsh_init_fnm
  fi
}

zsh_setup_fnm
unfunction zsh_setup_fnm
