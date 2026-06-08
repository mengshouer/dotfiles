# Final local override. This file is intentionally ignored by git/chezmoi.

local_zsh="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/local.zsh"
[[ -f "$local_zsh" ]] && source "$local_zsh"
unset local_zsh
