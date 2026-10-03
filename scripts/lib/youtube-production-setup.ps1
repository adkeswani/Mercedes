Set-StrictMode -Version Latest

function ConvertTo-NativeOutputText {
    param(
        [AllowNull()]
        [object[]]$Value
    )

    return (@($Value) -join [Environment]::NewLine).Trim()
}

function Test-YoutubeApiServiceListOutput {
    param(
        [AllowNull()]
        [object[]]$Value
    )

    return (ConvertTo-NativeOutputText $Value) -eq 'youtube.googleapis.com'
}

function Resolve-YoutubeSetupTarget {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('dev', 'staging', 'prod')]
        [string]$Environment,

        [Parameter(Mandatory)]
        [string]$Project,

        [Parameter(Mandatory)]
        [string]$ManifestPath,

        [Parameter(Mandatory)]
        [string]$FirebaseRcPath
    )

    $manifest =
        Get-Content -LiteralPath $ManifestPath -Raw |
        ConvertFrom-Json
    $environmentConfig = $manifest.environments.$Environment
    if (-not $environmentConfig) {
        throw "Environment '$Environment' is missing from the manifest."
    }
    if (-not $environmentConfig.projectId) {
        throw (
            "Environment '$Environment' is not provisioned in " +
            $ManifestPath
        )
    }

    $resolvedProjectId = $Project
    if (Test-Path -LiteralPath $FirebaseRcPath -PathType Leaf) {
        $firebaseRc =
            Get-Content -LiteralPath $FirebaseRcPath -Raw |
            ConvertFrom-Json
        if ($firebaseRc.projects.PSObject.Properties.Name -contains 'default') {
            throw "Firebase alias 'default' is forbidden."
        }
        $alias = $firebaseRc.projects.PSObject.Properties |
            Where-Object Name -EQ $Project |
            Select-Object -First 1
        if ($alias) {
            $resolvedProjectId = [string]$alias.Value
        }
    }

    if ($resolvedProjectId -ne $environmentConfig.projectId) {
        throw (
            "Environment '$Environment' expects project " +
            "'$($environmentConfig.projectId)', not '$resolvedProjectId'."
        )
    }
    if (
        $Environment -eq 'prod' -and
        $resolvedProjectId -ne $manifest.productionProjectId
    ) {
        throw (
            "Production setup must target " +
            "'$($manifest.productionProjectId)'."
        )
    }
    if (
        $Environment -ne 'prod' -and
        $resolvedProjectId -eq $manifest.productionProjectId
    ) {
        throw "Environment '$Environment' cannot target production."
    }

    return [pscustomobject]@{
        Environment = $Environment
        ProjectId = $resolvedProjectId
        Alias = [string]$environmentConfig.alias
        HostingUrl = [string]$environmentConfig.hostingUrl
    }
}

function Test-YoutubeSetupGitState {
    param(
        [Parameter(Mandatory)]
        [string]$Branch,

        [Parameter(Mandatory)]
        [string]$Head,

        [Parameter(Mandatory)]
        [string]$RequiredCommit,

        [Parameter(Mandatory)]
        [bool]$Clean
    )

    $problems = [Collections.Generic.List[string]]::new()
    if (-not $Clean) {
        $problems.Add('Working tree must be clean.')
    }
    if ($Branch -ne 'main') {
        $problems.Add("Current branch is '$Branch'; deployment requires main.")
    }
    if ($Head -ne $RequiredCommit) {
        $problems.Add(
            "main HEAD '$Head' does not equal intended commit " +
            "'$RequiredCommit'."
        )
    }
    return [pscustomobject]@{
        Ready = $problems.Count -eq 0
        Problems = $problems.ToArray()
    }
}

function Test-FunctionsBuildPrerequisites {
    param(
        [Parameter(Mandatory)]
        [string]$FunctionsPath
    )

    $problems = [Collections.Generic.List[string]]::new()
    $packagePath = Join-Path $FunctionsPath 'package.json'
    $lockPath = Join-Path $FunctionsPath 'package-lock.json'
    $modulesPath = Join-Path $FunctionsPath 'node_modules'
    $typescriptPath = Join-Path $modulesPath 'typescript\bin\tsc'

    if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
        $problems.Add("Missing Functions manifest: $packagePath")
    }
    if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) {
        $problems.Add(
            "Missing Functions lockfile: $lockPath. Restore it from Git; " +
            'the setup script will not generate or update lockfiles.'
        )
    }
    if (-not (Test-Path -LiteralPath $modulesPath -PathType Container)) {
        $problems.Add(
            'Locked Functions dependencies are not installed. In interactive ' +
            'mode, approve the guarded npm ci step, or run ' +
            "'npm --prefix functions ci --no-audit --no-fund'."
        )
    } elseif (-not (Test-Path -LiteralPath $typescriptPath -PathType Leaf)) {
        $problems.Add(
            'The local Functions TypeScript compiler is missing. Restore ' +
            "locked dependencies with 'npm --prefix functions ci " +
            "--no-audit --no-fund'."
        )
    }

    return [pscustomobject]@{
        Ready = $problems.Count -eq 0
        LockfilePresent = Test-Path -LiteralPath $lockPath -PathType Leaf
        Problems = $problems.ToArray()
    }
}

function Get-NodeMajorVersion {
    param(
        [Parameter(Mandatory)]
        [string]$Version
    )

    if ($Version -notmatch '^[vV]?(?<Major>\d+)(?:\.|$)') {
        throw "Unable to parse Node.js version '$Version'."
    }
    return [int]$Matches.Major
}

function Get-FunctionsNodeVersionWarning {
    param(
        [Parameter(Mandatory)]
        [int]$ActualMajor,

        [Parameter(Mandatory)]
        [int]$RuntimeMajor,

        [Parameter(Mandatory)]
        [int]$ToolingMajor
    )

    if ($ActualMajor -eq $RuntimeMajor) {
        return $null
    }
    if ($ActualMajor -eq $ToolingMajor) {
        return (
            "Local Node.js $ActualMajor matches tooling-config.json but the " +
            "Functions runtime is Node.js $RuntimeMajor. Use Node.js " +
            "$RuntimeMajor for runtime-parity validation before deployment."
        )
    }
    return (
        "Local Node.js $ActualMajor matches neither tooling-config.json " +
        "($ToolingMajor) nor the Functions runtime ($RuntimeMajor). Install " +
        'the repository-pinned local tooling, and use the runtime major for ' +
        'runtime-parity validation before deployment.'
    )
}
