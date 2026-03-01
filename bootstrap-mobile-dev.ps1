param(
    [ValidateSet('install', 'update', 'verify', 'report')]
    [string]$Command = 'install'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $RepoRoot 'tooling-config.json'
$LockPath = Join-Path $RepoRoot 'tooling-lock.json'
$VersionReportPath = Join-Path $RepoRoot 'tooling-versions.md'
$LogDir = Join-Path $RepoRoot 'logs'
$LogPath = Join-Path $LogDir "bootstrap-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$RawLogPath = Join-Path $LogDir "bootstrap-raw-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Set-Content -Path $RawLogPath -Value "Raw command log started: $(Get-Date -Format o)" -Encoding UTF8
Start-Transcript -Path $LogPath | Out-Null

function Write-Section {
    param([string]$Message)
    Write-Host "`n=== $Message ===" -ForegroundColor Cyan
}

function Ensure-Admin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this script in an elevated PowerShell terminal (Run as Administrator).'
    }
}

function Ensure-Command {
    param([string]$Name, [string]$InstallHint)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Missing required command '$Name'. $InstallHint"
    }
}

function Read-Json {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        return $null
    }
    return Get-Content -Path $Path -Raw | ConvertFrom-Json
}

function Write-Json {
    param(
        [string]$Path,
        [Parameter(Mandatory)]$Object
    )
    $json = $Object | ConvertTo-Json -Depth 20
    Set-Content -Path $Path -Value $json -Encoding UTF8
}

function Write-RawLog {
    param([string]$Text)

    if ($null -eq $Text) {
        return
    }

    Add-Content -Path $RawLogPath -Value $Text
}

function Invoke-NativeWithLogging {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [switch]$AllowNonZeroExit
    )

    Write-RawLog "`n$FilePath $($Arguments -join ' ')"

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $FilePath @Arguments 2>&1
        foreach ($line in @($output)) {
            $text = [string]$line
            Write-Host $text
            Write-RawLog $text
        }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    $exitCode = $LASTEXITCODE
    if (-not $AllowNonZeroExit -and $exitCode -ne 0) {
        throw "Command failed: $FilePath $($Arguments -join ' ') (exit code $exitCode)"
    }

    return [PSCustomObject]@{
        ExitCode = $exitCode
        Output = @($output)
    }
}

function Invoke-WingetInstall {
    param(
        [Parameter(Mandatory)]$Package,
        [bool]$UseConfiguredVersion
    )

    $existingVersion = Get-WingetInstalledVersion -Id $Package.id
    if ($UseConfiguredVersion -and $existingVersion) {
        if ($Package.version -and $existingVersion -ne $Package.version) {
            Write-Host "$($Package.id) version '$existingVersion' is already installed (requested '$($Package.version)'). Skipping reinstall in install mode." -ForegroundColor Yellow
        }
        else {
            Write-Host "$($Package.id) version '$existingVersion' is already installed. Skipping." -ForegroundColor Yellow
        }
        return
    }

    $baseArgs = @(
        'install',
        '--id', $Package.id,
        '--exact',
        '--accept-source-agreements',
        '--accept-package-agreements',
        '--disable-interactivity'
    )

    $wingetArgs = @($baseArgs)
    if ($UseConfiguredVersion -and $Package.version) {
        $wingetArgs += @('--version', $Package.version)
    }

    Write-Host "winget $($wingetArgs -join ' ')" -ForegroundColor DarkGray
    & winget @wingetArgs
    $firstExit = $LASTEXITCODE

    if ($firstExit -ne 0 -and $UseConfiguredVersion -and $Package.version) {
        Write-Host "Pinned version '$($Package.version)' unavailable for $($Package.id); retrying latest available version." -ForegroundColor Yellow
        Write-Host "winget $($baseArgs -join ' ')" -ForegroundColor DarkGray
        & winget @baseArgs
        $firstExit = $LASTEXITCODE
    }

    if ($firstExit -ne 0) {
        $existingVersion = Get-WingetInstalledVersion -Id $Package.id
        if ($existingVersion) {
            Write-Host "winget returned exit code $firstExit for $($Package.id), but version '$existingVersion' is already installed. Continuing." -ForegroundColor Yellow
            return
        }

        throw "winget install failed for '$($Package.id)' (exit code $firstExit)."
    }
}

