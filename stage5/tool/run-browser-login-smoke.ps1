param(
    [switch]$InsideEmulators,
    [string]$ChromeDriverPath = $env:CHROMEDRIVER_PATH
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectId = 'mercedes-app-11ce2'
$email = 'browser-smoke@mercedes.test'
$password = 'BrowserSmoke123!'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$stage5Path = Join-Path $repoRoot 'stage5'

if (-not $InsideEmulators) {
    if ($ChromeDriverPath) {
        $env:CHROMEDRIVER_PATH = (Resolve-Path $ChromeDriverPath).Path
    }

    Push-Location $repoRoot
    try {
        $innerCommand = 'powershell -NoProfile -ExecutionPolicy Bypass ' +
            '-File "stage5\tool\run-browser-login-smoke.ps1" -InsideEmulators'
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

$authBody = @{
    email = $email
    password = $password
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
        displayName = @{ stringValue = 'Browser Smoke' }
        email = @{ stringValue = $email }
        username = @{ stringValue = 'browser_smoke' }
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
        "--dart-define=BROWSER_SMOKE_EMAIL=$email" `
        "--dart-define=BROWSER_SMOKE_PASSWORD=$password"
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
