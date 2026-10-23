# Platform-specific runtime behavior.

dotfiles_is_wsl() {
  if [[ -z "${__dotfiles_is_wsl:-}" ]]; then
    if [[ -n "${WSL_DISTRO_NAME:-}" || -e /proc/sys/fs/binfmt_misc/WSLInterop || -e /run/WSL ]]; then
      __dotfiles_is_wsl=1
    elif [[ -r /proc/version ]]; then
      local proc_version=""
      IFS= read -r proc_version < /proc/version 2>/dev/null || proc_version=""
      case "$proc_version" in
        *[Mm]icrosoft*|*WSL*) __dotfiles_is_wsl=1 ;;
        *) __dotfiles_is_wsl=0 ;;
      esac
    else
      __dotfiles_is_wsl=0
    fi
  fi
  (( __dotfiles_is_wsl ))
}

if dotfiles_is_wsl; then
  command -v wslview >/dev/null 2>&1 && export BROWSER=wslview

  zsh_filter_path_patterns \
    "*/Scoop/apps/nodejs*" \
    "*/AppData/Roaming/npm*" \
    "*/.nvm/*" \
    "*/fnm_multishells/*"
fi
