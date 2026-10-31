function ConvertTo-ClimbingFixtureValue {
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return @{ nullValue = $null } }
    if ($Value -is [bool]) { return @{ booleanValue = $Value } }
    if ($Value -is [int] -or $Value -is [long]) {
        return @{ integerValue = $Value.ToString() }
    }
    if ($Value -is [DateTime]) {
        return @{ timestampValue = $Value.ToUniversalTime().ToString('o') }
    }
    if ($Value -is [Collections.IDictionary]) {
        $fields = @{}
        foreach ($key in $Value.Keys) {
            $fields[$key] = ConvertTo-ClimbingFixtureValue $Value[$key]
        }
        return @{ mapValue = @{ fields = $fields } }
    }
    if ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
        return @{ arrayValue = @{ values = @(
            foreach ($item in $Value) { ConvertTo-ClimbingFixtureValue $item }
        ) } }
    }
    return @{ stringValue = [string]$Value }
}

function Get-ClimbingBrowserFixtureWrites {
    param(
        [string]$ProjectId, [string]$TrainerId, [string]$AthleteId,
        [string]$ProgramId, [string]$ProgramInstanceId, [string]$ExerciseId,
        [string]$Timestamp, [string]$ScheduledDate
    )
    $time = [DateTime]::Parse($Timestamp)
    $workoutId = 'browser-climbing-workout'
    $prefix = "projects/$ProjectId/databases/(default)/documents"
    $blocks = @(
        @{
            blockId = 'block-climbing-circuit'; type = 'climbingCircuit'
            sortOrder = 0; slotStartOrder = 0; slotCount = 1
            slotIds = @('slot-climbing-circuit'); title = $null
            notes = 'Technique before intensity'
            rowIds = @('row-boulder', 'row-rope')
            rows = @(
                @{
                    rowId = 'row-boulder'; gradingSystem = 'vScale'; grade = 'V2'
                    climbs = 3; maxAttemptsPerClimb = 2; notes = 'Controlled feet'
                },
                @{
                    rowId = 'row-rope'; gradingSystem = 'yds'; grade = '5.13a'
                    climbs = 1; maxAttemptsPerClimb = $null; notes = $null
                }
            )
        },
        @{
            blockId = 'block-free-climbing'; type = 'freeClimbing'
            sortOrder = 1; slotStartOrder = 1; slotCount = 1
            slotIds = @('slot-free-climbing'); title = $null; notes = 'Explore routes'
        },
        @{
            blockId = 'block-free-climbing-optional'; type = 'freeClimbing'
            sortOrder = 2; slotStartOrder = 2; slotCount = 1
            slotIds = @('slot-free-climbing-optional'); title = $null
            notes = 'No result rows required'
        }
    )
    $slots = @(
        for ($i = 0; $i -lt $blocks.Count; $i++) {
            @{
                slotId = $blocks[$i].slotIds[0]; blockId = $blocks[$i].blockId
                blockSortOrder = $i; slotOrder = $i; sortOrder = 0
                exerciseId = $(if ($i -eq 0) { $ExerciseId } else { 'builtin-free-climbing' })
                exerciseVersion = 1
                exerciseName = $(if ($i -eq 0) { 'Boulder Problem' } else { 'Free Climbing' })
                prescription = @{
                    mode = 'reps'; sets = $null; reps = $null; weight = $null
                    durationSeconds = $null; restSeconds = $null; notes = $null
                }
            }
        }
    )
    $header = @{
        name = 'Browser Climbing Workout'; ownerId = $TrainerId; createdBy = $TrainerId
        currentVersion = 2; workoutType = 'skill'; clientAthleteId = $AthleteId
        createdAt = $time; updatedAt = $time; updatedBy = $TrainerId
        deletedAt = $null; deletedBy = $null
    }
    $version = @{
        versionNumber = 1; publishedAt = $time; ownerId = $TrainerId
        storageFormat = 'typedWorkoutBlocksV1'; publishState = 'published'
        blockCount = $blocks.Count; slotCount = $slots.Count
        blockIds = @($blocks | ForEach-Object { $_.blockId })
        slotIds = @($slots | ForEach-Object { $_.slotId })
        climbingSlotIds = @($slots | ForEach-Object { $_.slotId })
        blocks = $blocks; slots = $slots; childWorkouts = @()
    }
    $instance = @{
        programId = $ProgramId; programOwnerId = $TrainerId; programVersion = 1
        athleteProgramInstanceId = $ProgramInstanceId; programAssignmentId = $ProgramInstanceId
        relationshipMode = 'subscribed'; athleteId = $AthleteId
        workoutTemplateId = $workoutId; workoutTemplateVersion = 1
        scheduledDate = $ScheduledDate; assignedBy = $TrainerId; assignedAt = $time
        status = 'scheduled'; workoutType = 'skill'; createdAt = $time; updatedAt = $time
        actualsStorageFormat = 'slotResultsSubcollection'; actualSlotIds = @(); actuals = @()
    }
    $documents = @(
        @{ path = "workoutTemplates/$workoutId"; data = $header },
        @{ path = "workoutTemplates/$workoutId/workoutTemplateVersions/1"; data = $version },
        @{ path = 'workoutInstances/browser-climbing-workout'; data = $instance }
        for ($i = 0; $i -lt $blocks.Count; $i++) {
            @{ path = "workoutTemplates/$workoutId/workoutTemplateVersions/1/workoutBlocks/$($blocks[$i].blockId)"; data = $blocks[$i] }
            @{ path = "workoutTemplates/$workoutId/workoutTemplateVersions/1/exerciseSlots/$($slots[$i].slotId)"; data = $slots[$i] }
        }
    )
    $newVersion = $version.Clone()
    $newVersion.versionNumber = 2
    $newBlocks = @($blocks | ForEach-Object { $_.Clone() })
    $newRows = @($blocks[0].rows | ForEach-Object { $_.Clone() })
    $newRows[0].grade = 'V5'
    $newRows[0].climbs = 9
    $newBlocks[0].rows = $newRows
    $newVersion.blocks = $newBlocks
    $documents += @{
        path = "workoutTemplates/$workoutId/workoutTemplateVersions/2"; data = $newVersion
    }
    for ($i = 0; $i -lt $newBlocks.Count; $i++) {
        $documents += @{ path = "workoutTemplates/$workoutId/workoutTemplateVersions/2/workoutBlocks/$($newBlocks[$i].blockId)"; data = $newBlocks[$i] }
        $documents += @{ path = "workoutTemplates/$workoutId/workoutTemplateVersions/2/exerciseSlots/$($slots[$i].slotId)"; data = $slots[$i] }
    }
    foreach ($document in $documents) {
        $value = ConvertTo-ClimbingFixtureValue $document.data
        @{ update = @{ name = "$prefix/$($document.path)"; fields = $value.mapValue.fields } }
    }
}
