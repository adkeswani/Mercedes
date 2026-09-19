Set-StrictMode -Version Latest

function Get-InstalledChrome {
    $candidates = [Collections.Generic.List[string]]::new()
    $command = Get-Command 'chrome.exe' -ErrorAction SilentlyContinue
    if ($command) {
        $candidates.Add($command.Source)
    }

    foreach ($registryPath in @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe'
    )) {
        try {
            $value = (Get-Item -LiteralPath $registryPath -ErrorAction Stop).
                GetValue('')
            if ($value) {
                $candidates.Add([string]$value)
            }
        }
        catch {
            # Continue through the supported discovery locations.
        }
    }

    $standardPaths = [Collections.Generic.List[string]]::new()
    $standardPaths.Add(
        (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe')
    )
    if (${env:ProgramFiles(x86)}) {
        $standardPaths.Add(
            (Join-Path `
                ${env:ProgramFiles(x86)} `
                'Google\Chrome\Application\chrome.exe')
        )
    }
    $standardPaths.Add(
        (Join-Path `
            $env:LOCALAPPDATA `
            'Google\Chrome\Application\chrome.exe')
    )
    foreach ($path in $standardPaths) {
        if ($path) {
            $candidates.Add($path)
        }
    }

    foreach ($candidate in $candidates | Select-Object -Unique) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $version = (Get-Item -LiteralPath $candidate).VersionInfo.
                ProductVersion
            if ($version -match '^(?<major>[0-9]+)\.') {
                return [pscustomobject]@{
                    Path = [IO.Path]::GetFullPath($candidate)
                    Version = $version
                    Major = [int]$Matches.major
                }
            }
        }
    }

    throw (
        'Google Chrome was not found. Install Chrome before running browser ' +
        'validation, or make chrome.exe discoverable through its standard ' +
        'Windows installation path.'
    )
}

function Get-ChromeDriverVersion {
    param([Parameter(Mandatory)][string]$Path)

    $output = & $Path --version 2>&1
    if ($LASTEXITCODE -ne 0 -or "$output" -notmatch
        'ChromeDriver\s+(?<version>[0-9]+(?:\.[0-9]+){3})') {
        throw "Could not read the ChromeDriver version from '$Path'."
    }
    return $Matches.version
}

function Get-FinalizedCachedChromeDrivers {
    param(
        [Parameter(Mandatory)][string]$MajorCache,
        [Parameter(Mandatory)][string]$Platform
    )

    if (-not (Test-Path -LiteralPath $MajorCache -PathType Container)) {
        return @()
    }
    return @(
        Get-ChildItem -LiteralPath $MajorCache -Directory |
            Where-Object { $_.Name -match '^[0-9]+(?:\.[0-9]+){3}$' } |
            Sort-Object Name -Descending |
            ForEach-Object {
                $candidate = Join-Path $_.FullName "$Platform\chromedriver.exe"
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    Get-Item -LiteralPath $candidate
                }
            }
    )
}

function Assert-CompatibleChromeDriver {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][int]$ChromeMajor,
        [Parameter(Mandatory)][scriptblock]$VersionReader,
        [Parameter(Mandatory)][string]$Source
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "ChromeDriver from $Source does not exist: $Path"
    }
    $resolvedPath = [IO.Path]::GetFullPath($Path)
    $version = & $VersionReader $resolvedPath
    if ("$version" -notmatch '^(?<major>[0-9]+)\.') {
        throw (
            "ChromeDriver from $Source reported an invalid version " +
            "'$version': $resolvedPath"
        )
    }
    $driverMajor = [int]$Matches.major
    if ($driverMajor -ne $ChromeMajor) {
        throw (
            "ChromeDriver major $driverMajor from $Source does not match " +
            "installed Chrome major $ChromeMajor. Remove the override or " +
            'provide a compatible driver.'
        )
    }
    return $resolvedPath
}

