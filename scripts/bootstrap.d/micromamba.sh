#!/usr/bin/env bash
# Optional Linux-only, home-persistent Micromamba setup.

install_micromamba() (
  set -euo pipefail

  # Keep this layout in sync with dot_config/dotfiles/zsh/60-micromamba.zsh.
  local bin_dir="$HOME/.local/bin"
  local root_prefix="$HOME/.local/share/mamba"
  local executable="$bin_dir/micromamba"
  local platform tmp_dir="" dependency

  case "$(uname -m)" in
    x86_64|amd64) platform=linux-64 ;;
    aarch64|arm64) platform=linux-aarch64 ;;
    *) say "Micromamba bootstrap supports Linux x86_64 and aarch64 only."; return 1 ;;
  esac
  if ! have getconf || ! getconf GNU_LIBC_VERSION >/dev/null 2>&1; then
    say "Micromamba requires a glibc-based Linux image; musl/Alpine is not supported."
    return 1
  fi

  # Never replace a symlink that may point outside the persistent home.
  if [[ -L "$executable" ]]; then
    say "Refusing to reuse a symlink at $executable; a home-local executable is required."
    return 1
  fi
  if [[ ! -x "$executable" ]]; then
    if [[ -e "$executable" ]]; then
      say "Refusing to overwrite the existing non-executable path: $executable"
      return 1
    fi
    for dependency in curl tar bzip2; do
      if ! have "$dependency"; then
        say "Micromamba bootstrap requires $dependency in the base image; no system packages will be installed."
        return 1
      fi
    done

    mkdir -p "$bin_dir"
    tmp_dir="$(mktemp -d "$bin_dir/.micromamba-install.XXXXXX")"
    trap 'rm -rf -- "$tmp_dir"' EXIT
    say "Installing Micromamba from the official $platform release into $bin_dir."
    curl -fsSL --retry 3 -o "$tmp_dir/micromamba.tar.bz2" \
      "https://micro.mamba.pm/api/micromamba/$platform/latest"
    tar -xjf "$tmp_dir/micromamba.tar.bz2" -C "$tmp_dir" bin/micromamba
    chmod 0755 "$tmp_dir/bin/micromamba"
    "$tmp_dir/bin/micromamba" --version
    mv "$tmp_dir/bin/micromamba" "$executable"
  fi
  "$executable" --version

  mkdir -p "$root_prefix/pkgs" "$root_prefix/envs"
  # Seed only our root-prefix config; leave the user's other Conda configs alone.
  # Disable implicit base activation; leave prompt rendering to Starship.
  # Micromamba expands ~ in these directory settings, including homes with spaces.
  if [[ ! -e "$root_prefix/.mambarc" ]]; then
    printf '%s\n' \
      'channels:' '  - conda-forge' 'channel_priority: strict' \
      'envs_dirs:' '  - ~/.local/share/mamba/envs' \
      'pkgs_dirs:' '  - ~/.local/share/mamba/pkgs' \
      'auto_activate_base: false' 'changeps1: false' > "$root_prefix/.mambarc"
  fi

  if [[ ! -f "$root_prefix/conda-meta/history" ]]; then
    # Empty install initializes base metadata without packages or network access.
    # Unlike create, it supports an existing root prefix without replacing it.
    if ! "$executable" --no-rc --no-env install --root-prefix "$root_prefix" \
      --prefix "$root_prefix" --offline --yes; then
      say "Initializing Micromamba base failed at $root_prefix. Check the error and permissions, then rerun bootstrap micromamba."
      say "Do not delete the root prefix: it may contain configuration, cached packages and other environments."
      return 1
    fi
  fi
  if [[ ! -f "$root_prefix/conda-meta/history" ]]; then
    say "Micromamba did not initialize a valid base environment; shell activation remains disabled."
    return 1
  fi

  # Commit opt-in only after successful setup. Normal shell startup never installs.
  touch "$root_prefix/.dotfiles-enabled"
  say "Micromamba base environment is ready at $root_prefix."
  say "After chezmoi apply, open a new zsh terminal: its base/bin is added to PATH and full activation is deferred."
  say "Install packages there with: micromamba install -c conda-forge git ripgrep jq"
)
