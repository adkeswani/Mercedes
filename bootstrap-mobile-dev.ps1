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

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
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

function Invoke-WingetInstall {
    param(
        [Parameter(Mandatory)]$Package,
        [bool]$UseConfiguredVersion
    )

    $wingetArgs = @(
        'install',
        '--id', $Package.id,
        '--exact',
        '--accept-source-agreements',
        '--accept-package-agreements',
        '--disable-interactivity'
    )

    if ($UseConfiguredVersion -and $Package.version) {
        $wingetArgs += @('--version', $Package.version)
    }

    Write-Host "winget $($wingetArgs -join ' ')" -ForegroundColor DarkGray
    & winget @wingetArgs
}

function Get-WingetInstalledVersion {
    param([Parameter(Mandatory)][string]$Id)

    $out = & winget list --id $Id --exact --source winget 2>$null
    if (-not $out) {
        return $null
    }

    foreach ($line in $out) {
        if ($line -match '^-+$') { continue }
        if ($line -match [regex]::Escape($Id)) {
            $tokens = ($line -replace '\s{2,}', '|').Split('|')
            if ($tokens.Length -ge 3) {
                return $tokens[2].Trim()
            }
        }
    }
    return $null
}

function Get-ToolVersion {
    param(
        [string]$Name,
        [string]$Command,
        [string]$Pattern
    )

    try {
        $output = Invoke-Expression $Command 2>$null
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
}

function Ensure-PathContains {
    param([string]$PathToAdd)
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($userPath -notlike "*$PathToAdd*") {
        [Environment]::SetEnvironmentVariable('Path', "$userPath;$PathToAdd", 'User')
        Write-Host "Added to user PATH: $PathToAdd" -ForegroundColor Yellow
    }
}

function Install-NpmGlobal {
    param(
        [string]$Package,
        [string]$Version
    )

    if ($Version) {
        & npm install -g "$Package@$Version"
    }
    else {
        & npm install -g $Package
    }
}

function Activate-DartGlobal {
    param(
        [string]$Package,
        [string]$Version
    )

    if ($Version) {
        & dart pub global activate $Package $Version
    }
    else {
        & dart pub global activate $Package
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
        $lines += "- $($pkg.id): $($pkg.installedVersion)"
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
            [PSCustomObject]@{ id = 'OpenJS.NodeJS.LTS'; version = '22.14.0' },
            [PSCustomObject]@{ id = 'Flutter.Flutter'; version = '3.29.0' }
        );
        npmGlobals = @(
            [PSCustomObject]@{ name = 'firebase-tools'; version = '13.35.1' }
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
        return [PSCustomObject]@{
            wingetPackages = $lock.wingetPackages
            npmGlobals = $lock.npmGlobals
            dartGlobals = $lock.dartGlobals
        }
    }

    return [PSCustomObject]@{
        wingetPackages = $Config.wingetPackages
        npmGlobals = $Config.npmGlobals
        dartGlobals = $Config.dartGlobals
    }
}

function Save-LockFile {
    param(
        [Parameter(Mandatory)]$InstalledWinget,
        [Parameter(Mandatory)]$InstalledNpm,
        [Parameter(Mandatory)]$InstalledDart
    )

    $lock = [PSCustomObject]@{
        generatedAt = (Get-Date -Format o)
        wingetPackages = $InstalledWinget
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

    & flutter doctor -v
}

function Accept-AndroidLicenses {
    Write-Section 'Accepting Android SDK licenses'
    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        Write-Host 'flutter command not found yet; skipping Android license acceptance.' -ForegroundColor Yellow
        return
    }

    $answers = 1..40 | ForEach-Object { 'y' }
    $answers | & flutter doctor --android-licenses
}

function Invoke-InstallOrUpdate {
    param([string]$Mode)

    Write-Section "Preparing ($Mode)"
    Ensure-Admin
    Ensure-Command -Name winget -InstallHint 'Install App Installer from Microsoft Store to get winget.'

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
        $installedWinget += [PSCustomObject]@{ id = $pkg.id; installedVersion = $installedVersion }
    }

    Write-Section 'Ensuring PATH for Dart global executables'
    Ensure-PathContains -PathToAdd "$env:USERPROFILE\AppData\Local\Pub\Cache\bin"

    Write-Section 'Installing global npm packages'
    $installedNpm = @()
    foreach ($pkg in $desired.npmGlobals) {
        $targetVersion = if ($Mode -eq 'update') { $null } else { $pkg.version }
        Install-NpmGlobal -Package $pkg.name -Version $targetVersion
        $v = (& npm list -g --depth=0 $pkg.name | Out-String)
        $match = [regex]::Match($v, "$($pkg.name)@(?<v>[0-9\.]+)")
        $installedNpm += [PSCustomObject]@{ name = $pkg.name; installedVersion = $(if ($match.Success) { $match.Groups['v'].Value } else { $null }) }
    }

    Write-Section 'Installing global Dart packages'
    $installedDart = @()
    foreach ($pkg in $desired.dartGlobals) {
        $targetVersion = if ($Mode -eq 'update') { $null } else { $pkg.version }
        Activate-DartGlobal -Package $pkg.name -Version $targetVersion
        $d = (& dart pub global list | Out-String)
        $match = [regex]::Match($d, "$($pkg.name)\s+(?<v>[0-9\.]+)")
        $installedDart += [PSCustomObject]@{ name = $pkg.name; installedVersion = $(if ($match.Success) { $match.Groups['v'].Value } else { $null }) }
    }

    Write-Section 'Installing VS Code extensions'
    if (Get-Command code -ErrorAction SilentlyContinue) {
        Ensure-VSCodeExtensions
    }

    Accept-AndroidLicenses
    Invoke-FlutterDoctor

    Write-Section 'Saving lock + version report'
    Save-LockFile -InstalledWinget $installedWinget -InstalledNpm $installedNpm -InstalledDart $installedDart

    $detected = Collect-ToolVersions
    Build-VersionReport -Detected $detected -InstalledPackages $installedWinget -Mode $Mode

    Write-Host "`nDone. See:" -ForegroundColor Green
    Write-Host "- $LockPath"
    Write-Host "- $VersionReportPath"
    Write-Host "- $LogPath"
}

function Invoke-Verify {
    Write-Section 'Verifying installed tools'
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
