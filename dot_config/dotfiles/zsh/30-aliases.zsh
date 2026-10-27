# Shared aliases.

alias _al=alias

alias j="z"
alias ji="zi"

alias ..="cd .."
alias ...="cd ../.."

alias ll="ls -lah"
alias la="ls -A"
alias l="ls -CF"

alias g="git"
alias gs="git status"
alias gst="git stash"
alias ga="git add"
alias gaa="git add ."
alias gct="git commit"
alias gph="git push"
alias gpl="git pull"
alias gch="git checkout"
alias gr1="git reset --soft HEAD~1"
alias glg="git log --oneline --graph"

alias nr="npm run"

alias c="code ."

# Open a directory in the platform's default graphical file manager.
opendir() {
  if (( $# > 1 )); then
    print -u2 -- "Usage: opendir [directory]"
    return 2
  fi

  local input_path="."
  (( $# == 1 )) && input_path="$1"

  if [[ ! -d "$input_path" ]]; then
    print -u2 -- "opendir: not a directory: '$input_path'"
    return 1
  fi

  # Prefix relative paths without collapsing . or .., preserving symlink
  # traversal semantics. Absolute paths are passed through unchanged.
  local directory
  if [[ "$input_path" == /* ]]; then
    directory="$input_path"
  else
    directory="${PWD%/}/$input_path"
  fi

  local opener=""
  local -a opener_arguments=()

  if dotfiles_is_wsl; then
    if command -v wslpath >/dev/null 2>&1 && command -v explorer.exe >/dev/null 2>&1; then
      local windows_directory=""
      if windows_directory="$(command wslpath -w "$directory" 2>/dev/null)" &&
          [[ -n "$windows_directory" ]]; then
        opener="explorer.exe"
        opener_arguments=("$windows_directory")
      fi
    fi

    if [[ -z "$opener" ]] && command -v wslview >/dev/null 2>&1; then
      opener="wslview"
      opener_arguments=("$directory")
    fi

    if [[ -z "$opener" ]]; then
      print -u2 -- "opendir: no supported directory opener found for WSL"
      return 1
    fi
  else
    case "$OSTYPE" in
      darwin*)
        if command -v open >/dev/null 2>&1; then
          opener="open"
          opener_arguments=("$directory")
        else
          print -u2 -- "opendir: no supported directory opener found for macOS"
          return 1
        fi
        ;;
      linux*)
        if command -v xdg-open >/dev/null 2>&1; then
          opener="xdg-open"
          opener_arguments=("$directory")
        elif command -v gio >/dev/null 2>&1; then
          opener="gio"
          opener_arguments=(open "$directory")
        else
          print -u2 -- "opendir: no supported directory opener found for Linux"
          return 1
        fi
        ;;
      *)
        print -u2 -- "opendir: unsupported platform: '$OSTYPE'"
        return 1
        ;;
    esac
  fi

  (command "$opener" "${opener_arguments[@]}" </dev/null >/dev/null 2>&1 &)
  return 0
}

alias d="docker"
alias dc="docker compose"

alias py="python"
alias uvpy="uv run python"
alias uvpip="uv pip"

alias ard="aria2c --summary-interval=10 -x 3 --allow-overwrite=true -Z"

# Quick-edit local override files (machine-specific, not in repo).
# Defined as functions (not aliases) so syntax highlighters can recognize them.
dotfiles_edit_file() {
  setopt local_options sh_word_split
  local target="$1"
  local parent="${target%/*}"
  local editor="${VISUAL:-${EDITOR:-vi}}"

  [[ "$parent" != "$target" && ! -d "$parent" ]] && command mkdir -p "$parent"
  $editor "$target"
}

elocal()     { dotfiles_edit_file "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/local.${dotfiles_shell:-zsh}"; }
elocalenv()  { dotfiles_edit_file "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/local.env"; }
egit()       { dotfiles_edit_file "$HOME/.gitconfig"; }
egitignore() {
  # ~/.config/git/ignore is user-owned: chezmoi only seeds it once (create_),
  # so Git reads edits immediately with no `chezmoi apply` in between.
  dotfiles_edit_file "$HOME/.config/git/ignore"
}

if [[ "$OSTYPE" == linux* ]]; then
  alias sdr="systemctl daemon-reload"
  alias sr="systemctl restart"
  alias jl="journalctl -o cat -fu"
fi
