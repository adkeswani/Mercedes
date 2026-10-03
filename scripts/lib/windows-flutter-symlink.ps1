Set-StrictMode -Version Latest

$script:WindowsDeveloperModeInstruction = (
    'Open Windows Settings > System > Advanced > For developers, then turn ' +
    'on Developer Mode. Settings command: start ms-settings:developers'
)

function Test-FlutterProjectRequiresPluginSymlinks {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectPath
    )

    $lockPath = Join-Path $ProjectPath 'pubspec.lock'
    if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) {
        return $false
    }

    $lockContent = Get-Content -LiteralPath $lockPath -Raw
    return $lockContent -match (
        '(?m)^  [a-z0-9_]+_(?:android|ios|linux|macos|web|windows):\s*$'
    )
}

function Test-WindowsSymlinkCapability {
    param(
        [string]$TempRoot = [IO.Path]::GetTempPath(),

        [scriptblock]$CreateSymbolicLink = {
            param($LinkPath, $TargetPath)
            New-Item `
                -ItemType SymbolicLink `
                -Path $LinkPath `
                -Target $TargetPath `
                -ErrorAction Stop |
                Out-Null
        },

        [scriptblock]$ValidateSymbolicLink = {
            param($LinkPath, $ExpectedContent)
            $link = Get-Item `
                -LiteralPath $LinkPath `
                -Force `
                -ErrorAction Stop
            $isReparsePoint =
                ($link.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
            $linkedContent = Get-Content -LiteralPath $LinkPath -Raw
            return $isReparsePoint -and $linkedContent -eq $ExpectedContent
        },

        [AllowNull()]
        [Nullable[bool]]$IsWindowsOverride = $null
    )

    $platformIsWindows = if ($null -ne $IsWindowsOverride) {
        [bool]$IsWindowsOverride
    } else {
        [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    }
    if (-not $platformIsWindows) {
        return [pscustomobject]@{
            Applicable = $false
            Ready = $true
            Problem = $null
        }
    }

    $probePath = Join-Path $TempRoot (
        'mercedes-flutter-symlink-' + [Guid]::NewGuid().ToString('N')
    )
    $targetPath = Join-Path $probePath 'target.txt'
    $linkPath = Join-Path $probePath 'link.txt'
    $token = [Guid]::NewGuid().ToString('N')

    try {
        [IO.Directory]::CreateDirectory($probePath) | Out-Null
        [IO.File]::WriteAllText($targetPath, $token)
        & $CreateSymbolicLink $linkPath $targetPath

        if (-not (& $ValidateSymbolicLink $linkPath $token)) {
            throw 'The probe did not create a working symbolic link.'
        }

        return [pscustomobject]@{
            Applicable = $true
            Ready = $true
            Problem = $null
        }
    }
    catch {
        return [pscustomobject]@{
            Applicable = $true
            Ready = $false
            Problem = (
                'Windows cannot create the non-elevated symbolic links ' +
                "required by Flutter plugins. $($_.Exception.Message) " +
                $script:WindowsDeveloperModeInstruction
            )
        }
    }
    finally {
        if (Test-Path -LiteralPath $probePath) {
            Remove-Item -LiteralPath $probePath -Recurse -Force
        }
    }
}
