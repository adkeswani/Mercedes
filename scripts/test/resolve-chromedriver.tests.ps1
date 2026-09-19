Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\chromedriver.ps1')

$testRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'mercedes-chromedriver-tests-' + [Guid]::NewGuid().ToString('N')
)
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$originalEnvironmentPath = $env:CHROMEDRIVER_PATH
$passed = 0

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -ne $Actual) {
        throw "$Message Expected '$Expected', received '$Actual'."
    }
}

function Assert-ThrowsLike {
    param([scriptblock]$Action, [string]$Pattern)
    try {
        & $Action
    }
    catch {
        if ($_.Exception.Message -notlike $Pattern) {
            throw (
                "Expected error like '$Pattern', received " +
                "'$($_.Exception.Message)'."
            )
        }
        return
    }
    throw "Expected an error like '$Pattern'."
}

function New-FakeDriver {
    param([string]$Path)
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) |
        Out-Null
    [IO.File]::WriteAllText($Path, 'fake')
    return [IO.Path]::GetFullPath($Path)
}

$chromeDiscovery = {
    [pscustomobject]@{
        Path = 'C:\Chrome\chrome.exe'
        Version = '152.0.7977.84'
        Major = 152
    }
}
$matchingVersion = { param($Path) '152.0.7977.82' }
$noCommand = { param($Name) $null }

