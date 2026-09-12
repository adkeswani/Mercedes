#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$deployScript = Join-Path $repoRoot 'deploy.ps1'
$firebaseConfig = Join-Path $repoRoot 'firebase.json'
$waitScript = Join-Path $repoRoot 'scripts\wait-firestore-indexes.ps1'
$parityScript = Join-Path $repoRoot 'scripts\verify-deployed-config.ps1'
$environmentManifest =
    Join-Path $repoRoot 'config\firebase-environments.json'

$deploySource = Get-Content -LiteralPath $deployScript -Raw
$backendCommand =
    'firebase deploy --only "functions,firestore:rules,firestore:indexes"'
$waitCommand = "'scripts\wait-firestore-indexes.ps1'"
$hostingCommand =
    'firebase deploy --only hosting --project $resolvedProjectId'
$parityCommand = "'scripts\verify-deployed-config.ps1'"
$backendPosition = $deploySource.IndexOf($backendCommand)
$waitPosition = $deploySource.IndexOf($waitCommand)
$hostingPosition = $deploySource.IndexOf($hostingCommand)
$parityPosition = $deploySource.IndexOf($parityCommand)
if ($backendPosition -lt 0 -or
    $waitPosition -le $backendPosition -or
    $hostingPosition -le $waitPosition -or
    $parityPosition -le $hostingPosition) {
    throw (
        'Web deployment must release Functions and Firestore configuration, ' +
        'wait for every composite index, release Hosting, and verify parity.'
    )
}
if (-not $deploySource.Contains(
        "Web deployment requires an explicit -Project ID or CLI alias."
    )) {
    throw 'Web deployment must require an explicit Firebase project.'
}
if (-not $deploySource.Contains(
        "Web deployment requires an explicit -Environment."
    )) {
    throw 'Web deployment must require an explicit Firebase environment.'
}
if (-not $deploySource.Contains(
        "A production canary-enabled build requires both"
    )) {
    throw 'Production canary login must require an explicit opt-in.'
}
if (-not $deploySource.Contains("[string]`$StageDir = 'stage5'") -or
    -not $deploySource.Contains("but firebase.json ") -or
    -not $deploySource.Contains("deploys '`$hostingPublicPath'.")) {
    throw 'Web deployment must build the same Stage 5 directory Hosting uses.'
}
if (-not $deploySource.Contains(
        "Android builds use the production Firebase configuration"
    )) {
    throw 'Android builds must reject non-production environment selection.'
}
if (-not (Test-Path -LiteralPath $waitScript -PathType Leaf)) {
    throw 'Missing Firestore index readiness gate.'
}
if (-not (Test-Path -LiteralPath $parityScript -PathType Leaf)) {
    throw 'Missing deployed Firestore configuration parity gate.'
}
if (-not (Test-Path -LiteralPath $environmentManifest -PathType Leaf)) {
    throw 'Missing Firebase environment manifest.'
}

$environments =
    Get-Content -LiteralPath $environmentManifest -Raw | ConvertFrom-Json
if (
    $environments.environments.prod.projectId -ne 'mercedes-app-11ce2'
) {
    throw 'Environment manifest must pin the production project.'
}
foreach ($name in @('dev', 'staging')) {
    if (
        $environments.environments.$name.projectId -eq
        'mercedes-app-11ce2'
    ) {
        throw "Environment '$name' cannot target the production project."
    }
}

$config = Get-Content -LiteralPath $firebaseConfig -Raw | ConvertFrom-Json
if ($config.firestore.rules -ne 'firestore.rules' -or
    $config.firestore.indexes -ne 'firestore.indexes.json') {
    throw 'firebase.json must declare the repository Firestore rules and indexes.'
}

foreach ($path in @($config.firestore.rules, $config.firestore.indexes)) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $path) -PathType Leaf)) {
        throw "Missing Firestore deployment input: $path"
    }
}

Write-Host (
    'Web deployment contract verified: explicit environment, backend, ready ' +
    'indexes, Hosting, then deployed parity.'
) -ForegroundColor Green
