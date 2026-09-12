#!/usr/bin/env pwsh

param(
    [switch]$InsideEmulators,
    [switch]$SkipBuild,
    [string]$ChromeDriverPath = $env:CHROMEDRIVER_PATH
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$stagePath = Join-Path $repoRoot 'stage5'
$projectId = 'demo-mercedes-canary'

if (-not $InsideEmulators) {
    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', "`"$PSCommandPath`"",
        '-InsideEmulators'
    )
    if ($SkipBuild) {
        $arguments += '-SkipBuild'
    }
    if ($ChromeDriverPath) {
        $arguments += @('-ChromeDriverPath', "`"$ChromeDriverPath`"")
    }
    $innerCommand = 'powershell ' + ($arguments -join ' ')
    Push-Location $repoRoot
    try {
        & firebase emulators:exec `
            --only auth,firestore `
            --project $projectId `
            $innerCommand
        if ($LASTEXITCODE -ne 0) {
            throw 'Local release canary verification failed.'
        }
    }
    finally {
        Pop-Location
    }
    exit 0
}

function Get-FreeTcpPort {
    $listener = [Net.Sockets.TcpListener]::new(
        [Net.IPAddress]::Loopback,
        0
    )
    try {
        $listener.Start()
        return ([Net.IPEndPoint]$listener.LocalEndpoint).Port
    }
    finally {
        $listener.Stop()
    }
}

if (-not $SkipBuild) {
    Push-Location $stagePath
    try {
        & flutter build web `
            --debug `
            --no-pub `
            --dart-define=USE_FIREBASE_EMULATORS=true `
            --dart-define=ENABLE_RELEASE_CANARY_LOGIN=true `
            --dart-define=FIREBASE_ENVIRONMENT=dev `
            --dart-define=FIREBASE_WEB_API_KEY=fake-api-key `
            --dart-define=FIREBASE_WEB_APP_ID=1:123456789:web:releasecanary `
            --dart-define=FIREBASE_WEB_MESSAGING_SENDER_ID=123456789 `
            --dart-define=FIREBASE_WEB_PROJECT_ID=$projectId `
            --dart-define=FIREBASE_WEB_AUTH_DOMAIN=$projectId.firebaseapp.com `
            --dart-define=FIREBASE_WEB_STORAGE_BUCKET=$projectId.appspot.com
        if ($LASTEXITCODE -ne 0) {
            throw 'Local release canary web build failed.'
        }
    }
    finally {
        Pop-Location
    }
}

$python = Get-Command 'python' -ErrorAction Stop
$webPort = Get-FreeTcpPort
$appUrl = "http://127.0.0.1:$webPort"
$server = Start-Process `
    -FilePath $python.Source `
    -ArgumentList '-m', 'http.server', "$webPort", '--bind', '127.0.0.1' `
    -WorkingDirectory (Join-Path $stagePath 'build\web') `
    -PassThru `
    -WindowStyle Hidden

try {
    $ready = $false
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    do {
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $appUrl | Out-Null
            $ready = $true
        }
        catch {
            Start-Sleep -Milliseconds 200
        }
    } while (-not $ready -and [DateTime]::UtcNow -lt $deadline)
    if (-not $ready) {
        throw 'Local release canary web server did not become ready.'
    }

    & (Join-Path $repoRoot 'scripts\seed-release-canary.ps1') `
        -Environment dev `
        -Project $projectId `
        -AppUrl $appUrl `
        -UseEmulator
    & (Join-Path $repoRoot 'scripts\run-release-canary.ps1') `
        -Environment dev `
        -Project $projectId `
        -AppUrl $appUrl `
        -ChromeDriverPath $ChromeDriverPath `
        -UseEmulator
}
finally {
    try {
        & (Join-Path $repoRoot 'scripts\cleanup-release-canary.ps1') `
            -Environment dev `
            -Project $projectId `
            -AppUrl $appUrl `
            -UseEmulator
    }
    finally {
        if (-not $server.HasExited) {
            Stop-Process -Id $server.Id -Force
        }
    }
}
