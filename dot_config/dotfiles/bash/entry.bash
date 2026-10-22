# bash entry point managed by chezmoi.

[[ $- == *i* ]] || return 0
if [[ -z "${BASH_VERSINFO[0]:-}" ]] ||
   (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 2) )); then
  return 0
fi
# shellcheck disable=SC2034
dotfiles_shell="bash"

if (( EUID == 0 )); then
  dotfiles_home=~root
  HOME="$dotfiles_home"
  export HOME
  # Drop env vars leaked from a normal user's session or pointing to unsafe
  # locations; keep root's own values.
  for dotfiles_env_var in DOTFILES_BOOTSTRAP_BIN_DIR XDG_BIN_HOME XDG_CACHE_HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_RUNTIME_DIR ZDOTDIR ZIM_CONFIG_FILE MISE_HOME MISE_CONFIG_DIR MISE_DATA_DIR MISE_CACHE_DIR MISE_STATE_DIR MISE_TMP_DIR MISE_DOWNLOADS_DIR MISE_SHIMS_DIR MISE_RUSTUP_HOME MISE_CARGO_HOME; do
    case "${!dotfiles_env_var:-}" in
      "") ;;
      [!/]*|/home|/home/*|/Users|/Users/*|/tmp|/tmp/*|/var/tmp|/var/tmp/*|/run/user/[!0]*)
        unset "$dotfiles_env_var"
        ;;
    esac
  done
  unset dotfiles_env_var
else
  dotfiles_home="$HOME"
fi
dotfiles_config_home="${XDG_CONFIG_HOME:-$dotfiles_home/.config}"

dotfiles_load_env_file() {
  local env_file="$1"
  local line key value

  [[ -f "$env_file" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue

    if [[ "$line" == export[[:space:]]* ]]; then
      line="${line#export}"
      line="${line#"${line%%[![:space:]]*}"}"
    fi

    [[ "$line" == *=* ]] || continue
    key="${line%%=*}"
    value="${line#*=}"

    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    if (( ${#value} >= 2 )); then
      if [[ "$value" == \"*\" ]]; then
        value="${value#\"}"
        value="${value%\"}"
      elif [[ "$value" == \'*\' ]]; then
        value="${value#\'}"
        value="${value%\'}"
      fi
    fi

    export "$key=$value"
  done < "$env_file"
}

# XDG_* exported from local.env do not affect the dotfiles paths resolved above.
dotfiles_load_env_file "$dotfiles_config_home/dotfiles/local.env"

# Closest bash match for the zsh history options in 00-env.zsh. `erasedups`
# would map HIST_IGNORE_ALL_DUPS, but it duplicates entries once the history file
# is shared between shells, so keep the conservative pair on purpose.
HISTCONTROL=ignoreboth
HISTSIZE="${HISTSIZE:-10000}"
HISTFILESIZE="${HISTFILESIZE:-10000}"
shopt -s histappend checkwinsize
set -o emacs

# Zsh-compatible hooks so shared modules under dot_config/dotfiles/zsh/ can be
# sourced directly without duplicating business logic. These stay defined after
# startup on purpose: 60-mise.zsh (and local.bash overrides) call print/rehash/
# zsh_* at runtime, so they are the compatibility layer, not leftovers.
setopt() {
  :
}

print() {
  local to_stderr=0
  while (( $# > 0 )); do
    case "$1" in
      -r) shift ;;
      -u2) to_stderr=1; shift ;;
      --) shift; break ;;
      *) break ;;
    esac
  done
  if (( to_stderr )); then
    printf '%s\n' "$*" >&2
  else
    printf '%s\n' "$*"
  fi
}

rehash() {
  hash -r
}

unfunction() {
  unset -f "$@" 2>/dev/null || true
}

zsh_confirm() {
  local reply
  builtin read -r -n 1 -p "$1" reply && [[ "$reply" == [yY] ]]
}

zsh_fpath_prepend() {
  # bash has no completion fpath: source the generated completion script instead.
  # shellcheck disable=SC1091
  [[ -s "$1/_mise" ]] && source "$1/_mise"
}

zsh_defer_or_run() {
  "$@"
}

zsh_optional_eval() {
  local init_script
  init_script="$("$@" 2>/dev/null)" || return 0
  [[ -n "$init_script" ]] && eval "$init_script"
}

dotfiles_dedup_path() {
  local entry new_path="" old_ifs="$IFS"
  IFS=:
  for entry in $PATH; do
    [[ -n "$entry" ]] || continue
    case ":$new_path:" in
      *":$entry:"*) ;;
      *) new_path="${new_path:+$new_path:}$entry" ;;
    esac
  done
  IFS="$old_ifs"
  PATH="$new_path"
  export PATH
}

zsh_path_prepend() {
  local dir="$1"
  [[ -n "$dir" && -d "$dir" ]] || return 0
  local entry new_path="$dir" old_ifs="$IFS"
  IFS=:
  for entry in $PATH; do
    [[ -n "$entry" && "$entry" != "$dir" ]] || continue
    case ":$new_path:" in
      *":$entry:"*) ;;
      *) new_path="$new_path:$entry" ;;
    esac
  done
  IFS="$old_ifs"
  PATH="$new_path"
  export PATH
}

zsh_filter_path_patterns() {
  local entry pattern new_path="" old_ifs="$IFS"
  (($#)) || return 0
  IFS=:
  for entry in $PATH; do
    [[ -n "$entry" ]] || continue
    for pattern in "$@"; do
      # shellcheck disable=SC2254
      case "$entry" in
        $pattern) continue 2 ;;
      esac
    done
    case ":$new_path:" in
      *":$entry:"*) ;;
      *) new_path="${new_path:+$new_path:}$entry" ;;
    esac
  done
  IFS="$old_ifs"
  PATH="$new_path"
  export PATH
}

dotfiles_zsh_dir="$dotfiles_config_home/dotfiles/zsh"

# Early PATH & mise setup (shared directly with zsh).
dotfiles_dedup_path
# shellcheck disable=SC1091
[[ -f "$dotfiles_zsh_dir/05-path.zsh" ]] && source "$dotfiles_zsh_dir/05-path.zsh"
# shellcheck disable=SC1091
[[ -f "$dotfiles_zsh_dir/06-mise-path.zsh" ]] && source "$dotfiles_zsh_dir/06-mise-path.zsh"
# zsh keeps PATH deduplicated through `typeset -U path PATH`; rebuild once after
# the shared PATH modules so duplicates pulled in by `brew shellenv` cannot
# survive when the following prepends find nothing to do.
dotfiles_dedup_path

# Load bash-completion if not already loaded.
if ! shopt -oq posix && [[ -z "${BASH_COMPLETION_VERSINFO:-}" ]]; then
  for bash_comp_file in \
    "/usr/share/bash-completion/bash_completion" \
    "/etc/bash_completion" \
    "/opt/homebrew/etc/profile.d/bash_completion.sh" \
    "/usr/local/etc/profile.d/bash_completion.sh" \
    "/home/linuxbrew/.linuxbrew/etc/profile.d/bash_completion.sh"
  do
    if [[ -r "$bash_comp_file" ]]; then
      # shellcheck disable=SC1090
      source "$bash_comp_file"
      break
    fi
  done
  unset bash_comp_file
fi

# Degraded fnm setup (default alias on PATH + lazy init on first `fnm` call).
bash_setup_fnm() {
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
    if ! command -v fnm >/dev/null 2>&1; then
      [[ -d "$fnm_dir" ]] && zsh_path_prepend "$fnm_dir"
    fi
  fi

  command -v fnm >/dev/null 2>&1 || return 0
  [[ -z "${FNM_DIR:-}" && -d "$fnm_dir" ]] && export FNM_DIR="$fnm_dir"

  unset FNM_MULTISHELL_PATH
  zsh_filter_path_patterns "*/fnm_multishells/*"

  default_alias_bin="$fnm_dir/aliases/default/bin"
  if [[ -d "$default_alias_bin" ]]; then
    __dotfiles_fnm_default_bin="$default_alias_bin"
    zsh_path_prepend "$default_alias_bin"

    fnm() {
      unset -f fnm 2>/dev/null || true
      if [[ -n "${__dotfiles_fnm_default_bin:-}" ]]; then
        zsh_filter_path_patterns "$__dotfiles_fnm_default_bin"
        unset __dotfiles_fnm_default_bin
      fi
      if [[ -z "${XDG_RUNTIME_DIR:-}" || ! -d "$XDG_RUNTIME_DIR" || ! -w "$XDG_RUNTIME_DIR" ]]; then
        local fnm_rt_home="$HOME"
        (( EUID == 0 )) && fnm_rt_home=~root
        local fallback_runtime_dir="${XDG_CACHE_HOME:-$fnm_rt_home/.cache}/fnm-runtime"
        if command mkdir -p -m 0700 "$fallback_runtime_dir" 2>/dev/null; then
          export XDG_RUNTIME_DIR="$fallback_runtime_dir"
        fi
      fi
      if [[ -n "${XDG_RUNTIME_DIR:-}" && -d "$XDG_RUNTIME_DIR" && -w "$XDG_RUNTIME_DIR" ]]; then
        zsh_optional_eval command fnm env --shell bash
      fi
      command fnm "$@"
    }
  else
    if [[ -z "${XDG_RUNTIME_DIR:-}" || ! -d "$XDG_RUNTIME_DIR" || ! -w "$XDG_RUNTIME_DIR" ]]; then
      local fallback_runtime_dir="${XDG_CACHE_HOME:-$fnm_home/.cache}/fnm-runtime"
      if command mkdir -p -m 0700 "$fallback_runtime_dir" 2>/dev/null; then
        export XDG_RUNTIME_DIR="$fallback_runtime_dir"
      fi
    fi
    if [[ -n "${XDG_RUNTIME_DIR:-}" && -d "$XDG_RUNTIME_DIR" && -w "$XDG_RUNTIME_DIR" ]]; then
      zsh_optional_eval command fnm env --shell bash
    fi
  fi
}

# If re-sourcing ~/.bashrc in an active starship session, unwrap
# STARSHIP_PROMPT_COMMAND first so hooks are not duplicated or placed before
# starship_precmd (which would clobber $? before starship captures it).
if [[ -n "${STARSHIP_PROMPT_COMMAND:-}" && "${PROMPT_COMMAND:-}" == "starship_precmd" ]]; then
  PROMPT_COMMAND="$STARSHIP_PROMPT_COMMAND"
  unset STARSHIP_PROMPT_COMMAND
fi

# Source numbered modules from dot_config/dotfiles/zsh/ in order, skipping
# zsh-only leaf files (00-env, 20-tools, 50-fnm, 90-local) and early-loaded
# PATH files (05-path, 06-mise-path).
if [[ -d "$dotfiles_zsh_dir" ]]; then
  for dotfiles_zsh_file in "$dotfiles_zsh_dir"/[0-9][0-9]-*.zsh; do
    [[ -f "$dotfiles_zsh_file" ]] || continue
    case "${dotfiles_zsh_file##*/}" in
      00-env.zsh|05-path.zsh|06-mise-path.zsh|20-tools.zsh|90-local.zsh)
        continue
        ;;
      50-fnm.zsh)
        bash_setup_fnm
        continue
        ;;
    esac
    # shellcheck disable=SC1090
    source "$dotfiles_zsh_file"
  done
  unset dotfiles_zsh_file