function Get-WingetInstalledVersion {
    param([Parameter(Mandatory)][string]$Id)

    $out = & winget list --id $Id --exact 2>$null
    if (-not $out) {
        return $null
    }

    $idPattern = [regex]::Escape($Id)
    foreach ($line in $out) {
        if ($line -match '^-+$') { continue }
        $match = [regex]::Match($line, "$idPattern\s+(?<v>\S+)")
        if ($match.Success) {
            return $match.Groups['v'].Value.Trim()
        }
    }
    return $null
}

function Test-WingetPackageInstalled {
    param([Parameter(Mandatory)][string]$Id)

    $out = & winget list --id $Id --exact 2>$null
    if (-not $out) {
        return $false
    }

    $joined = ($out | Out-String)
    return ($joined -match [regex]::Escape($Id))
}
function Get-ToolVersion {
    param(
        [string]$Name,
        [string]$Command,
        [string]$Pattern
    )

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = Invoke-Expression $Command 2>&1
        if (-not $output) {
            return [PSCustomObject]@{ name = $Name; version = $null; raw = $null }
        }

        $raw = ($output | Out-String).Trim()
        $match = [regex]::Match($raw, $Pattern)
        $version = if ($match.Success) { $match.Groups['v'].Value } else { $raw.Split("`n")[0] }

        return [PSCustomObject]@{ name = $Name; version = $version; raw = $raw }
    }
    catch {
        return [PSCustomObject]@{ name = $Name; version = $null; raw = $null }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}

function Ensure-PathContains {
    param([string]$PathToAdd)
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($userPath -notlike "*$PathToAdd*") {
        [Environment]::SetEnvironmentVariable('Path', "$userPath;$PathToAdd", 'User')
        Write-Host "Added to user PATH: $PathToAdd" -ForegroundColor Yellow
    }
}

function Ensure-ProcessPathContains {
    param([string]$PathToAdd)

    $parts = $env:Path -split ';'
    if ($parts -notcontains $PathToAdd) {
        $env:Path = "$PathToAdd;$env:Path"
    }
}

function Ensure-JavaOnPath {
    if (Get-Command java -ErrorAction SilentlyContinue) {
        return
    }

    $candidates = @(
        "$env:ProgramFiles\Android\Android Studio\jbr\bin",
        "$env:ProgramFiles\Android\Android Studio\jre\bin"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path (Join-Path $candidate 'java.exe')) {
            Ensure-PathContains -PathToAdd $candidate
            Ensure-ProcessPathContains -PathToAdd $candidate
            Write-Host "Using Android Studio bundled Java from: $candidate" -ForegroundColor Yellow
            return
        }
    }
}

function Resolve-AndroidSdkPath {
    $candidates = @(
        $env:ANDROID_SDK_ROOT,
        $env:ANDROID_HOME,
        (Join-Path $env:LOCALAPPDATA 'Android\Sdk'),
        (Join-Path $env:ProgramFiles 'Android\Sdk')
    ) | Where-Object { $_ }

    foreach ($candidate in $candidates) {
        $expanded = [Environment]::ExpandEnvironmentVariables($candidate)
        if (Test-Path $expanded) {
            return $expanded
        }
    }

    return $null
}

