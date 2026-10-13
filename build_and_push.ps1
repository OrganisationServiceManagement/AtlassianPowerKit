param(
    [string]$EnvFile = (Join-Path -Path $PSScriptRoot -ChildPath '.env'),
    [string]$ImageName,
    [string]$Version,
    [switch]$Push,
    [switch]$Latest,
    [switch]$TestRun,
    [switch]$MultiArch,  # requires buildx configured
    [switch]$SkipBuild  # reuse an existing image without building or pushing
)

$ErrorActionPreference = 'Stop'

function Import-EnvFile {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Missing .env file at '$Path'. Copy env_example to .env and fill in the required values."
    }

    foreach ($rawLine in Get-Content -LiteralPath $Path) {
        $line = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) {
            continue
        }

        if ($line -notmatch '^(?:export\s+)?(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?<value>.*)$') {
            Write-Warning "Skipping invalid .env line: $rawLine"
            continue
        }

        $name = $Matches.name
        $value = $Matches.value.Trim()
        $quoted = ($value.Length -ge 2) -and (
            ($value.StartsWith('"') -and $value.EndsWith('"')) -or
            ($value.StartsWith("'") -and $value.EndsWith("'"))
        )

        if ($quoted) {
            $value = $value.Substring(1, $value.Length - 2)
        } elseif ($value -match '^(?<value>.*?)\s+#.*$') {
            $value = $Matches.value.TrimEnd()
        }

        Set-Item -Path "env:$name" -Value $value
    }
}

function Get-EnvBool {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [bool]$Default
    )

    $value = [Environment]::GetEnvironmentVariable($Name, 'Process')
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $Default
    }

    switch -Regex ($value.Trim().ToLowerInvariant()) {
        '^(1|true|yes|y|on)$' { return $true }
        '^(0|false|no|n|off)$' { return $false }
        default { throw "Environment variable '$Name' must be true or false, got '$value'." }
    }
}

function Invoke-Docker {
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & docker @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Docker '$($Arguments[0])' failed with exit code $LASTEXITCODE."
    }
}

Import-EnvFile -Path $EnvFile

if ([string]::IsNullOrWhiteSpace($ImageName)) {
    $ImageName = $env:DOCKER_IMAGE_NAME
}

if ([string]::IsNullOrWhiteSpace($ImageName)) {
    throw 'Missing required environment variable: DOCKER_IMAGE_NAME.'
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = if ([string]::IsNullOrWhiteSpace($env:DOCKER_IMAGE_VERSION)) {
        Get-Date -Format 'yyyy.MM.dd.HHmm'
    } else {
        $env:DOCKER_IMAGE_VERSION
    }
}

$shouldPush = if ($PSBoundParameters.ContainsKey('Push')) { [bool]$Push } else { Get-EnvBool -Name 'DOCKER_PUSH' -Default $false }
$tagLatest = if ($PSBoundParameters.ContainsKey('Latest')) { [bool]$Latest } else { Get-EnvBool -Name 'DOCKER_LATEST' -Default $false }
$testRunEnabled = if ($PSBoundParameters.ContainsKey('TestRun')) { [bool]$TestRun } else { Get-EnvBool -Name 'DOCKER_TEST_RUN' -Default $false }
$multiArchEnabled = if ($PSBoundParameters.ContainsKey('MultiArch')) { [bool]$MultiArch } else { Get-EnvBool -Name 'DOCKER_MULTI_ARCH' -Default $false }

Write-Host "Building image for: $ImageName Version: $Version"

$tags = @("${ImageName}:$Version")
if ($tagLatest) { $tags += "${ImageName}:latest" }

if (-not $SkipBuild) {
    if ($multiArchEnabled) {
        Invoke-Docker -Arguments @('buildx', 'ls') | Out-Null
        $dockerArguments = @('buildx', 'build', '--platform', 'linux/amd64,linux/arm64')
        foreach ($tag in $tags) {
            $dockerArguments += @('--tag', $tag)
        }
        $dockerArguments += @('--progress', 'plain')
        $dockerArguments += if ($shouldPush) { '--push' } else { '--load' }
        $dockerArguments += $PSScriptRoot
        Invoke-Docker -Arguments $dockerArguments
    } else {
        foreach ($tag in $tags) {
            Invoke-Docker -Arguments @('build', '--tag', $tag, $PSScriptRoot)
        }
        if ($shouldPush) {
            Write-Host 'Pushing tags...'
            foreach ($tag in $tags) {
                Invoke-Docker -Arguments @('push', $tag)
            }
        }
    }
}

if ($testRunEnabled) {
    Write-Host 'Test importing module inside container...'
    $testTag = $tags[0]
    $smokeCommand = @'
$ErrorActionPreference = 'Stop'
Get-ChildItem -Path /app -Filter *.psd1 -Recurse | ForEach-Object {
    Import-Module $_.FullName -Force
}
Get-Command AtlassianPowerKit, Export-JiraProjectIssues | Out-Null
'Modules Loaded OK'
'@
    Invoke-Docker -Arguments @('run', '--rm', '--entrypoint', 'pwsh', $testTag, '-NoLogo', '-NoProfile', '-Command', $smokeCommand)
}
Write-Host 'Done. Image tags:'
$tags | ForEach-Object { Write-Host "  $_" }
