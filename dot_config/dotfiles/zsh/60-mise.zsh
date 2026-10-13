# Optional mise functions; tools and manifests are machine-local.
# Names are long and namespaced, so they are defined directly; a local
# override in 90-local.zsh still wins because it loads after this file.

(( ${+functions[zsh_mise_prepare]} )) || return 0
zsh_mise_prepare || return 0

zsh_mise_global() {
  zsh_mise_prepare || return 1
  # Run global-tool operations from HOME so a project mise.toml cannot be
  # accidentally included when the command is called inside a repository.
  (
    builtin cd -- "$HOME" || return 1
    MISE_CEILING_PATHS="$HOME" "$HOME/.local/bin/mise" "$@"
  )
}

mise_activate() {
  zsh_mise_prepare || return 1
  local script
  script="$("$HOME/.local/bin/mise" activate zsh)" || return 1
  eval "$script"
}

mise_deactivate() {
  zsh_mise_prepare || return 1
  # Keep the queued autostart from re-activating this shell later.
  zsh_mise_autostart_disabled=1
  local script
  script="$("$HOME/.local/bin/mise" deactivate)" || return 1
  eval "$script"
}

mise_update() {
  zsh_mise_prepare || return 1
  "$HOME/.local/bin/mise" self-update --no-plugins && rehash
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
mise_doctor() { zsh_mise_prepare || return 1; "$HOME/.local/bin/mise" doctor "$@"; }
mise_reshim() { zsh_mise_prepare || return 1; "$HOME/.local/bin/mise" reshim && rehash; }

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
  local reply
  read -q "reply?Continue? [y/N] " || {
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
  mise_activate
}
zsh_defer_or_run zsh_mise_autostart
