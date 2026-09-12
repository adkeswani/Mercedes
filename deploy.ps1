#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Build and deploy Mercedes app to web, Android, or all platforms.

.DESCRIPTION
  Runs Flutter tests, builds release artifacts, and deploys.
  Web deploys Firebase Functions and Firestore configuration before Hosting.
  Android builds an AAB for Play Store upload.

.PARAMETER Target
  Deployment target: 'web', 'android', or 'all'. Default: 'all'.

.PARAMETER SkipTests
  Skip the test suite (use for hotfixes only).

.PARAMETER StageDir
  Stage directory to build from. Default: 'stage5'. Web releases must use
  the directory configured as Hosting public in firebase.json.

.PARAMETER Project
  Explicit Firebase project ID or configured CLI alias. Required for web.

.PARAMETER Environment
  Explicit Firebase environment: dev, staging, or prod. Required for web.

.PARAMETER EnableReleaseCanaryLogin
  Compiles the URL-gated email/password release canary form into the web app.

.PARAMETER AllowProductionCanary
  Required with EnableReleaseCanaryLogin when Environment is prod.

.EXAMPLE
  .\deploy.ps1 -Target web -StageDir stage5 -Environment staging -Project staging
  .\deploy.ps1 -Target android -Environment prod
  .\deploy.ps1 -Target all -Environment prod -Project prod
  .\deploy.ps1 -Target web -SkipTests -Environment prod -Project mercedes-app-11ce2
#>

param(
    [ValidateSet('web', 'android', 'all')]
    [string]$Target = 'all',

    [switch]$SkipTests,

    [string]$StageDir = 'stage5',

    [string]$Project,

    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment,

    [switch]$EnableReleaseCanaryLogin,

    [switch]$AllowProductionCanary
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = $PSScriptRoot
$stageRoot = Join-Path $repoRoot $StageDir
$environmentManifestPath =
    Join-Path $repoRoot 'config\firebase-environments.json'
$firebaseRcPath = Join-Path $repoRoot '.firebaserc'
$productionProjectId = 'mercedes-app-11ce2'

function Write-Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Write-Ok($msg) { Write-Host "  OK: $msg" -ForegroundColor Green }
function Write-Fail($msg) { Write-Host "  FAIL: $msg" -ForegroundColor Red; exit 1 }

$deploysWeb = $Target -eq 'web' -or $Target -eq 'all'
$deploysAndroid = $Target -eq 'android' -or $Target -eq 'all'
if ($deploysWeb -and [string]::IsNullOrWhiteSpace($Project)) {
    Write-Fail 'Web deployment requires an explicit -Project ID or CLI alias.'
}
if ($deploysWeb -and [string]::IsNullOrWhiteSpace($Environment)) {
    Write-Fail 'Web deployment requires an explicit -Environment.'
}
if ($deploysAndroid -and $Environment -ne 'prod') {
    Write-Fail (
        'Android builds use the production Firebase configuration and ' +
        'require -Environment prod.'
    )
}
if ($AllowProductionCanary -and -not $EnableReleaseCanaryLogin) {
    Write-Fail (
        '-AllowProductionCanary is valid only with ' +
        '-EnableReleaseCanaryLogin.'
    )
}
if (
    $deploysWeb -and
    $Environment -eq 'prod' -and
    $EnableReleaseCanaryLogin -and
    -not $AllowProductionCanary
) {
    Write-Fail (
        'A production canary-enabled build requires both ' +
        '-EnableReleaseCanaryLogin and -AllowProductionCanary.'
    )
}
$resolvedProjectId = $Project
function Get-RequiredWebOption {
    param([string]$Name)

    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        Write-Fail (
            "Environment '$Environment' requires environment variable $Name."
        )
    }
    return $value
}

