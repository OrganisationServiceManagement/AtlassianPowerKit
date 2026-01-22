[CmdletBinding()]
param(
    #[string]$IncFunctionName #= 'Set-AtlassianAPIHeader',
    ##[hashtable]$IncFunctionParams = @{
    ##    USERNAME      = 'mark.culhane@zoak.solutions'
    ##    sincedate     = $(Get-Date '2024-11-01')
    ##    unildate      = $(Get-Date)
    ##    OUTGOING_FILE = "$env:OSM_HOME\unknown\unknown-issues-2024-11-01-to-Now.csv"
    #}
)
# Clean reload of AtlassianPowerKit
function Update-ModuleSession {
    Remove-Module -Name 'AtlassianPowerKit*' -Force
    Set-Location "$env:OSM_INSTALL/AtlassianPowerKit"
    Import-Module "$env:OSM_INSTALL/AtlassianPowerKit/AtlassianPowerKit.psd1" -Force

    Set-Location "$env:OSM_INSTALL/AtlassianPowerKit"
}

function Invoke-ItNow {
    AtlassianPowerKit -FunctionName $IncFunctionName -FunctionParameters $IncFunctionParams
}
Update-ModuleSession
Invoke-ItNow