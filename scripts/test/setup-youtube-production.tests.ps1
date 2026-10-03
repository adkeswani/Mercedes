Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\lib\youtube-production-setup.ps1')

$testRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'mercedes-youtube-setup-tests-' + [Guid]::NewGuid().ToString('N')
)
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$passed = 0

function Assert-Equal($Expected, $Actual, [string]$Message) {
    if ($Expected -ne $Actual) {
        throw "$Message Expected '$Expected', received '$Actual'."
    }
}

function Assert-ThrowsLike([scriptblock]$Action, [string]$Pattern) {
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

try {
    $manifestPath = Join-Path $testRoot 'firebase-environments.json'
    $firebaseRcPath = Join-Path $testRoot '.firebaserc'
    [IO.File]::WriteAllText(
        $manifestPath,
        @'
{
  "productionProjectId": "prod-project",
  "environments": {
    "dev": {"alias": "dev", "projectId": null, "hostingUrl": null},
    "staging": {"alias": "staging", "projectId": "stage-project", "hostingUrl": "https://stage.web.app"},
    "prod": {"alias": "prod", "projectId": "prod-project", "hostingUrl": "https://prod.web.app"}
  }
}
'@
    )
    [IO.File]::WriteAllText(
        $firebaseRcPath,
        '{"projects":{"prod":"prod-project","staging":"stage-project"}}'
    )

    $target = Resolve-YoutubeSetupTarget `
        -Environment prod `
        -Project prod `
        -ManifestPath $manifestPath `
        -FirebaseRcPath $firebaseRcPath
    Assert-Equal 'prod-project' $target.ProjectId 'Alias resolution failed.'
    $passed++

    Assert-ThrowsLike {
        Resolve-YoutubeSetupTarget `
            -Environment prod `
            -Project stage-project `
            -ManifestPath $manifestPath `
            -FirebaseRcPath $firebaseRcPath
    } '*expects project*'
    $passed++

    Assert-ThrowsLike {
        Resolve-YoutubeSetupTarget `
            -Environment dev `
            -Project dev `
            -ManifestPath $manifestPath `
            -FirebaseRcPath $firebaseRcPath
    } '*not provisioned*'
    $passed++

    $ready = Test-YoutubeSetupGitState `
        -Branch main `
        -Head abc `
        -RequiredCommit abc `
        -Clean $true
    Assert-Equal $true $ready.Ready 'Expected clean intended main.'
    $passed++

    $blocked = Test-YoutubeSetupGitState `
        -Branch feature `
        -Head abc `
        -RequiredCommit def `
        -Clean $false
    Assert-Equal $false $blocked.Ready 'Unsafe git state must fail.'
    Assert-Equal 3 $blocked.Problems.Count 'Expected every git diagnostic.'
    $passed++

    Write-Host "Passed $passed YouTube production setup helper tests."
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
