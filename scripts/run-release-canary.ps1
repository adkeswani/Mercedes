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

    [string]$ChromeDriverPath = $env:CHROMEDRIVER_PATH,

    [string]$ArtifactDirectory,

    [switch]$UseEmulator,

    [switch]$AllowProduction
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Environment -eq 'prod' -and -not $AllowProduction) {
    throw 'Production canary execution requires -AllowProduction.'
}
if ($UseEmulator -and $Environment -eq 'prod') {
    throw 'Production cannot be selected with -UseEmulator.'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$nodeScript = Join-Path $PSScriptRoot 'release\browser-canary.js'
if (-not (Test-Path -LiteralPath $nodeScript -PathType Leaf)) {
    throw "Missing deployed browser canary implementation: $nodeScript"
}
if (-not $ChromeDriverPath) {
    $chromeDriver = Get-Command 'chromedriver' -ErrorAction SilentlyContinue
    if ($chromeDriver) {
        $ChromeDriverPath = $chromeDriver.Source
    }
}
if (-not $ChromeDriverPath -or
    -not (Test-Path -LiteralPath $ChromeDriverPath -PathType Leaf)) {
    throw (
        'ChromeDriver was not found. Set CHROMEDRIVER_PATH to a driver that ' +
        'matches the installed Chrome version.'
    )
}
if (-not $ArtifactDirectory) {
    $runId = '{0}-{1}' -f (
        (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'),
        [Guid]::NewGuid().ToString('N').Substring(0, 8)
    )
    $ArtifactDirectory = Join-Path `
        $repoRoot `
        "stage5\test-artifacts\release-canary\$runId"
}

$nodeArguments = @(
    $nodeScript,
    '--environment', $Environment,
    '--project', $Project,
    '--app-url', $AppUrl.AbsoluteUri,
    '--chrome-driver', (Resolve-Path $ChromeDriverPath).Path,
    '--artifact-dir', [IO.Path]::GetFullPath($ArtifactDirectory)
)
if ($UseEmulator) {
    $nodeArguments += '--emulator'
}
if ($AllowProduction) {
    $nodeArguments += '--allow-production'
}
& node @nodeArguments
if ($LASTEXITCODE -ne 0) {
    throw 'Deployed release canary failed.'
}
