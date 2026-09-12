#!/usr/bin/env pwsh

param(
    [Parameter(Mandatory)]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Project
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$nodeScript = Join-Path $PSScriptRoot 'release\verify-deployed-config.js'
if (-not (Test-Path -LiteralPath $nodeScript -PathType Leaf)) {
    throw "Missing deployed configuration verifier: $nodeScript"
}
$npmRoot = (& npm root -g).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($npmRoot)) {
    throw 'Unable to locate the global npm package directory.'
}
$firebaseToolsLib = Join-Path $npmRoot 'firebase-tools\lib'
if (-not (Test-Path -LiteralPath $firebaseToolsLib -PathType Container)) {
    throw 'firebase-tools must be installed globally for parity verification.'
}

$previousToolsLib = $env:RELEASE_FIREBASE_TOOLS_LIB
$env:RELEASE_FIREBASE_TOOLS_LIB = $firebaseToolsLib
try {
    & node $nodeScript --environment $Environment --project $Project
    if ($LASTEXITCODE -ne 0) {
        throw 'Deployed Firestore configuration parity check failed.'
    }
}
finally {
    $env:RELEASE_FIREBASE_TOOLS_LIB = $previousToolsLib
}
