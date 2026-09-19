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

    [string]$ChromeDriverPath,

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
. (Join-Path $repoRoot 'scripts\lib\chromedriver.ps1')
$ChromeDriverPath = Resolve-CompatibleChromeDriver `
    -ChromeDriverPath $ChromeDriverPath
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
    '--chrome-driver', $ChromeDriverPath,
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
