Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'scripts\lib\stage-validation-browser.ps1')
. (Join-Path $repoRoot 'scripts\lib\browser-automation.ps1')

$passed = 0

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
    $script:passed++
}

$browserSmokeSource = Get-Content -Raw -LiteralPath (
    Join-Path $repoRoot 'stage5\tool\run-browser-login-smoke.ps1'
)
Assert-True `
    -Condition $browserSmokeSource.Contains(
        'materializationKey = @{ nullValue = $null }'
    ) `
    -Message 'Browser fixture omitted the canonical materialization key.'

$functionalOutput = @'
BROWSER_TEST_STEP_START|identity=athlete|file=integration_test%2Frecovery.dart|condition=draft%20saved|route=%2Fathlete%2Fworkouts%2Fone|elapsedMs=0|artifact=C%3A%5Cartifacts
'@
$progress = Get-BrowserTestProgress -Output $functionalOutput
Assert-True `
    -Condition ($progress.Identity -eq 'athlete') `
    -Message 'Progress identity was not parsed.'
Assert-True `
    -Condition ($progress.Condition -eq 'draft saved') `
    -Message 'Progress condition was not decoded.'
Assert-True `
    -Condition (Test-BrowserScenarioStarted -Output $functionalOutput) `
    -Message 'Structured progress did not start the scenario clock.'
Assert-True `
    -Condition (Test-BrowserScenarioStarted `
        -Output '00:00 +0: recovery scenario') `
    -Message 'Flutter test output did not start the scenario clock.'
Assert-True `
    -Condition (-not (Test-BrowserScenarioStarted `
        -Output 'Building application for the web...')) `
    -Message 'Compilation output must not start the scenario clock.'
Assert-True `
    -Condition (-not (Test-ScreenshotHandshakeRetryEligible `
        -Output $functionalOutput `
        -Identity 'athlete')) `
    -Message 'A functional timeout must not be retried.'

$screenshotOutput =
    "BROWSER_SMOKE_ASSERTIONS_PASSED:athlete`n" +
    'waiting for screenshot response'
Assert-True `
    -Condition (Test-ScreenshotHandshakeRetryEligible `
        -Output $screenshotOutput `
        -Identity 'athlete') `
    -Message 'The post-assertion screenshot handshake should be retryable.'
Assert-True `
    -Condition (-not (Test-ScreenshotHandshakeRetryEligible `
        -Output "$screenshotOutput`nAll tests passed." `
        -Identity 'athlete')) `
    -Message 'A completed test must not be classified for retry.'

$diagnostic = Format-BrowserScenarioTimeout `
    -Identity 'athlete' `
    -TestFile 'integration_test/recovery.dart' `
    -ArtifactPath 'C:\artifacts' `
    -Progress $progress `
    -TimeoutSeconds 90
foreach ($expected in @(
        'athlete',
        'integration_test/recovery.dart',
        '/athlete/workouts/one',
        'draft saved',
        'C:\artifacts',
        '90 seconds'
    )) {
    Assert-True `
        -Condition $diagnostic.Contains($expected) `
        -Message "Timeout diagnostic omitted: $expected"
}

$chromeFlags = @(Get-FocusIndependentChromeFlags -ChromeFlags @(
        '--headless=new',
        '--disable-renderer-backgrounding=false',
        '--window-size=1280,800'
    ))
foreach ($requiredFlag in @(
        '--disable-background-timer-throttling',
        '--disable-backgrounding-occluded-windows'
    )) {
    Assert-True `
        -Condition ($chromeFlags -contains $requiredFlag) `
        -Message "Chrome automation flag was omitted: $requiredFlag"
}
Assert-True `
    -Condition ($chromeFlags -contains '--disable-renderer-backgrounding=false') `
    -Message 'An explicit Chrome flag value was overridden.'
Assert-True `
    -Condition (
        @($chromeFlags | Where-Object {
                $_ -like '--disable-renderer-backgrounding*'
            }).Count -eq 1
    ) `
    -Message 'A caller-provided Chrome flag was duplicated.'
Assert-True `
    -Condition ($chromeFlags[0] -eq '--headless=new') `
    -Message 'Existing Chrome flag order was not preserved.'

$flutterDriveFlags = @(Get-FlutterDriveChromeFlagArguments)
foreach ($requiredFlag in @(
        '--disable-background-timer-throttling',
        '--disable-renderer-backgrounding',
        '--disable-backgrounding-occluded-windows'
    )) {
    Assert-True `
        -Condition (
            $flutterDriveFlags -contains "--web-browser-flag=$requiredFlag"
        ) `
        -Message "Flutter drive did not receive Chrome flag: $requiredFlag"
}

$tempRoot = Join-Path $env:TEMP (
    'stage-validation-browser-test-' + [Guid]::NewGuid().ToString('N')
)
New-Item -ItemType Directory -Path $tempRoot | Out-Null
$childScript = Join-Path $tempRoot 'spawn-child.ps1'
$childPidPath = Join-Path $tempRoot 'child.pid'
$parent = $null
$unrelated = $null
$ownedChildId = $null
$job = $null
try {
    @'
param([string]$ChildPidPath)
$child = Start-Process powershell `
    -ArgumentList '-NoProfile', '-Command', 'Start-Sleep -Seconds 60' `
    -WindowStyle Hidden `
    -PassThru
Set-Content -LiteralPath $ChildPidPath -Value $child.Id
Start-Sleep -Seconds 60
'@ | Set-Content -LiteralPath $childScript

    $unrelated = Start-Process powershell `
        -ArgumentList '-NoProfile', '-Command', 'Start-Sleep -Seconds 60' `
        -WindowStyle Hidden `
        -PassThru
    $parent = Start-Process powershell `
        -ArgumentList @(
            '-NoProfile',
            '-File',
            "`"$childScript`"",
            '-ChildPidPath',
            "`"$childPidPath`""
        ) `
        -WindowStyle Hidden `
        -PassThru
    $job = [StageValidationProcessJob]::new()
    $job.Add($parent)

    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while (
        -not (Test-Path -LiteralPath $childPidPath) -and
        [DateTime]::UtcNow -lt $deadline
    ) {
        Start-Sleep -Milliseconds 100
    }
    Assert-True `
        -Condition (Test-Path -LiteralPath $childPidPath) `
        -Message 'Owned child process did not report its PID.'
    $ownedChildId = [int](Get-Content -LiteralPath $childPidPath)

    $job.Dispose()
    $job = $null
    Start-Sleep -Seconds 1

    Assert-True `
        -Condition (-not (Get-Process -Id $parent.Id -ErrorAction SilentlyContinue)) `
        -Message 'Closing the job did not terminate its exact parent PID.'
    Assert-True `
        -Condition (-not (Get-Process `
            -Id $ownedChildId `
            -ErrorAction SilentlyContinue)) `
        -Message 'Closing the job did not terminate its owned child PID.'
    Assert-True `
        -Condition ([bool](Get-Process `
            -Id $unrelated.Id `
            -ErrorAction SilentlyContinue)) `
        -Message 'Job cleanup terminated an unrelated process.'
}
finally {
    if ($job) {
        $job.Dispose()
    }
    foreach ($processId in @(
            if ($parent) { $parent.Id }
            if ($ownedChildId) { $ownedChildId }
            if ($unrelated) { $unrelated.Id }
        )) {
        if (Get-Process -Id $processId -ErrorAction SilentlyContinue) {
            Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
        }
    }
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

Write-Host "$passed stage validation browser harness assertions passed."
