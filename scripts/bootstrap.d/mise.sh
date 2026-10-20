#!/usr/bin/env bash
# Optional Unix mise setup (Linux and macOS); uses mise's official per-user
# layout (~/.local/bin/mise) inside the current user's HOME.

install_mise() (
  set -euo pipefail

  local bin_dir="$HOME/.local/bin"
  local executable="$bin_dir/mise"
  local data_dir="${MISE_DATA_DIR:-$HOME/.local/share/mise}"
  local config_dir="${MISE_CONFIG_DIR:-$HOME/.config/mise}"
  local state_dir="${MISE_STATE_DIR:-$HOME/.local/state/mise}"
  local cache_dir="${MISE_CACHE_DIR:-$HOME/.cache/mise}"
  local completions_dir="$data_dir/completions/zsh"
  local tmp_dir=""

  if [[ -z "${MISE_CACHE_DIR:-}" && ( "${OSTYPE:-}" == darwin* || "$(uname -s)" == "Darwin" ) ]]; then
    cache_dir="$HOME/Library/Caches/mise"
  fi

  case "$(uname -m)" in
    x86_64|amd64|aarch64|arm64) ;;
    *) say "mise bootstrap supports x86_64/amd64 and aarch64/arm64 only."; return 1 ;;
  esac

  export MISE_DATA_DIR="$data_dir"
  export MISE_CONFIG_DIR="$config_dir"
  export MISE_STATE_DIR="$state_dir"
  export MISE_CACHE_DIR="$cache_dir"

  # Never replace a symlink or an unrelated existing path.
  if [[ -L "$executable" ]]; then
    say "Refusing to reuse a symlink at $executable; a home-local executable is required."
    return 1
  fi
  if [[ -e "$executable" && ! -x "$executable" ]]; then
    say "Refusing to overwrite the existing non-executable path: $executable"
    return 1
  fi

  if [[ ! -x "$executable" ]]; then
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$tmp_dir"' EXIT

    say "Installing the latest stable mise release into $bin_dir."
    run mkdir -p "$bin_dir"
    run curl -fsSL --retry 3 -o "$tmp_dir/install.sh" https://mise.run
    MISE_INSTALL_PATH="$executable" MISE_INSTALL_HELP=0 run sh "$tmp_dir/install.sh"
  elif (( ${update:-0} )); then
    say "Updating mise at $executable."
    run "$executable" self-update --no-plugins -y
  fi

  if "$executable" completion zsh >/dev/null 2>&1; then
    run mkdir -p "$completions_dir"
    "$executable" completion zsh > "$completions_dir/_mise"
  fi

  run "$executable" --version
  say "mise is ready at $executable."
  say "Tool lists are machine-local; add tools with: mise use --global <tool>@<version>"
)
