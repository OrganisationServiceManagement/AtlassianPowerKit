# ...existing code...
param(
    [string]$ImageName = 'ghcr.io/organisationservicemanagement/atlassian-powerkit',
    [string]$Version = $(Get-Date -Format 'yyyy.MM.dd.HHmm'),
    [switch]$Push,
    [switch]$Latest,
    [switch]$TestRun,
    [switch]$MultiArch,  # requires buildx configured
    [switch]$SkipBuild  # for testing alias addition without building/pushing
)

$ErrorActionPreference = 'Stop'

Write-Host "Building image for: $ImageName Version: $Version"

$tags = @("${ImageName}:$Version")
if ($Latest) { $tags += "$ImageName:latest" }

# Build args (add if you need)
$buildArgs = @()

# Choose build command
if (-not $SkipBuild) {
    Write-Host 'Building image...'
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
} else {
    Write-Debug 'Skipping build/push. Tags that would have been built:'
    Write-Debug $tags 
}
$tags | ForEach-Object { Write-Host "  $_" }

# Add alias to relevant file (win/bashrc)
$aliasCmd = ("alias AtlassianPowerKit='docker run --rm -it {0}:latest pwsh'" -f $ImageName)
if ($IsWindows) {
    $profilePath = "$HOME\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
    if (-not (Test-Path $profilePath)) { New-Item -ItemType File -Path $profilePath -Force | Out-Null }
    if (-not (Get-Content $profilePath | Select-String -Pattern 'AtlassianPowerKit')) {
        Add-Content -Path $profilePath -Value $aliasCmd
        Write-Host "Alias added to profile: $aliasCmd"
    } else {
        Write-Host "Alias already exists in profile."
    }
} else {
    $bashrcPath = "$HOME/.bashrc"
    if (-not (Test-Path $bashrcPath)) { New-Item -ItemType File -Path $bashrcPath -Force | Out-Null }
    if (-not (Get-Content $bashrcPath | Select-String -Pattern 'AtlassianPowerKit')) {
        Add-Content -Path $bashrcPath -Value $aliasCmd
        Write-Host "Alias added to .bashrc: $aliasCmd"
    } else {
        Write-Host "Alias already exists in .bashrc."
    }
}