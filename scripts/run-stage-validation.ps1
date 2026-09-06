param(
    [string]$Stage,
    [string]$ChromeDriverPath = $env:CHROMEDRIVER_PATH
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

if (-not ('StageValidationProcessJob' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;

public sealed class StageValidationProcessJob : IDisposable
{
    private const uint KillOnJobClose = 0x00002000;
    private IntPtr handle;

    public StageValidationProcessJob()
    {
        handle = CreateJobObject(IntPtr.Zero, null);
        if (handle == IntPtr.Zero)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }

        var info = new ExtendedLimitInformation();
        info.BasicLimitInformation.LimitFlags = KillOnJobClose;
        int length = Marshal.SizeOf(info);
        IntPtr pointer = Marshal.AllocHGlobal(length);
        try
        {
            Marshal.StructureToPtr(info, pointer, false);
            if (!SetInformationJobObject(handle, 9, pointer, (uint)length))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
        }
        finally
        {
            Marshal.FreeHGlobal(pointer);
        }
    }

    public void Add(Process process)
    {
        if (!AssignProcessToJobObject(handle, process.Handle))
        {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }
    }

    public void Dispose()
    {
        if (handle != IntPtr.Zero)
        {
            CloseHandle(handle);
            handle = IntPtr.Zero;
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BasicLimitInformation
    {
        public long PerProcessUserTimeLimit;
        public long PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass;
        public uint SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct IoCounters
    {
        public ulong ReadOperationCount;
        public ulong WriteOperationCount;
        public ulong OtherOperationCount;
        public ulong ReadTransferCount;
        public ulong WriteTransferCount;
        public ulong OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct ExtendedLimitInformation
    {
        public BasicLimitInformation BasicLimitInformation;
        public IoCounters IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr CreateJobObject(
        IntPtr securityAttributes,
        string name
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetInformationJobObject(
        IntPtr job,
        int informationClass,
        IntPtr information,
        uint informationLength
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool AssignProcessToJobObject(
        IntPtr job,
        IntPtr process
    );

    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);
}
'@
}

function Write-ProcessOutput {
    param(
        [string]$OutputPath,
        [string]$ErrorPath
    )

    Get-Content -LiteralPath $OutputPath -ErrorAction SilentlyContinue |
        Write-Host
    Get-Content -LiteralPath $ErrorPath -ErrorAction SilentlyContinue |
        ForEach-Object { [Console]::Error.WriteLine($_) }
}

function Invoke-BrowserIntegrationTest {
    param(
        [string]$Identity,
        [string]$RunnerPath,
        [string]$Target
    )

    $powershellExe = (Get-Command 'powershell' -ErrorAction Stop).Source
    $lastFailure = $null

    for ($attempt = 1; $attempt -le 2; $attempt++) {
        $retryAllowed = $false
        $runId = [Guid]::NewGuid().ToString('N')
        $startGateName = "MercedesStageValidation-$runId"
        $outputPath = Join-Path $env:TEMP "stage-validation-$runId.out.log"
        $errorPath = Join-Path $env:TEMP "stage-validation-$runId.err.log"
        $arguments = '-NoProfile -ExecutionPolicy Bypass ' +
            "-File `"$RunnerPath`" -Identity $Identity -SkipPubGet " +
            "-TestTarget `"$Target`" -StartGateName $startGateName"
        $env:BROWSER_SMOKE_ATTEMPT = "$attempt"
        $job = [StageValidationProcessJob]::new()
        $createdNew = $false
        $startGate = [Threading.EventWaitHandle]::new(
            $false,
            [Threading.EventResetMode]::ManualReset,
            $startGateName,
            [ref]$createdNew
        )
        if (-not $createdNew) {
            $startGate.Dispose()
            $job.Dispose()
            throw "Could not create browser process start gate: $startGateName"
        }
        $process = $null

        try {
            $process = Start-Process `
                -FilePath $powershellExe `
                -ArgumentList $arguments `
                -PassThru `
                -NoNewWindow `
                -RedirectStandardOutput $outputPath `
                -RedirectStandardError $errorPath
            try {
                $job.Add($process)
                $startGate.Set() | Out-Null
            }
            catch {
                Stop-Process `
                    -Id $process.Id `
                    -Force `
                    -ErrorAction SilentlyContinue
                throw
            }

            if (-not $process.WaitForExit(240000)) {
                $lastFailure = 'timed out after 240 seconds'
                $output = Get-Content `
                    -LiteralPath $outputPath `
                    -Raw `
                    -ErrorAction SilentlyContinue
                $retryAllowed =
                    $output -match 'All tests passed\.' -and
                    $output -match '"screenshots"'
            }
            elseif ($process.ExitCode -ne 0) {
                $lastFailure = "exited with code $($process.ExitCode)"
            }
            else {
                Write-ProcessOutput `
                    -OutputPath $outputPath `
                    -ErrorPath $errorPath
                return
            }

            Write-ProcessOutput `
                -OutputPath $outputPath `
                -ErrorPath $errorPath
        }
        finally {
            $job.Dispose()
            $startGate.Dispose()
            Remove-Item `
                -LiteralPath $outputPath `
                -Force `
                -ErrorAction SilentlyContinue
            Remove-Item `
                -LiteralPath $errorPath `
                -Force `
                -ErrorAction SilentlyContinue
        }

        if ($attempt -lt 2 -and $retryAllowed) {
            Write-Warning (
                "$Target as $Identity completed its assertions but " +
                "$lastFailure during the screenshot handshake; retrying once."
            )
        }
        else {
            break
        }
    }

    throw "$Target failed for identity ${Identity}: $lastFailure."
}

function Write-TestArtifacts {
    param([string]$ArtifactPath)

    Write-Host "Test artifacts: $ArtifactPath" -ForegroundColor Green
    if (Test-Path -LiteralPath $ArtifactPath -PathType Container) {
        Get-ChildItem -LiteralPath $ArtifactPath -File -Recurse |
            Sort-Object FullName |
            ForEach-Object { Write-Host "  $($_.FullName)" }
    }
}

if (-not $Stage) {
    $stageDirectory = Get-ChildItem -Path $repoRoot -Directory |
        Where-Object { $_.Name -match '^stage[1-9][0-9]*$' } |
        Sort-Object { [int]$_.Name.Substring(5) } -Descending |
        Select-Object -First 1
    if (-not $stageDirectory) {
        throw 'No stage directory was found.'
    }
    $Stage = $stageDirectory.Name
}

if ($Stage -notmatch '^stage[1-9][0-9]*$') {
    throw "Invalid stage directory name: $Stage"
}

$stagePath = Join-Path $repoRoot $Stage
if (-not (Test-Path -LiteralPath $stagePath -PathType Container)) {
    throw "Stage directory not found: $stagePath"
}
$validationRunId = '{0}-{1}' -f (
    (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'),
    [Guid]::NewGuid().ToString('N').Substring(0, 8)
)
$artifactPath = Join-Path `
    $stagePath `
    "test-artifacts\stage-validation\$validationRunId"
try {
    $env:BROWSER_SMOKE_ARTIFACT_DIR_OVERRIDE = $artifactPath
    if ($ChromeDriverPath) {
        $env:CHROMEDRIVER_PATH = (Resolve-Path $ChromeDriverPath).Path
    }

    Write-Host "Validating $Stage" -ForegroundColor Cyan

    Push-Location $stagePath
    try {
        & flutter pub get
        if ($LASTEXITCODE -ne 0) {
            throw 'flutter pub get failed.'
        }

        & flutter test --no-pub
        if ($LASTEXITCODE -ne 0) {
            throw 'Flutter tests failed.'
        }

        & flutter analyze --no-pub --no-fatal-infos
        if ($LASTEXITCODE -ne 0) {
            throw 'Flutter analyzer reported errors or warnings.'
        }
    }
    finally {
        Pop-Location
    }

    $rulesPath = Join-Path $repoRoot 'test-rules'
    if (Test-Path -LiteralPath (Join-Path $rulesPath 'package.json')) {
        Push-Location $rulesPath
        try {
            & npm ci --quiet
            if ($LASTEXITCODE -ne 0) {
                throw 'Firestore rules dependency restore failed.'
            }

            & npm test
            if ($LASTEXITCODE -ne 0) {
                throw 'Firestore emulator rules tests failed.'
            }
        }
        finally {
            Pop-Location
        }
    }

    $integrationPath = Join-Path $stagePath 'integration_test'
    $integrationTests = @()
    if (Test-Path -LiteralPath $integrationPath -PathType Container) {
        $integrationTests = @(
            Get-ChildItem `
                -LiteralPath $integrationPath `
                -Filter '*_test.dart' `
                -File |
                Sort-Object Name
        )
    }

    if ($integrationTests.Count -gt 0) {
        $integrationRunner =
            Join-Path $stagePath 'tool\run-browser-login-smoke.ps1'
        if (-not (Test-Path -LiteralPath $integrationRunner -PathType Leaf)) {
            throw "Integration runner not found: $integrationRunner"
        }

        foreach ($integrationTest in $integrationTests) {
            $target = "integration_test\$($integrationTest.Name)"
            foreach ($identity in @('trainer', 'athlete')) {
                Write-Host "Running $target as $identity" -ForegroundColor Cyan
                Invoke-BrowserIntegrationTest `
                    -Identity $identity `
                    -RunnerPath $integrationRunner `
                    -Target $target
            }
        }
    }

    Write-Host "$Stage validation passed." -ForegroundColor Green
}
finally {
    $env:BROWSER_SMOKE_ATTEMPT = $null
    $env:BROWSER_SMOKE_ARTIFACT_DIR_OVERRIDE = $null
    Write-TestArtifacts -ArtifactPath $artifactPath
}
