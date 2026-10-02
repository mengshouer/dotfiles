# Command and environment management for the optional Micromamba layer.

(( ${+functions[zsh_micromamba_prepare]} )) || return 0
zsh_micromamba_prepare || return 0

zsh_micromamba_define_alias_if_free() {
  local name="$1" body="$2"

  (( ${+aliases[$name]} || ${+functions[$name]} || ${+commands[$name]} )) && return 1
  alias "$name=$body"
}

zsh_micromamba_define_function_if_free() {
  local name="$1"

  (( ${+aliases[$name]} || ${+functions[$name]} || ${+commands[$name]} )) && return 1
  return 0
}

zsh_micromamba_env_name_valid() {
  local name="$1"
  [[ "$name" =~ '^[A-Za-z0-9][A-Za-z0-9._-]*$' &&
    "$name" != base && "$name" != . && "$name" != .. ]]
}

zsh_micromamba_validate_specs() {
  local spec
  for spec in "$@"; do
    # Keep channel-qualified specs, bracket attributes and package files in `mm`.
    # Package functions own channel/safety flags; versions/build constraints work.
    if [[ -z "$spec" || "$spec" == -* || "$spec" == *:* ||
          "$spec" == *'['* || "$spec" == *']'* ||
          "$spec" == */* || "$spec" == *\\* ||
          "$spec" == *.conda || "$spec" == *.tar.bz2 ]]; then
      print -u2 -- "unsupported package argument; use 'mm' for advanced micromamba options"
      return 2
    fi
  done
}

zsh_micromamba_require_tty() {
  [[ -t 0 && -t 1 ]] || {
    print -u2 -- "confirmation requires an interactive terminal"
    return 1
  }
}

zsh_micromamba_confirm() {
  zsh_micromamba_require_tty || return 1
  local reply
  read -q "reply?$1 [y/N] " || {
    print
    return 1
  }
  print
  return 0
}

zsh_micromamba_confirm_exact() {
  local expected="$1" reply
  zsh_micromamba_require_tty || return 1
  read "reply?Type environment name to confirm deletion: "
  print
  [[ "$reply" == "$expected" ]]
}

zsh_micromamba_install() {
  zsh_micromamba_prepare || return 1
  local env_name="" command_name

  if [[ "${1:-}" == -n ]]; then
    (( $# >= 2 )) || {
      print -u2 -- "usage: mmi [-n ENV] PACKAGE..."
      return 2
    }
    env_name="$2"
    shift 2
    zsh_micromamba_env_name_valid "$env_name" || {
      print -u2 -- "invalid named environment: $env_name"
      return 2
    }
  fi

  (( $# )) || {
    print -u2 -- "usage: mmi [-n ENV] PACKAGE..."
    return 2
  }
  zsh_micromamba_validate_specs "$@" || return

  if [[ -n "$env_name" ]]; then
    if [[ -f "$MAMBA_ROOT_PREFIX/envs/$env_name/conda-meta/history" ]]; then
      command_name=install
    else
      command_name=create
    fi
    "$MAMBA_EXE" "$command_name" -p "$MAMBA_ROOT_PREFIX/envs/$env_name" \
      --override-channels -c conda-forge --strict-channel-priority \
      --no-allow-uninstall "$@" || return
  else
    "$MAMBA_EXE" install -p "$MAMBA_ROOT_PREFIX" \
      --override-channels -c conda-forge --strict-channel-priority \
      --no-allow-uninstall "$@" || return
  fi

  zsh_micromamba_refresh_path
  rehash
}

zsh_micromamba_remove() {
  zsh_micromamba_prepare || return 1
  (( $# )) || {
    print -u2 -- "usage: mmr [-n ENV] PACKAGE..."
    return 2
  }

  local -a remove_args
  local env_name=""
  if [[ "${1:-}" == -n ]]; then
    (( $# >= 2 )) || {
      print -u2 -- "mmr: -n requires an environment"
      return 2
    }
    env_name="$2"
    shift 2
    zsh_micromamba_env_name_valid "$env_name" || {
      print -u2 -- "invalid named environment: $env_name"
      return 2
    }
    remove_args=(-p "$MAMBA_ROOT_PREFIX/envs/$env_name")
  else
    remove_args=(-p "$MAMBA_ROOT_PREFIX")
  fi

  (( $# )) || {
    print -u2 -- "mmr: at least one package is required"
    return 2
  }
  zsh_micromamba_validate_specs "$@" || return

  print -- "Planned package removal: ${env_name:-base}"
  "$MAMBA_EXE" remove "${remove_args[@]}" --no-prune-deps --dry-run "$@" || return
  zsh_micromamba_confirm "Continue package removal?" || return 1
  "$MAMBA_EXE" remove "${remove_args[@]}" --no-prune-deps --yes "$@" || return
  zsh_micromamba_refresh_path
  rehash
}

zsh_micromamba_env_blockers() {
  setopt localoptions nullglob extendedglob
  local prefix="$1" unit_dir references file proc_dir pid exe cwd pattern char
  # Escape the literal prefix for grep ERE, then require token/path boundaries.
  pattern="$prefix"
  for char in '\' '.' '[' ']' '^' '$' '*' '+' '?' '(' ')' '{' '}' '|'; do
    pattern="${pattern//"$char"/\\$char}"
  done
  pattern="(^|[[:space:]\"'=:(,;!+@-])$pattern($|[/[:space:]\"':),;])"

  local -a unit_dirs=(
    /etc/systemd/system
    /etc/systemd/user
    /usr/lib/systemd/system
    /usr/lib/systemd/user
    /usr/local/lib/systemd/system
    /usr/local/lib/systemd/user
    /run/systemd/system
    /run/systemd/user
    "$HOME/.config/systemd/user"
    "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
    "${XDG_RUNTIME_DIR:-/run/user/$EUID}/systemd/user"
  )

  [[ "${CONDA_PREFIX:-}" == "$prefix" ]] &&
    print "shell: active CONDA_PREFIX=$prefix"

  for unit_dir in "${unit_dirs[@]}"; do
    [[ -d "$unit_dir" ]] || continue
    references="$(command grep -RslE -- "$pattern" "$unit_dir" 2>/dev/null || true)"
    if [[ -n "$references" ]]; then
      while IFS= read -r file; do
        [[ -n "$file" ]] && print "systemd: $file"
      done <<< "$references"
    fi
  done

  for proc_dir in /proc/[0-9]##; do
    pid="${proc_dir:t}"
    [[ "$pid" == "$$" ]] && continue
    exe="$(readlink "$proc_dir/exe" 2>/dev/null || true)"
    cwd="$(readlink "$proc_dir/cwd" 2>/dev/null || true)"
    if [[ "$exe" == "$prefix"/* ]]; then
      print "process: PID $pid exe=$exe"
      continue
    fi
    if [[ "$cwd" == "$prefix" || "$cwd" == "$prefix"/* ]]; then
      print "process: PID $pid cwd=$cwd"
      continue
    fi
    if [[ -r "$proc_dir/maps" ]] && command grep -Eq -- "$pattern" "$proc_dir/maps" 2>/dev/null; then
      print "process: PID $pid maps=$prefix"
      continue
    fi
    if [[ -r "$proc_dir/environ" ]] && command cat "$proc_dir/environ" 2>/dev/null | \
      command tr '\0' '\n' | command grep -Fqx -- "CONDA_PREFIX=$prefix"; then
      print "process: PID $pid CONDA_PREFIX=$prefix"
      continue
    fi
    if [[ -r "$proc_dir/cmdline" ]] && command cat "$proc_dir/cmdline" 2>/dev/null | \
      command tr '\0' '\n' | command grep -Eq -- "$pattern"; then
      print "process: PID $pid command line references environment"
    fi
  done
}

zsh_micromamba_remove_env() {
  zsh_micromamba_prepare || return 1
  local force=0
  if [[ "${1:-}" == --force ]]; then
    force=1
    shift
  fi
  (( $# == 1 )) || {
    print -u2 -- "usage: mmre [--force] ENV"
    return 2
  }

  local env_name="$1"
  zsh_micromamba_env_name_valid "$env_name" || {
    print -u2 -- "refusing to delete invalid/base environment: $env_name"
    return 2
  }

  local prefix="$MAMBA_ROOT_PREFIX/envs/$env_name"
  # Never let an environment alias redirect removal to base or another prefix.
  if [[ -L "$MAMBA_ROOT_PREFIX/envs" || -L "$prefix" ]]; then
    print -u2 -- "refusing to delete environment through a symlink: $env_name"
    return 1
  fi
  [[ -f "$prefix/conda-meta/history" ]] || {
    print -u2 -- "named environment does not exist: $env_name"
    return 1
  }

  local blockers
  blockers="$(zsh_micromamba_env_blockers "$prefix")"
  if [[ -n "$blockers" && $force == 0 ]]; then
    print -u2 -- "refusing to delete environment: $env_name"
    print -u2 -- "$blockers"
    print -u2 -- "Use: mmre --force $env_name"
    return 1
  fi

  print -- "Environment to delete: $prefix"
  "$MAMBA_EXE" list -p "$prefix" || return
  if (( force )); then
    print -u2 -- "FORCE deletion will not stop services or kill processes:"
    [[ -n "$blockers" ]] && print -u2 -- "$blockers"
    zsh_micromamba_confirm_exact "$env_name" || return 1
  else
    zsh_micromamba_confirm "Delete the entire environment?" || return 1
  fi

  "$MAMBA_EXE" env remove -p "$prefix" --yes || return
  zsh_micromamba_refresh_path
  rehash
}

zsh_micromamba_list() {
  zsh_micromamba_prepare || return 1
  if (( $# == 0 )); then
    "$MAMBA_EXE" env list
  elif (( $# == 1 )); then
    if [[ "$1" == base ]]; then
      "$MAMBA_EXE" list -p "$MAMBA_ROOT_PREFIX"
    else
      zsh_micromamba_env_name_valid "$1" || {
        print -u2 -- "invalid named environment: $1"
        return 2
      }
      "$MAMBA_EXE" list -p "$MAMBA_ROOT_PREFIX/envs/$1"
    fi
  else
    print -u2 -- "usage: mml [ENV]"
    return 2
  fi
}

zsh_micromamba_clean() {
  zsh_micromamba_prepare || return 1
  (( $# == 0 )) || {
    print -u2 -- "usage: mmc"
    return 2
  }
  print -- "This removes micromamba caches, not environments."
  zsh_micromamba_confirm "Clean all caches?" || return 1
  "$MAMBA_EXE" clean --all --yes
}

zsh_micromamba_define_functions() {
  # Keep the raw command available for advanced operations.
  zsh_micromamba_define_alias_if_free mm 'micromamba'

  if zsh_micromamba_define_function_if_free mmi; then
    function mmi { zsh_micromamba_install "$@"; }
  fi
  if zsh_micromamba_define_function_if_free mmr; then
    function mmr { zsh_micromamba_remove "$@"; }
  fi
  if zsh_micromamba_define_function_if_free mmre; then
    function mmre { zsh_micromamba_remove_env "$@"; }
  fi
  if zsh_micromamba_define_function_if_free mml; then
    function mml { zsh_micromamba_list "$@"; }
  fi
  if zsh_micromamba_define_function_if_free mmc; then
    function mmc { zsh_micromamba_clean "$@"; }
  fi
  if zsh_micromamba_define_function_if_free mm-path-refresh; then
    function mm-path-refresh {
      zsh_micromamba_prepare || return 1
      zsh_micromamba_refresh_path --report
      rehash
    }
  fi
}

zsh_micromamba_owns_prefix() {
  [[ "$1" == "$MAMBA_ROOT_PREFIX" || "$1" == "$MAMBA_ROOT_PREFIX"/envs/* ]]
}

zsh_activate_micromamba() {
  local target="${1:-base}" activation target_prefix previous

  zsh_micromamba_prepare || return 0
  if [[ "$target" == base ]]; then
    target_prefix="$MAMBA_ROOT_PREFIX"
  else
    zsh_micromamba_env_name_valid "$target" || {
      print -u2 -- "Invalid micromamba environment: $target"
      return 1
    }
    target_prefix="$MAMBA_ROOT_PREFIX/envs/$target"
    [[ -f "$target_prefix/conda-meta/history" ]] || {
      print -u2 -- "Micromamba environment does not exist: $target"
      return 1
    }
  fi

  if [[ -n "${CONDA_PREFIX:-}" ]] && ! zsh_micromamba_owns_prefix "$CONDA_PREFIX"; then
    print -u2 -- "Another Conda environment is active: $CONDA_PREFIX"
    return 1
  fi
  [[ "${CONDA_PREFIX:-}" == "$target_prefix" ]] && return 0

  # Deactivate any of our own stacked environments before activating the target.
  while [[ -n "${CONDA_PREFIX:-}" ]] && zsh_micromamba_owns_prefix "$CONDA_PREFIX"; do
    previous="$CONDA_PREFIX"
    if ! activation="$($MAMBA_EXE shell deactivate --shell zsh 2>/dev/null)"; then
      print -u2 -- "Micromamba deactivation failed: $CONDA_PREFIX"
      return 1
    fi
    eval "$activation" || return 1
    [[ "${CONDA_PREFIX:-}" != "$previous" ]] || {
      print -u2 -- "Micromamba deactivation made no progress"
      return 1
    }
  done

  if ! activation="$($MAMBA_EXE shell activate \
      --shell zsh --prefix "$target_prefix" 2>/dev/null)"; then
    print -u2 -- "Micromamba activation failed: $target"
    return 1
  fi
  eval "$activation" || return 1
}

# Load the full hook only when interactive environment switching is requested.
mm-hook() {
  zsh_micromamba_prepare || return 1

  local hook
  if ! hook="$("$MAMBA_EXE" shell hook \
      --shell zsh --root-prefix "$MAMBA_ROOT_PREFIX" 2>/dev/null)"; then
    print -u2 -- "Micromamba shell hook failed."
    return 1
  fi
  eval "$hook"
}

# Explicit full activation; normal startup only changes PATH.
mm-activate() {
  zsh_activate_micromamba "${1:-base}"
}

zsh_micromamba_define_functions
# Reassert cached paths after synchronous modules without activating an env.
# Deferred fnm may later prepend its Node path; that priority is intentional.
zsh_micromamba_reassert_path
