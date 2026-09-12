#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$deployScript = Join-Path $repoRoot 'deploy.ps1'
$firebaseConfig = Join-Path $repoRoot 'firebase.json'
$waitScript = Join-Path $repoRoot 'scripts\wait-firestore-indexes.ps1'

$deploySource = Get-Content -LiteralPath $deployScript -Raw
$backendCommand =
    'firebase deploy --only "firestore:rules,firestore:indexes" --project $Project'
$waitCommand = "'scripts\wait-firestore-indexes.ps1'"
$hostingCommand = 'firebase deploy --only hosting --project $Project'
$backendPosition = $deploySource.IndexOf($backendCommand)
$waitPosition = $deploySource.IndexOf($waitCommand)
$hostingPosition = $deploySource.IndexOf($hostingCommand)
if ($backendPosition -lt 0 -or
    $waitPosition -le $backendPosition -or
    $hostingPosition -le $waitPosition) {
    throw (
        'Web deployment must release Firestore configuration, wait for every ' +
        'composite index, and only then release Hosting.'
    )
}
if (-not $deploySource.Contains(
        "Web deployment requires an explicit -Project ID or CLI alias."
    )) {
    throw 'Web deployment must require an explicit Firebase project.'
}
if (-not (Test-Path -LiteralPath $waitScript -PathType Leaf)) {
    throw 'Missing Firestore index readiness gate.'
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
    'Web deployment contract verified: backend, ready indexes, then Hosting.'
) -ForegroundColor Green
