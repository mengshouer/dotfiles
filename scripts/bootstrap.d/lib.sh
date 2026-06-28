#!/usr/bin/env bash
# Shared helpers for Unix bootstrap scripts.

bootstrap_parse_args() {
  layer="terminal"
  set_shell=0
  update=0

  if (($#)); then
    case "$1" in
      terminal|dev) layer="$1"; shift ;;
      -h|--help) usage; exit 0 ;;
    esac
  fi

  while (($#)); do
    case "$1" in
      --set-shell) set_shell=1 ;;
      --update) update=1 ;;
      -h|--help) usage; exit 0 ;;
      *) printf 'Unknown argument: %s\n' "$1" >&2; usage; exit 2 ;;
    esac
    shift
  done
}

run() {
  "$@"
}

say() {
  printf '%s\n' "$*"
}

have() {
  command -v "$1" >/dev/null 2>&1
}

have_usable_brew() {
  (( EUID != 0 )) && have brew
}

bootstrap_root_home() {
  printf '%s\n' ~root
}

bootstrap_prepare_root_environment() {
  (( EUID == 0 )) || return 0

  HOME="$(bootstrap_root_home)"
  export HOME

  unset DOTFILES_BOOTSTRAP_BIN_DIR XDG_BIN_HOME XDG_CACHE_HOME XDG_CONFIG_HOME XDG_DATA_HOME ZDOTDIR ZIM_CONFIG_FILE
}

run_as_root() {
  if (( EUID == 0 )); then
    run "$@"
    return
  fi

  if have sudo; then
    run sudo "$@"
    return
  fi

  say "Root privileges are required to run: $*"
  say "Run bootstrap as root or install sudo."
  return 1
}

path_prepend() {
  local dir="$1"
  [[ -n "$dir" ]] || return 0

  case ":$PATH:" in
    *":$dir:"*) ;;
    *) PATH="$dir${PATH:+:$PATH}" ;;
  esac

  export PATH
}

path_remove_patterns() {
  local entry new_path old_ifs pattern

  (($#)) || return 0

  new_path=""
  old_ifs="$IFS"
  IFS=:
  for entry in $PATH; do
    for pattern in "$@"; do
      case "$entry" in
        $pattern) continue 2 ;;
      esac
    done

    new_path="${new_path:+$new_path:}$entry"
  done
  IFS="$old_ifs"

  PATH="$new_path"
  export PATH
}

bootstrap_remove_root_unsafe_paths() {
  path_remove_patterns \
    "/home/*" \
    "/Users/*" \
    "/opt/homebrew/bin" \
    "/opt/homebrew/sbin"

  [[ "${OSTYPE:-}" == darwin* ]] && path_remove_patterns "/usr/local/bin" "/usr/local/sbin"
  return 0
}

path_contains_dir() {
  local search_path="$1"
  local dir="$2"

  [[ -n "$dir" ]] || return 1

  case ":$search_path:" in
    *":$dir:"*) return 0 ;;
    *) return 1 ;;
  esac
}

bootstrap_bin_dir() {
  if (( EUID == 0 )); then
    printf '%s\n' "$(bootstrap_root_home)/.local/bin"
    return 0
  fi

  if [[ -n "${DOTFILES_BOOTSTRAP_BIN_DIR:-}" ]]; then
    printf '%s\n' "$DOTFILES_BOOTSTRAP_BIN_DIR"
  elif [[ -n "${XDG_BIN_HOME:-}" ]]; then
    printf '%s\n' "$XDG_BIN_HOME"
  else
    printf '%s\n' "$HOME/.local/bin"
  fi
}

