#!/usr/bin/env pwsh

<#
.SYNOPSIS
  Safely prepares a Firebase environment for public YouTube browsing.

.DESCRIPTION
  Performs read-only checks by default in -CheckOnly mode. Interactive mode
  can enable YouTube Data API v3, hand secret entry to Firebase CLI, run a
  backend dry run, and optionally invoke deploy.ps1. The script never accepts,
  reads, prints, stores, or logs an API key value.

.EXAMPLE
  .\scripts\setup-youtube-production.ps1 -CheckOnly

.EXAMPLE
  .\scripts\setup-youtube-production.ps1 `
    -RequiredCommit origin/adkeswani-youtube-public-import
#>

[CmdletBinding()]
param(
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment = 'prod',

    [string]$Project = 'mercedes-app-11ce2',

    [string]$RequiredCommit = 'origin/adkeswani-youtube-public-import',

    [switch]$CheckOnly,

    [switch]$NoBrowser
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $repoRoot 'config\firebase-environments.json'
$firebaseRcPath = Join-Path $repoRoot '.firebaserc'
$functionsPath = Join-Path $repoRoot 'functions'
$functionsPackagePath = Join-Path $functionsPath 'package.json'
$functionsLockPath = Join-Path $functionsPath 'package-lock.json'
$toolingConfigPath = Join-Path $repoRoot 'tooling-config.json'
. (Join-Path $PSScriptRoot 'lib\youtube-production-setup.ps1')
. (Join-Path $PSScriptRoot 'lib\windows-flutter-symlink.ps1')

function Write-Step([string]$Message) {
    Write-Host "`n=== $Message ===" -ForegroundColor Cyan
}

function Confirm-ExactPhrase {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,

        [Parameter(Mandatory)]
        [string]$Phrase
    )

    $answer = Read-Host "$Prompt Type '$Phrase' to continue (default: no)"
    return $answer -ceq $Phrase
}

function Require-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found on PATH."
    }
}

function Get-GitValue {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    $output = & git -C $repoRoot @Arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed."
    }
    return ConvertTo-NativeOutputText $output
}

function Test-YoutubeApiEnabled([string]$ProjectId) {
    $output = & gcloud services list `
        --enabled `
        '--filter=config.name:youtube.googleapis.com' `
        '--format=value(config.name)' `
        --project $ProjectId
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Unable to inspect enabled APIs for '$ProjectId'."
    }
    return Test-YoutubeApiServiceListOutput $output
}

function Test-YoutubeSecretMetadata([string]$ProjectId) {
    & firebase functions:secrets:get YOUTUBE_API_KEY `
        --project $ProjectId `
        *> $null
    return $LASTEXITCODE -eq 0
}