function Get-FlutterAndroidRequirements {
    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        return $null
    }

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & flutter doctor -v 2>&1
        $raw = ($output | Out-String)

        $sdkMatch = [regex]::Match($raw, 'Flutter requires Android SDK\s+(?<sdk>\d+)')
        $buildToolsMatch = [regex]::Match($raw, 'Android BuildTools\s+(?<bt>[0-9\.]+)')

        if (-not $sdkMatch.Success -and -not $buildToolsMatch.Success) {
            return $null
        }

        return [PSCustomObject]@{
            sdkPlatform = $(if ($sdkMatch.Success) { $sdkMatch.Groups['sdk'].Value } else { $null })
            buildTools = $(if ($buildToolsMatch.Success) { $buildToolsMatch.Groups['bt'].Value } else { $null })
        }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}

function Write-AndroidSdkManualInstructions {
    param(
        [bool]$SdkPathFound = $false,
        [string]$RequiredSdkPlatform,
        [string]$RequiredBuildTools
    )

    if ($SdkPathFound) {
        Write-Host 'Android SDK components are incomplete.' -ForegroundColor Yellow
    }
    else {
        Write-Host 'Android SDK was not detected on this machine.' -ForegroundColor Yellow
    }
    Write-Host 'Note: the default Android Studio install commonly does NOT include Android SDK Command-line Tools.' -ForegroundColor Yellow
    if ($RequiredSdkPlatform) {
        Write-Host "Flutter Doctor requires Android SDK Platform $RequiredSdkPlatform." -ForegroundColor Yellow
    }
    if ($RequiredBuildTools) {
        Write-Host "Flutter Doctor requires Android SDK Build-Tools $RequiredBuildTools." -ForegroundColor Yellow
    }
    Write-Host 'Manual setup required:' -ForegroundColor Yellow
    Write-Host '  1) Open Android Studio' -ForegroundColor Yellow
    Write-Host '  2) Go to Settings > Languages & Frameworks > Android SDK' -ForegroundColor Yellow
    if ($RequiredSdkPlatform) {
        Write-Host "  3) In SDK Platforms, install Android SDK Platform $RequiredSdkPlatform" -ForegroundColor Yellow
    }
    else {
        Write-Host '  3) In SDK Platforms, install the Android SDK Platform version requested by Flutter Doctor' -ForegroundColor Yellow
    }
    Write-Host '  4) In SDK Tools, check:' -ForegroundColor Yellow
    Write-Host '     - Android SDK Platform-Tools' -ForegroundColor Yellow
    Write-Host '     - Android SDK Command-line Tools (latest)' -ForegroundColor Yellow
    if ($RequiredBuildTools) {
        Write-Host "     - Android SDK Build-Tools $RequiredBuildTools" -ForegroundColor Yellow
    }
    else {
        Write-Host '     - Android SDK Build-Tools (version requested by Flutter Doctor)' -ForegroundColor Yellow
    }
    Write-Host '     (Enable "Show Package Details" if needed to see specific versions.)' -ForegroundColor Yellow
    Write-Host '  5) Apply changes and close Android Studio' -ForegroundColor Yellow
    Write-Host '  6) Re-run: .\bootstrap-mobile-dev.ps1 -Command update' -ForegroundColor Yellow
}

