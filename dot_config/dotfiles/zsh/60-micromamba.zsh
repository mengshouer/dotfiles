# Opt-in Micromamba integration; enabled only by `bootstrap micromamba`.

zsh_micromamba_prepare() {
  [[ "$OSTYPE" == linux* && $- == *i* ]] || return 1

  dotfiles_micromamba_home="${dotfiles_micromamba_home:-${dotfiles_home:-$HOME}}"
  dotfiles_micromamba_root_prefix="${dotfiles_micromamba_root_prefix:-$dotfiles_micromamba_home/.local/share/mamba}"
  dotfiles_micromamba_executable="${dotfiles_micromamba_executable:-$dotfiles_micromamba_home/.local/bin/micromamba}"

  [[ -f "$dotfiles_micromamba_root_prefix/.dotfiles-enabled" ]] || return 1
  [[ -x "$dotfiles_micromamba_executable" &&
    -f "$dotfiles_micromamba_root_prefix/conda-meta/history" ]] || return 1

  export MAMBA_EXE="$dotfiles_micromamba_executable"
  export MAMBA_ROOT_PREFIX="$dotfiles_micromamba_root_prefix"
  return 0
}

zsh_micromamba_alias_if_free() {
  local name="$1" body="$2"

  (( ${+aliases[$name]} || ${+functions[$name]} || ${+commands[$name]} )) && return 0
  alias "$name=$body"
}

zsh_micromamba_aliases() {
  zsh_micromamba_alias_if_free mm '"$MAMBA_EXE"'
  zsh_micromamba_alias_if_free mmi '"$MAMBA_EXE" install -p "$MAMBA_ROOT_PREFIX"'
}

zsh_micromamba_path() {
  zsh_micromamba_prepare || return 1

  # Never put this base ahead of an explicitly active environment from another
  # Conda installation.
  [[ -z "${CONDA_PREFIX:-}" || "$CONDA_PREFIX" == "$dotfiles_micromamba_root_prefix" ]] || return 1
  zsh_path_prepend "$dotfiles_micromamba_root_prefix/bin"
  zsh_path_prepend "$dotfiles_micromamba_home/.local/bin"
  return 0
}

zsh_activate_micromamba() {
  local manual=0 activation
  [[ "${1:-}" == --manual ]] && manual=1

  zsh_micromamba_prepare || return 0
  if [[ -n "${CONDA_PREFIX:-}" &&
        "$CONDA_PREFIX" != "$dotfiles_micromamba_root_prefix" ]]; then
    (( manual )) && print -u2 -- "Micromamba base activation skipped: another Conda environment is active: $CONDA_PREFIX"
    return $manual
  fi

  zsh_path_prepend "$dotfiles_micromamba_root_prefix/bin"
  zsh_path_prepend "$dotfiles_micromamba_home/.local/bin"
  [[ "${CONDA_PREFIX:-}" == "$dotfiles_micromamba_root_prefix" ]] && return 0

  if ! activation="$("$dotfiles_micromamba_executable" shell activate \
      --shell zsh --prefix "$dotfiles_micromamba_root_prefix" 2>/dev/null)"; then
    print -u2 -- "Micromamba base activation failed; PATH remains available."
    return 0
  fi
  if ! eval "$activation"; then
    print -u2 -- "Micromamba base activation script failed; PATH remains available."
  fi
}

# Load the full hook only when interactive environment switching is requested.
mm-hook() {
  zsh_micromamba_prepare || return 1

  local hook
  if ! hook="$("$dotfiles_micromamba_executable" shell hook \
      --shell zsh --root-prefix "$dotfiles_micromamba_root_prefix" 2>/dev/null)"; then
    print -u2 -- "Micromamba shell hook failed."
    return 1
  fi
  eval "$hook"
}

# Complete activation is available immediately for commands that cannot wait for
# zsh-defer, while ordinary startup only pays the PATH setup cost.
mm-activate() {
  zsh_activate_micromamba --manual
}

if zsh_micromamba_prepare; then
  zsh_micromamba_aliases
  if zsh_micromamba_path; then
    if (( $+functions[zsh-defer] )); then
      # Keep activation diagnostics visible; zsh-defer otherwise hides output.
      zsh-defer -12 zsh_activate_micromamba
    else
      zsh_activate_micromamba
    fi
  fi
fi
