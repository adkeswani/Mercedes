param(
    [string]$AppDir = 'flutter_smoke_test',
    [string]$AvdName,
    [switch]$SkipPubGet,
    [ValidateSet('run', 'build-run', 'install-run')]
    [string]$Mode = 'run',
    [ValidateSet('debug', 'release')]
    [string]$BuildType = 'debug',
    [int]$BootTimeoutSeconds = 300
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$appPath = Join-Path $repoRoot $AppDir

if (-not (Test-Path $appPath)) {
    throw "App directory not found: $appPath"
}

function Resolve-Executable {
    param(
        [string]$CommandName,
        [string[]]$FallbackPaths = @()
    )

    foreach ($path in $FallbackPaths) {
        if (Test-Path $path) {
            return $path
        }
    }

    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    return $null
}

function Get-RunningEmulatorIds {
    param([string]$AdbExe)

    $output = & $AdbExe devices
    $ids = @()

    foreach ($line in $output) {
        $match = [regex]::Match($line, '^(emulator-\d+)\s+device$')
        if ($match.Success) {
            $ids += $match.Groups[1].Value
        }
    }

    return $ids
}

function Wait-ForBoot {
    param(
        [string]$AdbExe,
        [string]$DeviceId,
        [int]$TimeoutSeconds = 180
    )

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 2

            $state = (& $AdbExe -s $DeviceId get-state 2>&1 | Out-String).Trim()
            if ($state -notmatch 'device') {
                continue
            }

            $boot = (& $AdbExe -s $DeviceId shell getprop sys.boot_completed 2>&1 | Out-String).Trim()
            if ($boot -eq '1') {
                return
            }
        }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    throw "Emulator '$DeviceId' did not finish booting within $TimeoutSeconds seconds."
}

function Get-ApplicationId {
    param([string]$ProjectPath)

    $gradleKts = Join-Path $ProjectPath 'android\app\build.gradle.kts'
    if (-not (Test-Path $gradleKts)) {
        return $null
    }

    $content = Get-Content -Path $gradleKts -Raw
    $match = [regex]::Match($content, 'applicationId\s*=\s*"(?<id>[^"]+)"')
    if ($match.Success) {
        return $match.Groups['id'].Value
    }

    return $null
}

$flutterExe = Resolve-Executable -CommandName 'flutter' -FallbackPaths @(
    (Join-Path $env:USERPROFILE 'development\flutter\bin\flutter.bat')
)
if (-not $flutterExe) {
    throw 'Could not find flutter executable. Add Flutter to PATH or install at %USERPROFILE%\development\flutter\bin\flutter.bat.'
}

$adbExe = Resolve-Executable -CommandName 'adb' -FallbackPaths @(
    (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe')
)
if (-not $adbExe) {
    throw 'Could not find adb executable. Ensure Android SDK Platform-Tools are installed.'
}

$emulatorExe = Resolve-Executable -CommandName 'emulator' -FallbackPaths @(
    (Join-Path $env:LOCALAPPDATA 'Android\Sdk\emulator\emulator.exe')
)
if (-not $emulatorExe) {
    throw 'Could not find emulator executable. Ensure Android Emulator is installed.'
}

Write-Host "Using Flutter: $flutterExe" -ForegroundColor Cyan
Write-Host "Using ADB: $adbExe" -ForegroundColor Cyan

$runningEmulators = @(Get-RunningEmulatorIds -AdbExe $adbExe)
$targetDeviceId = $null

if (@($runningEmulators).Count -gt 0) {
    $targetDeviceId = $runningEmulators[0]
    Write-Host "Emulator already running: $targetDeviceId" -ForegroundColor Green
}
else {
    $avds = @(& $emulatorExe -list-avds)
    if ($avds.Count -eq 0) {
        throw 'No Android Virtual Devices found. Create one in Android Studio Device Manager first.'
    }

    $selectedAvd = if ($AvdName) { $AvdName } else { $avds[0] }
    if ($avds -notcontains $selectedAvd) {
        throw "Requested AVD '$selectedAvd' was not found. Available AVDs: $($avds -join ', ')"
    }

    Write-Host "Starting emulator: $selectedAvd" -ForegroundColor Yellow
    Start-Process -FilePath $emulatorExe -ArgumentList @('-avd', $selectedAvd) | Out-Null

    Write-Host 'Waiting for emulator device to register with ADB...' -ForegroundColor Yellow
    $registerDeadline = (Get-Date).AddSeconds($BootTimeoutSeconds)
    do {
        Start-Sleep -Seconds 2
        $runningEmulators = @(Get-RunningEmulatorIds -AdbExe $adbExe)
    } while (@($runningEmulators).Count -eq 0 -and (Get-Date) -lt $registerDeadline)

    if (@($runningEmulators).Count -eq 0) {
        throw "Emulator process started but no emulator device was detected by adb within $BootTimeoutSeconds seconds."
    }

    $targetDeviceId = $runningEmulators[0]
    Write-Host "Waiting for emulator boot completion: $targetDeviceId" -ForegroundColor Yellow
    Wait-ForBoot -AdbExe $adbExe -DeviceId $targetDeviceId -TimeoutSeconds $BootTimeoutSeconds
    Write-Host 'Emulator boot completed.' -ForegroundColor Green
}

Push-Location $appPath
try {
    if (-not $SkipPubGet) {
        Write-Host 'Running flutter pub get...' -ForegroundColor Yellow
        & $flutterExe pub get
        if ($LASTEXITCODE -ne 0) {
            throw 'flutter pub get failed.'
        }
    }

    if ($Mode -eq 'run') {
        Write-Host "Launching app with flutter run on $targetDeviceId..." -ForegroundColor Cyan
        & $flutterExe run -d $targetDeviceId
        if ($LASTEXITCODE -ne 0) {
            throw 'flutter run failed.'
        }
        return
    }

    if ($Mode -eq 'build-run') {
        Write-Host "Building APK ($BuildType)..." -ForegroundColor Cyan
        & $flutterExe build apk --$BuildType
        if ($LASTEXITCODE -ne 0) {
            throw "flutter build apk --$BuildType failed."
        }
    }

    $apkPath = Join-Path $appPath "build\app\outputs\flutter-apk\app-$BuildType.apk"
    if (-not (Test-Path $apkPath)) {
        throw "APK not found at $apkPath. Run with -Mode build-run first."
    }

    Write-Host "Installing APK on ${targetDeviceId}: $apkPath" -ForegroundColor Cyan
    & $adbExe -s $targetDeviceId install -r $apkPath
    if ($LASTEXITCODE -ne 0) {
        throw 'adb install failed.'
    }

    $applicationId = Get-ApplicationId -ProjectPath $appPath
    if ($applicationId) {
        Write-Host "Launching app package: $applicationId" -ForegroundColor Cyan
        & $adbExe -s $targetDeviceId shell monkey -p $applicationId -c android.intent.category.LAUNCHER 1
    }
    else {
        Write-Host 'Application ID not detected; APK installed but launch command was skipped.' -ForegroundColor Yellow
    }
}
finally {
    Pop-Location
}
