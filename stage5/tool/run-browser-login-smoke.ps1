param(
    [switch]$InsideEmulators,
    [string]$ChromeDriverPath = $env:CHROMEDRIVER_PATH,
    [ValidateSet('trainer', 'athlete')]
    [string]$Identity = 'trainer'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectId = 'mercedes-app-11ce2'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$stage5Path = Join-Path $repoRoot 'stage5'
$artifactPath = Join-Path $stage5Path 'test-artifacts\browser-login'
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

    Push-Location $repoRoot
    try {
        $innerCommand = 'powershell -NoProfile -ExecutionPolicy Bypass ' +
            '-File "stage5\tool\run-browser-login-smoke.ps1" ' +
            "-InsideEmulators -Identity $Identity"
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

$selectedIdentity = if ($Identity -eq 'trainer') { $trainer } else { $athlete }
$env:BROWSER_SMOKE_ARTIFACT_DIR = $artifactPath
New-Item -ItemType Directory -Force -Path $artifactPath | Out-Null
Remove-Item `
    -LiteralPath (Join-Path $artifactPath "$Identity-auth-before-login.png") `
    -Force `
    -ErrorAction SilentlyContinue
Remove-Item `
    -LiteralPath (Join-Path $artifactPath "$Identity-app-after-login.png") `
    -Force `
    -ErrorAction SilentlyContinue

Push-Location $stage5Path
$chromeDriverProcess = $null
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

    & flutter pub get
    if ($LASTEXITCODE -ne 0) {
        throw 'flutter pub get failed.'
    }

    $chromeDriverProcess = Start-Process `
        -FilePath $ChromeDriverPath `
        -ArgumentList '--port=4444' `
        -PassThru `
        -WindowStyle Hidden
    Start-Sleep -Seconds 1
    if ($chromeDriverProcess.HasExited) {
        throw 'ChromeDriver exited before the browser test started.'
    }

    & flutter drive `
        --driver 'test_driver\integration_test.dart' `
        --target 'integration_test\browser_login_smoke_test.dart' `
        -d chrome `
        --headless `
        --no-keep-app-running `
        --browser-dimension=1280x800 `
        --driver-port=4444 `
        --timeout=180 `
        --no-pub `
        --dart-define=USE_FIREBASE_EMULATORS=true `
        --dart-define=BROWSER_LOGIN_SMOKE=true `
        "--dart-define=BROWSER_SMOKE_ROLE=$($selectedIdentity.Role)" `
        "--dart-define=BROWSER_SMOKE_EMAIL=$($selectedIdentity.Email)" `
        "--dart-define=BROWSER_SMOKE_PASSWORD=$($selectedIdentity.Password)"
    if ($LASTEXITCODE -ne 0) {
        throw 'Flutter browser login smoke test failed.'
    }
}
finally {
    if ($chromeDriverProcess -and -not $chromeDriverProcess.HasExited) {
        Stop-Process -Id $chromeDriverProcess.Id
    }
    Pop-Location
}