function Ensure-AndroidSdkConfigured {
    $requirements = Get-FlutterAndroidRequirements
    $requiredSdkPlatform = $null
    $requiredBuildTools = $null
    if ($requirements) {
        $requiredSdkPlatform = $requirements.sdkPlatform
        $requiredBuildTools = $requirements.buildTools
    }

    $sdkPath = Resolve-AndroidSdkPath
    if (-not $sdkPath) {
        Write-AndroidSdkManualInstructions -SdkPathFound:$false -RequiredSdkPlatform $requiredSdkPlatform -RequiredBuildTools $requiredBuildTools
        return
    }

    $platformToolsAdb = Join-Path $sdkPath 'platform-tools\adb.exe'
    $sdkManagerBat = Join-Path $sdkPath 'cmdline-tools\latest\bin\sdkmanager.bat'
    if (-not (Test-Path $platformToolsAdb) -or -not (Test-Path $sdkManagerBat)) {
        Write-Host "Android SDK path found at '$sdkPath' but required components are missing." -ForegroundColor Yellow
        Write-AndroidSdkManualInstructions -SdkPathFound:$true -RequiredSdkPlatform $requiredSdkPlatform -RequiredBuildTools $requiredBuildTools
        return
    }

    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        return
    }

    Ensure-PathContains -PathToAdd (Join-Path $sdkPath 'platform-tools')
    Ensure-ProcessPathContains -PathToAdd (Join-Path $sdkPath 'platform-tools')

    $cmdlineLatest = Join-Path $sdkPath 'cmdline-tools\latest\bin'
    if (Test-Path $cmdlineLatest) {
        Ensure-PathContains -PathToAdd $cmdlineLatest
        Ensure-ProcessPathContains -PathToAdd $cmdlineLatest
    }

    $result = Invoke-NativeWithLogging -FilePath 'flutter' -Arguments @('config', '--android-sdk', $sdkPath) -AllowNonZeroExit
    if ($result.ExitCode -eq 0) {
        Write-Host "Configured Flutter Android SDK path: $sdkPath" -ForegroundColor Yellow
    }
    else {
        Write-Host "Failed to configure Flutter Android SDK path automatically (exit code $($result.ExitCode))." -ForegroundColor Yellow
    }
}

function Resolve-InstallPath {
    param([string]$InputPath)

    if (-not $InputPath) {
        return Join-Path $env:USERPROFILE 'development\flutter'
    }

    return [Environment]::ExpandEnvironmentVariables($InputPath)
}

function Install-FlutterSdk {
    param(
        [Parameter(Mandatory)]$FlutterConfig,
        [string]$Mode
    )

    Ensure-Command -Name git -InstallHint 'Git is required to install Flutter SDK from source control.'

    $installPath = Resolve-InstallPath -InputPath $FlutterConfig.installPath
    $binPath = Join-Path $installPath 'bin'

    if (-not (Test-Path $installPath)) {
        Write-Section "Installing Flutter SDK to $installPath"
        New-Item -ItemType Directory -Path (Split-Path -Parent $installPath) -Force | Out-Null
        $cloneResult = Invoke-NativeWithLogging -FilePath 'git' -Arguments @('clone', 'https://github.com/flutter/flutter.git', $installPath, '--branch', 'stable') -AllowNonZeroExit
        if ($cloneResult.ExitCode -ne 0) {
            throw 'Failed to clone Flutter SDK repository.'
        }
    }

    Push-Location $installPath
    try {
        $status = & git status --porcelain
        if ($status) {
            Write-Host 'Flutter SDK repository has local changes; resetting generated files before version switch.' -ForegroundColor Yellow
            $resetResult = Invoke-NativeWithLogging -FilePath 'git' -Arguments @('reset', '--hard', 'HEAD') -AllowNonZeroExit
            if ($resetResult.ExitCode -ne 0) {
                throw 'Failed to reset Flutter SDK repository state.'
            }
            $cleanResult = Invoke-NativeWithLogging -FilePath 'git' -Arguments @('clean', '-fd') -AllowNonZeroExit
            if ($cleanResult.ExitCode -ne 0) {
                throw 'Failed to clean Flutter SDK repository state.'
            }
        }

        $fetchResult = Invoke-NativeWithLogging -FilePath 'git' -Arguments @('fetch', '--tags', '--force') -AllowNonZeroExit
        if ($fetchResult.ExitCode -ne 0) {
            throw 'Failed to fetch Flutter SDK tags.'
        }

        if ($Mode -eq 'install' -and $FlutterConfig.version) {
            $checkoutTagResult = Invoke-NativeWithLogging -FilePath 'git' -Arguments @('checkout', $FlutterConfig.version) -AllowNonZeroExit
            if ($checkoutTagResult.ExitCode -ne 0) {
                throw "Failed to checkout Flutter version '$($FlutterConfig.version)'."
            }
        }
        elseif ($Mode -eq 'update') {
            $checkoutStableResult = Invoke-NativeWithLogging -FilePath 'git' -Arguments @('checkout', 'stable') -AllowNonZeroExit
            if ($checkoutStableResult.ExitCode -ne 0) {
                throw 'Failed to switch Flutter SDK to stable branch.'
            }
            $pullResult = Invoke-NativeWithLogging -FilePath 'git' -Arguments @('pull', '--ff-only') -AllowNonZeroExit
            if ($pullResult.ExitCode -ne 0) {
                throw 'Failed to update Flutter SDK stable branch.'
            }
        }
    }
    finally {
        Pop-Location
    }

    Ensure-PathContains -PathToAdd $binPath
    Ensure-ProcessPathContains -PathToAdd $binPath

    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        throw "Flutter executable was not found after installation. Expected in '$binPath'."
    }

    return [PSCustomObject]@{
        version = (Get-ToolVersion -Name 'flutter' -Command 'flutter --version' -Pattern 'Flutter\s+(?<v>[0-9\.]+)').version
        installPath = $installPath
    }
}