function Expand-ChromeDriverArchiveSafely {
    param(
        [Parameter(Mandatory)][string]$ArchivePath,
        [Parameter(Mandatory)][string]$DestinationPath
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $destination = [IO.Path]::GetFullPath($DestinationPath)
    [IO.Directory]::CreateDirectory($destination) | Out-Null
    $destinationPrefix = $destination.TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    ) + [IO.Path]::DirectorySeparatorChar

    $archive = [IO.Compression.ZipFile]::OpenRead(
        [IO.Path]::GetFullPath($ArchivePath)
    )
    try {
        foreach ($entry in $archive.Entries) {
            $target = [IO.Path]::GetFullPath(
                (Join-Path $destination $entry.FullName)
            )
            if (-not $target.StartsWith(
                    $destinationPrefix,
                    [StringComparison]::OrdinalIgnoreCase
                )) {
                throw (
                    "ChromeDriver archive contains an unsafe path: " +
                    $entry.FullName
                )
            }
            if (-not $entry.Name) {
                [IO.Directory]::CreateDirectory($target) | Out-Null
                continue
            }
            [IO.Directory]::CreateDirectory(
                [IO.Path]::GetDirectoryName($target)
            ) | Out-Null
            $input = $entry.Open()
            $output = [IO.File]::Open(
                $target,
                [IO.FileMode]::CreateNew,
                [IO.FileAccess]::Write,
                [IO.FileShare]::None
            )
            try {
                $input.CopyTo($output)
            }
            finally {
                $output.Dispose()
                $input.Dispose()
            }
        }
    }
    finally {
        $archive.Dispose()
    }
}

function Get-OfficialChromeDriverDownload {
    param(
        [Parameter(Mandatory)][string]$ChromeVersion,
        [Parameter(Mandatory)][int]$ChromeMajor,
        [Parameter(Mandatory)][string]$Platform,
        [Parameter(Mandatory)][scriptblock]$MetadataFetcher
    )

    $metadataRoot =
        'https://googlechromelabs.github.io/chrome-for-testing/'
    $build = ($ChromeVersion.Split('.')[0..2] -join '.')
    $metadata = & $MetadataFetcher (
        $metadataRoot +
        'latest-patch-versions-per-build-with-downloads.json'
    )
    $property = $metadata.builds.PSObject.Properties[$build]
    $entry = if ($property) { $property.Value } else { $null }

    if (-not $entry) {
        $metadata = & $MetadataFetcher (
            $metadataRoot +
            'latest-versions-per-milestone-with-downloads.json'
        )
        $property = $metadata.milestones.PSObject.Properties["$ChromeMajor"]
        $entry = if ($property) { $property.Value } else { $null }
    }
    if (-not $entry) {
        throw (
            "Chrome for Testing does not publish a ChromeDriver for installed " +
            "Chrome $ChromeVersion ($Platform)."
        )
    }

    $download = @($entry.downloads.chromedriver |
        Where-Object { $_.platform -eq $Platform }) |
        Select-Object -First 1
    if (-not $download) {
        throw (
            "Chrome for Testing has no ChromeDriver download for installed " +
            "Chrome $ChromeVersion on $Platform."
        )
    }
    $uri = [uri]$download.url
    if ($uri.Scheme -ne 'https' -or
        $uri.Host -ne 'storage.googleapis.com' -or
        -not $uri.AbsolutePath.StartsWith(
            '/chrome-for-testing-public/',
            [StringComparison]::Ordinal
        )) {
        throw "Chrome for Testing returned an untrusted download URL: $uri"
    }
    return [pscustomobject]@{
        Version = [string]$entry.version
        Uri = $uri
        Sha256 = if ($download.PSObject.Properties['sha256']) {
            [string]$download.sha256
        }
        else {
            $null
        }
    }
}

