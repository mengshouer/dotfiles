# Profile cache builder (loaded only on cache miss).

function script:ConvertTo-DotfilesStaticLocalScript {
    param(
        [Parameter(Mandatory)]
        [string]$LocalPs1Path
    )

    $rawText = [System.IO.File]::ReadAllText($LocalPs1Path)
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($LocalPs1Path, [ref]$tokens, [ref]$errors)
    if (($null -ne $errors) -and ($errors.Count -gt 0)) {
        return ". '$($LocalPs1Path.Replace("'", "''"))'"
    }

    $aliasCommands = @(
        $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -in @('_al', 'Set-DotfilesAlias')
        }, $false)
    )

    if ($aliasCommands.Count -eq 0) {
        return $rawText
    }

    $sb = [System.Text.StringBuilder]::new($rawText.Length + 256)
    $lastIndex = 0

    foreach ($cmdAst in $aliasCommands) {
        $elements = $cmdAst.CommandElements
        $aliasName = $null
        $aliasTarget = $null

        if ($cmdAst.GetCommandName() -eq '_al' -and $elements.Count -ge 2) {
            $defText = $elements[1].Extent.Text.Trim()
            if (($defText.Length -ge 2) -and
                (($defText.StartsWith("'", [System.StringComparison]::Ordinal) -and $defText.EndsWith("'", [System.StringComparison]::Ordinal)) -or
                 ($defText.StartsWith('"', [System.StringComparison]::Ordinal) -and $defText.EndsWith('"', [System.StringComparison]::Ordinal)))) {
                $defText = $defText.Substring(1, $defText.Length - 2)
            }
            $eqIdx = $defText.IndexOf('=')
            if ($eqIdx -gt 0) {
                $aliasName = $defText.Substring(0, $eqIdx).Trim()
                $valText = $defText.Substring($eqIdx + 1).Trim()
                if (($valText.Length -ge 2) -and
                    (($valText.StartsWith("'", [System.StringComparison]::Ordinal) -and $valText.EndsWith("'", [System.StringComparison]::Ordinal)) -or
                     ($valText.StartsWith('"', [System.StringComparison]::Ordinal) -and $valText.EndsWith('"', [System.StringComparison]::Ordinal)))) {
                    $valText = $valText.Substring(1, $valText.Length - 2)
                }
                $aliasTarget = $valText
            }
        }

        if ((-not $aliasName) -or (-not $aliasTarget)) {
            continue
        }

        $startOffset = $cmdAst.Extent.StartOffset
        $endOffset = $cmdAst.Extent.EndOffset
        if ($startOffset -gt $lastIndex) {
            [void]$sb.Append($rawText, $lastIndex, $startOffset - $lastIndex)
        }

        $escapedTarget = $aliasTarget.Replace("'", "''")
        if (Get-Alias -Name $aliasName -ErrorAction SilentlyContinue) {
            [void]$sb.AppendLine("Remove-Item -LiteralPath 'Alias:$($aliasName.Replace("'", "''"))' -Force -Confirm:`$false -ErrorAction SilentlyContinue")
        }
        [void]$sb.Append("function global:$aliasName { Invoke-DotfilesAliasCommand '$escapedTarget' `$args }")
        $lastIndex = $endOffset
    }

    if ($lastIndex -lt $rawText.Length) {
        [void]$sb.Append($rawText, $lastIndex, $rawText.Length - $lastIndex)
    }

    return $sb.ToString()
}

