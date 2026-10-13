param(
    [ValidateNotNullOrEmpty()]
    [string]$ImageName = 'markz0r/atlassian-powerkit',
    [ValidateNotNullOrEmpty()]
    [string]$Version = (Get-Date -Format 'yyyy.MM.dd.HHmm'),
    [switch]$Push,
    [switch]$Latest,
    [switch]$TestRun,
    [switch]$MultiArch,  # requires buildx configured
    [switch]$SkipBuild  # reuse an existing image without building or pushing
)

$ErrorActionPreference = 'Stop'

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

# Runtime configuration is supplied to docker run, never loaded during a build.
Write-Host "Building image for: $ImageName Version: $Version"

$tags = @("${ImageName}:$Version")
if ($Latest) { $tags += "${ImageName}:latest" }

if (-not $SkipBuild) {
    if ($MultiArch) {
        Invoke-Docker -Arguments @('buildx', 'ls') | Out-Null
        $dockerArguments = @('buildx', 'build', '--platform', 'linux/amd64,linux/arm64')
        foreach ($tag in $tags) {
            $dockerArguments += @('--tag', $tag)
        }
        $dockerArguments += @('--progress', 'plain')
        $dockerArguments += if ($Push) { '--push' } else { '--load' }
        $dockerArguments += $PSScriptRoot
        Invoke-Docker -Arguments $dockerArguments
    } else {
        foreach ($tag in $tags) {
            Invoke-Docker -Arguments @('build', '--tag', $tag, $PSScriptRoot)
        }
        if ($Push) {
            Write-Host 'Pushing tags...'
            foreach ($tag in $tags) {
                Invoke-Docker -Arguments @('push', $tag)
            }
        }
    }
}

if ($TestRun) {
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
