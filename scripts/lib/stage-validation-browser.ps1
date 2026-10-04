Set-StrictMode -Version Latest

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

function Get-BrowserTestProgress {
    param([AllowEmptyString()][string]$Output)

    $matches = [regex]::Matches(
        $Output,
        '(?m)^BROWSER_TEST_STEP_(START|PASS|FAIL)\|([^\r\n]+)$'
    )
    if ($matches.Count -eq 0) {
        return $null
    }

    $latest = $matches[$matches.Count - 1]
    $fields = @{}
    foreach ($entry in $latest.Groups[2].Value.Split('|')) {
        $separator = $entry.IndexOf('=')
        if ($separator -le 0) {
            continue
        }
        $name = $entry.Substring(0, $separator)
        $value = [Uri]::UnescapeDataString($entry.Substring($separator + 1))
        $fields[$name] = $value
    }

    return [pscustomobject]@{
        State = $latest.Groups[1].Value
        Identity = $fields['identity']
        TestFile = $fields['file']
        Condition = $fields['condition']
        Route = $fields['route']
        ElapsedMilliseconds = $fields['elapsedMs']
        ArtifactPath = $fields['artifact']
    }
}

function Test-BrowserScenarioStarted {
    param([AllowEmptyString()][string]$Output)

    return (
        $Output -match '(?m)^BROWSER_TEST_STEP_(START|PASS|FAIL)\|' -or
        $Output -match '(?m)^\d{2}:\d{2} \+\d+(?: -\d+)?:'
    )
}

function Test-ScreenshotHandshakeRetryEligible {
    param(
        [AllowEmptyString()][string]$Output,
        [string]$Identity
    )

    return (
        $Output -match "BROWSER_SMOKE_ASSERTIONS_PASSED:$Identity" -and
        $Output -notmatch 'All tests passed[.!]'
    )
}

function Format-BrowserScenarioTimeout {
    param(
        [string]$Identity,
        [string]$TestFile,
        [string]$ArtifactPath,
        $Progress,
        [int]$TimeoutSeconds
    )

    $condition = if ($Progress) {
        $Progress.Condition
    }
    else {
        '<test body did not report a step>'
    }
    $route = if ($Progress) { $Progress.Route } else { '<unavailable>' }

    return (
        "scenario timed out after $TimeoutSeconds seconds. " +
        "Identity: $Identity. Test file: $TestFile. " +
        "Current route: $route. Awaited condition: $condition. " +
        "Artifact path: $ArtifactPath"
    )
}
