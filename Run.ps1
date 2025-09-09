Remove-Module -Name 'AtlassianPowerKit*' -Force
Set-Location "$env:OSM_INSTALL/AtlassianPowerKit"
Import-Module "$env:OSM_INSTALL/AtlassianPowerKit/AtlassianPowerKit.psd1" -Force

# Load Environment Variables from the host

# Check if arguments were passed to the script
if ($args.Count -gt 0) {
    # Run AtlassianPowerKit with the provided arguments
    AtlassianPowerKit @args
} else {
    # Default command
    Write-Output 'No arguments provided. Starting Atlassian PowerKit...'
    AtlassianPowerKit
}