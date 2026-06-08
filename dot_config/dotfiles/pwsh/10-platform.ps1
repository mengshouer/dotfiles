# Platform facts for shared startup modules.

$script:DotfilesPowerShellMajor = $PSVersionTable.PSVersion.Major
$script:DotfilesIsWindowsPowerShell = ($script:DotfilesPowerShellMajor -lt 6)
