function Get-ProgressBrowserFixtureWrites {
    param(
        [string]$ProjectId, [string]$TrainerId, [string]$AthleteId,
        [string]$ProgramId, [string]$ExerciseId, [DateTime]$Today
    )
    $prefix = "projects/$ProjectId/databases/(default)/documents"
    $workoutId = 'browser-progress-template'
    $blocks = @(
        @{
            blockId = 'progress-boulder'; type = 'climbingRoute'
            sortOrder = 0; slotStartOrder = 0; slotCount = 1
            slotIds = @('progress-boulder'); gradingSystem = 'vScale'
            grade = 'V4'; color = ''; targetAttempts = 3
        },
        @{
            blockId = 'progress-rope'; type = 'climbingRoute'
            sortOrder = 1; slotStartOrder = 1; slotCount = 1
            slotIds = @('progress-rope'); gradingSystem = 'yds'
            grade = '5.11a'; color = ''; targetAttempts = 4
        },
        @{
            blockId = 'progress-circuit'; type = 'climbingCircuit'
            sortOrder = 2; slotStartOrder = 2; slotCount = 1
            slotIds = @('progress-circuit'); rowIds = @('v-row', 'rope-row')
            rows = @(
                @{ rowId = 'v-row'; gradingSystem = 'vScale'; grade = 'V2'
                    climbs = 3; maxAttemptsPerClimb = 2 },
                @{ rowId = 'rope-row'; gradingSystem = 'yds'; grade = '5.10a'
                    climbs = 2; maxAttemptsPerClimb = $null }
            )
        },
        @{
            blockId = 'progress-free'; type = 'freeClimbing'
            sortOrder = 3; slotStartOrder = 3; slotCount = 1
            slotIds = @('progress-free'); notes = 'Progress fixture free climbing'
        }
    )
    $slots = @(
        for ($i = 0; $i -lt $blocks.Count; $i++) {
            @{
                slotId = $blocks[$i].slotIds[0]; blockId = $blocks[$i].blockId
                blockSortOrder = $i; slotOrder = $i; sortOrder = 0
                exerciseId = $(if ($i -eq 2) { 'builtin-climbing-circuit' }
                    elseif ($i -eq 3) { 'builtin-free-climbing' } else { $ExerciseId })
                exerciseVersion = 1
                exerciseName = $(if ($i -eq 2) { 'Climbing Circuit' }
                    elseif ($i -eq 3) { 'Free Climbing' } else { 'Progress route' })
                prescription = @{
                    mode = 'reps'; sets = $null; reps = $null; weight = $null
                    durationSeconds = $null; restSeconds = $null; notes = $null
                }
            }
        }
    )
    $time = $Today.Date.AddDays(-1500)
    $header = @{
        name = 'Browser Progress Workout'; ownerId = $TrainerId; createdBy = $TrainerId
        currentVersion = 2; workoutType = 'skill'; clientAthleteId = $AthleteId
        createdAt = $time; updatedAt = $time; updatedBy = $TrainerId
        deletedAt = $null; deletedBy = $null
    }
    $version = @{
        versionNumber = 1; publishedAt = $time; ownerId = $TrainerId
        storageFormat = 'typedWorkoutBlocksV1'; publishState = 'published'
        blockCount = 4; slotCount = 4
        blockIds = @($blocks | ForEach-Object { $_.blockId })
        slotIds = @($slots | ForEach-Object { $_.slotId })
        climbingSlotIds = @('progress-circuit', 'progress-free')
        blocks = $blocks; slots = $slots; childWorkouts = @()
    }
    $documents = @(
        @{ path = 'programs/browser-progress-second-program'; data = @{
            name = 'Browser Second Progress Program'; ownerId = $TrainerId
            clientAthleteId = $AthleteId; type = 'assignable'; status = 'published'
            currentVersion = 1; createdAt = $time; updatedAt = $time
            createdBy = $TrainerId; updatedBy = $TrainerId
            deletedAt = $null; deletedBy = $null
        } }
        @{ path = "workoutTemplates/$workoutId"; data = $header }
        @{ path = "workoutTemplates/$workoutId/workoutTemplateVersions/1"; data = $version }
        for ($i = 0; $i -lt $blocks.Count; $i++) {
            @{ path = "workoutTemplates/$workoutId/workoutTemplateVersions/1/workoutBlocks/$($blocks[$i].blockId)"; data = $blocks[$i] }
            @{ path = "workoutTemplates/$workoutId/workoutTemplateVersions/1/exerciseSlots/$($slots[$i].slotId)"; data = $slots[$i] }
        }
    )
    $newVersion = $version.Clone()
    $newVersion.versionNumber = 2
    $newBlocks = @($blocks | ForEach-Object { $_.Clone() })
    $newBlocks[0].grade = 'V9'
    $newVersion.blocks = $newBlocks
    $documents += @{ path = "workoutTemplates/$workoutId/workoutTemplateVersions/2"; data = $newVersion }
    for ($i = 0; $i -lt $newBlocks.Count; $i++) {
        $documents += @{ path = "workoutTemplates/$workoutId/workoutTemplateVersions/2/workoutBlocks/$($newBlocks[$i].blockId)"; data = $newBlocks[$i] }
        $documents += @{ path = "workoutTemplates/$workoutId/workoutTemplateVersions/2/exerciseSlots/$($slots[$i].slotId)"; data = $slots[$i] }
    }
    foreach ($age in @(1, 10, 35, 200)) {
        $completed = $Today.Date.AddDays(-$age).AddHours(12)
        $instanceId = "browser-progress-$age"
        $instance = @{
            programId = $ProgramId; programOwnerId = $TrainerId; programVersion = 0
            athleteId = $AthleteId; workoutTemplateId = $workoutId
            workoutTemplateVersion = 1
            scheduledDate = $time.ToString('yyyy-MM-dd')
            assignedBy = $TrainerId; assignedAt = $time
            status = 'completed'; workoutType = 'skill'; completedAt = $completed
            rpe = 7; durationMinutes = 45; createdAt = $time; updatedAt = $completed
            actualsStorageFormat = 'slotResultsSubcollection'
            actualSlotIds = @($slots | ForEach-Object { $_.slotId }); actuals = @()
        }
        $results = @(
            @{ exerciseId = $ExerciseId; mode = 'reps'; sent = $true; attempts = 2 },
            @{ exerciseId = $ExerciseId; mode = 'reps'; sent = $true; attempts = 3 },
            @{ exerciseId = 'builtin-climbing-circuit'; mode = 'reps'
                climbingType = 'climbingCircuit'; rowIds = @('v-row', 'rope-row')
                circuitRows = @(
                    @{ rowId = 'v-row'; completed = $true },
                    @{ rowId = 'rope-row'; completed = $false }
                ) },
            @{ exerciseId = 'builtin-free-climbing'; mode = 'reps'
                climbingType = 'freeClimbing'; rowIds = @(0..3 | ForEach-Object { "free-row-$_" })
                freeRows = @(
                    0..3 | ForEach-Object {
                        @{ rowId = "free-row-$_"; gradingSystem = 'vScale'; grade = 'V8'; attempts = 2; sent = $false }
                    }
                ) }
        )
        if ($age -in @(1, 10)) {
            $instance.programVersion = 1
            $instance.athleteProgramInstanceId = 'browser-athlete-program-instance'
        } elseif ($age -eq 200) {
            $instance.programVersion = 1
            $instance.programId = 'browser-progress-second-program'
        }
        $documents += @{ path = "workoutInstances/$instanceId"; data = $instance }
        for ($i = 0; $i -lt $results.Count; $i++) {
            $documents += @{ path = "workoutInstances/$instanceId/slotResults/$($slots[$i].slotId)"; data = $results[$i] }
        }
    }
    $pageDate = $Today.Date.AddDays(-1000).AddHours(12)
    for ($i = 0; $i -lt 105; $i++) {
        $pageId = "browser-progress-page-$($i.ToString('000'))"
        $pageInstance = $instance.Clone()
        $pageInstance.completedAt = $pageDate
        $pageInstance.updatedAt = $pageDate
        $pageInstance.actualSlotIds = @('progress-boulder')
        $documents += @{ path = "workoutInstances/$pageId"; data = $pageInstance }
        $documents += @{ path = "workoutInstances/$pageId/slotResults/progress-boulder"; data = $results[0] }
    }
    foreach ($document in $documents) {
        $value = ConvertTo-ClimbingFixtureValue $document.data
        @{ update = @{ name = "$prefix/$($document.path)"; fields = $value.mapValue.fields } }
    }
}
