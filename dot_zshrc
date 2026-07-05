# zsh entry point managed by chezmoi.

[[ $- == *i* ]] || return 0

if (( EUID == 0 )); then
  dotfiles_home=~root
  # Drop env vars leaked from a normal user's session; keep root's own values.
  for dotfiles_env_var in DOTFILES_BOOTSTRAP_BIN_DIR XDG_BIN_HOME XDG_CACHE_HOME XDG_CONFIG_HOME XDG_DATA_HOME ZDOTDIR ZIM_CONFIG_FILE; do
    case "${(P)dotfiles_env_var}" in
      /home/*|/Users/*) unset "$dotfiles_env_var" ;;
    esac
  done
  unset dotfiles_env_var
else
  dotfiles_home="$HOME"
fi
dotfiles_config_home="${XDG_CONFIG_HOME:-$dotfiles_home/.config}"
dotfiles_cache_home="${XDG_CACHE_HOME:-$dotfiles_home/.cache}"

dotfiles_load_env_file() {
  local env_file="$1"
  local line key value

  [[ -f "$env_file" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    [[ "$key" == "$line" ]] && continue
    [[ "$key" =~ '^[A-Za-z_][A-Za-z0-9_]*$' ]] || continue
    export "$key=$value"
  done < "$env_file"
}

# XDG_* exported from local.env do not affect the dotfiles paths resolved above.
dotfiles_load_env_file "$dotfiles_config_home/dotfiles/local.env"

dotfiles_zsh_dir="$dotfiles_config_home/dotfiles/zsh"
dotfiles_zsh_early_path_file="$dotfiles_zsh_dir/05-path.zsh"

zsh_path_prepend() {
  [[ -d "$1" ]] || return 0
  path=("$1" "${path[@]:#$1}")
  typeset -U path PATH
}

# Prompt modules need tool paths before zimfw sources modules.
[[ -f "$dotfiles_zsh_early_path_file" ]] && source "$dotfiles_zsh_early_path_file"

# Module configuration that must exist before zimfw sources modules.
ZSH_AUTOSUGGEST_MANUAL_REBIND=1
ZSH_AUTOSUGGEST_USE_ASYNC=1
ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets)

ZIM_HOME="${ZDOTDIR:-$dotfiles_home}/.zim"
ZSH_CACHE_DIR="$dotfiles_cache_home/zsh"
[[ -d "$ZSH_CACHE_DIR" ]] || command mkdir -p "$ZSH_CACHE_DIR"
zstyle ':zim:completion' dumpfile "$ZSH_CACHE_DIR/.zcompdump"

zimrc_file="${ZIM_CONFIG_FILE:-${ZDOTDIR:-$dotfiles_home}/.zimrc}"
zimfw_file="$ZIM_HOME/zimfw.zsh"
zim_init_file="$ZIM_HOME/init.zsh"

if [[ -f "$zimfw_file" ]]; then
  if [[ ! "$zim_init_file" -nt "$zimrc_file" ]]; then
    source "$zimfw_file" init
  fi

  [[ -f "$zim_init_file" ]] && source "$zim_init_file"
fi

if [[ -d "$dotfiles_zsh_dir" ]]; then
  for dotfiles_zsh_file in "$dotfiles_zsh_dir"/[0-9][0-9]-*.zsh; do
    [[ "$dotfiles_zsh_file" == "$dotfiles_zsh_early_path_file" ]] && continue
    [[ -f "$dotfiles_zsh_file" ]] && source "$dotfiles_zsh_file"
  done
fi

unset dotfiles_cache_home dotfiles_config_home dotfiles_home dotfiles_zsh_early_path_file dotfiles_zsh_file dotfiles_zsh_dir zim_init_file zimfw_file zimrc_file
unfunction dotfiles_load_env_file
