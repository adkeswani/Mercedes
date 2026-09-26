param(
    [switch]$InsideEmulators,
    [switch]$SkipPubGet,
    [switch]$WorkoutDragOnly,
    [string]$ChromeDriverPath,
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
. (Join-Path $repoRoot 'scripts\lib\chromedriver.ps1')
$ChromeDriverPath = Resolve-CompatibleChromeDriver `
    -ChromeDriverPath $ChromeDriverPath
$env:CHROMEDRIVER_PATH = $ChromeDriverPath
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
    $env:BROWSER_SMOKE_TEST_TARGET = $TestTarget

    Push-Location $repoRoot
    try {
        $innerCommand = 'powershell -NoProfile -ExecutionPolicy Bypass ' +
            "-File `"$stageName\tool\run-browser-login-smoke.ps1`" " +
            "-InsideEmulators -Identity $Identity"
        if ($SkipPubGet) {
            $innerCommand += ' -SkipPubGet'
        }
        if ($WorkoutDragOnly) {
            $innerCommand += ' -WorkoutDragOnly'
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
$commentTimestamp = [DateTime]::Parse($historyTimestamp).
    AddMinutes(1).ToUniversalTime().ToString('o')
$reactionTimestamp = [DateTime]::Parse($historyTimestamp).
    AddMinutes(2).ToUniversalTime().ToString('o')
$seedTimestamp = $today.ToUniversalTime().ToString('o')
$builderSeedTimestamp = $today.AddMinutes(-10).ToUniversalTime().ToString('o')
$programId = 'browser-athlete-program'
$programInstanceId = 'browser-athlete-program-instance'
$exerciseTemplateId = 'browser-trainer-exercise'
$secondExerciseTemplateId = 'browser-trainer-exercise-two'
$calendarTemplateId = 'browser-calendar-workout'
$historyTemplateId = 'browser-history-workout'
$builderSourceWorkoutId = 'browser-builder-source-workout'
$dragWorkoutBuilderId = 'browser-workout-builder-drag'
$controlsWorkoutBuilderId = 'browser-workout-builder-controls'
$dragProgramBuilderId = 'browser-program-builder-drag'
$controlsProgramBuilderId = 'browser-program-builder-controls'
$exerciseFolderId = 'browser-exercise-folder'
$workoutFolderId = 'browser-workout-folder'
$programFolderId = 'browser-program-folder'
$discussionThreadId = 'browser-history-workout'
$discussionMessageId = 'browser-workout-discussion-message'
$celebrate = [char]::ConvertFromUtf32(0x1F389)
$workspaceSeedBody = @{
    writes = @(
        @(
            @('exercise', $exerciseFolderId, 'Browser exercises'),
            @('workout', $workoutFolderId, 'Browser workouts'),
            @('program', $programFolderId, 'Browser programs')
        ) | ForEach-Object {
            @{
                update = @{
                    name = "projects/$projectId/databases/(default)/documents/" +
                        "programFolders/$($_[1])"
                    fields = @{
                        ownerId = @{ stringValue = $trainer.Uid }
                        itemType = @{ stringValue = $_[0] }
                        name = @{ stringValue = $_[2] }
                        createdBy = @{ stringValue = $trainer.Uid }
                        createdAt = @{ timestampValue = $builderSeedTimestamp }
                        updatedBy = @{ stringValue = $trainer.Uid }
                        updatedAt = @{ timestampValue = $builderSeedTimestamp }
                        deletedAt = @{ nullValue = $null }
                        deletedBy = @{ nullValue = $null }
                    }
                }
            }
        }
        @{
            update = @{
                name = "projects/$projectId/databases/(default)/documents/" +
                    "exerciseTemplates/$exerciseTemplateId"
                fields = @{
                    ownerId = @{ stringValue = $trainer.Uid }
                    currentVersion = @{ integerValue = '1' }
                    tags = @{
                        arrayValue = @{
                            values = @(@{ stringValue = 'Strength' })
                        }
                    }
                    folderId = @{ stringValue = $exerciseFolderId }
                    provenance = @{ nullValue = $null }
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
                    "exerciseTemplates/$exerciseTemplateId/" +
                    'exerciseVersions/1'
                fields = @{
                    versionNumber = @{ integerValue = '1' }
                    name = @{ stringValue = 'Browser Trainer Exercise' }
                    description = @{
                        stringValue = 'Deterministic trainer exercise'
                    }
                    instructions = @{ stringValue = 'Controlled smoke movement' }
                    videoUrl = @{ nullValue = $null }
                    mediaUrls = @{ arrayValue = @{} }
                    exerciseType = @{ stringValue = 'strength' }
                    measurementConfiguration = @{
                        mapValue = @{
                            fields = @{
                                primary = @{ stringValue = 'repetitions' }
                                secondary = @{ arrayValue = @{} }
                            }
                        }
                    }
                    gradingConfiguration = @{ nullValue = $null }
                    publishedAt = @{ timestampValue = $builderSeedTimestamp }
                    publishedBy = @{ stringValue = $trainer.Uid }
                }
            }
        },
        @{
            update = @{
                name = "projects/$projectId/databases/(default)/documents/" +
                    "exerciseTemplates/$secondExerciseTemplateId"
                fields = @{
                    ownerId = @{ stringValue = $trainer.Uid }
                    currentVersion = @{ integerValue = '1' }
                    tags = @{
                        arrayValue = @{
                            values = @(@{ stringValue = 'Strength' })
                        }
                    }
                    folderId = @{ stringValue = $exerciseFolderId }
                    provenance = @{ nullValue = $null }
                    createdAt = @{ timestampValue = $builderSeedTimestamp }
                    createdBy = @{ stringValue = $trainer.Uid }
                    updatedAt = @{ timestampValue = $builderSeedTimestamp }
                    updatedBy = @{ stringValue = $trainer.Uid }
                    deletedAt = @{ nullValue = $null }
                    deletedBy = @{ nullValue = $null }
                }
            }
        },
        @{
            update = @{
                name = "projects/$projectId/databases/(default)/documents/" +
                    "exerciseTemplates/$secondExerciseTemplateId/" +
                    'exerciseVersions/1'
                fields = @{
                    versionNumber = @{ integerValue = '1' }
                    name = @{ stringValue = 'Browser Trainer Row' }
                    description = @{
                        stringValue = 'Second deterministic trainer exercise'
                    }
                    instructions = @{ stringValue = 'Controlled row movement' }
                    videoUrl = @{ nullValue = $null }
                    mediaUrls = @{ arrayValue = @{} }
                    exerciseType = @{ stringValue = 'strength' }
                    measurementConfiguration = @{
                        mapValue = @{
                            fields = @{
                                primary = @{ stringValue = 'repetitions' }
                                secondary = @{ arrayValue = @{} }
                            }
                        }
                    }
                    gradingConfiguration = @{ nullValue = $null }
                    publishedAt = @{ timestampValue = $seedTimestamp }
                    publishedBy = @{ stringValue = $trainer.Uid }
                }
            }
        },
        @{
            update = @{
                name = "projects/$projectId/databases/(default)/documents/" +
                    "workoutTemplates/$dragWorkoutBuilderId"
                fields = @{
                    name = @{ stringValue = 'Browser Workout Builder Drag' }
                    ownerId = @{ stringValue = $trainer.Uid }
                    workoutType = @{ stringValue = 'fullBody' }
                    currentVersion = @{ integerValue = '0' }
                    tags = @{ arrayValue = @{} }
                    folderId = @{ nullValue = $null }
                    clientAthleteId = @{ nullValue = $null }
                    provenance = @{ nullValue = $null }
                    createdAt = @{ timestampValue = $builderSeedTimestamp }
                    createdBy = @{ stringValue = $trainer.Uid }
                    updatedAt = @{ timestampValue = $builderSeedTimestamp }
                    updatedBy = @{ stringValue = $trainer.Uid }
                    deletedAt = @{ nullValue = $null }
                    deletedBy = @{ nullValue = $null }
                }
            }
        },
        @{
            update = @{
                name = "projects/$projectId/databases/(default)/documents/" +
                    "workoutTemplates/$controlsWorkoutBuilderId"
                fields = @{
                    name = @{
                        stringValue = 'Browser Workout Builder Controls'
                    }
                    ownerId = @{ stringValue = $trainer.Uid }
                    workoutType = @{ stringValue = 'fullBody' }
                    currentVersion = @{ integerValue = '0' }
                    tags = @{ arrayValue = @{} }
                    folderId = @{ nullValue = $null }
                    clientAthleteId = @{ nullValue = $null }
                    provenance = @{ nullValue = $null }
                    createdAt = @{ timestampValue = $builderSeedTimestamp }
                    createdBy = @{ stringValue = $trainer.Uid }
                    updatedAt = @{ timestampValue = $builderSeedTimestamp }
                    updatedBy = @{ stringValue = $trainer.Uid }
                    deletedAt = @{ nullValue = $null }
                    deletedBy = @{ nullValue = $null }
                }
            }
        },
        @{
            update = @{
                name = "projects/$projectId/databases/(default)/documents/" +
                    "workoutTemplates/$builderSourceWorkoutId"
                fields = @{
                    name = @{ stringValue = 'Browser Builder Workout' }
                    ownerId = @{ stringValue = $trainer.Uid }
                    workoutType = @{ stringValue = 'fullBody' }
                    currentVersion = @{ integerValue = '1' }
                    tags = @{ arrayValue = @{} }
                    folderId = @{ nullValue = $null }
                    clientAthleteId = @{ nullValue = $null }
                    provenance = @{ nullValue = $null }
                    createdAt = @{ timestampValue = $builderSeedTimestamp }
                    createdBy = @{ stringValue = $trainer.Uid }
                    updatedAt = @{ timestampValue = $builderSeedTimestamp }
                    updatedBy = @{ stringValue = $trainer.Uid }
                    deletedAt = @{ nullValue = $null }
                    deletedBy = @{ nullValue = $null }
                }
            }
        },
        @{
            update = @{
                name = "projects/$projectId/databases/(default)/documents/" +
                    "workoutTemplates/$builderSourceWorkoutId/" +
                    'workoutTemplateVersions/1'
                fields = @{
                    versionNumber = @{ integerValue = '1' }
                    publishedAt = @{ timestampValue = $builderSeedTimestamp }
                    exercises = @{ arrayValue = @{} }
                }
            }
        },
        @{
            update = @{
                name = "projects/$projectId/databases/(default)/documents/" +
                    "programs/$dragProgramBuilderId"
                fields = @{
                    name = @{ stringValue = 'Browser Program Builder Drag' }
                    description = @{
                        stringValue = 'Deterministic builder target'
                    }
                    ownerId = @{ stringValue = $trainer.Uid }
                    type = @{ stringValue = 'assignable' }
                    status = @{ stringValue = 'draft' }
                    currentVersion = @{ integerValue = '0' }
                    tags = @{ arrayValue = @{} }
                    folderId = @{ nullValue = $null }
                    clientAthleteId = @{ nullValue = $null }
                    provenance = @{ nullValue = $null }
                    createdAt = @{ timestampValue = $builderSeedTimestamp }
                    createdBy = @{ stringValue = $trainer.Uid }
                    updatedAt = @{ timestampValue = $builderSeedTimestamp }
                    updatedBy = @{ stringValue = $trainer.Uid }
                    deletedAt = @{ nullValue = $null }
                    deletedBy = @{ nullValue = $null }
                }
            }
        },
        @{
            update = @{
                name = "projects/$projectId/databases/(default)/documents/" +
                    "programs/$controlsProgramBuilderId"
                fields = @{
                    name = @{
                        stringValue = 'Browser Program Builder Controls'
                    }
                    description = @{
                        stringValue = 'Deterministic builder target'
                    }
                    ownerId = @{ stringValue = $trainer.Uid }
                    type = @{ stringValue = 'assignable' }
                    status = @{ stringValue = 'draft' }
                    currentVersion = @{ integerValue = '0' }
                    tags = @{ arrayValue = @{} }
                    folderId = @{ nullValue = $null }
                    clientAthleteId = @{ nullValue = $null }
                    provenance = @{ nullValue = $null }
                    createdAt = @{ timestampValue = $builderSeedTimestamp }
                    createdBy = @{ stringValue = $trainer.Uid }
                    updatedAt = @{ timestampValue = $builderSeedTimestamp }
                    updatedBy = @{ stringValue = $trainer.Uid }
                    deletedAt = @{ nullValue = $null }
                    deletedBy = @{ nullValue = $null }
                }
            }
        },
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
                    tags = @{
                        arrayValue = @{
                            values = @(
                                @{ stringValue = 'Client' },
                                @{ stringValue = 'Strength' }
                            )
                        }
                    }
                    folderId = @{ stringValue = $programFolderId }
                    clientAthleteId = @{ stringValue = $athlete.Uid }
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
                    "programs/$programId/programVersions/1"
                fields = @{
                    versionNumber = @{ integerValue = '1' }
                    publishedAt = @{ timestampValue = $seedTimestamp }
                    entries = @{
                        arrayValue = @{
                            values = @(
                                @{
                                    mapValue = @{
                                        fields = @{
                                            entryId = @{
                                                stringValue = $calendarTemplateId
                                            }
                                            workoutTemplateId = @{
                                                stringValue = $calendarTemplateId
                                            }
                                            workoutTemplateVersion = @{
                                                integerValue = '1'
                                            }
                                            dayOffset = @{ integerValue = '0' }
                                            sortOrder = @{ integerValue = '0' }
                                            workoutName = @{
                                                stringValue = 'Browser Calendar Workout'
                                            }
                                        }
                                    }
                                }
                            )
                        }
                    }
                    changeNote = @{
                        stringValue = 'Deterministic trainer program version'
                    }
                    propagationState = @{ stringValue = 'complete' }
                    propagationAttempt = @{ integerValue = '0' }
                    propagationStartedAt = @{ nullValue = $null }
                    propagationCompletedAt = @{
                        timestampValue = $seedTimestamp
                    }
                    propagationFailedAt = @{ nullValue = $null }
                    propagationError = @{ nullValue = $null }
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
                    "workoutTemplates/$calendarTemplateId/" +
                    'workoutTemplateVersions/1'
                fields = @{
                    versionNumber = @{ integerValue = '1' }
                    publishedAt = @{ timestampValue = $seedTimestamp }
                    exercises = @{ arrayValue = @{} }
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
                        stringValue = $today.AddDays(7).ToString('yyyy-MM-dd')
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
                    "workoutTemplates/$historyTemplateId/" +
                    'workoutTemplateVersions/1'
                fields = @{
                    versionNumber = @{ integerValue = '1' }
                    publishedAt = @{ timestampValue = $seedTimestamp }
                    exercises = @{ arrayValue = @{} }
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
                    tags = @{
                        arrayValue = @{
                            values = @(
                                @{ stringValue = 'Client' },
                                @{ stringValue = 'Full Body' }
                            )
                        }
                    }
                    folderId = @{ stringValue = $workoutFolderId }
                    clientAthleteId = @{ stringValue = $athlete.Uid }
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
                    updatedAt = @{ timestampValue = $historyTimestamp }
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
        },
        @{
            update = @{
                name = "projects/$projectId/databases/(default)/documents/" +
                    "workoutDiscussionThreads/$discussionThreadId"
                fields = @{
                    workoutInstanceId = @{
                        stringValue = 'browser-history-workout'
                    }
                    trainerId = @{ stringValue = $trainer.Uid }
                    athleteId = @{ stringValue = $athlete.Uid }
                    completedAt = @{ timestampValue = $historyTimestamp }
                    createdAt = @{ timestampValue = $historyTimestamp }
                    createdBy = @{ stringValue = $athlete.Uid }
                    lastActivityAt = @{
                        timestampValue = $reactionTimestamp
                    }
                }
            }
        },
        @{
            update = @{
                name = "projects/$projectId/databases/(default)/documents/" +
                    "workoutDiscussionThreads/$discussionThreadId/" +
                    "threadMessages/$discussionMessageId"
                fields = @{
                    authorId = @{ stringValue = $athlete.Uid }
                    body = @{ stringValue = 'Browser dashboard comment' }
                    createdAt = @{ timestampValue = $commentTimestamp }
                }
            }
        },
        @{
            update = @{
                name = "projects/$projectId/databases/(default)/documents/" +
                    "workoutDiscussionThreads/$discussionThreadId/" +
                    "threadMessages/$discussionMessageId/" +
                    "reactions/$($trainer.Uid)"
                fields = @{
                    actorId = @{ stringValue = $trainer.Uid }
                    reactionId = @{ stringValue = 'celebrate' }
                    createdAt = @{ timestampValue = $reactionTimestamp }
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
$identityArtifacts = @(
    "$Identity-auth-before-login.png",
    "$Identity-app-after-login.png",
    "$Identity-header-identity.png"
)
if ($Identity -eq 'trainer') {
    $identityArtifacts += @(
        'trainer-clients.png',
        'trainer-exercise-library.png',
        'trainer-exercise-library-collapsed.png',
        'trainer-workout-library.png',
        'trainer-workout-library-collapsed.png',
        'trainer-program-library.png',
        'trainer-program-library-collapsed.png',
        'trainer-workout-builder-drag.png',
        'trainer-workout-builder-controls.png',
        'trainer-program-builder-drag.png',
        'trainer-program-builder-controls.png',
        'trainer-calendar-assignments.png',
        'trainer-dashboard.png'
    )
}
else {
    $identityArtifacts += @(
        'athlete-my-programs.png',
        'athlete-workout-history.png',
        'athlete-calendar.png'
    )
}
foreach ($artifactName in $identityArtifacts) {
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
                        '--window-size=1440,1200',
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

    function Invoke-BrowserScript {
        param(
            [string]$Script,
            [object[]]$Arguments = @()
        )

        $body = @{
            script = $Script
            args = $Arguments
        } | ConvertTo-Json -Depth 8
        return Invoke-RestMethod `
            -Method Post `
            -Uri "$driverBaseUri/session/$browserSessionId/execute/sync" `
            -ContentType 'application/json' `
            -Body $body
    }

    function Enable-BrowserSemantics {
        Invoke-BrowserScript -Script @'
const placeholder = document.querySelector('flt-semantics-placeholder');
if (placeholder) placeholder.click();
return true;
'@ | Out-Null
    }

    function Wait-BrowserLabel {
        param(
            [string]$Label,
            [int]$TimeoutSeconds = 30
        )

        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        do {
            $result = Invoke-BrowserScript -Script @'
const expected = arguments[0];
return Array.from(document.querySelectorAll('[aria-label]')).some(
  (element) => (element.getAttribute('aria-label') || '').includes(expected)
);
'@ -Arguments @($Label)
            if ($result.value) {
                return
            }
            Start-Sleep -Milliseconds 200
        } while ([DateTime]::UtcNow -lt $deadline)
        $labels = Invoke-BrowserScript -Script @'
return Array.from(document.querySelectorAll('[aria-label]'))
  .map((element) => element.getAttribute('aria-label'))
  .filter(Boolean);
'@
        throw (
            "Browser did not expose accessible label '$Label'. Available: " +
            (@($labels.value) -join ' | ')
        )
    }

    function Invoke-BrowserLabelClick {
        param(
            [string]$Label,
            [switch]$Contains
        )

        $deadline = [DateTime]::UtcNow.AddSeconds(30)
        do {
            $result = Invoke-BrowserScript -Script @'
const expected = arguments[0];
const candidates = Array.from(document.querySelectorAll('[aria-label]'));
const available = candidates.filter((candidate) =>
  candidate.getAttribute('aria-disabled') !== 'true' &&
  !candidate.hasAttribute('disabled')
);
const element = available.find(
  (candidate) => {
    const label = candidate.getAttribute('aria-label') || '';
    return label === expected;
  }
) || available.find((candidate) => {
  const label = candidate.getAttribute('aria-label') || '';
  return label.includes(expected);
});
if (!element) return false;
element.click();
return true;
'@ -Arguments @($Label, [bool]$Contains)
            if ($result.value) {
                Start-Sleep -Milliseconds 400
                return
            }
            Start-Sleep -Milliseconds 200
        } while ([DateTime]::UtcNow -lt $deadline)
        $labels = Invoke-BrowserScript -Script @'
return Array.from(document.querySelectorAll('[aria-label]')).map(
  (element) => ({
    label: element.getAttribute('aria-label'),
    disabled: element.getAttribute('aria-disabled')
  })
);
'@
        throw (
            "Browser could not click accessible control '$Label'. " +
            "Available: $($labels.value | ConvertTo-Json -Compress)"
        )
    }

    function Get-BrowserElementId {
        param(
            [string]$Label,
            [switch]$Last
        )

        $result = Invoke-RestMethod `
            -Method Post `
            -Uri "$driverBaseUri/session/$browserSessionId/elements" `
            -ContentType 'application/json' `
            -Body (@{
                using = 'xpath'
                value = "//*[contains(@aria-label, '$Label')]"
            } | ConvertTo-Json)
        $elements = @($result.value)
        $element = if ($Last) {
            $elements | Select-Object -Last 1
        }
        else {
            $elements | Select-Object -First 1
        }
        if (-not $element) {
            throw "Browser did not find element '$Label'."
        }
        return $element.PSObject.Properties.Value | Select-Object -First 1
    }

    function Invoke-BrowserDrag {
        param(
            [string]$SourceLabel,
            [string]$TargetLabel,
            [int]$TargetYOffset = 0,
            [switch]$SourceLast,
            [switch]$TargetLast,
            [switch]$UseLeadingHandle
        )

        Wait-BrowserLabel -Label $SourceLabel
        Wait-BrowserLabel -Label $TargetLabel
        Invoke-BrowserScript -Script @'
for (const expected of arguments) {
  const element = Array.from(document.querySelectorAll('[aria-label]')).find(
    (candidate) => (candidate.getAttribute('aria-label') || '').includes(expected)
  );
  if (element) element.scrollIntoView({block: 'center', inline: 'center'});
}
return true;
'@ -Arguments @($SourceLabel, $TargetLabel) | Out-Null
        Start-Sleep -Milliseconds 300
        $sourceId = Get-BrowserElementId `
            -Label $SourceLabel `
            -Last:$SourceLast
        $targetId = Get-BrowserElementId `
            -Label $TargetLabel `
            -Last:$TargetLast
        $elementKey = 'element-6066-11e4-a52e-4f735466cecf'
        $sourceX = 0
        $sourceY = 0
        $sourceOrigin = @{ $elementKey = $sourceId }
        if ($UseLeadingHandle) {
            $sourceRect = Invoke-RestMethod -Uri (
                "$driverBaseUri/session/$browserSessionId/element/" +
                "$sourceId/rect"
            )
            $sourceOrigin = 'viewport'
            $sourceX = [Math]::Round($sourceRect.value.x - 24)
            $sourceY = [Math]::Round(
                $sourceRect.value.y + $sourceRect.value.height / 2
            )
        }
        $actions = @{
            actions = @(
                @{
                    type = 'pointer'
                    id = 'builder-mouse'
                    parameters = @{ pointerType = 'mouse' }
                    actions = @(
                        @{
                            type = 'pointerMove'
                            duration = 0
                            origin = $sourceOrigin
                            x = $sourceX
                            y = $sourceY
                        },
                        @{ type = 'pointerDown'; button = 0 },
                        @{ type = 'pause'; duration = 500 },
                        @{
                            type = 'pointerMove'
                            duration = 900
                            origin = @{ $elementKey = $targetId }
                            x = 0
                            y = $TargetYOffset
                        },
                        @{ type = 'pause'; duration = 300 },
                        @{ type = 'pointerUp'; button = 0 }
                    )
                }
            )
        } | ConvertTo-Json -Depth 10
        Invoke-RestMethod `
            -Method Post `
            -Uri "$driverBaseUri/session/$browserSessionId/actions" `
            -ContentType 'application/json' `
            -Body $actions | Out-Null
        Start-Sleep -Milliseconds 700
    }

    function Invoke-BrowserCoordinateClick {
        param(
            [int]$X,
            [int]$Y
        )

        $actions = @{
            actions = @(
                @{
                    type = 'pointer'
                    id = 'builder-click'
                    parameters = @{ pointerType = 'mouse' }
                    actions = @(
                        @{
                            type = 'pointerMove'
                            duration = 0
                            origin = 'viewport'
                            x = $X
                            y = $Y
                        },
                        @{ type = 'pointerDown'; button = 0 },
                        @{ type = 'pointerUp'; button = 0 }
                    )
                }
            )
        } | ConvertTo-Json -Depth 8
        Invoke-RestMethod `
            -Method Post `
            -Uri "$driverBaseUri/session/$browserSessionId/actions" `
            -ContentType 'application/json' `
            -Body $actions | Out-Null
        Start-Sleep -Milliseconds 500
    }

    function Invoke-BrowserCoordinateDrag {
        param(
            [int]$SourceX,
            [int]$SourceY,
            [int]$TargetX,
            [int]$TargetY
        )

        $actions = @{
            actions = @(
                @{
                    type = 'pointer'
                    id = 'builder-coordinate-drag'
                    parameters = @{ pointerType = 'mouse' }
                    actions = @(
                        @{
                            type = 'pointerMove'
                            duration = 0
                            origin = 'viewport'
                            x = $SourceX
                            y = $SourceY
                        },
                        @{ type = 'pointerDown'; button = 0 },
                        @{ type = 'pause'; duration = 400 },
                        @{
                            type = 'pointerMove'
                            duration = 900
                            origin = 'viewport'
                            x = $TargetX
                            y = $TargetY
                        },
                        @{ type = 'pause'; duration = 250 },
                        @{ type = 'pointerUp'; button = 0 }
                    )
                }
            )
        } | ConvertTo-Json -Depth 8
        Invoke-RestMethod `
            -Method Post `
            -Uri "$driverBaseUri/session/$browserSessionId/actions" `
            -ContentType 'application/json' `
            -Body $actions | Out-Null
        Start-Sleep -Milliseconds 700
    }

    function Set-BrowserTextField {
        param(
            [string]$Label,
            [string]$Text
        )

        Wait-BrowserLabel -Label $Label
        $elementId = Get-BrowserElementId -Label $Label
        Invoke-RestMethod `
            -Method Post `
            -Uri (
                "$driverBaseUri/session/$browserSessionId/element/" +
                "$elementId/value"
            ) `
            -ContentType 'application/json' `
            -Body (@{
                text = $Text
                value = @($Text.ToCharArray() | ForEach-Object { "$_" })
            } | ConvertTo-Json) | Out-Null
        Start-Sleep -Milliseconds 300
    }

    function Scroll-BrowserCanvasToTop {
        $actions = @{
            actions = @(
                @{
                    type = 'wheel'
                    id = 'builder-wheel'
                    actions = @(
                        @{
                            type = 'scroll'
                            duration = 500
                            origin = 'viewport'
                            x = 1100
                            y = 500
                            deltaX = 0
                            deltaY = -2400
                        }
                    )
                }
            )
        } | ConvertTo-Json -Depth 8
        Invoke-RestMethod `
            -Method Post `
            -Uri "$driverBaseUri/session/$browserSessionId/actions" `
            -ContentType 'application/json' `
            -Body $actions | Out-Null
        Start-Sleep -Milliseconds 500
    }

    function Open-BuilderRoute {
        param(
            [string]$Route,
            [string]$ReadyLabel
        )

        Invoke-BrowserScript `
            -Script 'window.location.hash = arguments[0]; return true;' `
            -Arguments @($Route) | Out-Null
        Start-Sleep -Milliseconds 500
        Enable-BrowserSemantics
        Wait-BrowserLabel -Label $ReadyLabel
    }

    function Get-EmulatorDocument {
        param([string]$Path)

        $uri = "http://127.0.0.1:8080/v1/projects/$projectId/" +
            "databases/(default)/documents/$Path"
        return Invoke-RestMethod `
            -Uri $uri `
            -Headers @{ Authorization = "Bearer $($selectedIdentity.IdToken)" }
    }

    function Wait-EmulatorDocument {
        param(
            [string]$Path,
            [scriptblock]$Predicate,
            [int]$TimeoutSeconds = 30
        )

        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        do {
            try {
                $document = Get-EmulatorDocument -Path $Path
                if (& $Predicate $document) {
                    return $document
                }
            }
            catch {
                if ([DateTime]::UtcNow -ge $deadline) {
                    throw
                }
            }
            Start-Sleep -Milliseconds 250
        } while ([DateTime]::UtcNow -lt $deadline)
        throw "Timed out waiting for Firestore document $Path."
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
                ExpectedContent = 'Browser Athlete Program'
            },
            [ordered]@{
                Route = '/athlete/history'
                Marker = 'data-browser-smoke-surface-athlete-history'
                Screenshot = 'athlete-workout-history'
                ExpectedContent = 'Browser Completed Workout'
            },
            [ordered]@{
                Route = '/athlete/calendar'
                Marker = 'data-browser-smoke-surface-athlete-calendar'
                Screenshot = 'athlete-calendar'
                ExpectedContent = 'Browser Calendar Workout'
            }
        )
    }
    else {
        $surfaceChecks = @(
            [ordered]@{
                Route = '/trainer/dashboard'
                Marker = 'data-browser-smoke-surface-trainer-dashboard'
                Screenshot = 'trainer-dashboard'
                ExpectedContent = (
                    'Program ending soon: Browser Athlete Program (7 days) | ' +
                    "Reaction: $celebrate 1 | " +
                    'Comment: Browser dashboard comment | ' +
                    'Completion: Browser Completed Workout'
                )
                ExpectedControls = @(
                    [ordered]@{ Label = 'All filter'; Disabled = $false },
                    [ordered]@{
                        Label = 'Completions filter'
                        Disabled = $false
                    },
                    [ordered]@{
                        Label = 'Comments filter'
                        Disabled = $false
                    },
                    [ordered]@{
                        Label = 'Reactions filter'
                        Disabled = $false
                    },
                    [ordered]@{
                        Label = 'Programs filter'
                        Disabled = $false
                    },
                    [ordered]@{
                        Label = 'Personal bests'
                        Disabled = $true
                    }
                )
            },
            [ordered]@{
                Route = '/trainer/clients'
                Marker = 'data-browser-smoke-surface-trainer-clients'
                Screenshot = 'trainer-clients'
                ExpectedContent = 'Browser Smoke Athlete'
            },
            [ordered]@{
                Route = '/trainer/exercises'
                Marker = 'data-browser-smoke-surface-trainer-exercises'
                Screenshot = 'trainer-exercise-library'
                ExpectedContent = (
                    'Browser Trainer Exercise | Strength | ' +
                    'Browser exercises | Unfiled'
                )
                CollapseControl = 'Collapse Browser exercises'
            },
            [ordered]@{
                Route = '/trainer/workouts'
                Marker = 'data-browser-smoke-surface-trainer-workouts'
                Screenshot = 'trainer-workout-library'
                ExpectedContent = (
                    'Browser Calendar Workout | Client | Full Body | ' +
                    'Browser workouts | Clients | Unfiled'
                )
                CollapseControl = 'Collapse Browser Smoke Athlete'
            },
            [ordered]@{
                Route = '/trainer/programs'
                Marker = 'data-browser-smoke-surface-trainer-programs'
                Screenshot = 'trainer-program-library'
                ExpectedContent = (
                    'Browser Athlete Program | Client | Strength | ' +
                    'Browser programs | Clients | Unfiled'
                )
                CollapseControl = 'Collapse Browser Smoke Athlete'
            },
            [ordered]@{
                Route = '/trainer/calendar'
                Marker = 'data-browser-smoke-surface-trainer-calendar'
                Screenshot = 'trainer-calendar-assignments'
                ExpectedContent = (
                    'Browser Smoke Athlete | Browser Athlete Program | ' +
                    'Browser Calendar Workout'
                )
            }
        )
    }
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
            $surfaceState = $null
            $surfaceDeadline = [DateTime]::UtcNow.AddSeconds(30)
            $surfaceScript = @{
                script = @'
return document.body ? {
  state: document.body.getAttribute(arguments[0]),
  content: document.body.getAttribute(arguments[0] + '-content'),
  text: document.body.innerText || ''
} : null;
'@
                args = @($surface.Marker)
            } | ConvertTo-Json
            while ([DateTime]::UtcNow -lt $surfaceDeadline) {
                $result = Invoke-RestMethod `
                    -Method Post `
                    -Uri "$driverBaseUri/session/$browserSessionId/execute/sync" `
                    -ContentType 'application/json' `
                    -Body $surfaceScript
                $surfaceState = $result.value
                if (
                    $surfaceState.state -and
                    $surfaceState.state -ne 'ready'
                ) {
                    throw (
                        "$($surface.Route) reported " +
                        "'$($surfaceState.state)' instead of populated."
                    )
                }
                if (
                    $surfaceState.text -match
                    'permission-denied|something went wrong|unable to load|' +
                    'error:|no .* yet|unavailable'
                ) {
                    throw "$($surface.Route) rendered an error or empty state."
                }
                if ($surfaceState.state -eq 'ready') {
                    if ($surfaceState.content -eq $surface.ExpectedContent) {
                        $surfaceReady = $true
                        break
                    }
                }
                Start-Sleep -Milliseconds 250
            }
            if (-not $surfaceReady) {
                if ($surfaceState.state -eq 'ready') {
                    throw (
                        "$($surface.Route) loaded " +
                        "'$($surfaceState.content)', expected " +
                        "'$($surface.ExpectedContent)'."
                    )
                }
                throw "Browser smoke did not load $($surface.Route)."
            }
            $expectedControls = @()
            if ($surface.Contains('ExpectedControls')) {
                $expectedControls = @($surface['ExpectedControls'])
            }
            if (
                $expectedControls.Count -gt 0 -or
                $surface.Contains('CollapseControl')
            ) {
                $semanticsScript = @{
                    script = @'
const placeholder = document.querySelector('flt-semantics-placeholder');
if (placeholder) {
  placeholder.click();
}
return true;
'@
                    args = @()
                } | ConvertTo-Json
                Invoke-RestMethod `
                    -Method Post `
                    -Uri (
                        "$driverBaseUri/session/$browserSessionId/" +
                        'execute/sync'
                    ) `
                    -ContentType 'application/json' `
                    -Body $semanticsScript | Out-Null
            }
            foreach ($control in $expectedControls) {
                if (-not $control) {
                    continue
                }
                $controlScript = @{
                    script = @'
const expected = arguments[0];
const element = Array.from(document.querySelectorAll('[aria-label]'))
  .find((candidate) =>
    (candidate.getAttribute('aria-label') || '').includes(expected)
  );
return element ? {
  found: true,
  disabled: element.getAttribute('aria-disabled') === 'true' ||
    element.hasAttribute('disabled')
} : { found: false, disabled: false };
'@
                    args = @($control.Label)
                } | ConvertTo-Json
                $controlResult = $null
                $controlDeadline = [DateTime]::UtcNow.AddSeconds(10)
                do {
                    $controlResult = Invoke-RestMethod `
                        -Method Post `
                        -Uri (
                            "$driverBaseUri/session/$browserSessionId/" +
                            'execute/sync'
                        ) `
                        -ContentType 'application/json' `
                        -Body $controlScript
                    if (-not $controlResult.value.found) {
                        Start-Sleep -Milliseconds 200
                    }
                } while (
                    -not $controlResult.value.found -and
                    [DateTime]::UtcNow -lt $controlDeadline
                )
                if (-not $controlResult.value.found) {
                    throw (
                        "$($surface.Route) did not expose accessible control " +
                        "'$($control.Label)'."
                    )
                }
                if (
                    [bool]$controlResult.value.disabled -ne
                    [bool]$control.Disabled
                ) {
                    throw (
                        "$($surface.Route) control '$($control.Label)' " +
                        'reported the wrong disabled state.'
                    )
                }
            }
            if ($surface.Contains('CollapseControl')) {
                $labelsScript = @{
                    script = @'
return Array.from(document.querySelectorAll('[aria-label]'))
  .map((candidate) => candidate.getAttribute('aria-label'))
  .filter(Boolean);
'@
                    args = @()
                } | ConvertTo-Json
                $collapseScript = @{
                    script = @'
const expected = arguments[0];
const element = Array.from(document.querySelectorAll('[aria-label]'))
  .find((candidate) =>
    (candidate.getAttribute('aria-label') || '').includes(expected)
  );
if (!element) return false;
element.click();
return true;
'@
                    args = @($surface.CollapseControl)
                } | ConvertTo-Json
                $collapseResult = $null
                $collapseDeadline = [DateTime]::UtcNow.AddSeconds(10)
                do {
                    $collapseResult = Invoke-RestMethod `
                        -Method Post `
                        -Uri (
                            "$driverBaseUri/session/$browserSessionId/" +
                            'execute/sync'
                        ) `
                        -ContentType 'application/json' `
                        -Body $collapseScript
                    if (-not $collapseResult.value) {
                        Start-Sleep -Milliseconds 200
                    }
                } while (
                    -not $collapseResult.value -and
                    [DateTime]::UtcNow -lt $collapseDeadline
                )
                if (-not $collapseResult.value) {
                    $labelsResult = Invoke-RestMethod `
                        -Method Post `
                        -Uri (
                            "$driverBaseUri/session/$browserSessionId/" +
                            'execute/sync'
                        ) `
                        -ContentType 'application/json' `
                        -Body $labelsScript
                    throw (
                        "$($surface.Route) did not expose collapse control " +
                        "'$($surface.CollapseControl)'. Available labels: " +
                        (@($labelsResult.value) -join ' | ')
                    )
                }
                Start-Sleep -Milliseconds 500
                Save-BrowserScreenshot -Name "$($surface.Screenshot)-collapsed"
                $expandLabel = $surface.CollapseControl -replace '^Collapse ', 'Expand '
                $expandScript = @{
                    script = @'
const expected = arguments[0];
const element = Array.from(document.querySelectorAll('[aria-label]'))
  .find((candidate) =>
    (candidate.getAttribute('aria-label') || '').includes(expected)
  );
if (!element) return false;
element.click();
return true;
'@
                    args = @($expandLabel)
                } | ConvertTo-Json
                $expandResult = $null
                $expandDeadline = [DateTime]::UtcNow.AddSeconds(10)
                do {
                    $expandResult = Invoke-RestMethod `
                        -Method Post `
                        -Uri (
                            "$driverBaseUri/session/$browserSessionId/" +
                            'execute/sync'
                        ) `
                        -ContentType 'application/json' `
                        -Body $expandScript
                    if (-not $expandResult.value) {
                        Start-Sleep -Milliseconds 200
                    }
                } while (
                    -not $expandResult.value -and
                    [DateTime]::UtcNow -lt $expandDeadline
                )
                if (-not $expandResult.value) {
                    $labelsResult = Invoke-RestMethod `
                        -Method Post `
                        -Uri (
                            "$driverBaseUri/session/$browserSessionId/" +
                            'execute/sync'
                        ) `
                        -ContentType 'application/json' `
                        -Body $labelsScript
                    throw (
                        "$($surface.Route) did not expose expand control " +
                        "'$expandLabel' after collapsing. Available labels: " +
                        (@($labelsResult.value) -join ' | ')
                    )
                }
                Start-Sleep -Milliseconds 500
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
    if ($Identity -eq 'trainer') {
        $exerciseSourceA =
            'Browser Trainer Exercise, draggable exercise, published version 1'
        $exerciseSourceB =
            'Browser Trainer Row, draggable exercise, published version 1'
        $workoutSourceA =
            'Browser Builder Workout, draggable workout, published version 1'
        $workoutSourceB =
            'Browser Completed Workout, draggable workout, published version 1'

        function Assert-ExactOrder {
            param(
                [object[]]$Actual,
                [string[]]$Expected,
                [string]$Label
            )

            $actualText = @($Actual) -join '|'
            $expectedText = @($Expected) -join '|'
            if ($actualText -ne $expectedText) {
                throw "$Label order was '$actualText', expected '$expectedText'."
            }
        }

        function Save-And-PublishWorkoutBuilder {
            param(
                [string]$TemplateId,
                [string]$ScreenshotName
            )

            Save-BrowserScreenshot -Name $ScreenshotName
            Invoke-BrowserCoordinateClick -X 580 -Y 240
            $headerPath = "workoutTemplates/$TemplateId"
            $draft = Wait-EmulatorDocument `
                -Path "$headerPath/builderDrafts/current" `
                -Predicate {
                param($document)
                $slots = @(
                    $document.fields.slots.arrayValue.values
                )
                if ($slots.Count -ne 2) {
                    return $false
                }
                return $true
            }
            $draftSlots = @(
                $draft.fields.slots.arrayValue.values
            )
            $draftOrder = @(
                $draftSlots | ForEach-Object {
                    $_.mapValue.fields.exerciseId.stringValue
                }
            )
            Assert-ExactOrder `
                -Actual $draftOrder `
                -Expected @(
                    $secondExerciseTemplateId,
                    $exerciseTemplateId
                ) `
                -Label "$TemplateId draft"
            $draftIds = @(
                $draftSlots | ForEach-Object {
                    $_.mapValue.fields.slotId.stringValue
                }
            )
            if (($draftIds | Select-Object -Unique).Count -ne 2) {
                throw "$TemplateId draft did not preserve unique stable IDs."
            }
            Start-Sleep -Seconds 1
            Invoke-BrowserCoordinateClick -X 694 -Y 240
            $version = Wait-EmulatorDocument `
                -Path "$headerPath/workoutTemplateVersions/1" `
                -Predicate {
                    param($document)
                    return (
                        $document.fields.publishState.stringValue -eq
                            'published'
                    )
                }
            $publishedSlots = @($version.fields.slots.arrayValue.values)
            $publishedOrder = @(
                $publishedSlots | ForEach-Object {
                    $_.mapValue.fields.exerciseId.stringValue
                }
            )
            Assert-ExactOrder `
                -Actual $publishedOrder `
                -Expected @(
                    $secondExerciseTemplateId,
                    $exerciseTemplateId
                ) `
                -Label "$TemplateId published version"
            $publishedVersions = @(
                $publishedSlots | ForEach-Object {
                    $_.mapValue.fields.exerciseVersion.integerValue
                }
            )
            Assert-ExactOrder `
                -Actual $publishedVersions `
                -Expected @('1', '1') `
                -Label "$TemplateId pinned versions"
            $publishedIds = @(
                $publishedSlots | ForEach-Object {
                    $_.mapValue.fields.slotId.stringValue
                }
            )
            Assert-ExactOrder `
                -Actual $publishedIds `
                -Expected $draftIds `
                -Label "$TemplateId stable IDs"
            $publishedHeader = Get-EmulatorDocument -Path $headerPath
            if (
                $publishedHeader.fields.currentVersion.integerValue -ne '1' -or
                -not $publishedHeader.fields.builderDraft.PSObject.Properties[
                    'nullValue'
                ]
            ) {
                throw "$TemplateId did not clear its draft on publish."
            }
        }

        function Add-ProgramPhase {
            param([string]$Name)

            Scroll-BrowserCanvasToTop
            Invoke-BrowserLabelClick -Label 'Add phase'
            Set-BrowserTextField -Label 'Phase name' -Text $Name
            Invoke-BrowserLabelClick -Label 'Save'
            Wait-BrowserLabel -Label $Name
        }

        function Add-ProgramWorkout {
            param(
                [string]$WorkoutName,
                [switch]$UseDrag,
                [string]$DropLabel
            )

            if ($UseDrag) {
                $sourceLabel =
                    "$WorkoutName, draggable workout, published version 1"
                Invoke-BrowserDrag `
                    -SourceLabel $sourceLabel `
                    -TargetLabel $DropLabel
            }
            else {
                Invoke-BrowserLabelClick `
                    -Label "Add $WorkoutName to program"
            }
            Wait-BrowserLabel -Label 'OK'
            Invoke-BrowserLabelClick -Label 'OK'
        }

        function Save-And-PublishProgramBuilder {
            param(
                [string]$ProgramId,
                [string]$ScreenshotName
            )

            Save-BrowserScreenshot -Name $ScreenshotName
            Invoke-BrowserCoordinateClick -X 1190 -Y 28
            $headerPath = "programs/$ProgramId"
            $draft = Wait-EmulatorDocument `
                -Path "$headerPath/builderDrafts/current" `
                -Predicate {
                param($document)
                $entries = @($document.fields.entries.arrayValue.values)
                $phases = @($document.fields.phases.arrayValue.values)
                return $entries.Count -eq 2 -and $phases.Count -eq 2
            }
            $draftEntries = @(
                $draft.fields.entries.arrayValue.values
            )
            $draftEntryOrder = @(
                $draftEntries | ForEach-Object {
                    $_.mapValue.fields.workoutTemplateId.stringValue
                }
            )
            Assert-ExactOrder `
                -Actual $draftEntryOrder `
                -Expected @($historyTemplateId, $builderSourceWorkoutId) `
                -Label "$ProgramId draft"
            $draftEntryIds = @(
                $draftEntries | ForEach-Object {
                    $_.mapValue.fields.entryId.stringValue
                }
            )
            if (($draftEntryIds | Select-Object -Unique).Count -ne 2) {
                throw "$ProgramId draft did not preserve unique stable IDs."
            }
            Start-Sleep -Seconds 1
            Invoke-BrowserCoordinateClick -X 1380 -Y 28
            $version = Wait-EmulatorDocument `
                -Path "$headerPath/programVersions/1" `
                -Predicate {
                    param($document)
                    return $document.fields.entries.arrayValue.values.Count -eq 2
                }
            $publishedEntries = @($version.fields.entries.arrayValue.values)
            $publishedOrder = @(
                $publishedEntries | ForEach-Object {
                    $_.mapValue.fields.workoutTemplateId.stringValue
                }
            )
            Assert-ExactOrder `
                -Actual $publishedOrder `
                -Expected @($historyTemplateId, $builderSourceWorkoutId) `
                -Label "$ProgramId published version"
            $publishedVersions = @(
                $publishedEntries | ForEach-Object {
                    $_.mapValue.fields.workoutTemplateVersion.integerValue
                }
            )
            Assert-ExactOrder `
                -Actual $publishedVersions `
                -Expected @('1', '1') `
                -Label "$ProgramId pinned versions"
            $publishedEntryIds = @(
                $publishedEntries | ForEach-Object {
                    $_.mapValue.fields.entryId.stringValue
                }
            )
            Assert-ExactOrder `
                -Actual $publishedEntryIds `
                -Expected $draftEntryIds `
                -Label "$ProgramId stable IDs"
            $publishedPhases = @(
                $version.fields.phases.arrayValue.values |
                    ForEach-Object { $_.mapValue.fields.name.stringValue }
            )
            Assert-ExactOrder `
                -Actual $publishedPhases `
                -Expected @('Peak', 'Build') `
                -Label "$ProgramId phases"
            $publishedHeader = Get-EmulatorDocument -Path $headerPath
            if (
                $publishedHeader.fields.currentVersion.integerValue -ne '1' -or
                -not $publishedHeader.fields.builderDraft.PSObject.Properties[
                    'nullValue'
                ]
            ) {
                throw "$ProgramId did not clear its draft on publish."
            }
        }

        Open-BuilderRoute `
            -Route "/workouts/$dragWorkoutBuilderId" `
            -ReadyLabel $exerciseSourceA
        Invoke-BrowserDrag `
            -SourceLabel $exerciseSourceA `
            -TargetLabel 'Drop exercise at start'
        Invoke-BrowserDrag `
            -SourceLabel $exerciseSourceB `
            -TargetLabel 'Drop exercise after 1'
        Invoke-BrowserDrag `
            -SourceLabel $exerciseSourceB `
            -TargetLabel 'Drop exercise at start'
        Invoke-BrowserCoordinateClick -X 1353 -Y 580
        Save-And-PublishWorkoutBuilder `
            -TemplateId $dragWorkoutBuilderId `
            -ScreenshotName 'trainer-workout-builder-drag'

        if ($WorkoutDragOnly) {
            Write-Host 'BROWSER_BUILDER_ASSERTIONS_PASSED:trainer:workout-drag'
            Write-Host "BROWSER_SMOKE_ASSERTIONS_PASSED:$Identity"
            return
        }

        Open-BuilderRoute `
            -Route "/workouts/$controlsWorkoutBuilderId" `
            -ReadyLabel $exerciseSourceA
        Invoke-BrowserLabelClick `
            -Label 'Add Browser Trainer Exercise to workout'
        Invoke-BrowserLabelClick `
            -Label 'Add Browser Trainer Row to workout'
        Invoke-BrowserLabelClick -Label 'Move block up'
        Save-And-PublishWorkoutBuilder `
            -TemplateId $controlsWorkoutBuilderId `
            -ScreenshotName 'trainer-workout-builder-controls'

        Open-BuilderRoute `
            -Route "/programs/$dragProgramBuilderId" `
            -ReadyLabel $workoutSourceA
        Add-ProgramWorkout `
            -WorkoutName 'Browser Builder Workout' `
            -UseDrag `
            -DropLabel 'Drop workout at start'
        Add-ProgramWorkout `
            -WorkoutName 'Browser Completed Workout' `
            -UseDrag `
            -DropLabel 'Drop workout after 1'
        Add-ProgramPhase -Name 'Build'
        Add-ProgramPhase -Name 'Peak'
        Invoke-BrowserDrag `
            -SourceLabel 'Draggable phase 1' `
            -TargetLabel 'Draggable phase 2'
        Invoke-BrowserDrag `
            -SourceLabel 'Draggable workout 1' `
            -TargetLabel 'Drop workout after 2'
        Save-And-PublishProgramBuilder `
            -ProgramId $dragProgramBuilderId `
            -ScreenshotName 'trainer-program-builder-drag'

        Open-BuilderRoute `
            -Route "/programs/$controlsProgramBuilderId" `
            -ReadyLabel $workoutSourceA
        Add-ProgramWorkout -WorkoutName 'Browser Builder Workout'
        Add-ProgramWorkout -WorkoutName 'Browser Completed Workout'
        Invoke-BrowserLabelClick -Label 'Move workout up'
        Add-ProgramPhase -Name 'Build'
        Add-ProgramPhase -Name 'Peak'
        Invoke-BrowserLabelClick -Label 'Move phase down'
        Save-And-PublishProgramBuilder `
            -ProgramId $controlsProgramBuilderId `
            -ScreenshotName 'trainer-program-builder-controls'
        Write-Host 'BROWSER_BUILDER_ASSERTIONS_PASSED:trainer'
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