function Install-NpmGlobal {
    param(
        [string]$Package,
        [string]$Version
    )

    if ($Version) {
        $result = Invoke-NativeWithLogging -FilePath 'npm' -Arguments @('install', '-g', "$Package@$Version") -AllowNonZeroExit
    }
    else {
        $result = Invoke-NativeWithLogging -FilePath 'npm' -Arguments @('install', '-g', $Package) -AllowNonZeroExit
    }

    if ($result.ExitCode -ne 0) {
        throw "npm global install failed for '$Package' (exit code $($result.ExitCode))."
    }
}

function Activate-DartGlobal {
    param(
        [string]$Package,
        [string]$Version
    )

    if ($Version) {
        $result = Invoke-NativeWithLogging -FilePath 'dart' -Arguments @('pub', 'global', 'activate', $Package, $Version) -AllowNonZeroExit
    }
    else {
        $result = Invoke-NativeWithLogging -FilePath 'dart' -Arguments @('pub', 'global', 'activate', $Package) -AllowNonZeroExit
    }

    if ($result.ExitCode -ne 0) {
        throw "dart global activate failed for '$Package' (exit code $($result.ExitCode))."
    }
}

function Build-VersionReport {
    param(
        [Parameter(Mandatory)]$Detected,
        [Parameter(Mandatory)]$InstalledPackages,
        [string]$Mode
    )

    $lines = @(
        "# Mobile Tooling Version Report",
        "",
        "Generated: $(Get-Date -Format o)",
        "Mode: $Mode",
        "",
        "## Winget Packages",
        ""
    )

    foreach ($pkg in $InstalledPackages) {
        $lines += "- $($pkg.id): $($pkg.version)"
    }

    $lines += ""
    $lines += "## CLI Tools"
    $lines += ""
    foreach ($tool in $Detected) {
        $lines += "- $($tool.name): $($tool.version)"
    }

    $lines += ""
    $lines += "Log: $LogPath"

    Set-Content -Path $VersionReportPath -Value ($lines -join "`r`n") -Encoding UTF8
}

function Load-Config {
    $default = [PSCustomObject]@{
        wingetPackages = @(
            [PSCustomObject]@{ id = 'Git.Git'; version = '2.51.0' },
            [PSCustomObject]@{ id = 'Google.AndroidStudio'; version = '2024.3.2.15' },
            [PSCustomObject]@{ id = 'Microsoft.VisualStudioCode'; version = '1.99.3' },
            [PSCustomObject]@{ id = 'OpenJS.NodeJS.LTS'; version = '24.14.0' }
        );
        flutterSdk = [PSCustomObject]@{ version = '3.29.0'; installPath = '%USERPROFILE%\development\flutter' };
        npmGlobals = @(
            [PSCustomObject]@{ name = 'firebase-tools'; version = '15.8.0' }
        );
        dartGlobals = @(
            [PSCustomObject]@{ name = 'flutterfire_cli'; version = '1.2.0' }
        )
    }

    if (-not (Test-Path $ConfigPath)) {
        Write-Json -Path $ConfigPath -Object $default
    }

    return Read-Json -Path $ConfigPath
}

