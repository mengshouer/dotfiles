# Terminal tool initialization.

zsh_source_cached_tool_init() {
  local tool_name="$1"
  shift

  local bin_path="${commands[$tool_name]:-}"
  [[ -n "$bin_path" ]] || return 0

  local home_dir="$HOME"
  (( EUID == 0 )) && home_dir=~root

  local real_bin_path="${bin_path:A}"
  local bin_sig="$real_bin_path"
  if zmodload -F zsh/stat b:zstat 2>/dev/null; then
    local -A bin_stat
    if zstat -H bin_stat -- "$real_bin_path" 2>/dev/null; then
      bin_sig="${real_bin_path}|${bin_stat[mtime]:-0}:${bin_stat[size]:-0}"
    fi
  fi

  local config_dir="${XDG_CONFIG_HOME:-$home_dir/.config}/dotfiles"
  local cache_dir="${ZSH_CACHE_DIR:-${XDG_CACHE_HOME:-$home_dir/.cache}/zsh}"
  local cache_file="$cache_dir/${tool_name}-init.zsh"
  local local_env_file="$config_dir/local.env"
  local local_zsh_file="$config_dir/local.zsh"
  local tools_script_file="$config_dir/zsh/20-tools.zsh"
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
    [[ -f "$local_zsh_file" && "$local_zsh_file" -nt "$cache_file" ]] && needs_refresh=1
    [[ -f "$tools_script_file" && "$tools_script_file" -nt "$cache_file" ]] && needs_refresh=1
  fi

  if (( needs_refresh )); then
    local init_script
    init_script="$("$bin_path" "$@" 2>/dev/null)" || return 0
    [[ -n "$init_script" ]] || return 0

    [[ -d "$cache_dir" ]] || command mkdir -p "$cache_dir" 2>/dev/null || true
    local tmp_file="$cache_file.$$.tmp"
    if {
      print -r -- "$expected_header"
      print -r -- "$init_script"
    } >| "$tmp_file" 2>/dev/null && command mv -f "$tmp_file" "$cache_file" 2>/dev/null; then
      zcompile -UR "$cache_file" 2>/dev/null || true
    else
      command rm -f "$tmp_file" 2>/dev/null || true
      eval "$init_script"
      return 0
    fi
  fi

  source "$cache_file"
}

if (( ! $+functions[prompt_starship_precmd] )); then
  zsh_optional_eval starship init zsh
fi

zsh_defer_or_run zsh_source_cached_tool_init zoxide init zsh
zsh_defer_or_run zsh_source_cached_tool_init fzf --zsh
