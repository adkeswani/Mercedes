param(
    [switch]$InsideEmulators,
    [switch]$SkipPubGet,
    [string]$ChromeDriverPath = $env:CHROMEDRIVER_PATH,
    [string]$TestTarget = $env:BROWSER_SMOKE_TEST_TARGET,
    [string]$StartGateName = $env:BROWSER_SMOKE_START_GATE,
    [ValidateSet('trainer', 'athlete')]
    [string]$Identity = 'trainer'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($StartGateName) {
    $startGate = [Threading.EventWaitHandle]::OpenExisting($StartGateName)
    try {
        if (-not $startGate.WaitOne(30000)) {
            throw 'Timed out waiting for the stage validation start gate.'
        }
    }
    finally {
        $startGate.Dispose()
    }
}

$projectId = 'mercedes-app-11ce2'
$stagePath = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $stagePath
$stageName = Split-Path -Leaf $stagePath
$artifactRoot = Join-Path $stagePath 'test-artifacts'
$artifactPath = Join-Path $artifactRoot 'browser-login'
if ($env:BROWSER_SMOKE_ARTIFACT_DIR_OVERRIDE) {
    $resolvedArtifactRoot = [IO.Path]::GetFullPath($artifactRoot)
    $resolvedArtifactPath = [IO.Path]::GetFullPath(
        $env:BROWSER_SMOKE_ARTIFACT_DIR_OVERRIDE
    )
    if (-not $resolvedArtifactPath.StartsWith(
            "$resolvedArtifactRoot\",
            [StringComparison]::OrdinalIgnoreCase
        )) {
        throw "Artifact directory must be inside $resolvedArtifactRoot."
    }
    $artifactPath = $resolvedArtifactPath
}
$identities = @{
    trainer = [ordered]@{
        Role = 'trainer'
        Email = 'browser-smoke-trainer@mercedes.test'
        Password = 'BrowserSmokeTrainer123!'
        DisplayName = 'Browser Smoke Trainer'
        Username = 'browser_smoke_trainer'
    }
    athlete = [ordered]@{
        Role = 'athlete'
        Email = 'browser-smoke-athlete@mercedes.test'
        Password = 'BrowserSmokeAthlete123!'
        DisplayName = 'Browser Smoke Athlete'
        Username = 'browser_smoke_athlete'
    }
}

if (-not $InsideEmulators) {
    if ($ChromeDriverPath) {
        $env:CHROMEDRIVER_PATH = (Resolve-Path $ChromeDriverPath).Path
    }
    $env:BROWSER_SMOKE_TEST_TARGET = $TestTarget

    Push-Location $repoRoot
    try {
        $innerCommand = 'powershell -NoProfile -ExecutionPolicy Bypass ' +
            "-File `"$stageName\tool\run-browser-login-smoke.ps1`" " +
            "-InsideEmulators -Identity $Identity"
        if ($SkipPubGet) {
            $innerCommand += ' -SkipPubGet'
        }
        & firebase emulators:exec `
            --only auth,firestore `
            --project $projectId `
            $innerCommand
        if ($LASTEXITCODE -ne 0) {
            throw 'Browser login smoke test failed.'
        }
    }
    finally {
        Pop-Location
    }

    exit 0
}

function New-BrowserSmokeIdentity {
    param([System.Collections.IDictionary]$Config)

    $authBody = @{
        email = $Config.Email
        password = $Config.Password
        returnSecureToken = $true
    } | ConvertTo-Json
    $authUri = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/' +
        'v1/accounts:signUp?key=local-emulator'
    $authUser = Invoke-RestMethod `
        -Method Post `
        -Uri $authUri `
        -ContentType 'application/json' `
        -Body $authBody
    $uid = $authUser.localId
    $timestamp = (Get-Date).ToUniversalTime().ToString('o')

    $profileBody = @{
        fields = @{
            uid = @{ stringValue = $uid }
            displayName = @{ stringValue = $Config.DisplayName }
            email = @{ stringValue = $Config.Email }
            username = @{ stringValue = $Config.Username }
            discoverable = @{ booleanValue = $false }
            createdAt = @{ timestampValue = $timestamp }
            createdBy = @{ stringValue = $uid }
            updatedAt = @{ timestampValue = $timestamp }
            updatedBy = @{ stringValue = $uid }
        }

    } | ConvertTo-Json -Depth 5
    $profileUri = "http://127.0.0.1:8080/v1/projects/$projectId/" +
        "databases/(default)/documents/users/$uid"
    Invoke-RestMethod `
        -Method Patch `
        -Uri $profileUri `
        -Headers @{ Authorization = "Bearer $($authUser.idToken)" } `
        -ContentType 'application/json' `
        -Body $profileBody | Out-Null

    return [pscustomobject]@{
        Role = $Config.Role
        Email = $Config.Email
        Password = $Config.Password
        Uid = $uid
        IdToken = $authUser.idToken
    }
}

function Get-FreeTcpPort {
    $listener = [Net.Sockets.TcpListener]::new(
        [Net.IPAddress]::Loopback,
        0
    )
    try {
        $listener.Start()
        return ([Net.IPEndPoint]$listener.LocalEndpoint).Port
    }
    finally {
        $listener.Stop()
    }
}

$trainer = New-BrowserSmokeIdentity -Config $identities.trainer
$athlete = New-BrowserSmokeIdentity -Config $identities.athlete
$relationshipId = "$($trainer.Uid)_$($athlete.Uid)"
$relationshipBody = @{
    writes = @(
        @{
            update = @{
                name = "projects/$projectId/databases/(default)/documents/" +
                    "trainerClientRelationships/$relationshipId"
                fields = @{
                    trainerId = @{ stringValue = $trainer.Uid }
                    athleteId = @{ stringValue = $athlete.Uid }
                    status = @{ stringValue = 'active' }
                    endedAt = @{ nullValue = $null }
                    createdBy = @{ stringValue = $trainer.Uid }
                    updatedBy = @{ stringValue = $trainer.Uid }
                    deletedAt = @{ nullValue = $null }
                    deletedBy = @{ nullValue = $null }
                }
            }
            updateTransforms = @(
                @{
                    fieldPath = 'startedAt'
                    setToServerValue = 'REQUEST_TIME'
                },
                @{
                    fieldPath = 'createdAt'
                    setToServerValue = 'REQUEST_TIME'
                },
                @{
                    fieldPath = 'updatedAt'
                    setToServerValue = 'REQUEST_TIME'
                }
            )
        }
    )
} | ConvertTo-Json -Depth 8
$commitUri = "http://127.0.0.1:8080/v1/projects/$projectId/" +
    'databases/(default)/documents:commit'
Invoke-RestMethod `
    -Method Post `
    -Uri $commitUri `
    -Headers @{ Authorization = "Bearer $($trainer.IdToken)" } `
    -ContentType 'application/json' `
    -Body $relationshipBody | Out-Null

$today = Get-Date
$calendarDate = $today.ToString('yyyy-MM-dd')
$historyDate = $today.AddDays(-7).ToString('yyyy-MM-dd')
$calendarTimestamp = [DateTime]::ParseExact(
    $calendarDate,
    'yyyy-MM-dd',
    [Globalization.CultureInfo]::InvariantCulture
).ToUniversalTime().ToString('o')
$historyTimestamp = [DateTime]::ParseExact(
    $historyDate,
    'yyyy-MM-dd',
    [Globalization.CultureInfo]::InvariantCulture
).ToUniversalTime().ToString('o')
$seedTimestamp = $today.ToUniversalTime().ToString('o')
$programId = 'browser-athlete-program'
$programInstanceId = 'browser-athlete-program-instance'
$calendarTemplateId = 'browser-calendar-workout'
$historyTemplateId = 'browser-history-workout'
$workspaceSeedBody = @{
    writes = @(
        @{
            update = @{
                name = "projects/$projectId/databases/(default)/documents/" +
                    "programs/$programId"
                fields = @{
                    name = @{ stringValue = 'Browser Athlete Program' }
                    description = @{
                        stringValue = 'Deterministic athlete workspace program'
                    }
                    ownerId = @{ stringValue = $trainer.Uid }
                    type = @{ stringValue = 'assignable' }
                    status = @{ stringValue = 'published' }
                    currentVersion = @{ integerValue = '1' }
                    createdAt = @{ timestampValue = $seedTimestamp }
                    createdBy = @{ stringValue = $trainer.Uid }
                    updatedAt = @{ timestampValue = $seedTimestamp }
                    updatedBy = @{ stringValue = $trainer.Uid }
                    deletedAt = @{ nullValue = $null }
                    deletedBy = @{ nullValue = $null }
                }
            }
        },
        @{
            update = @{
                name = "projects/$projectId/databases/(default)/documents/" +
                    "enrollments/$($programId)_$($athlete.Uid)"
                fields = @{
                    programId = @{ stringValue = $programId }
                    athleteId = @{ stringValue = $athlete.Uid }
                    addedAt = @{ timestampValue = $seedTimestamp }
                    addedBy = @{ stringValue = $trainer.Uid }
                    status = @{ stringValue = 'active' }
                    createdAt = @{ timestampValue = $seedTimestamp }
                    createdBy = @{ stringValue = $trainer.Uid }
                    updatedAt = @{ timestampValue = $seedTimestamp }
                    updatedBy = @{ stringValue = $trainer.Uid }
                    deletedAt = @{ nullValue = $null }
                    deletedBy = @{ nullValue = $null }
                }
            }
        },
        @{
            update = @{
                name = "projects/$projectId/databases/(default)/documents/" +
                    "athleteProgramInstances/$programInstanceId"
                fields = @{
                    athleteOwnerId = @{ stringValue = $athlete.Uid }
                    assigningTrainerId = @{ stringValue = $trainer.Uid }
                    sourceProgramId = @{ stringValue = $programId }
                    sourceProgramVersion = @{ integerValue = '1' }
                    relationshipMode = @{ stringValue = 'subscribed' }
                    startDate = @{ stringValue = $calendarDate }
                    expectedEndDate = @{
                        stringValue = $today.AddDays(14).ToString('yyyy-MM-dd')
                    }
                    workoutCount = @{ integerValue = '2' }
                    status = @{ stringValue = 'active' }
                    linkedAt = @{ timestampValue = $seedTimestamp }
                    unlinkedAt = @{ nullValue = $null }
                    unlinkReason = @{ nullValue = $null }
                    propagationState = @{ stringValue = 'complete' }
                    propagationTargetVersion = @{ integerValue = '1' }
                    propagationAttempt = @{ integerValue = '0' }
                    propagationCompletedAt = @{
                        timestampValue = $seedTimestamp
                    }
                    createdAt = @{ timestampValue = $seedTimestamp }
                    createdBy = @{ stringValue = $trainer.Uid }
                    updatedAt = @{ timestampValue = $seedTimestamp }
                    updatedBy = @{ stringValue = $trainer.Uid }
                    deletedAt = @{ nullValue = $null }
                    deletedBy = @{ nullValue = $null }
                }
            }
        },
        @{
            update = @{
                name = "projects/$projectId/databases/(default)/documents/" +
                    "workoutTemplates/$calendarTemplateId"
                fields = @{
                    name = @{ stringValue = 'Browser Calendar Workout' }
                    ownerId = @{ stringValue = $trainer.Uid }
                    workoutType = @{ stringValue = 'fullBody' }
                    currentVersion = @{ integerValue = '1' }
                    createdAt = @{ timestampValue = $seedTimestamp }
                    createdBy = @{ stringValue = $trainer.Uid }
                    updatedAt = @{ timestampValue = $seedTimestamp }
                    updatedBy = @{ stringValue = $trainer.Uid }
                    deletedAt = @{ nullValue = $null }
                    deletedBy = @{ nullValue = $null }
                }
            }
        },
        @{
            update = @{
                name = "projects/$projectId/databases/(default)/documents/" +
                    "workoutTemplates/$historyTemplateId"
                fields = @{
                    name = @{ stringValue = 'Browser Completed Workout' }
                    ownerId = @{ stringValue = $trainer.Uid }
                    workoutType = @{ stringValue = 'fullBody' }
                    currentVersion = @{ integerValue = '1' }
                    createdAt = @{ timestampValue = $seedTimestamp }
                    createdBy = @{ stringValue = $trainer.Uid }
                    updatedAt = @{ timestampValue = $seedTimestamp }
                    updatedBy = @{ stringValue = $trainer.Uid }
                    deletedAt = @{ nullValue = $null }
                    deletedBy = @{ nullValue = $null }
                }
            }
        },
        @{
            update = @{
                name = "projects/$projectId/databases/(default)/documents/" +
                    'workoutInstances/browser-calendar-workout'
                fields = @{
                    programId = @{ stringValue = $programId }
                    programOwnerId = @{ stringValue = $trainer.Uid }
                    programVersion = @{ integerValue = '1' }
                    athleteProgramInstanceId = @{
                        stringValue = $programInstanceId
                    }
                    programAssignmentId = @{
                        stringValue = $programInstanceId
                    }
                    relationshipMode = @{ stringValue = 'subscribed' }
                    athleteId = @{ stringValue = $athlete.Uid }
                    workoutTemplateId = @{
                        stringValue = $calendarTemplateId
                    }
                    workoutTemplateVersion = @{ integerValue = '1' }
                    scheduledDate = @{ stringValue = $calendarDate }
                    scheduledAt = @{ timestampValue = $calendarTimestamp }
                    assignedBy = @{ stringValue = $trainer.Uid }
                    assignedAt = @{ timestampValue = $seedTimestamp }
                    status = @{ stringValue = 'scheduled' }
                    workoutType = @{ stringValue = 'fullBody' }
                    createdAt = @{ timestampValue = $seedTimestamp }
                    updatedAt = @{ timestampValue = $seedTimestamp }
                }
            }
        },
        @{
            update = @{
                name = "projects/$projectId/databases/(default)/documents/" +
                    'workoutInstances/browser-history-workout'
                fields = @{
                    programId = @{ stringValue = $programId }
                    programOwnerId = @{ stringValue = $trainer.Uid }
                    programVersion = @{ integerValue = '1' }
                    athleteProgramInstanceId = @{
                        stringValue = $programInstanceId
                    }
                    programAssignmentId = @{
                        stringValue = $programInstanceId
                    }
                    relationshipMode = @{ stringValue = 'subscribed' }
                    athleteId = @{ stringValue = $athlete.Uid }
                    workoutTemplateId = @{ stringValue = $historyTemplateId }
                    workoutTemplateVersion = @{ integerValue = '1' }
                    scheduledDate = @{ stringValue = $historyDate }
                    scheduledAt = @{ timestampValue = $historyTimestamp }
                    assignedBy = @{ stringValue = $trainer.Uid }
                    assignedAt = @{ timestampValue = $historyTimestamp }
                    status = @{ stringValue = 'completed' }
                    completedAt = @{ timestampValue = $historyTimestamp }
                    rpe = @{ integerValue = '8' }
                    durationMinutes = @{ integerValue = '45' }
                    workoutType = @{ stringValue = 'fullBody' }
                    createdAt = @{ timestampValue = $historyTimestamp }
                    updatedAt = @{ timestampValue = $historyTimestamp }
                }
            }
        }
    )
} | ConvertTo-Json -Depth 12
Invoke-RestMethod `
    -Method Post `
    -Uri $commitUri `
    -Headers @{ Authorization = 'Bearer owner' } `
    -ContentType 'application/json' `
    -Body $workspaceSeedBody | Out-Null

$selectedIdentity = if ($Identity -eq 'trainer') { $trainer } else { $athlete }
$attempt = $env:BROWSER_SMOKE_ATTEMPT
if ($attempt -and $attempt -ne '1') {
    $artifactPath = Join-Path $artifactPath "retry-$attempt"
}
$env:BROWSER_SMOKE_ARTIFACT_DIR = $artifactPath
New-Item -ItemType Directory -Force -Path $artifactPath | Out-Null
foreach ($artifactName in @(
        "$Identity-auth-before-login.png",
        "$Identity-app-after-login.png",
        "$Identity-header-identity.png",
        'athlete-my-programs.png',
        'athlete-workout-history.png',
        'athlete-calendar.png'
    )) {
    Remove-Item `
        -LiteralPath (Join-Path $artifactPath $artifactName) `
        -Force `
        -ErrorAction SilentlyContinue
}

Push-Location $stagePath
$webServerProcess = $null
$chromeDriverProcess = $null
$browserSessionId = $null
$driverBaseUri = $null
try {
    if (-not $ChromeDriverPath) {
        $chromeDriver = Get-Command 'chromedriver' -ErrorAction SilentlyContinue
        if ($chromeDriver) {
            $ChromeDriverPath = $chromeDriver.Source
        }
    }
    if (-not $ChromeDriverPath -or -not (Test-Path $ChromeDriverPath)) {
        throw 'ChromeDriver was not found. Set CHROMEDRIVER_PATH to a driver that matches the installed Chrome version.'
    }

    if (-not $SkipPubGet) {
        & flutter pub get
        if ($LASTEXITCODE -ne 0) {
            throw 'flutter pub get failed.'
        }
    }

    if ($TestTarget) {
        $integrationPath = (Resolve-Path 'integration_test').Path
        $resolvedTestTarget = (Resolve-Path $TestTarget).Path
        if (-not $resolvedTestTarget.StartsWith(
                "$integrationPath\",
                [StringComparison]::OrdinalIgnoreCase
            )) {
            throw "Integration test must be inside $integrationPath."
        }
        $relativeTestTarget = $resolvedTestTarget.Substring(
            $stagePath.Length
        ).TrimStart('\')
        $driverPort = Get-FreeTcpPort
        $chromeDriverProcess = Start-Process `
            -FilePath $ChromeDriverPath `
            -ArgumentList "--port=$driverPort" `
            -PassThru `
            -WindowStyle Hidden
        Start-Sleep -Seconds 1
        if ($chromeDriverProcess.HasExited) {
            throw 'ChromeDriver exited before the browser test started.'
        }

        & flutter drive `
            --driver 'test_driver\integration_test.dart' `
            --target $relativeTestTarget `
            -d chrome `
            --headless `
            --no-keep-app-running `
            --browser-dimension=1280x800 `
            "--driver-port=$driverPort" `
            --timeout=180 `
            --no-pub `
            --dart-define=USE_FIREBASE_EMULATORS=true `
            --dart-define=BROWSER_LOGIN_SMOKE=true `
            "--dart-define=BROWSER_SMOKE_ROLE=$($selectedIdentity.Role)" `
            "--dart-define=BROWSER_SMOKE_EMAIL=$($selectedIdentity.Email)" `
            "--dart-define=BROWSER_SMOKE_PASSWORD=$($selectedIdentity.Password)"
        if ($LASTEXITCODE -ne 0) {
            throw "Flutter integration test failed: $relativeTestTarget"
        }
        return
    }

    & flutter build web `
        --debug `
        --no-pub `
        --dart-define=USE_FIREBASE_EMULATORS=true `
        --dart-define=BROWSER_LOGIN_SMOKE=true `
        --dart-define=BROWSER_SMOKE_AUTO_LOGIN=true `
        "--dart-define=BROWSER_SMOKE_ROLE=$($selectedIdentity.Role)" `
        "--dart-define=BROWSER_SMOKE_EMAIL=$($selectedIdentity.Email)" `
        "--dart-define=BROWSER_SMOKE_PASSWORD=$($selectedIdentity.Password)"
    if ($LASTEXITCODE -ne 0) {
        throw 'Flutter web build failed.'
    }

    $python = Get-Command 'python' -ErrorAction Stop
    $webPort = Get-FreeTcpPort
    $driverPort = Get-FreeTcpPort
    $webServerProcess = Start-Process `
        -FilePath $python.Source `
        -ArgumentList '-m', 'http.server', "$webPort", '--bind', '127.0.0.1' `
        -WorkingDirectory (Join-Path $stagePath 'build\web') `
        -PassThru `
        -WindowStyle Hidden
    $chromeDriverProcess = Start-Process `
        -FilePath $ChromeDriverPath `
        -ArgumentList "--port=$driverPort" `
        -PassThru `
        -WindowStyle Hidden

    $driverBaseUri = "http://127.0.0.1:$driverPort"
    $driverDeadline = [DateTime]::UtcNow.AddSeconds(15)
    $driverReady = $false
    while ([DateTime]::UtcNow -lt $driverDeadline) {
        try {
            Invoke-RestMethod -Uri "$driverBaseUri/status" | Out-Null
            $driverReady = $true
            break
        }
        catch {
            Start-Sleep -Milliseconds 200
        }
    }
    if (-not $driverReady -or $chromeDriverProcess.HasExited) {
        throw 'ChromeDriver did not become ready for the browser smoke test.'
    }

    $sessionBody = @{
        capabilities = @{
            alwaysMatch = @{
                browserName = 'chrome'
                'goog:chromeOptions' = @{
                    args = @(
                        '--headless=new',
                        '--window-size=1280,800',
                        '--disable-gpu',
                        '--no-sandbox'
                    )
                }
            }
        }
    } | ConvertTo-Json -Depth 6
    $session = Invoke-RestMethod `
        -Method Post `
        -Uri "$driverBaseUri/session" `
        -ContentType 'application/json' `
        -Body $sessionBody
    $browserSessionId = $session.value.sessionId
    if (-not $browserSessionId) {
        throw 'ChromeDriver did not return a browser session ID.'
    }

    function Save-BrowserScreenshot {
        param([string]$Name)

        $screenshot = Invoke-RestMethod `
            -Uri "$driverBaseUri/session/$browserSessionId/screenshot"
        $screenshotBytes = [Convert]::FromBase64String($screenshot.value)
        if ($screenshotBytes.Length -eq 0) {
            throw "Browser smoke screenshot was empty: $Name"
        }
        [IO.File]::WriteAllBytes(
            (Join-Path $artifactPath "$Name.png"),
            $screenshotBytes
        )
    }

    $expectedWorkspace = if ($Identity -eq 'trainer') {
        'trainer'
    }
    else {
        'athlete'
    }
    $workspaceRoute = if ($Identity -eq 'trainer') {
        'trainer/dashboard'
    }
    else {
        'athlete/today'
    }
    $appUri = "http://127.0.0.1:$webPort/#/$workspaceRoute"
    Invoke-RestMethod `
        -Method Post `
        -Uri "$driverBaseUri/session/$browserSessionId/url" `
        -ContentType 'application/json' `
        -Body (@{ url = $appUri } | ConvertTo-Json) |
        Out-Null

    $authenticatedState = $null
    $loginDeadline = [DateTime]::UtcNow.AddSeconds(60)
    $identityScript = @{
        script = @'
return document.body ? {
  email: document.body.getAttribute('data-browser-smoke-authenticated'),
  workspace: document.body.getAttribute('data-browser-smoke-workspace'),
  identity: document.body.getAttribute('data-browser-smoke-account-identity')
} : null;
'@
        args = @()
    } | ConvertTo-Json
    while ([DateTime]::UtcNow -lt $loginDeadline) {
        $result = Invoke-RestMethod `
            -Method Post `
            -Uri "$driverBaseUri/session/$browserSessionId/execute/sync" `
            -ContentType 'application/json' `
            -Body $identityScript
        $authenticatedState = $result.value
        if (
            $authenticatedState.email -eq $selectedIdentity.Email -and
            $authenticatedState.workspace -eq $expectedWorkspace -and
            $authenticatedState.identity -eq $identities[$Identity].DisplayName
        ) {
            break
        }
        Start-Sleep -Milliseconds 250
    }
    if (
        $authenticatedState.email -ne $selectedIdentity.Email -or
        $authenticatedState.workspace -ne $expectedWorkspace -or
        $authenticatedState.identity -ne $identities[$Identity].DisplayName
    ) {
        $currentUrl = Invoke-RestMethod `
            -Uri "$driverBaseUri/session/$browserSessionId/url"
        throw (
            'Browser smoke did not reach the expected authenticated ' +
            "workspace. URL: $($currentUrl.value)"
        )
    }

    $currentUrl = Invoke-RestMethod `
        -Uri "$driverBaseUri/session/$browserSessionId/url"
    $currentRoute = ([Uri]$currentUrl.value).Fragment.TrimStart('#')
    if ($currentRoute -ne "/$workspaceRoute") {
        throw (
            "Browser smoke expected /$workspaceRoute but reached " +
            "$currentRoute."
        )
    }

    Write-Host "BROWSER_SMOKE_ROUTE_ASSERTIONS_PASSED:$Identity"
    Save-BrowserScreenshot -Name "$Identity-header-identity"

    if ($Identity -eq 'athlete') {
        $surfaceChecks = @(
            [ordered]@{
                Route = '/athlete/programs'
                Marker = 'data-browser-smoke-surface-athlete-programs'
                Screenshot = 'athlete-my-programs'
            },
            [ordered]@{
                Route = '/athlete/history'
                Marker = 'data-browser-smoke-surface-athlete-history'
                Screenshot = 'athlete-workout-history'
            },
            [ordered]@{
                Route = '/athlete/calendar'
                Marker = 'data-browser-smoke-surface-athlete-calendar'
                Screenshot = 'athlete-calendar'
            }
        )
        foreach ($surface in $surfaceChecks) {
            $navigateScript = @{
                script = 'window.location.hash = arguments[0]; return true;'
                args = @($surface.Route)
            } | ConvertTo-Json
            Invoke-RestMethod `
                -Method Post `
                -Uri "$driverBaseUri/session/$browserSessionId/execute/sync" `
                -ContentType 'application/json' `
                -Body $navigateScript | Out-Null

            $surfaceReady = $false
            $surfaceDeadline = [DateTime]::UtcNow.AddSeconds(30)
            $surfaceScript = @{
                script = @'
return document.body
  ? document.body.getAttribute(arguments[0])
  : null;
'@
                args = @($surface.Marker)
            } | ConvertTo-Json
            while ([DateTime]::UtcNow -lt $surfaceDeadline) {
                $result = Invoke-RestMethod `
                    -Method Post `
                    -Uri "$driverBaseUri/session/$browserSessionId/execute/sync" `
                    -ContentType 'application/json' `
                    -Body $surfaceScript
                if ($result.value -eq 'ready') {
                    $surfaceReady = $true
                    break
                }
                Start-Sleep -Milliseconds 250
            }
            if (-not $surfaceReady) {
                throw "Browser smoke did not load $($surface.Route)."
            }
            $currentUrl = Invoke-RestMethod `
                -Uri "$driverBaseUri/session/$browserSessionId/url"
            $currentRoute = ([Uri]$currentUrl.value).Fragment.TrimStart('#')
            if ($currentRoute -ne $surface.Route) {
                throw (
                    "Browser smoke expected $($surface.Route) but reached " +
                    "$currentRoute."
                )
            }
            Save-BrowserScreenshot -Name $surface.Screenshot
        }
    }
    Write-Host "BROWSER_SMOKE_ASSERTIONS_PASSED:$Identity"
}
finally {
    if ($browserSessionId -and $driverBaseUri) {
        try {
            Invoke-RestMethod `
                -Method Delete `
                -Uri "$driverBaseUri/session/$browserSessionId" |
                Out-Null
        }
        catch {
            Write-Warning "Could not close Chrome session: $_"
        }
    }
    if ($chromeDriverProcess -and -not $chromeDriverProcess.HasExited) {
        Stop-Process -Id $chromeDriverProcess.Id -Force
    }
    if ($webServerProcess -and -not $webServerProcess.HasExited) {
        Stop-Process -Id $webServerProcess.Id -Force
    }
    Pop-Location
}