function Get-CurrentLock {
    if (Test-Path $LockPath) {
        return Read-Json -Path $LockPath
    }
    return $null
}

function Resolve-DesiredVersions {
    param(
        [Parameter(Mandatory)]$Config,
        [string]$Mode
    )

    $lock = Get-CurrentLock

    if ($Mode -eq 'install' -and $lock) {
        $lockWinget = @()
        if ($lock.wingetPackages) {
            $lockWinget = @($lock.wingetPackages | ForEach-Object {
                [PSCustomObject]@{
                    id = $_.id
                    version = $(if ($_.version) { $_.version } else { $_.installedVersion })
                }
            })
        }

        $lockNpm = @()
        if ($lock.npmGlobals) {
            $lockNpm = @($lock.npmGlobals | ForEach-Object {
                [PSCustomObject]@{
                    name = $_.name
                    version = $(if ($_.version) { $_.version } else { $_.installedVersion })
                }
            })
        }

        $lockDart = @()
        if ($lock.dartGlobals) {
            $lockDart = @($lock.dartGlobals | ForEach-Object {
                [PSCustomObject]@{
                    name = $_.name
                    version = $(if ($_.version) { $_.version } else { $_.installedVersion })
                }
            })
        }

        $lockFlutter = $null
        if ($lock.flutterSdk) {
            if ($lock.flutterSdk -is [System.Array]) {
                $flutterCandidates = @($lock.flutterSdk | Where-Object { $_ -is [PSCustomObject] -and $_.version })
                if ($flutterCandidates.Count -gt 0) {
                    $lockFlutter = $flutterCandidates[-1]
                }
            }
            elseif ($lock.flutterSdk.version) {
                $lockFlutter = $lock.flutterSdk
            }
        }

        if (-not $lockFlutter) {
            $lockFlutter = $config.flutterSdk
        }
        else {
            if (-not $lockFlutter.installPath) {
                $lockFlutter = [PSCustomObject]@{
                    version = $lockFlutter.version
                    installPath = $config.flutterSdk.installPath
                }
            }
        }

        return [PSCustomObject]@{
            wingetPackages = $lockWinget
            flutterSdk = $lockFlutter
            npmGlobals = $lockNpm
            dartGlobals = $lockDart
        }
    }

    return [PSCustomObject]@{
        wingetPackages = $Config.wingetPackages
        flutterSdk = $Config.flutterSdk
        npmGlobals = $Config.npmGlobals
        dartGlobals = $Config.dartGlobals
    }
}

function Save-LockFile {
    param(
        [Parameter(Mandatory)]$InstalledWinget,
        [Parameter(Mandatory)]$InstalledFlutter,
        [Parameter(Mandatory)]$InstalledNpm,
        [Parameter(Mandatory)]$InstalledDart
    )

    $lock = [PSCustomObject]@{
        generatedAt = (Get-Date -Format o)
        wingetPackages = $InstalledWinget
        flutterSdk = $InstalledFlutter
        npmGlobals = $InstalledNpm
        dartGlobals = $InstalledDart
    }

    Write-Json -Path $LockPath -Object $lock
}

