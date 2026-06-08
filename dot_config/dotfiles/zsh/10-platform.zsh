# Platform-specific runtime behavior.

dotfiles_is_wsl() {
  [[ -r /proc/version ]] && grep -qi microsoft /proc/version
}

if dotfiles_is_wsl; then
  (( ${+commands[wslview]} )) && export BROWSER=wslview

  zsh_filter_path_patterns \
    "*/Scoop/apps/nodejs*" \
    "*/AppData/Roaming/npm*" \
    "*/.nvm/*" \
    "*/fnm_multishells/*"
fi
