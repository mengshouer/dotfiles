# Optional pixi global shortcuts; manifests and environments are machine-local.

(( ${+functions[zsh_pixi_prepare]} )) || return 0
zsh_pixi_prepare || return 0

zsh_pixi_name_available() {
  ! builtin whence -w -- "$1" >/dev/null 2>&1
}

zsh_pixi_global() {
  zsh_pixi_prepare || return 1
  "$PIXI_HOME/bin/pixi" global "$@"
}

zsh_pixi_confirm() {
  [[ -t 0 && -t 1 ]] || {
    print -u2 -- "confirmation requires an interactive terminal"
    return 1
  }
  local reply
  read -q "reply?$1 [y/N] " || {
    print
    return 1
  }
  print
}

# Best-effort direct-path checks only, not a service dependency inventory.
# No match does not guarantee safety (e.g. trampoline references or launchd).
zsh_pixi_env_blockers() {
  setopt localoptions nullglob extendedglob
  local prefix="$1" unit_dir references file proc_dir pid exe cwd pattern char
  # Match a literal prefix with token/path boundaries, not php-debug for php.
  pattern="$prefix"
  for char in '\' '.' '[' ']' '^' '$' '*' '+' '?' '(' ')' '{' '}' '|'; do
    pattern="${pattern//"$char"/\\$char}"
  done
  pattern="(^|[[:space:]\"'=:(,;!+@-])$pattern($|[/[:space:]\"':),;])"

  local -aU unit_dirs=(
    /etc/systemd/system
    /etc/systemd/user
    /usr/lib/systemd/system
    /usr/lib/systemd/user
    /usr/local/lib/systemd/system
    /usr/local/lib/systemd/user
    "$HOME/.config/systemd/user"
    "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  )

  for unit_dir in "${unit_dirs[@]}"; do
    [[ -d "$unit_dir" ]] || continue
    references="$(command grep -RslE -- "$pattern" "$unit_dir" 2>/dev/null || true)"
    for file in "${(@f)references}"; do
      [[ -n "$file" ]] && print "systemd: $file"
    done
  done

  for proc_dir in /proc/[0-9]##; do
    pid="${proc_dir:t}"
    [[ "$pid" == "$$" ]] && continue
    exe="$(readlink "$proc_dir/exe" 2>/dev/null || true)"
    cwd="$(readlink "$proc_dir/cwd" 2>/dev/null || true)"
    if [[ "$exe" == "$prefix"/* ]]; then
      print "process: PID $pid exe=$exe"
    elif [[ "$cwd" == "$prefix" || "$cwd" == "$prefix"/* ]]; then
      print "process: PID $pid cwd=$cwd"
    fi
  done
}

zsh_pixi_uninstall() {
  (( $# == 1 )) || {
    print -u2 -- "usage: pxr ENV"
    return 2
  }
  local env_name="$1"
  [[ "$env_name" =~ '^[A-Za-z0-9][A-Za-z0-9._-]*$' && "$env_name" != . && "$env_name" != .. ]] || {
    print -u2 -- "invalid environment name"
    return 2
  }

  zsh_pixi_prepare || return 1
  local home_dir="${PIXI_HOME:a}"
  local prefix="$home_dir/envs/$env_name"
  [[ -d "$prefix" ]] || {
    print -u2 -- "environment does not exist: $env_name"
    return 1
  }

  local blockers
  blockers="$(zsh_pixi_env_blockers "$prefix")"
  if [[ -n "$blockers" ]]; then
    print -u2 -- "refusing to delete environment: $env_name"
    print -u2 -- "$blockers"
    print -u2 -- "Remove those references first, then retry."
    return 1
  fi

  print -- "Environment to delete: $env_name ($prefix)"
  zsh_pixi_confirm "Delete it?" || return 1
  PIXI_HOME="$home_dir" "$home_dir/bin/pixi" global uninstall "$env_name" && rehash
}

# Leave existing aliases, functions and executables alone. Raw pixi remains
# available for project workspaces and advanced operations.
if zsh_pixi_name_available pxi; then
  function pxi { zsh_pixi_global install "$@" && rehash; }
fi
if zsh_pixi_name_available pxr; then
  function pxr { zsh_pixi_uninstall "$@"; }
fi
if zsh_pixi_name_available pxl; then
  function pxl { zsh_pixi_global list "$@"; }
fi
if zsh_pixi_name_available pxu; then
  function pxu { zsh_pixi_global update "$@" && rehash; }
fi
if zsh_pixi_name_available pxs; then
  function pxs { zsh_pixi_global sync "$@" && rehash; }
fi
if zsh_pixi_name_available pxe; then
  function pxe { zsh_pixi_global edit "$@"; }
fi