function Collect-ToolVersions {
    return @(
        (Get-ToolVersion -Name 'flutter' -Command 'flutter --version' -Pattern 'Flutter\s+(?<v>[0-9\.]+)'),
        (Get-ToolVersion -Name 'dart' -Command 'dart --version' -Pattern 'version:\s*(?<v>[0-9\.]+)'),
        (Get-ToolVersion -Name 'java' -Command 'java --version' -Pattern '(?<v>[0-9]+(?:\.[0-9]+){0,2})'),
        (Get-ToolVersion -Name 'adb' -Command 'adb version' -Pattern 'Version\s+(?<v>[0-9\.]+)'),
        (Get-ToolVersion -Name 'node' -Command 'node --version' -Pattern 'v(?<v>[0-9\.]+)'),
        (Get-ToolVersion -Name 'npm' -Command 'npm --version' -Pattern '(?<v>[0-9\.]+)'),
        (Get-ToolVersion -Name 'firebase' -Command 'firebase --version' -Pattern '(?<v>[0-9\.]+)'),
        (Get-ToolVersion -Name 'flutterfire' -Command 'flutterfire --version' -Pattern '(?<v>[0-9\.]+)'),
        (Get-ToolVersion -Name 'git' -Command 'git --version' -Pattern 'version\s+(?<v>[0-9\.]+)')
    )
}

function Ensure-VSCodeExtensions {
    $extensions = @('Dart-Code.dart-code', 'Dart-Code.flutter')
    foreach ($ext in $extensions) {
        & code --install-extension $ext --force | Out-Null
    }
}

function Invoke-FlutterDoctor {
    Write-Section 'Running flutter doctor'
    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        Write-Host 'flutter command not found yet; skipping flutter doctor.' -ForegroundColor Yellow
        return
    }

    $null = Invoke-NativeWithLogging -FilePath 'flutter' -Arguments @('doctor', '-v') -AllowNonZeroExit
}

function Accept-AndroidLicenses {
    Write-Section 'Accepting Android SDK licenses'
    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        Write-Host 'flutter command not found yet; skipping Android license acceptance.' -ForegroundColor Yellow
        return
    }

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        Write-RawLog "`nflutter doctor --android-licenses"
        $answers = 1..40 | ForEach-Object { 'y' }
        $licenseOutput = $answers | & flutter doctor --android-licenses 2>&1
        foreach ($line in @($licenseOutput)) {
            $text = [string]$line
            Write-Host $text
            Write-RawLog $text
        }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}