function Resolve-CompatibleChromeDriver {
    [CmdletBinding()]
    param(
        [string]$ChromeDriverPath,
        [string]$CacheRoot = (
            Join-Path (
                [Environment]::GetFolderPath(
                    [Environment+SpecialFolder]::LocalApplicationData
                )
            ) 'Copilot\Mercedes\ChromeDriver'
        ),
        [scriptblock]$ChromeDiscovery = ${function:Get-InstalledChrome},
        [scriptblock]$CommandLookup = {
            param($Name)
            Get-Command $Name -ErrorAction SilentlyContinue
        },
        [scriptblock]$VersionReader = ${function:Get-ChromeDriverVersion},
        [scriptblock]$MetadataFetcher = {
            param($Uri)
            Invoke-RestMethod -Uri $Uri
        },
        [scriptblock]$Downloader = {
            param($Uri, $Destination)
            Invoke-WebRequest -Uri $Uri -OutFile $Destination
        },
        [scriptblock]$ArchiveExtractor = {
            param($Archive, $Destination)
            Expand-ChromeDriverArchiveSafely `
                -ArchivePath $Archive `
                -DestinationPath $Destination
        }
    )

    $chrome = & $ChromeDiscovery
    $chromeMajor = [int]$chrome.Major

    if ($ChromeDriverPath) {
        $resolved = Assert-CompatibleChromeDriver `
            -Path $ChromeDriverPath `
            -ChromeMajor $chromeMajor `
            -VersionReader $VersionReader `
            -Source 'the explicit -ChromeDriverPath parameter'
        Write-Host "ChromeDriver: using explicit driver $resolved"
        return $resolved
    }
    if ($env:CHROMEDRIVER_PATH) {
        $resolved = Assert-CompatibleChromeDriver `
            -Path $env:CHROMEDRIVER_PATH `
            -ChromeMajor $chromeMajor `
            -VersionReader $VersionReader `
            -Source 'CHROMEDRIVER_PATH'
        Write-Host "ChromeDriver: using environment driver $resolved"
        return $resolved
    }

    $pathCommand = & $CommandLookup 'chromedriver'
    if ($pathCommand) {
        $path = if ($pathCommand -is [string]) {
            $pathCommand
        }
        else {
            $pathCommand.Source
        }
        $resolved = Assert-CompatibleChromeDriver `
            -Path $path `
            -ChromeMajor $chromeMajor `
            -VersionReader $VersionReader `
            -Source 'PATH'
        Write-Host "ChromeDriver: using PATH driver $resolved"
        return $resolved
    }

    $majorCache = Join-Path $CacheRoot "$chromeMajor"
    $platform = if ([Environment]::Is64BitOperatingSystem) {
        'win64'
    }
    else {
        'win32'
    }
    $cachedDrivers = Get-FinalizedCachedChromeDrivers `
        -MajorCache $majorCache `
        -Platform $platform
    foreach ($cached in $cachedDrivers) {
        try {
            $resolved = Assert-CompatibleChromeDriver `
                -Path $cached.FullName `
                -ChromeMajor $chromeMajor `
                -VersionReader $VersionReader `
                -Source 'the persistent cache'
            Write-Host "ChromeDriver: reusing cached driver $resolved"
            return $resolved
        }
        catch {
            Write-Verbose $_
        }
    }

    [IO.Directory]::CreateDirectory($CacheRoot) | Out-Null
    $lockPath = Join-Path $CacheRoot "$chromeMajor.install.lock"
    $lock = $null
    $deadline = [DateTime]::UtcNow.AddSeconds(60)
    while (-not $lock -and [DateTime]::UtcNow -lt $deadline) {
        try {
            $lock = [IO.File]::Open(
                $lockPath,
                [IO.FileMode]::OpenOrCreate,
                [IO.FileAccess]::ReadWrite,
                [IO.FileShare]::None
            )
        }
        catch [IO.IOException] {
            Start-Sleep -Milliseconds 200
        }
    }
    if (-not $lock) {
        throw (
            "Timed out waiting for another ChromeDriver installation at " +
            "$CacheRoot."
        )
    }

    $temporaryRoot = Join-Path $CacheRoot (
        '.tmp-' + [Guid]::NewGuid().ToString('N')
    )
    $stagingPath = $null
    try {
        $cachedDrivers = Get-FinalizedCachedChromeDrivers `
            -MajorCache $majorCache `
            -Platform $platform
        foreach ($cached in $cachedDrivers) {
            try {
                $resolved = Assert-CompatibleChromeDriver `
                    -Path $cached.FullName `
                    -ChromeMajor $chromeMajor `
                    -VersionReader $VersionReader `
                    -Source 'the persistent cache'
                Write-Host "ChromeDriver: reusing cached driver $resolved"
                return $resolved
            }
            catch {
                Write-Verbose $_
            }
        }

        try {
            $download = Get-OfficialChromeDriverDownload `
                -ChromeVersion $chrome.Version `
                -ChromeMajor $chromeMajor `
                -Platform $platform `
                -MetadataFetcher $MetadataFetcher
        }
        catch {
            throw (
                "Unable to resolve ChromeDriver for installed Chrome " +
                "$($chrome.Version): $($_.Exception.Message)"
            )
        }

        [IO.Directory]::CreateDirectory($temporaryRoot) | Out-Null
        $archivePath = Join-Path $temporaryRoot 'chromedriver.zip'
        try {
            & $Downloader $download.Uri $archivePath
        }
        catch {
            throw (
                "Unable to download ChromeDriver $($download.Version) from " +
                "$($download.Uri): $($_.Exception.Message)"
            )
        }
        if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
            throw 'ChromeDriver download completed without producing an archive.'
        }
        if ($download.Sha256) {
            $actualHash = (Get-FileHash `
                -LiteralPath $archivePath `
                -Algorithm SHA256).Hash
            if ($actualHash -ne $download.Sha256) {
                throw (
                    "ChromeDriver archive checksum mismatch. Expected " +
                    "$($download.Sha256), received $actualHash."
                )
            }
        }

        $extractedPath = Join-Path $temporaryRoot 'extracted'
        & $ArchiveExtractor $archivePath $extractedPath
        $drivers = @(Get-ChildItem `
            -LiteralPath $extractedPath `
            -Filter 'chromedriver.exe' `
            -File `
            -Recurse)
        if ($drivers.Count -ne 1) {
            throw (
                'ChromeDriver archive must contain exactly one ' +
                "chromedriver.exe; found $($drivers.Count)."
            )
        }

        [IO.Directory]::CreateDirectory($majorCache) | Out-Null
        $stagingPath = Join-Path $temporaryRoot 'staging'
        $stagedPlatform = Join-Path $stagingPath $platform
        [IO.Directory]::CreateDirectory($stagedPlatform) | Out-Null
        $stagedDriver = Join-Path $stagedPlatform 'chromedriver.exe'
        Copy-Item -LiteralPath $drivers[0].FullName -Destination $stagedDriver
        $null = Assert-CompatibleChromeDriver `
            -Path $stagedDriver `
            -ChromeMajor $chromeMajor `
            -VersionReader $VersionReader `
            -Source 'the downloaded Chrome for Testing archive'

        $versionPath = Join-Path $majorCache $download.Version
        if (-not (Test-Path -LiteralPath $versionPath)) {
            [IO.Directory]::Move($stagingPath, $versionPath)
            $stagingPath = $null
        }
        $cachedDriver = Join-Path $versionPath "$platform\chromedriver.exe"
        $resolved = Assert-CompatibleChromeDriver `
            -Path $cachedDriver `
            -ChromeMajor $chromeMajor `
            -VersionReader $VersionReader `
            -Source 'the persistent cache'
        Write-Host (
            "ChromeDriver: provisioned $($download.Version) for Chrome " +
            "$($chrome.Version) at $resolved"
        )
        return $resolved
    }
    finally {
        if ($stagingPath -and (Test-Path -LiteralPath $stagingPath)) {
            Remove-Item -LiteralPath $stagingPath -Recurse -Force
        }
        if (Test-Path -LiteralPath $temporaryRoot) {
            Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
        }
        $lock.Dispose()
    }
}
