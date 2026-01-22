# ...existing code...
param(
    [string]$ImageName = 'markz0r/atlassian-powerkit',
    [string]$Version = $(Get-Date -Format 'yyyy.MM.dd.HHmm'),
    [switch]$Push,
    [switch]$Latest,
    [switch]$TestRun,
    [switch]$MultiArch  # requires buildx configured
)

$ErrorActionPreference = 'Stop'

Write-Host "Building image for: $ImageName Version: $Version"

$tags = @("${ImageName}:$Version")
if ($Latest) { $tags += "$ImageName:latest" }

# Build args (add if you need)
$buildArgs = @()

# Choose build command
if ($MultiArch) {
    if (-not (docker buildx ls 2>$null)) { throw 'docker buildx not configured.' }
    $tagArgs = $tags | ForEach-Object { "--tag $_" } | Out-String
    $cmd = "docker buildx build --platform linux/amd64,linux/arm64 $tagArgs --progress plain ."
    if ($Push) { $cmd += ' --push' } else { $cmd += ' --load' }
    Write-Host $cmd
    Invoke-Expression $cmd
} else {
    foreach ($t in $tags) {
        docker build -t $t @buildArgs .
    }
    if ($Push) {
        Write-Host 'Pushing tags...'
        foreach ($t in $tags) { docker push $t }
    }
}

if ($TestRun) {
    Write-Host 'Test importing module inside container...'
    $testTag = $tags[0]
    docker run --rm $testTag pwsh -NoLogo -Command "Import-Module /app/AtlassianPowerKit.psd1; 'Module Loaded OK'; Get-Command AtlassianPowerKit | Out-Null"
}

Write-Host 'Done. Tags built:'
$tags | ForEach-Object { Write-Host "  $_" }