# Shared PowerShell profile loader with whole-profile merged cache.

$private:dotfilesLocalAppData = if ($env:LOCALAPPDATA) {
    $env:LOCALAPPDATA
} else {
    $private:dir = [System.Environment]::GetFolderPath('LocalApplicationData')
    if ($private:dir) { $private:dir }
    elseif ($env:XDG_CACHE_HOME) { $env:XDG_CACHE_HOME }
    elseif ($HOME) { [System.IO.Path]::Combine($HOME, ".cache") }
    else { [System.IO.Path]::GetTempPath() }
}
$private:dotfilesProfileCachePath = [System.IO.Path]::Combine(
    $private:dotfilesLocalAppData,
    "dotfiles\profile.pwsh$($PSVersionTable.PSVersion.Major).cached.ps1"
)

if ($global:__dotfiles_profile_cache_miss) {
    $global:__dotfiles_profile_cache_miss = $false
    $global:__dotfiles_profile_cache_ok = $false
} else {
    $global:__dotfiles_profile_cache_ok = $false
    if ([System.IO.File]::Exists($private:dotfilesProfileCachePath)) {
        . $private:dotfilesProfileCachePath
    }
}

if (-not $global:__dotfiles_profile_cache_ok) {
    $private:dotfilesPwshDir = [System.IO.Path]::Combine($HOME, ".config\dotfiles\pwsh")
    if ([System.IO.Directory]::Exists($private:dotfilesPwshDir)) {
        $private:allScripts = [System.IO.Directory]::GetFiles($private:dotfilesPwshDir, "*.ps1")
        [System.Array]::Sort($private:allScripts, [System.StringComparer]::OrdinalIgnoreCase)
        $private:moduleScripts = [System.Collections.Generic.List[string]]::new()

        foreach ($private:scriptPath in $private:allScripts) {
            $private:scriptName = [System.IO.Path]::GetFileName($private:scriptPath)
            if (($private:scriptName -eq "00-profile-loader.ps1") -or
                ($private:scriptName -eq "lazy-commands.ps1") -or
                ($private:scriptName -eq "cache-builder.ps1")) {
                continue
            }
            if ($private:scriptName -match '^[0-9][0-9]-') {
                $private:moduleScripts.Add($private:scriptPath)
                . $private:scriptPath
            }
        }

        $private:builderPath = [System.IO.Path]::Combine($private:dotfilesPwshDir, "cache-builder.ps1")
        if ([System.IO.File]::Exists($private:builderPath)) {
            . $private:builderPath
            Build-DotfilesMergedProfileCache `
                -CachePath $private:dotfilesProfileCachePath `
                -PwshDir $private:dotfilesPwshDir `
                -ModuleScripts $private:moduleScripts.ToArray()
        }
    }
    $global:__dotfiles_profile_cache_ok = $true
}
