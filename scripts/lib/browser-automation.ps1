Set-StrictMode -Version Latest

function Get-FocusIndependentChromeFlags {
    param([string[]]$ChromeFlags = @())

    $result = [Collections.Generic.List[string]]::new()
    foreach ($flag in $ChromeFlags) {
        if ($flag) {
            $result.Add($flag)
        }
    }

    foreach ($requiredFlag in @(
            '--disable-background-timer-throttling',
            '--disable-renderer-backgrounding',
            '--disable-backgrounding-occluded-windows'
        )) {
        $requiredName = $requiredFlag.Split('=', 2)[0]
        $alreadyConfigured = $false
        foreach ($existingFlag in $result) {
            if ($existingFlag.Split('=', 2)[0] -ieq $requiredName) {
                $alreadyConfigured = $true
                break
            }
        }
        if (-not $alreadyConfigured) {
            $result.Add($requiredFlag)
        }
    }

    return $result.ToArray()
}

function Get-FlutterDriveChromeFlagArguments {
    param([string[]]$ChromeFlags = @())

    return @(
        Get-FocusIndependentChromeFlags -ChromeFlags $ChromeFlags |
            ForEach-Object { "--web-browser-flag=$_" }
    )
}
