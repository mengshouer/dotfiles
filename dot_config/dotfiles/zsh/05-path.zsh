# PATH setup and runtime package manager detection.

typeset -U path PATH

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

# User-local paths prepend AFTER brew so they take priority.
zsh_path_prepend "$HOME/.local/bin"
[[ -n "${XDG_BIN_HOME:-}" ]] && zsh_path_prepend "$XDG_BIN_HOME"
[[ -n "${DOTFILES_BOOTSTRAP_BIN_DIR:-}" ]] && zsh_path_prepend "$DOTFILES_BOOTSTRAP_BIN_DIR"

export PATH