fi
unset -f bash_setup_fnm

# Prompt hook for history persistence (installed before zoxide/starship so
# starship wraps PROMPT_COMMAND into STARSHIP_PROMPT_COMMAND without losing $?).
# `history -a` plus `history -n` approximates zsh's SHARE_HISTORY both ways.
dotfiles_bash_prompt_hook() {
  history -a
  history -n
}
case ";${PROMPT_COMMAND:-};" in
  *";dotfiles_bash_prompt_hook;"*) ;;
  *) PROMPT_COMMAND="dotfiles_bash_prompt_hook${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
esac

# Cached terminal tool initialization (zoxide, fzf, starship).
bash_source_cached_tool_init() {
  local tool_name="$1"
  shift

  local bin_path
  bin_path="$(type -P "$tool_name" 2>/dev/null)" || return 0
  [[ -n "$bin_path" ]] || return 0

  local home_dir="$HOME"
  (( EUID == 0 )) && home_dir=~root

  local real_bin_path="$bin_path"
  if command -v readlink >/dev/null 2>&1; then
    real_bin_path="$(command readlink -f "$bin_path" 2>/dev/null || printf '%s\n' "$bin_path")"
  fi

  local stat_sig=""
  if [[ "$OSTYPE" == darwin* ]]; then
    stat_sig="$(command stat -f '%m:%z' "$real_bin_path" 2>/dev/null || true)"
  else
    stat_sig="$(command stat -c '%Y:%s' "$real_bin_path" 2>/dev/null || true)"
  fi
  local bin_sig="${real_bin_path}${stat_sig:+|$stat_sig}"

  local config_dir="${XDG_CONFIG_HOME:-$home_dir/.config}/dotfiles"
  local cache_dir="${XDG_CACHE_HOME:-$home_dir/.cache}/bash"
  local cache_file="$cache_dir/${tool_name}-init.bash"
  local local_env_file="$config_dir/local.env"
  local local_bash_file="$config_dir/local.bash"
  local entry_script_file="$config_dir/bash/entry.bash"
  local expected_header="# DOTFILES_SOURCE_BINARY: $bin_sig"
  local needs_refresh=0

  if [[ ! -s "$cache_file" ]]; then
    needs_refresh=1
  else
    local first_line=""
    IFS= read -r first_line < "$cache_file" 2>/dev/null || first_line=""
    [[ "$first_line" == "$expected_header" ]] || needs_refresh=1
    [[ "$bin_path" -nt "$cache_file" || "$real_bin_path" -nt "$cache_file" ]] && needs_refresh=1
    [[ -f "$local_env_file" && "$local_env_file" -nt "$cache_file" ]] && needs_refresh=1
    [[ -f "$local_bash_file" && "$local_bash_file" -nt "$cache_file" ]] && needs_refresh=1
    [[ -f "$entry_script_file" && "$entry_script_file" -nt "$cache_file" ]] && needs_refresh=1
  fi

  if (( needs_refresh )); then
    local init_script
    init_script="$("$bin_path" "$@" 2>/dev/null)" || return 0
    [[ -n "$init_script" ]] || return 0

    [[ -d "$cache_dir" ]] || command mkdir -p "$cache_dir" 2>/dev/null || true
    local tmp_file="$cache_file.$$.tmp"
    if {
      printf '%s\n' "$expected_header"
      printf '%s\n' "$init_script"
    } >| "$tmp_file" 2>/dev/null && command mv -f "$tmp_file" "$cache_file" 2>/dev/null; then
      :
    else
      command rm -f "$tmp_file" 2>/dev/null || true
      eval "$init_script"
      return 0
    fi
  fi

  # shellcheck disable=SC1090
  source "$cache_file"
}

bash_source_cached_tool_init zoxide init bash
bash_source_cached_tool_init fzf --bash
if declare -F starship_precmd >/dev/null 2>&1; then
  dotfiles_saved_ps0="${PS0-}"
  bash_source_cached_tool_init starship init bash --print-full-init
  PS0="$dotfiles_saved_ps0"
  unset dotfiles_saved_ps0
else
  bash_source_cached_tool_init starship init bash --print-full-init
fi
unset STARSHIP_START_TIME

# Final local override. This file is intentionally ignored by git/chezmoi.
local_bash="$dotfiles_config_home/dotfiles/local.bash"
# shellcheck disable=SC1090
[[ -f "$local_bash" ]] && source "$local_bash"

unset dotfiles_config_home dotfiles_home dotfiles_zsh_dir local_bash
unset -f bash_source_cached_tool_init dotfiles_dedup_path dotfiles_load_env_file