$webBuildArguments = @('build', 'web')
if ($deploysWeb) {
    $firebaseConfigPath = Join-Path $repoRoot 'firebase.json'
    $firebaseConfig =
        Get-Content -LiteralPath $firebaseConfigPath -Raw | ConvertFrom-Json
    $hostingPublicPath =
        [IO.Path]::GetFullPath((Join-Path $repoRoot $firebaseConfig.hosting.public))
    $stageBuildPath =
        [IO.Path]::GetFullPath((Join-Path $stageRoot 'build\web'))
    if ($hostingPublicPath -ne $stageBuildPath) {
        Write-Fail (
            "StageDir '$StageDir' builds '$stageBuildPath', but firebase.json " +
            "deploys '$hostingPublicPath'."
        )
    }
    if (-not (
            Test-Path -LiteralPath $environmentManifestPath -PathType Leaf
        )) {
        Write-Fail (
            "Firebase environment manifest not found: " +
            $environmentManifestPath
        )
    }
    if (Test-Path -LiteralPath $firebaseRcPath -PathType Leaf) {
        $firebaseRc =
            Get-Content -LiteralPath $firebaseRcPath -Raw | ConvertFrom-Json
        if ($firebaseRc.projects.PSObject.Properties.Name -contains 'default') {
            Write-Fail (
                "Firebase alias 'default' is forbidden; select dev, staging, " +
                'or prod explicitly.'
            )
        }
        $projectAlias = $firebaseRc.projects.PSObject.Properties |
            Where-Object Name -EQ $Project |
            Select-Object -First 1
        if ($projectAlias) {
            $resolvedProjectId = $projectAlias.Value
        }
    }

    $environmentManifest = Get-Content `
        -LiteralPath $environmentManifestPath `
        -Raw |
        ConvertFrom-Json
    $environmentConfig = $environmentManifest.environments.$Environment
    if (-not $environmentConfig) {
        Write-Fail "Environment '$Environment' is missing from the manifest."
    }
    if (-not $environmentConfig.projectId -or
        -not $environmentConfig.hostingUrl) {
        Write-Fail (
            "Environment '$Environment' is not provisioned in " +
            'config\firebase-environments.json.'
        )
    }
    if (
        $environmentConfig.projectId -and
        $resolvedProjectId -ne $environmentConfig.projectId
    ) {
        Write-Fail (
            "Environment '$Environment' expects project " +
            "'$($environmentConfig.projectId)', not '$resolvedProjectId'."
        )
    }
    if (
        $Environment -ne 'prod' -and
        $resolvedProjectId -eq $productionProjectId
    ) {
        Write-Fail (
            "Environment '$Environment' cannot target production project " +
            "'$productionProjectId'."
        )
    }
    if (
        $Environment -eq 'prod' -and
        $resolvedProjectId -ne $productionProjectId
    ) {
        Write-Fail (
            "Production releases must target '$productionProjectId', not " +
            "'$resolvedProjectId'."
        )
    }

    $webBuildArguments +=
        "--dart-define=FIREBASE_ENVIRONMENT=$Environment"
    if ($Environment -ne 'prod') {
        $webProjectId = Get-RequiredWebOption 'FIREBASE_WEB_PROJECT_ID'
        if ($webProjectId -ne $resolvedProjectId) {
            Write-Fail (
                "FIREBASE_WEB_PROJECT_ID '$webProjectId' does not match " +
                "selected project '$resolvedProjectId'."
            )
        }
        foreach ($option in @(
                'FIREBASE_WEB_API_KEY',
                'FIREBASE_WEB_APP_ID',
                'FIREBASE_WEB_MESSAGING_SENDER_ID',
                'FIREBASE_WEB_PROJECT_ID',
                'FIREBASE_WEB_AUTH_DOMAIN',
                'FIREBASE_WEB_STORAGE_BUCKET'
            )) {
            $webBuildArguments +=
                "--dart-define=$option=$(Get-RequiredWebOption $option)"
        }
        if ($env:FIREBASE_WEB_MEASUREMENT_ID) {
            $webBuildArguments += (
                '--dart-define=FIREBASE_WEB_MEASUREMENT_ID=' +
                $env:FIREBASE_WEB_MEASUREMENT_ID
            )
        }
    }
    if ($EnableReleaseCanaryLogin) {
        $webBuildArguments +=
            '--dart-define=ENABLE_RELEASE_CANARY_LOGIN=true'
    }
}

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
    & flutter @webBuildArguments
    if ($LASTEXITCODE -ne 0) { Pop-Location; Write-Fail "Web build failed" }
    Pop-Location
    Write-Ok "Web build complete"

    Write-Step "Deploying Functions and Firestore configuration"
    Push-Location $repoRoot
    firebase deploy --only "functions,firestore:rules,firestore:indexes" `
        --project $resolvedProjectId
    if ($LASTEXITCODE -ne 0) {
        Pop-Location
        Write-Fail "Functions or Firestore deployment failed"
    }
    & (Join-Path $repoRoot 'scripts\wait-firestore-indexes.ps1') `
        -Project $resolvedProjectId
    if ($LASTEXITCODE -ne 0) {
        Pop-Location
        Write-Fail "Firestore indexes did not become ready"
    }

    Write-Step "Deploying Firebase Hosting"
    firebase deploy --only hosting --project $resolvedProjectId
    if ($LASTEXITCODE -ne 0) {
        Pop-Location
        Write-Fail "Firebase Hosting deployment failed"
    }
    Pop-Location
    & (Join-Path $repoRoot 'scripts\verify-deployed-config.ps1') `
        -Environment $Environment `
        -Project $resolvedProjectId
    if ($LASTEXITCODE -ne 0) {
        Write-Fail 'Deployed Firestore configuration parity check failed'
    }
    Write-Ok (
        "Firebase web release completed for $Environment/$resolvedProjectId"
    )
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
