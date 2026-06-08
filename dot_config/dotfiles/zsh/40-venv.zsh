# Python virtual environment helpers.

activate_venv() {
  local venv_path="${1:-.venv}"
  local candidate
  local activate=""
  local candidates=(
    "$venv_path"
    "$venv_path/bin/activate"
    "$venv_path/.venv/bin/activate"
  )

  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      activate="$candidate"
      break
    fi
  done

  if [[ -z "$activate" ]]; then
    print -u2 "No virtual environment activation script found for '$venv_path'."
    return 1
  fi

  source "$activate"
}

deactivate_venv() {
  if (( $+functions[deactivate] )); then
    deactivate
    return
  fi

  print "No active Python virtual environment."
}

alias venv="activate_venv"
alias va="activate_venv"
alias vde="deactivate_venv"
