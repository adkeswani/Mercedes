#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Build and deploy Mercedes app to web, Android, or all platforms.

.DESCRIPTION
  Runs Flutter tests, builds release artifacts, and deploys.
  Web deploys to Firebase Hosting. Android builds an AAB for Play Store upload.

.PARAMETER Target
  Deployment target: 'web', 'android', or 'all'. Default: 'all'.

.PARAMETER SkipTests
  Skip the test suite (use for hotfixes only).

.PARAMETER StageDir
  Stage directory to build from. Default: 'stage3'.

.EXAMPLE
  .\deploy.ps1 -Target web
  .\deploy.ps1 -Target android
  .\deploy.ps1 -Target all
  .\deploy.ps1 -Target web -SkipTests
#>

param(
    [ValidateSet('web', 'android', 'all')]
    [string]$Target = 'all',

    [switch]$SkipTests,

    [string]$StageDir = 'stage3'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = $PSScriptRoot
$stageRoot = Join-Path $repoRoot $StageDir

function Write-Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Write-Ok($msg) { Write-Host "  OK: $msg" -ForegroundColor Green }
function Write-Fail($msg) { Write-Host "  FAIL: $msg" -ForegroundColor Red; exit 1 }

# Verify we're on main
Write-Step "Checking branch"
$branch = git -C $repoRoot rev-parse --abbrev-ref HEAD
if ($branch -ne 'main') {
    Write-Fail "Must deploy from 'main' branch (currently on '$branch')"
}
$dirty = git -C $repoRoot status --porcelain
if ($dirty) {
    Write-Fail "Working tree is dirty. Commit or stash changes first."
}
Write-Ok "On main, clean working tree"

# Run tests
if (-not $SkipTests) {
    Write-Step "Running tests"
    Push-Location $stageRoot
    flutter test
    if ($LASTEXITCODE -ne 0) { Pop-Location; Write-Fail "Tests failed" }
    Pop-Location
    Write-Ok "All tests passed"
} else {
    Write-Host "`n  Skipping tests (--SkipTests)" -ForegroundColor Yellow
}

# Web deployment
if ($Target -eq 'web' -or $Target -eq 'all') {
    Write-Step "Building for web"
    Push-Location $stageRoot
    flutter build web
    if ($LASTEXITCODE -ne 0) { Pop-Location; Write-Fail "Web build failed" }
    Pop-Location
    Write-Ok "Web build complete"

    Write-Step "Deploying to Firebase Hosting"
    Push-Location $repoRoot
    firebase deploy --only hosting
    if ($LASTEXITCODE -ne 0) { Pop-Location; Write-Fail "Firebase deploy failed" }
    Pop-Location
    Write-Ok "Deployed to https://mercedes-app-11ce2.web.app"
}

# Android deployment
if ($Target -eq 'android' -or $Target -eq 'all') {
    $keystorePath = Join-Path $stageRoot "android\app\upload-keystore.jks"
    $keyPropertiesPath = Join-Path $stageRoot "android\key.properties"

    if (-not (Test-Path $keystorePath) -or -not (Test-Path $keyPropertiesPath)) {
        Write-Host "`n  Android signing not configured. Skipping Android build." -ForegroundColor Yellow
        Write-Host "  To set up:" -ForegroundColor Yellow
        Write-Host "    1. Generate keystore:" -ForegroundColor Yellow
        Write-Host "       keytool -genkey -v -keystore android/app/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload" -ForegroundColor Yellow
        Write-Host "    2. Create android/key.properties:" -ForegroundColor Yellow
        Write-Host "       storePassword=<password>" -ForegroundColor Yellow
        Write-Host "       keyPassword=<password>" -ForegroundColor Yellow
        Write-Host "       keyAlias=upload" -ForegroundColor Yellow
        Write-Host "       storeFile=app/upload-keystore.jks" -ForegroundColor Yellow
        Write-Host "    3. Update android/app/build.gradle with signing config" -ForegroundColor Yellow
        Write-Host "    4. Add upload-keystore.jks and key.properties to .gitignore" -ForegroundColor Yellow
    } else {
        Write-Step "Building Android App Bundle"
        Push-Location $stageRoot
        flutter build appbundle --release
        if ($LASTEXITCODE -ne 0) { Pop-Location; Write-Fail "Android build failed" }
        Pop-Location
        $aabPath = Join-Path $stageRoot "build\app\outputs\bundle\release\app-release.aab"
        Write-Ok "AAB built at: $aabPath"
        Write-Host "  Upload to Google Play Console: https://play.google.com/console" -ForegroundColor Yellow
    }
}

Write-Step "Deployment complete"
