# Early optional Micromamba PATH integration.
# This file is sourced explicitly by entry.zsh after 05-path.zsh and before
# zimfw. It must remain a no-op when the fixed installation is absent.

: ${DOTFILES_MICROMAMBA_STATUS:=unknown}
typeset -ga DOTFILES_MICROMAMBA_PATH_ENTRIES

zsh_micromamba_prepare() {
  [[ "$DOTFILES_MICROMAMBA_STATUS" == ready ]] && return 0
  [[ "$DOTFILES_MICROMAMBA_STATUS" == unknown ]] || return 1

  local home="${dotfiles_home:-$HOME}"
  local executable="$home/.local/bin/micromamba"
  local root_prefix="$home/.local/share/mamba"

  if [[ -f "$executable" && -x "$executable" &&
        -f "$root_prefix/conda-meta/history" ]]; then
    dotfiles_micromamba_home="$home"
    dotfiles_micromamba_executable="$executable"
    dotfiles_micromamba_root_prefix="$root_prefix"
    export MAMBA_EXE="$executable"
    export MAMBA_ROOT_PREFIX="$root_prefix"
    DOTFILES_MICROMAMBA_STATUS=ready
    return 0
  fi

  DOTFILES_MICROMAMBA_STATUS=disabled
  return 1
}

zsh_micromamba_reassert_path() {
  zsh_micromamba_prepare || return 0
  if [[ -n "${CONDA_PREFIX:-}" &&
        "$CONDA_PREFIX" != "$MAMBA_ROOT_PREFIX" ]]; then
    return 0
  fi

  local i
  for (( i=${#DOTFILES_MICROMAMBA_PATH_ENTRIES}; i >= 1; i-- )); do
    zsh_path_prepend "${DOTFILES_MICROMAMBA_PATH_ENTRIES[i]}"
  done
  export PATH
}

zsh_micromamba_refresh_path() {
  zsh_micromamba_prepare || return 0

  local report=0
  [[ "${1:-}" == --report ]] && report=1
  if [[ -n "${CONDA_PREFIX:-}" &&
        "$CONDA_PREFIX" != "$MAMBA_ROOT_PREFIX" ]]; then
    (( report )) &&
      print -u2 -- "PATH refresh skipped: active environment is $CONDA_PREFIX"
    return 0
  fi

  setopt localoptions nullglob
  local entry env_dir i
  local -a original_path filtered env_bins desired
  original_path=("${path[@]}")
  for entry in "${path[@]}"; do
    case "$entry" in
      "$MAMBA_ROOT_PREFIX"/bin|"$MAMBA_ROOT_PREFIX"/envs/*/bin) ;;
      *) filtered+=("$entry") ;;
    esac
  done
  # Keep a usable fallback if an inherited PATH consisted only of mamba paths.
  (( ${#filtered[@]} )) || filtered=("${original_path[@]}")

  if [[ -d "$MAMBA_ROOT_PREFIX/envs" ]]; then
    for env_dir in "$MAMBA_ROOT_PREFIX"/envs/*; do
      [[ -d "$env_dir/bin" && -f "$env_dir/conda-meta/history" ]] || continue
      env_bins+=("$env_dir/bin")
    done
  fi
  env_bins=("${(@o)env_bins}")
  desired=("$MAMBA_ROOT_PREFIX/bin" "${env_bins[@]}")
  DOTFILES_MICROMAMBA_PATH_ENTRIES=("${desired[@]}")

  path=("${filtered[@]}")
  for (( i=${#DOTFILES_MICROMAMBA_PATH_ENTRIES}; i >= 1; i-- )); do
    zsh_path_prepend "${DOTFILES_MICROMAMBA_PATH_ENTRIES[i]}"
  done
  export PATH
}

if zsh_micromamba_prepare; then
  zsh_micromamba_refresh_path
fi
