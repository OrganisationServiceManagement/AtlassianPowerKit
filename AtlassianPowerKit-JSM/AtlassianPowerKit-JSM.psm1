<#

.LINK
GitHub: https://github.com/markz0r/AtlassianPowerKit

#>
$ErrorActionPreference = 'Stop'; $DebugPreference = 'Continue'

# Function to export Org history from Jira Cloud
function Export-OrgHistory {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ORG_ID,
        [Parameter(Mandatory = $false)]
        [string]$OUTPUT_PATH = "$($env:OSM_HOME)\$($env:AtlassianPowerKit_PROFILE_NAME)\JIRA"
    )
    $FILENAME = "$env:AtlassianPowerKit_PROFILE_NAME-$ORG_ID-OrgHistory-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $ORG_HISTORY = Invoke-RestMethod -Uri "https://api.atlassian.com/admin/v1/orgs/$ORG_ID/events" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get -ContentType 'application/json'
    $ORG_HISTORY | ConvertTo-Json -Depth 50 | Out-File -FilePath "$OUTPUT_PATH\$FILENAME"
    Return $ORG_HISTORY
}

# Function to get list of Orgs from Jira Cloud
function Get-AtlassianOrgs {
    param (
        [Parameter(Mandatory = $false)]
        [string]$OUTPUT_PATH = "$($env:OSM_HOME)\$($env:AtlassianPowerKit_PROFILE_NAME)\JIRA"
    )
    $FILENAME = "$env:AtlassianPowerKit_PROFILE_NAME-OrgList-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $ORG_LIST = Invoke-RestMethod -Uri 'https://api.atlassian.com/admin/v1/orgs' -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get -ContentType 'application/json'
    $ORG_LIST | ConvertTo-Json -Depth 50 | Out-File -FilePath "$OUTPUT_PATH\$FILENAME"
    Write-Debug "ORG_LIST written to $OUTPUT_PATH\$FILENAME"
    Return $ORG_LIST
}

# Function to get  list of Request Types from Jira Cloud JSM project
function Get-JiraServiceDeskRequestTypes {
    param (
        [Parameter(Mandatory = $true)]
        [string]$PROJECT_KEY,
        [Parameter(Mandatory = $false)]
        [string]$OUTPUT_PATH = "$($env:OSM_HOME)\$($env:AtlassianPowerKit_PROFILE_NAME)\JIRA"
    )
    $FILENAME = "$env:AtlassianPowerKit_PROFILE_NAME-$PROJECT_KEY-RequestTypeSchema-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $REQUEST_TYPE_ARRAY = @()
    $REQUEST_TYPES = Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/servicedeskapi/servicedesk/$PROJECT_KEY/requesttype" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get -ContentType 'application/json'
    $REQUEST_TYPE_ARRAY += $REQUEST_TYPES.values
    while (! $REQUEST_TYPES.isLastPage) {
        $REQUEST_TYPES = Invoke-RestMethod -Uri $REQUEST_TYPES._links.next -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get -ContentType 'application/json'
        $REQUEST_TYPE_ARRAY += $REQUEST_TYPES.values
    }
    $REQUEST_TYPES | ConvertTo-Json -Depth 50 | Out-File -FilePath "$OUTPUT_PATH\$FILENAME"
    Write-Debug "REQUEST_TYPES [$PROJECT_KEY] written to $OUTPUT_PATH\$FILENAME"
    Return $REQUEST_TYPES | ConvertTo-Json -Depth 100 -Compress
}

# Function to get All Request Types from Jira Cloud JSM project
function Get-JiraServiceDeskAllRequestTypes {
    param (
        [Parameter(Mandatory = $false)]
        [string]$OUTPUT_PATH = "$($env:OSM_HOME)\$($env:AtlassianPowerKit_PROFILE_NAME)\JIRA"
    )
    $FILENAME = "$($env:AtlassianPowerKit_PROFILE_NAME)-AllIssueTypeSchema-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $ALL_REQUEST_TYPES += Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_JiraCloudInstance)/rest/servicedeskapi/requesttype" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get -ContentType 'application/json'
    $ALL_REQUEST_TYPES | ConvertTo-Json -Depth 50 | Out-File -FilePath "$OUTPUT_PATH\$FILENAME"
    Write-Debug "ALL_REQUEST_TYPES written to $OUTPUT_PATH\$FILENAME"
    Return $ALL_REQUEST_TYPES

}
