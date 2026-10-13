#!/usr/bin/env bash
# Optional Linux-only mise setup; uses mise's official per-user layout
# (~/.local/bin/mise) inside the current user's HOME.

install_mise() (
  set -euo pipefail

  local bin_dir="$HOME/.local/bin"
  local executable="$bin_dir/mise"
  local tmp_dir=""

  case "$(uname -m)" in
    x86_64|amd64|aarch64|arm64) ;;
    *) say "mise bootstrap supports Linux x86_64 and aarch64 only."; return 1 ;;
  esac

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
    run curl -fsSL --retry 3 -o "$tmp_dir/install.sh" https://mise.run
    MISE_INSTALL_HELP=0 run sh "$tmp_dir/install.sh"
  fi

  run "$executable" --version
  say "mise is ready at $executable."
  say "Tool lists are machine-local; add tools with: mise use --global <tool>@<version>"
)