try {
    Write-Step 'Checking Windows Flutter plugin symlink support'
    $symlinkState = Test-WindowsSymlinkCapability
    if (-not $symlinkState.Ready) {
        Write-Warning $symlinkState.Problem
        if ($CheckOnly) {
            throw (
                'Check-only validation requires Windows symlink support. ' +
                'No Settings page was opened and no setting was changed.'
            )
        }

        Write-Host $script:WindowsDeveloperModeInstruction
        if (Confirm-ExactPhrase `
                -Prompt 'Open the Windows Developer settings page?' `
                -Phrase 'OPEN DEVELOPER SETTINGS') {
            try {
                Start-Process 'ms-settings:developers'
            }
            catch {
                Write-Warning (
                    'Could not open Windows Settings. Use the printed ' +
                    'command manually.'
                )
            }
        } else {
            Write-Host (
                'Settings was not opened. Use the printed command manually.'
            )
        }
        if (-not (Confirm-ExactPhrase `
                -Prompt 'After turning on Developer Mode, recheck support?' `
                -Phrase 'DEVELOPER MODE ENABLED')) {
            throw 'Developer Mode enablement was not confirmed.'
        }
        $symlinkState = Test-WindowsSymlinkCapability
        if (-not $symlinkState.Ready) {
            throw (
                'Windows symlink support is still unavailable. ' +
                $symlinkState.Problem
            )
        }
    }
    if ($symlinkState.Applicable) {
        Write-Host 'Non-elevated Windows symbolic-link creation verified.'
    } else {
        Write-Host 'Windows symbolic-link preflight is not applicable.'
    }

    Write-Step 'Resolving environment and project'
    $target = Resolve-YoutubeSetupTarget `
        -Environment $Environment `
        -Project $Project `
        -ManifestPath $manifestPath `
        -FirebaseRcPath $firebaseRcPath
    Write-Host "Environment: $($target.Environment)"
    Write-Host "Project:     $($target.ProjectId)"

    Write-Step 'Checking local prerequisites'
    foreach ($command in @('git', 'gcloud', 'firebase')) {
        Require-Command $command
        Write-Host "Found $command."
    }
    Require-Command 'node'
    Require-Command 'npm'
    $functionsState = Test-FunctionsBuildPrerequisites `
        -FunctionsPath $functionsPath
    if (-not $functionsState.Ready) {
        foreach ($problem in $functionsState.Problems) {
            Write-Warning $problem
        }
    } else {
        Write-Host 'Locked Functions dependencies and local tsc are present.'
    }

    $functionsPackage =
        Get-Content -LiteralPath $functionsPackagePath -Raw |
        ConvertFrom-Json
    $toolingConfig =
        Get-Content -LiteralPath $toolingConfigPath -Raw |
        ConvertFrom-Json
    $nodeVersion = ConvertTo-NativeOutputText (& node --version)
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to inspect the local Node.js version.'
    }
    $runtimeNodeMajor = Get-NodeMajorVersion `
        -Version ([string]$functionsPackage.engines.node)
    $toolingNodeVersion = @($toolingConfig.wingetPackages) |
        Where-Object id -EQ 'OpenJS.NodeJS.LTS' |
        Select-Object -ExpandProperty version -First 1
    if (-not $toolingNodeVersion) {
        throw 'tooling-config.json does not pin OpenJS.NodeJS.LTS.'
    }
    $nodeWarning = Get-FunctionsNodeVersionWarning `
        -ActualMajor (Get-NodeMajorVersion -Version $nodeVersion) `
        -RuntimeMajor $runtimeNodeMajor `
        -ToolingMajor (Get-NodeMajorVersion -Version $toolingNodeVersion)
    if ($nodeWarning) {
        Write-Warning $nodeWarning
    }

    Write-Step 'Checking authenticated project access'
    & gcloud projects describe $target.ProjectId `
        '--format=value(projectId)' |
        Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw (
            "gcloud cannot access '$($target.ProjectId)'. Run " +
            "'gcloud auth login' and select an authorized account."
        )
    }
    $firebaseProjects = & firebase projects:list --json
    if ($LASTEXITCODE -ne 0) {
        throw (
            "Firebase CLI cannot list projects. Run 'firebase login' with " +
            'an authorized account.'
        )
    }
    $firebaseResult = $firebaseProjects | ConvertFrom-Json
    $hasFirebaseProject = @($firebaseResult.result) |
        Where-Object projectId -EQ $target.ProjectId |
        Select-Object -First 1
    if (-not $hasFirebaseProject) {
        throw "Firebase CLI cannot access '$($target.ProjectId)'."
    }
    Write-Host 'gcloud and Firebase project access verified.'

    Write-Step 'Checking repository integration state'
    $branch = Get-GitValue rev-parse --abbrev-ref HEAD
    $head = Get-GitValue rev-parse HEAD
    $requiredSha = Get-GitValue rev-parse "$RequiredCommit`^{commit}"
    $dirty = & git -C $repoRoot status --porcelain
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to inspect git working tree state.'
    }
    $gitState = Test-YoutubeSetupGitState `
        -Branch $branch `
        -Head $head `
        -RequiredCommit $requiredSha `
        -Clean ([string]::IsNullOrWhiteSpace(($dirty -join "`n")))
    if (-not $gitState.Ready) {
        foreach ($problem in $gitState.Problems) {
            Write-Warning $problem
        }
        & git -C $repoRoot show-ref --verify --quiet refs/heads/main
        $mainExists = $LASTEXITCODE -eq 0
        if ($mainExists) {
            & git -C $repoRoot merge-base --is-ancestor main $requiredSha
            if ($LASTEXITCODE -eq 0) {
                Write-Host 'Safe integration commands (not executed):'
                Write-Host '  git fetch origin'
                Write-Host '  git switch main'
                Write-Host "  git merge --ff-only $RequiredCommit"
            } else {
                Write-Warning (
                    'main cannot fast-forward to the required commit. Stop ' +
                    'and resolve integration in a separate topic branch.'
                )
            }
        }
    } else {
        Write-Host "Clean main is at intended commit $requiredSha."
    }

    Write-Step 'Checking YouTube API and secret metadata'
    $apiEnabled = Test-YoutubeApiEnabled $target.ProjectId
    $secretExists = Test-YoutubeSecretMetadata $target.ProjectId
    Write-Host "YouTube Data API v3 enabled: $apiEnabled"
    Write-Host "YOUTUBE_API_KEY metadata exists: $secretExists"

    if ($CheckOnly) {
        if (
            -not $gitState.Ready -or
            -not $apiEnabled -or
            -not $secretExists -or
            -not $functionsState.Ready
        ) {
            throw (
                'Check-only validation found unresolved prerequisites. ' +
                'No cloud or repository mutation was attempted.'
            )
        }
        Write-Host 'Check-only validation passed. No mutation was attempted.'
        exit 0
    }

    if (-not $gitState.Ready) {
        throw (
            'Refusing cloud mutation until clean main is at the intended ' +
            'commit. Use only the printed fast-forward commands when valid.'
        )
    }

    if (-not $apiEnabled) {
        if (-not (Confirm-ExactPhrase `
                -Prompt (
                    "Enable YouTube Data API v3 in $($target.ProjectId)?"
                ) `
                -Phrase 'ENABLE YOUTUBE API')) {
            throw 'YouTube Data API v3 remains disabled.'
        }
        & gcloud services enable youtube.googleapis.com `
            --project $target.ProjectId
        if ($LASTEXITCODE -ne 0 -or
            -not (Test-YoutubeApiEnabled $target.ProjectId)) {
            throw 'YouTube Data API v3 could not be enabled and verified.'
        }
        Write-Host 'YouTube Data API v3 enabled and verified.'
    }

    $keyPhrase = if ($secretExists) {
        'ROTATE YOUTUBE KEY'
    } else {
        'CREATE YOUTUBE KEY'
    }
    if (Confirm-ExactPhrase `
            -Prompt (
                'Create a new Google Cloud API key and secret version?'
            ) `
            -Phrase $keyPhrase) {
        $credentialsUrl = (
            'https://console.cloud.google.com/apis/credentials?project=' +
            $target.ProjectId
        )
        Write-Host "Credentials URL: $credentialsUrl"
        Write-Host (
            'Create a server key restricted to YouTube Data API v3. ' +
            'Cloud Functions has no stable outbound IP by default, so add ' +
            'an application restriction only when a supported stable egress ' +
            'or identity boundary exists.'
        )
        if (-not $NoBrowser) {
            try {
                Start-Process $credentialsUrl
            }
            catch {
                Write-Warning (
                    'Could not open a browser. Use the printed URL manually.'
                )
            }
        }
        if (-not (Confirm-ExactPhrase `
                -Prompt (
                    'Confirm the new key exists and is API-restricted.'
                ) `
                -Phrase 'KEY RESTRICTED')) {
            throw 'Key creation/restriction was not confirmed.'
        }
        if (-not (Confirm-ExactPhrase `
                -Prompt (
                    'Create a new Firebase secret version now? Firebase CLI ' +
                    'will securely prompt for the value.'
                ) `
                -Phrase 'SET YOUTUBE SECRET')) {
            throw 'Secret creation was not confirmed.'
        }
        & firebase functions:secrets:set YOUTUBE_API_KEY `
            --project $target.ProjectId
        if ($LASTEXITCODE -ne 0) {
            throw 'Firebase could not create the secret version.'
        }
        $secretExists = Test-YoutubeSecretMetadata $target.ProjectId
        if (-not $secretExists) {
            throw 'Secret metadata was not visible after creation.'
        }
        Write-Host 'Secret metadata verified; the value was never read.'
    } elseif (-not $secretExists) {
        throw 'YOUTUBE_API_KEY is required before dry-run or deployment.'
    }

    $dryRunCommand = (
        'firebase deploy --only ' +
        '"functions,firestore:rules,firestore:indexes" ' +
        "--project $($target.ProjectId) --dry-run --force"
    )
    Write-Host "Backend dry-run command: $dryRunCommand"
    Write-Warning (
        'This dry run does not release Functions or Firestore revisions, but ' +
        'Firebase CLI may enable required service APIs, create service ' +
        'identities, or prepare IAM. It is a cloud-preparation mutation.'
    )
    $confirmationEnvironment = $Environment.ToUpperInvariant()
    $dryRunPassed = $false
    if (Confirm-ExactPhrase `
            -Prompt 'Allow the Firebase cloud-preparation dry run?' `
            -Phrase "DRY RUN $confirmationEnvironment") {
        if (-not $functionsState.Ready) {
            if (-not $functionsState.LockfilePresent) {
                throw (
                    'Cannot restore Functions dependencies without the ' +
                    'committed package-lock.json.'
                )
            }
            if (-not (Confirm-ExactPhrase `
                    -Prompt (
                        'Install exactly the locked Functions dependencies ' +
                        'with npm ci? No manifest or lockfile changes are allowed.'
                    ) `
                    -Phrase 'INSTALL FUNCTIONS DEPENDENCIES')) {
                throw (
                    'Functions dependencies remain unresolved; dry run was ' +
                    'not invoked.'
                )
            }
            $packageHash = (Get-FileHash `
                    -LiteralPath $functionsPackagePath `
                    -Algorithm SHA256).Hash
            $lockHash = (Get-FileHash `
                    -LiteralPath $functionsLockPath `
                    -Algorithm SHA256).Hash
            & npm --prefix $functionsPath ci --no-audit --no-fund
            if ($LASTEXITCODE -ne 0) {
                throw 'Locked Functions dependency installation failed.'
            }
            if (
                $packageHash -ne (Get-FileHash `
                    -LiteralPath $functionsPackagePath `
                    -Algorithm SHA256).Hash -or
                $lockHash -ne (Get-FileHash `
                    -LiteralPath $functionsLockPath `
                    -Algorithm SHA256).Hash
            ) {
                throw (
                    'npm ci changed a Functions manifest or lockfile; ' +
                    'refusing to continue.'
                )
            }
            $functionsState = Test-FunctionsBuildPrerequisites `
                -FunctionsPath $functionsPath
            if (-not $functionsState.Ready) {
                throw (
                    'Functions dependencies remain incomplete after npm ci: ' +
                    ($functionsState.Problems -join ' ')
                )
            }
            Write-Host 'Locked Functions dependencies installed and verified.'
        }
        & npm --prefix $functionsPath run build
        if ($LASTEXITCODE -ne 0) {
            throw 'Functions TypeScript build failed; dry run was not invoked.'
        }
        Write-Host 'Functions TypeScript build passed.'
        & firebase deploy `
            --only 'functions,firestore:rules,firestore:indexes' `
            --project $target.ProjectId `
            --dry-run `
            --force
        if ($LASTEXITCODE -ne 0) {
            throw 'Firebase backend dry run failed.'
        }
        $dryRunPassed = $true
        Write-Host (
            'Firebase backend dry run passed; no Functions or Firestore ' +
            'revision was released. Cloud preparation may have mutated APIs, ' +
            'service identities, or IAM.'
        )
    } else {
        Write-Host 'Dry run not invoked.'
    }

    if (-not $dryRunPassed) {
        Write-Host (
            'Deployment command and invocation are unavailable until this ' +
            'script runs a successful backend dry run.'
        )
    } else {
        $deployCommand = (
            ".\deploy.ps1 -Target web -StageDir stage5 " +
            "-Environment $Environment -Project $Project"
        )
        Write-Host "Production deploy command: $deployCommand"
    }
    if ($dryRunPassed -and (Confirm-ExactPhrase `
            -Prompt (
                'DANGER: deploy Functions, Firestore, and Hosting now?'
            ) `
            -Phrase "DEPLOY $confirmationEnvironment")) {
        & (Join-Path $repoRoot 'deploy.ps1') `
            -Target web `
            -StageDir stage5 `
            -Environment $Environment `
            -Project $Project
        if ($LASTEXITCODE -ne 0) {
            throw 'Production deployment failed.'
        }
    } elseif ($dryRunPassed) {
        Write-Host 'Deployment not invoked (default safe behavior).'
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