function Invoke-InstallOrUpdate {
    param([string]$Mode)

    Write-Section "Preparing ($Mode)"
    Ensure-Admin
    Ensure-Command -Name winget -InstallHint 'Install App Installer from Microsoft Store to get winget.'
    Ensure-JavaOnPath

    $config = Load-Config
    $desired = Resolve-DesiredVersions -Config $config -Mode $Mode

    $installedWinget = @()
    foreach ($pkg in $desired.wingetPackages) {
        Write-Section "Installing $($pkg.id)"
        $useConfiguredVersion = $true
        if ($Mode -eq 'update') {
            $useConfiguredVersion = $false
        }
        Invoke-WingetInstall -Package $pkg -UseConfiguredVersion:$useConfiguredVersion
        $installedVersion = Get-WingetInstalledVersion -Id $pkg.id
        $installedWinget += [PSCustomObject]@{ id = $pkg.id; version = $installedVersion }
    }

    $installedFlutter = Install-FlutterSdk -FlutterConfig $desired.flutterSdk -Mode $Mode
    Ensure-AndroidSdkConfigured

    Write-Section 'Ensuring PATH for Dart global executables'
    Ensure-PathContains -PathToAdd "$env:USERPROFILE\AppData\Local\Pub\Cache\bin"
    Ensure-ProcessPathContains -PathToAdd "$env:USERPROFILE\AppData\Local\Pub\Cache\bin"

    Ensure-Command -Name npm -InstallHint 'Node.js/npm is required for firebase-tools global install.'
    Ensure-Command -Name dart -InstallHint 'Dart (from Flutter SDK) is required for flutterfire_cli install.'

    Write-Section 'Installing global npm packages'
    $installedNpm = @()
    foreach ($pkg in $desired.npmGlobals) {
        $targetVersion = if ($Mode -eq 'update') { $null } else { $pkg.version }
        Install-NpmGlobal -Package $pkg.name -Version $targetVersion
        $listResult = Invoke-NativeWithLogging -FilePath 'npm' -Arguments @('list', '-g', '--depth=0', $pkg.name) -AllowNonZeroExit
        $v = ($listResult.Output | Out-String)
        $match = [regex]::Match($v, "$($pkg.name)@(?<v>[0-9\.]+)")
        $installedNpm += [PSCustomObject]@{ name = $pkg.name; version = $(if ($match.Success) { $match.Groups['v'].Value } else { $null }) }
    }

    Write-Section 'Installing global Dart packages'
    $installedDart = @()
    foreach ($pkg in $desired.dartGlobals) {
        $targetVersion = if ($Mode -eq 'update') { $null } else { $pkg.version }
        Activate-DartGlobal -Package $pkg.name -Version $targetVersion
        $dartListResult = Invoke-NativeWithLogging -FilePath 'dart' -Arguments @('pub', 'global', 'list') -AllowNonZeroExit
        $d = ($dartListResult.Output | Out-String)
        $match = [regex]::Match($d, "$($pkg.name)\s+(?<v>[0-9\.]+)")
        $installedDart += [PSCustomObject]@{ name = $pkg.name; version = $(if ($match.Success) { $match.Groups['v'].Value } else { $null }) }
    }

    Write-Section 'Installing VS Code extensions'
    if (Get-Command code -ErrorAction SilentlyContinue) {
        Ensure-VSCodeExtensions
    }

    Accept-AndroidLicenses
    Invoke-FlutterDoctor

    Write-Section 'Saving lock + version report'
    Save-LockFile -InstalledWinget $installedWinget -InstalledFlutter $installedFlutter -InstalledNpm $installedNpm -InstalledDart $installedDart

    $detected = Collect-ToolVersions
    Build-VersionReport -Detected $detected -InstalledPackages $installedWinget -Mode $Mode

    Write-Host "`nDone. See:" -ForegroundColor Green
    Write-Host "- $LockPath"
    Write-Host "- $VersionReportPath"
    Write-Host "- $LogPath"
    Write-Host "- $RawLogPath"
}

function Invoke-Verify {
    Write-Section 'Verifying installed tools'
    Ensure-JavaOnPath
    Ensure-AndroidSdkConfigured
    $detected = Collect-ToolVersions
    foreach ($tool in $detected) {
        $state = if ($tool.version) { $tool.version } else { 'NOT FOUND' }
        Write-Host ("{0,-14} {1}" -f $tool.name, $state)
    }
    $lock = Get-CurrentLock
    if ($lock) {
        Write-Host "`nLock file: $LockPath" -ForegroundColor Green
    }
    else {
        Write-Host "`nNo lock file found. Run install first." -ForegroundColor Yellow
    }
}

function Invoke-Report {
    Write-Section 'Generating fresh tooling report'
    Ensure-JavaOnPath
    Ensure-AndroidSdkConfigured
    $detected = Collect-ToolVersions
    $lock = Get-CurrentLock
    $winget = @()
    if ($lock -and $lock.wingetPackages) {
        $winget = $lock.wingetPackages
    }
    Build-VersionReport -Detected $detected -InstalledPackages $winget -Mode 'report'
    Write-Host "Wrote report to $VersionReportPath" -ForegroundColor Green
}

try {
    switch ($Command) {
        'install' { Invoke-InstallOrUpdate -Mode 'install' }
        'update' { Invoke-InstallOrUpdate -Mode 'update' }
        'verify' { Invoke-Verify }
        'report' { Invoke-Report }
    }
}
finally {
    Stop-Transcript | Out-Null
}