function script:Build-DotfilesMergedProfileCache {
    param(
        [Parameter(Mandatory)]
        [string]$CachePath,

        [Parameter(Mandatory)]
        [string]$PwshDir,

        [Parameter(Mandatory)]
        [string[]]$ModuleScripts
    )

    $localEnvPath = [System.IO.Path]::Combine($HOME, ".config\dotfiles\local.env")
    $localPs1Path = [System.IO.Path]::Combine($HOME, ".config\dotfiles\local.ps1")
    $lazyCmdsPath = [System.IO.Path]::Combine($PwshDir, "lazy-commands.ps1")
    $builderPath = [System.IO.Path]::Combine($PwshDir, "cache-builder.ps1")
    $loaderPath = [System.IO.Path]::Combine($PwshDir, "00-profile-loader.ps1")
    $starshipConfigPath = if ($env:STARSHIP_CONFIG) {
        $env:STARSHIP_CONFIG
    } else {
        [System.IO.Path]::Combine($HOME, ".config\starship.toml")
    }

    $trackedFiles = [System.Collections.Generic.List[string]]::new()
    foreach ($s in $ModuleScripts) {
        $trackedFiles.Add($s)
    }
    foreach ($extra in @($loaderPath, $builderPath, $lazyCmdsPath, $localEnvPath, $localPs1Path, $starshipConfigPath, $global:__dotfiles_starship_bin, $global:__dotfiles_zoxide_bin, $global:__dotfiles_fnm_bin)) {
        if ($extra -and (-not $trackedFiles.Contains($extra))) {
            $trackedFiles.Add($extra)
        }
    }

    $out = [System.Text.StringBuilder]::new(32768)
    $escapedPwshDir = $PwshDir.Replace("'", "''")
    $dirTicks = [System.IO.Directory]::GetLastWriteTimeUtc($PwshDir).Ticks
    [void]$out.AppendLine("if (")
    [void]$out.Append("    ([System.IO.Directory]::GetLastWriteTimeUtc('$escapedPwshDir').Ticks -ne ${dirTicks}L)")

    foreach ($filePath in $trackedFiles) {
        $escapedFile = $filePath.Replace("'", "''")
        $fileTicks = [System.IO.File]::GetLastWriteTimeUtc($filePath).Ticks
        [void]$out.AppendLine(" -or")
        [void]$out.Append("    ([System.IO.File]::GetLastWriteTimeUtc('$escapedFile').Ticks -ne ${fileTicks}L)")
    }
    [void]$out.AppendLine("")
    [void]$out.AppendLine(") { return }")
    [void]$out.AppendLine('$global:__dotfiles_profile_cache_ok = $true')

    foreach ($scriptPath in $ModuleScripts) {
        $fileName = [System.IO.Path]::GetFileName($scriptPath)
        switch -Exact ($fileName) {
            "00-env.ps1" {
                $envScript = [System.IO.File]::ReadAllText($scriptPath)
                if (-not [System.IO.File]::Exists($localEnvPath)) {
                    $envScript = $envScript.Replace(
                        'Import-DotfilesEnvFile -Path ([System.IO.Path]::Combine($HOME, ".config\dotfiles\local.env"))',
                        ''
                    )
                }
                [void]$out.AppendLine($envScript)
            }
            "20-tools.ps1" {
                if ($global:__dotfiles_starship_cache -and [System.IO.File]::Exists($global:__dotfiles_starship_cache)) {
                    [void]$out.AppendLine([System.IO.File]::ReadAllText($global:__dotfiles_starship_cache))
                }
                if ($global:__dotfiles_zoxide_cache -and [System.IO.File]::Exists($global:__dotfiles_zoxide_cache)) {
                    [void]$out.AppendLine('Remove-Variable -Scope Global -Name __zoxide_hooked -ErrorAction SilentlyContinue')
                    [void]$out.AppendLine([System.IO.File]::ReadAllText($global:__dotfiles_zoxide_cache))
                }
            }
            "50-fnm.ps1" {
                if ($global:__dotfiles_fnm_bin) {
                    $escBin = $global:__dotfiles_fnm_bin.Replace("'", "''")
                    $escAlias = if ($global:__dotfiles_fnm_default_alias) { $global:__dotfiles_fnm_default_alias.Replace("'", "''") } else { "" }
                    $escDir = if ($global:__dotfiles_fnm_dir_resolved) { $global:__dotfiles_fnm_dir_resolved.Replace("'", "''") } else { "" }
                    [void]$out.AppendLine('$global:__dotfiles_fnm_precached = $true')
                    [void]$out.AppendLine("`$global:__dotfiles_fnm_bin = '$escBin'")
                    [void]$out.AppendLine("`$global:__dotfiles_fnm_default_alias = '$escAlias'")
                    [void]$out.AppendLine("`$global:__dotfiles_fnm_dir_resolved = '$escDir'")
                    [void]$out.AppendLine([System.IO.File]::ReadAllText($scriptPath))
                }
            }
            "90-local.ps1" {
                # Handled after compacting built-in sections so multi-line strings
                # in local.ps1 are preserved verbatim.
            }
            default {
                [void]$out.AppendLine([System.IO.File]::ReadAllText($scriptPath))
            }
        }
    }

    $compactLines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in ($out.ToString() -split "\r?\n")) {
        $trimmed = $line.Trim()
        if ($trimmed -and (-not $trimmed.StartsWith("#", [System.StringComparison]::Ordinal))) {
            $compactLines.Add($line)
        }
    }
    if ([System.IO.File]::Exists($localPs1Path)) {
        $compactLines.Add((ConvertTo-DotfilesStaticLocalScript -LocalPs1Path $localPs1Path))
    }
    $finalContent = [string]::Join([Environment]::NewLine, $compactLines)

    try {
        $cacheDir = [System.IO.Path]::GetDirectoryName($CachePath)
        if ($cacheDir -and (-not [System.IO.Directory]::Exists($cacheDir))) {
            [void][System.IO.Directory]::CreateDirectory($cacheDir)
        }
        $tempPath = "$CachePath.$PID.tmp"
        try {
            [System.IO.File]::WriteAllText($tempPath, $finalContent, [System.Text.UTF8Encoding]::new($true))
            if ($PSVersionTable.PSVersion.Major -ge 6) {
                [System.IO.File]::Move($tempPath, $CachePath, $true)
            } else {
                if ([System.IO.File]::Exists($CachePath)) {
                    [System.IO.File]::Delete($CachePath)
                }
                [System.IO.File]::Move($tempPath, $CachePath)
            }
        } finally {
            if ([System.IO.File]::Exists($tempPath)) {
                try { [System.IO.File]::Delete($tempPath) } catch {}
            }
        }
    } catch {}
}
