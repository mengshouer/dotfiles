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
alias gc="git commit"
alias gp="git push"
alias gpl="git pull"
alias gch="git checkout"
alias gr1="git reset --soft HEAD~1"
alias gl="git log --oneline --graph"

alias nr="npm run"

alias c="code ."

alias d="docker"
alias dc="docker compose"

alias py="python"
alias uvpy="uv run python"
alias uvpip="uv pip"

alias ard="aria2c --summary-interval=10 -x 3 --allow-overwrite=true -Z"

# Quick-edit local override files (machine-specific, not in repo).
# Defined as functions (not aliases) so syntax highlighters can recognize them.
elocal()      { ${EDITOR:-${VISUAL:-vi}} "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/local.zsh"; }
elocalenv()   { ${EDITOR:-${VISUAL:-vi}} "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/local.env"; }
egit()        { ${EDITOR:-${VISUAL:-vi}} "$HOME/.gitconfig"; }
egitignore() {
  local target="${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore.local"
  local editor="${EDITOR:-${VISUAL:-vi}}"
  ${=editor} "$target"
  # ignore.local is included into ~/.config/git/ignore via chezmoi template.
  # Re-apply so edits take effect immediately. If the editor is a GUI that
  # detaches (e.g. `code` without -w), this will run before your save;
  # re-run `chezmoi apply ~/.config/git/ignore` after saving.
  if command -v chezmoi >/dev/null 2>&1; then
    chezmoi apply "${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore" 2>/dev/null
  fi
}

if [[ "$OSTYPE" == linux* ]]; then
  alias sdr="systemctl daemon-reload"
  alias sr="systemctl restart"
  alias jl="journalctl -o cat -fu"
fi
