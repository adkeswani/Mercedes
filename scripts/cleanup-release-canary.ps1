#!/usr/bin/env pwsh

param(
    [Parameter(Mandatory)]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Project,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [uri]$AppUrl,

    [switch]$UseEmulator,

    [switch]$AllowProduction
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Environment -eq 'prod' -and -not $AllowProduction) {
    throw 'Production canary cleanup requires -AllowProduction.'
}
if ($UseEmulator -and $Environment -eq 'prod') {
    throw 'Production cannot be selected with -UseEmulator.'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$nodeScript = Join-Path $PSScriptRoot 'release\cleanup-release-canary.js'
$adminModule = Join-Path $repoRoot 'functions\node_modules\firebase-admin'
if (-not (Test-Path -LiteralPath $nodeScript -PathType Leaf)) {
    throw "Missing release canary cleanup implementation: $nodeScript"
}
if (-not (Test-Path -LiteralPath $adminModule -PathType Container)) {
    throw (
        'firebase-admin is not installed. Restore the existing functions ' +
        'dependencies with npm ci --prefix .\functions.'
    )
}

$nodeArguments = @(
    $nodeScript,
    '--environment', $Environment,
    '--project', $Project,
    '--app-url', $AppUrl.AbsoluteUri
)
if ($UseEmulator) {
    $nodeArguments += '--emulator'
}
if ($AllowProduction) {
    $nodeArguments += '--allow-production'
}
& node @nodeArguments
if ($LASTEXITCODE -ne 0) {
    throw 'Release canary cleanup failed.'
}
