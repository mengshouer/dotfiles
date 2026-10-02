# Early optional pixi global PATH integration, before zimfw/compinit.

zsh_pixi_prepare() {
  local home="${dotfiles_home:-$HOME}"
  if (( EUID == 0 )); then
    home=~root
    # Keep inherited user-writable paths out of root's optional tool layer.
    case "${PIXI_HOME:-}" in
      [!/]*|/home|/home/*|/Users|/Users/*|/tmp|/tmp/*|/var/tmp|/var/tmp/*|/opt/homebrew|/opt/homebrew/*)
        unset PIXI_HOME ;;
    esac
  fi

  local home_dir="${PIXI_HOME:-$home/.pixi}"
  [[ -x "$home_dir/bin/pixi" ]] || return 1
  export PIXI_HOME="$home_dir"
}

# Only package completions live here; this does not generate Pixi CLI completion.
() {
  zsh_pixi_prepare || return 0
  zsh_path_prepend "$PIXI_HOME/bin"

  local completions_dir="$PIXI_HOME/completions/zsh"
  if [[ -d "$completions_dir" ]]; then
    fpath=("$completions_dir" "${(@)fpath:#$completions_dir}")
  fi
}
