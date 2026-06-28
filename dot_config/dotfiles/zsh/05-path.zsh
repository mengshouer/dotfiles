# PATH setup and runtime package manager detection.

typeset -U path PATH

if (( EUID == 0 )); then
  root_home="${dotfiles_home:-}"
  if [[ -z "$root_home" ]]; then
    root_home=~root
  fi

  path=("${path[@]:#/home/*}")
  path=("${path[@]:#/Users/*}")
  path=("${path[@]:#/opt/homebrew/bin}")
  path=("${path[@]:#/opt/homebrew/sbin}")
  if [[ "$OSTYPE" == darwin* ]]; then
    path=("${path[@]:#/usr/local/bin}")
    path=("${path[@]:#/usr/local/sbin}")
  fi

  zsh_path_prepend "$root_home/bin"
  zsh_path_prepend "$root_home/.local/bin"
  unset root_home
else
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
fi

export PATH
