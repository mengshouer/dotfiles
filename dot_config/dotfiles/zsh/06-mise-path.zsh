# Early optional mise PATH integration, before zimfw/compinit.
# Uses mise's official per-user layout: the binary lives in ~/.local/bin and
# installs/shims live under ~/.local/share/mise, inside the current user's HOME.

zsh_mise_prepare() {
  [[ -x "$HOME/.local/bin/mise" ]] || return 1

  zsh_path_prepend "$HOME/.local/share/mise/shims"

  local completions_dir="$HOME/.local/share/mise/completions/zsh"
  if [[ -d "$completions_dir" ]]; then
    fpath=("$completions_dir" "${(@)fpath:#$completions_dir}")
  fi
}

zsh_mise_prepare || return 0
