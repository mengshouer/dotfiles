# PATH setup and runtime package manager detection.

typeset -U path PATH

zsh_path_prepend "$HOME/.local/bin"
[[ -n "${XDG_BIN_HOME:-}" ]] && zsh_path_prepend "$XDG_BIN_HOME"
[[ -n "${DOTFILES_BOOTSTRAP_BIN_DIR:-}" ]] && zsh_path_prepend "$DOTFILES_BOOTSTRAP_BIN_DIR"

for brew_bin in \
  "/opt/homebrew/bin/brew" \
  "/usr/local/bin/brew" \
  "/home/linuxbrew/.linuxbrew/bin/brew"
do
  if [[ -x "$brew_bin" ]]; then
    eval "$("$brew_bin" shellenv)"
    break
  fi
done

unset brew_bin
export PATH