try {
    $explicit = New-FakeDriver (Join-Path $testRoot 'explicit.exe')
    $environment = New-FakeDriver (Join-Path $testRoot 'environment.exe')
    $pathDriver = New-FakeDriver (Join-Path $testRoot 'path.exe')
    $env:CHROMEDRIVER_PATH = $environment
    $actual = Resolve-CompatibleChromeDriver `
        -ChromeDriverPath $explicit `
        -CacheRoot (Join-Path $testRoot 'precedence-cache') `
        -ChromeDiscovery $chromeDiscovery `
        -CommandLookup { param($Name) $pathDriver } `
        -VersionReader $matchingVersion
    Assert-Equal $explicit $actual 'Explicit path must win.'
    $passed++

    $actual = Resolve-CompatibleChromeDriver `
        -CacheRoot (Join-Path $testRoot 'environment-cache') `
        -ChromeDiscovery $chromeDiscovery `
        -CommandLookup { param($Name) $pathDriver } `
        -VersionReader $matchingVersion
    Assert-Equal $environment $actual 'Environment path must win over PATH.'
    $passed++

    $env:CHROMEDRIVER_PATH = $null
    $actual = Resolve-CompatibleChromeDriver `
        -CacheRoot (Join-Path $testRoot 'path-cache') `
        -ChromeDiscovery $chromeDiscovery `
        -CommandLookup { param($Name) $pathDriver } `
        -VersionReader $matchingVersion
    Assert-Equal $pathDriver $actual 'PATH must win over the cache.'
    $passed++

    $cacheRoot = Join-Path $testRoot 'reuse-cache'
    $cached = New-FakeDriver (
        Join-Path $cacheRoot '152\152.0.7977.82\win64\chromedriver.exe'
    )
    $actual = Resolve-CompatibleChromeDriver `
        -CacheRoot $cacheRoot `
        -ChromeDiscovery $chromeDiscovery `
        -CommandLookup $noCommand `
        -VersionReader $matchingVersion `
        -Downloader { throw 'download should not run' }
    Assert-Equal $cached $actual 'A compatible cache entry must be reused.'
    $passed++

    $raceCache = Join-Path $testRoot 'race-cache'
    $staged = New-FakeDriver (
        Join-Path $raceCache '152\.staging-race\win64\chromedriver.exe'
    )
    Assert-ThrowsLike {
        Resolve-CompatibleChromeDriver `
            -CacheRoot $raceCache `
            -ChromeDiscovery $chromeDiscovery `
            -CommandLookup $noCommand `
            -VersionReader $matchingVersion `
            -MetadataFetcher { throw 'staged entry was correctly ignored' }
    } '*staged entry was correctly ignored*'
    if (-not (Test-Path -LiteralPath $staged)) {
        throw 'The resolver must not mutate another installer staging path.'
    }
    $passed++

    Assert-ThrowsLike {
        Resolve-CompatibleChromeDriver `
            -ChromeDriverPath $explicit `
            -CacheRoot (Join-Path $testRoot 'mismatch-cache') `
            -ChromeDiscovery $chromeDiscovery `
            -VersionReader { param($Path) '151.0.0.0' }
    } '*does not match installed Chrome major 152*'
    $passed++

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $unsafeArchive = Join-Path $testRoot 'unsafe.zip'
    $zip = [IO.Compression.ZipFile]::Open(
        $unsafeArchive,
        [IO.Compression.ZipArchiveMode]::Create
    )
    try {
        $entry = $zip.CreateEntry('..\escape.txt')
        $writer = [IO.StreamWriter]::new($entry.Open())
        try {
            $writer.Write('escape')
        }
        finally {
            $writer.Dispose()
        }
    }
    finally {
        $zip.Dispose()
    }
    Assert-ThrowsLike {
        Expand-ChromeDriverArchiveSafely `
            -ArchivePath $unsafeArchive `
            -DestinationPath (Join-Path $testRoot 'unsafe-output')
    } '*unsafe path*'
    $passed++

    $downloadCache = Join-Path $testRoot 'download-cache'
    $metadataFetcher = {
        param($Uri)
        [pscustomobject]@{
            builds = [pscustomobject]@{
                '152.0.7977' = [pscustomobject]@{
                    version = '152.0.7977.82'
                    downloads = [pscustomobject]@{
                        chromedriver = @(
                            [pscustomobject]@{
                                platform = 'win64'
                                url = 'https://storage.googleapis.com/chrome-for-testing-public/152.0.7977.82/win64/chromedriver-win64.zip'
                            }
                        )
                    }
                }
            }
        }
    }
    $downloader = {
        param($Uri, $Destination)
        $archive = [IO.Compression.ZipFile]::Open(
            $Destination,
            [IO.Compression.ZipArchiveMode]::Create
        )
        try {
            $entry = $archive.CreateEntry(
                'chromedriver-win64/chromedriver.exe'
            )
            $writer = [IO.StreamWriter]::new($entry.Open())
            try {
                $writer.Write('fake')
            }
            finally {
                $writer.Dispose()
            }
        }
        finally {
            $archive.Dispose()
        }
    }
    $actual = Resolve-CompatibleChromeDriver `
        -CacheRoot $downloadCache `
        -ChromeDiscovery $chromeDiscovery `
        -CommandLookup $noCommand `
        -VersionReader $matchingVersion `
        -MetadataFetcher $metadataFetcher `
        -Downloader $downloader
    if (-not (Test-Path -LiteralPath $actual -PathType Leaf)) {
        throw 'The downloaded driver was not promoted into the cache.'
    }
    $passed++

    Assert-ThrowsLike {
        Resolve-CompatibleChromeDriver `
            -CacheRoot (Join-Path $testRoot 'network-cache') `
            -ChromeDiscovery $chromeDiscovery `
            -CommandLookup $noCommand `
            -VersionReader $matchingVersion `
            -MetadataFetcher { throw 'network unavailable' }
    } '*Unable to resolve ChromeDriver*network unavailable*'
    $passed++

    Assert-ThrowsLike {
        Resolve-CompatibleChromeDriver `
            -CacheRoot (Join-Path $testRoot 'chrome-cache') `
            -ChromeDiscovery { throw 'Google Chrome was not found.' } `
            -CommandLookup $noCommand `
            -VersionReader $matchingVersion
    } '*Google Chrome was not found*'
    $passed++

    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($relativePath in @(
        'scripts\run-stage-validation.ps1',
        'scripts\run-release-canary.ps1',
        'scripts\test-release-canary-emulator.ps1',
        'stage5\tool\run-browser-login-smoke.ps1'
    )) {
        $content = Get-Content `
            -LiteralPath (Join-Path $repoRoot $relativePath) `
            -Raw
        if ($content -notmatch 'Resolve-CompatibleChromeDriver') {
            throw "$relativePath does not use the shared ChromeDriver resolver."
        }
        if ($content -match "Get-Command\s+['`"]?chromedriver") {
            throw "$relativePath duplicates ChromeDriver discovery."
        }
    }
    $passed++

    Write-Host "ChromeDriver resolver tests passed: $passed"
}
finally {
    $env:CHROMEDRIVER_PATH = $originalEnvironmentPath
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