bootstrap_prepare_path() {
  bootstrap_prepare_root_environment
  bootstrap_original_path="${bootstrap_original_path:-${PATH:-}}"

  if (( EUID == 0 )); then
    local fnm_dir root_home
    root_home="$(bootstrap_root_home)"
    bootstrap_remove_root_unsafe_paths
    path_prepend "$root_home/bin"
    path_prepend "$root_home/.local/bin"

    case "${OSTYPE:-}" in
      darwin*) fnm_dir="$root_home/Library/Application Support/fnm" ;;
      *)      fnm_dir="$root_home/.local/share/fnm" ;;
    esac
    path_prepend "$fnm_dir"
    bootstrap_remove_root_unsafe_paths
    return 0
  else
    path_prepend "/home/linuxbrew/.linuxbrew/bin"
    path_prepend "/usr/local/bin"
    path_prepend "/opt/homebrew/bin"
  fi
  path_prepend "$HOME/bin"
  path_prepend "$HOME/.local/bin"
  path_prepend "${XDG_BIN_HOME:-}"
  path_prepend "$(bootstrap_bin_dir)"

  local fnm_dir
  case "${OSTYPE:-}" in
    darwin*) fnm_dir="${XDG_DATA_HOME:-$HOME/Library/Application Support}/fnm" ;;
    *)      fnm_dir="${XDG_DATA_HOME:-$HOME/.local/share}/fnm" ;;
  esac
  path_prepend "$fnm_dir"
}

update_source_repo() {
  (( update )) || return 0

  local repo_dir="$1"
  have git || {
    say "git is required for --update."
    return 1
  }

  if ! git -C "$repo_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    say "Skipping source update: $repo_dir is not a git worktree."
    return 0
  fi

  run git -C "$repo_dir" pull --ff-only
}

install_zimfw() {
  local zim_home="${ZDOTDIR:-$HOME}/.zim"
  local zimfw_file="$zim_home/zimfw.zsh"
  local zimrc_file="${ZIM_CONFIG_FILE:-${ZDOTDIR:-$HOME}/.zimrc}"
  local init_file="$zim_home/init.zsh"

  if [[ ! -f "$zimrc_file" ]]; then
    bootstrap_zimfw_pending=1
    say "No .zimrc found at $zimrc_file. Run chezmoi apply, then rerun terminal bootstrap."
    return 0
  fi

  if [[ ! -f "$zimfw_file" ]]; then
    run mkdir -p "$zim_home"
    run curl -fsSL --create-dirs -o "$zimfw_file" \
      https://github.com/zimfw/zimfw/releases/latest/download/zimfw.zsh
  fi

  if [[ -f "$zimfw_file" ]]; then
    if [[ ! -f "$init_file" || "$zimrc_file" -nt "$init_file" ]]; then
      run zsh -lc "ZIM_HOME='$zim_home' ZIM_CONFIG_FILE='$zimrc_file' source '$zimfw_file' init"
    fi

    if (( update )); then
      run zsh -lc "ZIM_HOME='$zim_home' ZIM_CONFIG_FILE='$zimrc_file' source '$zimfw_file' update"
    fi
  fi
}

apply_after_update() {
  (( update )) || return 0
  have chezmoi || {
    say "chezmoi is required for --update."
    return 1
  }
  run chezmoi apply
}

print_manual_chezmoi_steps() {
  local chezmoi_bin chezmoi_dir original_path

  original_path="${bootstrap_original_path:-${PATH:-}}"

  say ""
  say "Next steps:"
  if have chezmoi; then
    chezmoi_bin="$(command -v chezmoi)"
    chezmoi_dir="$(dirname "$chezmoi_bin")"

    if ! path_contains_dir "$original_path" "$chezmoi_dir"; then
      say "  export PATH=\"$chezmoi_dir:\$PATH\""
    fi
  else
    say "  # Ensure chezmoi is installed and on PATH first."
  fi
  say "  chezmoi diff  # optional: review changes before apply"
  say "  chezmoi apply"
  say "  bash scripts/bootstrap terminal --set-shell  # optional: set zsh as default shell"
  if [[ "${bootstrap_zimfw_pending:-0}" == "1" ]]; then
    say "  bash scripts/bootstrap terminal --update  # finish zimfw setup after apply"
  fi
}

set_shell_if_requested() {
  (( set_shell )) || return 0
  have zsh || {
    say "zsh is required for --set-shell."
    return 1
  }

  local target_shell
  target_shell="$(command -v zsh)"

  if [[ -r /etc/shells ]] && ! grep -qxF "$target_shell" /etc/shells; then
    say "Skipping chsh: $target_shell is not in /etc/shells."
    if (( EUID == 0 )); then
      say "Add it first with: echo $target_shell >> /etc/shells"
    else
      say "Add it first with: echo $target_shell | sudo tee -a /etc/shells"
    fi
    return 1
  fi

  run chsh -s "$target_shell"
}
