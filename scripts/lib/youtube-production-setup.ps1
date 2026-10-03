Set-StrictMode -Version Latest

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
