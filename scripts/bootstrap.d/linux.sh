#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/bootstrap [dev] [--set-shell] [--update]

Layers:
  terminal   git curl ca-certificates chezmoi zsh starship zoxide fzf zimfw
  dev        fnm uv

Flags:
  --set-shell   opt in to setting zsh as the default shell (chsh, or usermod when chsh is unavailable)
  --update      git pull --ff-only, apply dotfiles, update zimfw

Run as root to install shared tools into /usr/local/bin for all users.
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
source "$script_dir/lib.sh"
bootstrap_parse_args "$@"
bootstrap_prepare_path
update_source_repo "$repo_root"

apt_updated=0

is_debian_like() {
  command -v apt-get >/dev/null 2>&1
}

is_rhel_like() {
  have dnf || have yum
}

apt_package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
}

rpm_package_installed() {
  rpm -q "$1" >/dev/null 2>&1
}

apt_update_once() {
  (( apt_updated )) && return 0
  run_as_root apt-get update || return 1
  apt_updated=1
}

apt_install() {
  local packages=("$@")
  local missing=()
  local package

  # Callers must gate this with is_debian_like; see distro_install.
  for package in "${packages[@]}"; do
    apt_package_installed "$package" || missing+=("$package")
  done

  if ((${#missing[@]})); then
    apt_update_once
    run_as_root apt-get install -y "${missing[@]}"
  fi
}

rhel_install() {
  local packages=("$@")
  local missing=()
  local package
  local installer

  installer=dnf
  have dnf || installer=yum

  for package in "${packages[@]}"; do
    rpm_package_installed "$package" || missing+=("$package")
  done

  if ((${#missing[@]})); then
    run_as_root "$installer" install -y "${missing[@]}"
  fi
}

distro_install() {
  local packages=("$@")

  if is_debian_like; then
    apt_install "${packages[@]}"
  elif is_rhel_like; then
    rhel_install "${packages[@]}"
  else
    say "No supported package manager (apt-get, dnf, or yum). Install manually: ${packages[*]}"
  fi
}

# dnf/yum abort the whole transaction when a package name is unknown, so
# optional tools check availability before asking the distro to install them.
# Return 2 for metadata refresh errors; these must not trigger a release fallback.
distro_package_available() {
  local package="$1"

  if is_debian_like; then
    apt-cache show "$package" >/dev/null 2>&1 && return 0
    apt_update_once || return 2
    apt-cache show "$package" >/dev/null 2>&1 || return 1
  elif is_rhel_like; then
    { have dnf && dnf list --available "$package" >/dev/null 2>&1; } ||
      { have yum && yum list available "$package" >/dev/null 2>&1; } || return 1
  else
    return 1
  fi
}

brew_formula_installed() {
  have_usable_brew && brew list --formula "$1" >/dev/null 2>&1
}

brew_install_formula() {
  local package="$1"

  have_usable_brew || return 1
  brew_formula_installed "$package" && return 0
  run brew install "$package"
}

install_brew_or_distro_package() {
  local command_name="$1"
  local package="${2:-$command_name}"

  have "$command_name" && return 0

  if have_usable_brew; then
    brew_install_formula "$package"
    return 0
  fi

  distro_install "$package"
}

install_chezmoi() {
  have chezmoi && return 0

  if have_usable_brew; then
    brew_install_formula chezmoi
    return 0
  fi

  if is_debian_like && apt-cache show chezmoi >/dev/null 2>&1; then
    apt_install chezmoi
    return 0
  fi

  local bin_dir
  bin_dir="$(bootstrap_bin_dir)"
  say "Installing chezmoi with the official installer."
  run mkdir -p "$bin_dir"
  run sh -c 'sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$1"' sh "$bin_dir"
}

install_starship() {
  have starship && return 0

  if have_usable_brew; then
    brew_install_formula starship
    return 0
  fi

  local bin_dir
  bin_dir="$(bootstrap_bin_dir)"
  say "Installing starship with the official installer."
  run mkdir -p "$bin_dir"
  run sh -c 'curl -sS https://starship.rs/install.sh | sh -s -- -y -b "$1"' sh "$bin_dir"
}

install_zoxide() {
  have zoxide && return 0

  if have_usable_brew; then
    brew_install_formula zoxide
    return 0
  fi

  if is_debian_like && apt-cache show zoxide >/dev/null 2>&1; then
    apt_install zoxide
    return 0
  fi

  local bin_dir
  bin_dir="$(bootstrap_bin_dir)"
  say "Installing zoxide with the official installer."
  run mkdir -p "$bin_dir"
  run sh -c 'curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh -s -- --bin-dir "$1"' sh "$bin_dir"
}

install_fzf() {
  have fzf && return 0

  if have_usable_brew; then
    brew_install_formula fzf
    return 0
  fi

  # fzf usually lives in EPEL on RHEL-family images, where a bare
  # `dnf install fzf` would abort the whole transaction.
  if distro_package_available fzf; then
    distro_install fzf
    return 0
  else
    local availability_status=$?
    if (( availability_status != 1 )); then
      say "Failed to refresh package metadata; cannot determine whether fzf is available."
      return "$availability_status"
    fi
  fi

  if install_fzf_from_release; then
    return 0
  fi

  say ""
  say "fzf is not installed. Install it manually, for example:"
  say "  RHEL/CentOS: sudo dnf install -y epel-release && sudo dnf install -y fzf"
  say "  Alpine:      sudo apk add fzf"
  say "  Arch:        sudo pacman -S fzf"
  say ""
}

# Minimal images often have neither Homebrew nor a distro package for fzf.
# fzf ships static release binaries, so fall back to the same asset a manual
# install would use.
install_fzf_from_release() {
  have curl || return 1
  have tar || return 1

  local arch
  case "$(uname -m)" in
    x86_64|amd64) arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) return 1 ;;
  esac

  # Latest release tag, e.g. v0.74.4; asset names omit the leading v.
  local version
  version="$(curl -fsSL https://api.github.com/repos/junegunn/fzf/releases/latest 2>/dev/null \
    | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p')" || version=""
  [[ -n "$version" ]] || return 1

  local bin_dir tmp_dir
  bin_dir="$(bootstrap_bin_dir)"
  tmp_dir="$(mktemp -d)" || return 1

  say "Installing fzf $version with the official release binary."
  if ! run curl -fsSL -o "$tmp_dir/fzf.tar.gz" \
    "https://github.com/junegunn/fzf/releases/download/v${version}/fzf-${version}-linux_${arch}.tar.gz"; then
    rm -rf "$tmp_dir"
    return 1
  fi

  if ! run tar -xzf "$tmp_dir/fzf.tar.gz" -C "$tmp_dir" fzf; then
    rm -rf "$tmp_dir"
    return 1
  fi

  run mkdir -p "$bin_dir"
  if ! run cp "$tmp_dir/fzf" "$bin_dir/fzf"; then
    rm -rf "$tmp_dir"
    return 1
  fi
  run chmod 0755 "$bin_dir/fzf"

  rm -rf "$tmp_dir"
}

install_fnm() {
  have fnm && return 0

  if have_usable_brew; then
    brew_install_formula fnm
    return 0
  fi

  if is_debian_like && apt-cache show fnm >/dev/null 2>&1; then
    apt_install fnm
    return 0
  fi

  say ""
  say "fnm is not installed. Run the following command to install it:"
  if (( EUID == 0 )); then
    say "  curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir /usr/local/bin --skip-shell"
  else
    say "  curl -fsSL https://fnm.vercel.app/install | bash"
  fi
  say ""
}

install_uv() {
  have uv && return 0

  if have_usable_brew; then
    brew_install_formula uv
    return 0
  fi

  if is_debian_like && apt-cache show uv >/dev/null 2>&1; then
    apt_install uv
    return 0
  fi

  say ""
  say "uv is not installed. Run the following command to install it:"
  if (( EUID == 0 )); then
    say "  curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh"
  else
    say "  curl -LsSf https://astral.sh/uv/install.sh | sh"
  fi
  say ""
}

case "$layer" in
  terminal)
    install_brew_or_distro_package curl
    install_brew_or_distro_package git
    if ! have_usable_brew && { is_debian_like || is_rhel_like; }; then
      distro_install ca-certificates
    fi
    install_chezmoi
    install_brew_or_distro_package zsh
    install_starship
    install_zoxide
    install_fzf
    ;;
  dev)
    install_fnm
    install_uv
    ;;
esac

apply_after_update

if [[ "$layer" == "terminal" ]]; then
  install_zimfw
fi

set_shell_if_requested
if (( ! update && ! set_shell )); then
  print_manual_chezmoi_steps
fi
