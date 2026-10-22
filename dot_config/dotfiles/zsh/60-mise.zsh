# Optional mise functions; tools and manifests are machine-local.
# Names are long and namespaced, so they are defined directly; a local
# override in 90-local.zsh still wins because it loads after this file.

typeset -f zsh_mise_check >/dev/null 2>&1 || return 0
zsh_mise_check || return 0

zsh_mise_bin() {
  local mise_home="$HOME"
  (( EUID == 0 )) && mise_home=~root
  print -r -- "$mise_home/.local/bin/mise"
}

zsh_mise_global() {
  zsh_mise_check || return 1
  local mise_home="$HOME"
  (( EUID == 0 )) && mise_home=~root
  # Run global-tool operations from HOME so a project mise.toml cannot be
  # accidentally included when the command is called inside a repository.
  (
    builtin cd -- "$mise_home" || return 1
    MISE_CEILING_PATHS="$mise_home" "$mise_home/.local/bin/mise" "$@"
  )
}

zsh_mise_refresh_completions() {
  zsh_mise_check || return 1
  local completions_dir="$MISE_DATA_DIR/completions/${dotfiles_shell:-zsh}"
  local completion_file="$completions_dir/_mise"
  local tmp_file="$completion_file.$$.tmp"
  local script

  script="$("$(zsh_mise_bin)" completion "${dotfiles_shell:-zsh}" 2>/dev/null)" || return 0
  [[ -n "$script" ]] || return 0

  [[ -d "$completions_dir" ]] || command mkdir -p "$completions_dir" 2>/dev/null || return 0
  if print -r -- "$script" >| "$tmp_file" 2>/dev/null && command mv -f "$tmp_file" "$completion_file" 2>/dev/null; then
    zsh_fpath_prepend "$completions_dir"
  else
    command rm -f "$tmp_file" 2>/dev/null || true
  fi
}

mise_activate() {
  zsh_mise_check || return 1
  unset zsh_mise_autostart_disabled
  local script
  script="$("$(zsh_mise_bin)" activate "${dotfiles_shell:-zsh}")" || return 1
  eval "$script"
}

mise_deactivate() {
  zsh_mise_check || return 1
  # Keep the queued autostart from re-activating this shell later.
  typeset -g zsh_mise_autostart_disabled=1
  if [[ -n "${MISE_SHELL:-}" || -n "${__MISE_DIFF:-}" ]]; then
    local script
    script="$("$(zsh_mise_bin)" deactivate)" || return 1
    eval "$script"
  fi
}

mise_update() {
  zsh_mise_check || return 1
  "$(zsh_mise_bin)" self-update --no-plugins &&
    zsh_mise_refresh_completions &&
    rehash
}

mise_use() { zsh_mise_global use --global "$@" && rehash; }
mise_install() { zsh_mise_global install "$@" && rehash; }
mise_list() { zsh_mise_global ls --current "$@"; }
mise_outdated() { zsh_mise_global outdated "$@"; }
mise_upgrade() { zsh_mise_global upgrade "$@" && rehash; }
mise_edit() { zsh_mise_global edit --global "$@"; }
mise_lock() { zsh_mise_global lock --global "$@"; }
mise_which() { zsh_mise_global which "$@"; }
mise_search() { zsh_mise_global search "$@"; }
mise_versions() { zsh_mise_global ls-remote "$@"; }
mise_registry() { zsh_mise_global registry "$@"; }
mise_doctor() { zsh_mise_check || return 1; "$(zsh_mise_bin)" doctor "$@"; }
mise_reshim() { zsh_mise_check || return 1; "$(zsh_mise_bin)" reshim && rehash; }

mise_remove() {
  (( $# > 0 )) || {
    print -u2 -- "usage: mise_remove TOOL[@VERSION] ..."
    return 2
  }
  [[ -t 0 && -t 1 ]] || {
    print -u2 -- "confirmation requires an interactive terminal"
    return 1
  }

  print -- "Global mise tool requests to remove: $*"
  zsh_confirm "Continue? [y/N] " || {
    print
    return 1
  }
  print

  zsh_mise_global unuse --global "$@" && rehash
}

# Activate after the first prompt so shell startup stays subprocess-free.
# zsh_defer_or_run falls back to immediate activation without zsh-defer.
zsh_mise_autostart() {
  [[ -n "${zsh_mise_autostart_disabled:-}" ]] && return 0
  if [[ ! -s "${MISE_DATA_DIR:-$HOME/.local/share/mise}/completions/${dotfiles_shell:-zsh}/_mise" ]]; then
    zsh_mise_refresh_completions
  fi
  mise_activate
}
zsh_defer_or_run zsh_mise_autostart
