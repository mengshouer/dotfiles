# Optional fnm initialization.

if (Get-Command fnm -CommandType Application -ErrorAction SilentlyContinue) {
    fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression
}
