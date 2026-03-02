Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $repoRoot

$generatedFiles = @(
    'flutter_smoke_test/linux/flutter/generated_plugin_registrant.cc',
    'flutter_smoke_test/linux/flutter/generated_plugin_registrant.h',
    'flutter_smoke_test/linux/flutter/generated_plugins.cmake',
    'flutter_smoke_test/macos/Flutter/GeneratedPluginRegistrant.swift',
    'flutter_smoke_test/windows/flutter/generated_plugin_registrant.cc',
    'flutter_smoke_test/windows/flutter/generated_plugin_registrant.h',
    'flutter_smoke_test/windows/flutter/generated_plugins.cmake'
)

git restore @generatedFiles

Write-Host 'Restored generated Flutter registrant files.' -ForegroundColor Green
git status --short
