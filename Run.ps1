# Run.ps1

# Import necessary modules
Import-Module -Name Microsoft.PowerShell.SecretManagement, Microsoft.PowerShell.SecretStore -Force
Set-Location "$env:OSM_INSTALL/AtlassianPowerKit"
Import-Module "$env:OSM_INSTALL/AtlassianPowerKit/AtlassianPowerKit.psd1" -Force
$env:SECRETSTORE_PATH = $env:OSM_HOME

# Load Environment Variables from the host


# Check if arguments were passed to the script
if ($args.Count -gt 0) {
    # Run AtlassianPowerKit with the provided arguments
    AtlassianPowerKit @args
}
else {
    # Default command
    Write-Output 'No arguments provided. Starting Atlassian PowerKit...'
    AtlassianPowerKit 
}

Function Get-DeploymentConfigs {
    param (
        [Parameter(Mandatory = $true)]
        [string]$PROFILE_NAME
    )
    Write-Host "Processing profile: $PROFILE_NAME"
    # If there is a env:AtlassianPowerKit_PROFILE_NAME-ProjectList-*.json that was created in the last 12 hours, use it
    $PROFILE_PROJECT_LIST = Test-ExistingConfigJSON -CONFIG_FILE_PATHPATTERN "$($env:OSM_HOME)\$PROFILE_NAME\$PROFILE_NAME-ProjectList-*.json"
    if ($PROFILE_PROJECT_LIST) {
        $PROJECT_LIST = Get-Content $PROFILE_PROJECT_LIST.FullName | ConvertFrom-Json -AsHashtable -NoEnumerate
    }
    else {
        $PROJECT_LIST = AtlassianPowerKit -Profile $PROFILE_NAME -FunctionName 'Get-JiraProjectList' | ConvertFrom-Json -AsHashtable -NoEnumerate
    }
    #$PROJECT_LIST | ForEach-Object { Write-Host "Project: $($_.name) - $($_.key)" }
    #$PROJECT_LIST | ConvertTo-Json -Depth 100 | Write-Debug
    $OSM_PROJECT_LIST = $PROJECT_LIST | Where-Object { $_.key -match '.*OSM.*' -and $_.key -notin @('CUBOSM') }

    $JIRA_PROJECTS = $OSM_PROJECT_LIST | ForEach-Object {
        $PROJECT_NAME = $($_.name)
        $PROJECT_KEY = $($_.key)
        # PROJECT_PROPERTIES
        $PROFILE_PROJECT_PROPERTIES = Test-ExistingConfigJSON -CONFIG_FILE_PATHPATTERN "$($env:OSM_HOME)\$PROFILE_NAME\$PROFILE_NAME-$PROJECT_KEY-ProjectProperties-*.json"
        if ($PROFILE_PROJECT_PROPERTIES) {
            $PROFILE_PROJECT_PROPERTIES = Get-Content $PROFILE_PROJECT_PROPERTIES.FullName | ConvertFrom-Json -AsHashtable -NoEnumerate
        }
        else {
            $PROFILE_PROJECT_PROPERTIES = AtlassianPowerKit -Profile $PROFILE_NAME -FunctionName 'Get-JiraProjectProperties' -FunctionParameters @{ PROJECT_KEY = $PROJECT_KEY } | ConvertFrom-Json -AsHashtable -NoEnumerate
        }
        # PROJECT_ISSUE_TYPE_SCHEMA
        $PROJECT_ISSUE_TYPE_SCHEMA = Test-ExistingConfigJSON -CONFIG_FILE_PATHPATTERN "$($env:OSM_HOME)\$PROFILE_NAME\$PROFILE_NAME-$PROJECT_KEY-IssueTypeSchema-*.json"
        if ($PROJECT_ISSUE_TYPE_SCHEMA) {
            $PROJECT_ISSUE_TYPE_SCHEMA = Get-Content $PROJECT_ISSUE_TYPE_SCHEMA.FullName | ConvertFrom-Json -AsHashtable -NoEnumerate
        }
        else {
            $PROJECT_ISSUE_TYPE_SCHEMA = AtlassianPowerKit -Profile $PROFILE_NAME -FunctionName 'Get-JiraCloudIssueTypeSchema' -FunctionParameters @{ PROJECT_KEY = $PROJECT_KEY }
        }
        # 
        # PROJECT_ISSUE_TYPES
        $PROJECT_ISSUE_TYPES = Test-ExistingConfigJSON -CONFIG_FILE_PATHPATTERN "$($env:OSM_HOME)\$PROFILE_NAME\$PROFILE_NAME-$PROJECT_KEY-ProjectIssuesTypes-*.json"
        if ($PROJECT_ISSUE_TYPES) {
            $PROJECT_ISSUE_TYPES = Get-Content $PROJECT_ISSUE_TYPES.FullName | ConvertFrom-Json -AsHashtable -NoEnumerate
        }
        else {
            $PROJECT_ISSUE_TYPES = AtlassianPowerKit -Profile $PROFILE_NAME -FunctionName 'Get-JiraProjectIssuesTypes' -FunctionParameters @{ PROJECT_KEY_OR_ID = $PROJECT_KEY } | ConvertFrom-Json -AsHashtable -NoEnumerate
        }
        $PROJECT_REQUEST_TYPES = Test-ExistingConfigJSON -CONFIG_FILE_PATHPATTERN "$($env:OSM_HOME)\$PROFILE_NAME\$PROFILE_NAME-$PROJECT_KEY-RequestTypeSchema-*.json"
        if ($PROJECT_REQUEST_TYPES) {
            $PROJECT_REQUEST_TYPES = Get-Content $PROJECT_REQUEST_TYPES.FullName | ConvertFrom-Json -AsHashtable -NoEnumerate
        }
        else {
            $PROJECT_REQUEST_TYPES = AtlassianPowerKit -Profile $PROFILE_NAME -FunctionName 'Get-JiraServiceDeskRequestTypes' -FunctionParameters @{ PROJECT_KEY = $PROJECT_KEY } | ConvertFrom-Json -AsHashtable -NoEnumerate
        }
        
        # FORMS
        $PROJECT_FORMS = Test-ExistingConfigJSON -CONFIG_FILE_PATHPATTERN "$($env:OSM_HOME)\$PROFILE_NAME\$PROFILE_NAME-$PROJECT_KEY-Forms-*.json"
        if ($PROJECT_FORMS) {
            $PROJECT_FORMS = Get-Content $PROJECT_FORMS.FullName | ConvertFrom-Json -AsHashtable -NoEnumerate
        }
        else {
            $PROJECT_FORMS = AtlassianPowerKit -Profile $PROFILE_NAME -FunctionName 'Get-FormsForJiraProject' -FunctionParameters @{ PROJECT_KEY = $PROJECT_KEY } | ConvertFrom-Json -AsHashtable -NoEnumerate
        }

        # $FORMS = AtlassianPowerKit -Profile $PROFILE_NAME -FunctionName 'Get-FormsForJiraProject' -FunctionParameters @{ PROJECT_KEY = $PROJECT_KEY }
        # WORKFLOW_SCHEMES
        $PROJECT_WORKFLOWS_SCHEMES = Test-ExistingConfigJSON -CONFIG_FILE_PATHPATTERN "$($env:OSM_HOME)\$PROFILE_NAME\$PROFILE_NAME-$PROJECT_KEY-ProjectWorkflowSchemes-*.json"
        if ($PROJECT_WORKFLOWS_SCHEMES) {
            $PROJECT_WORKFLOWS_SCHEMES = Get-Content $PROJECT_WORKFLOWS_SCHEMES.FullName | ConvertFrom-Json -AsHashtable -NoEnumerate
        }
        else {
            $PROJECT_WORKFLOWS_SCHEMES = AtlassianPowerKit -Profile $PROFILE_NAME -FunctionName 'Get-JiraProjectWorkflowSchemes' -FunctionParameters @{ PROJECT_KEY = $PROJECT_KEY } | ConvertFrom-Json -AsHashtable -NoEnumerate
        }

        # Return object
        [PSCustomObject]@{
            PROJECT_NAME              = $PROJECT_NAME
            PROJECT_KEY               = $PROJECT_KEY
            PROJECT_ISSUE_TYPE_SCHEMA = $PROJECT_ISSUE_TYPE_SCHEMA
            PROJECT_ISSUE_TYPES       = $PROJECT_ISSUE_TYPES
            PROJECT_REQUEST_TYPES     = $PROJECT_REQUEST_TYPES
            PROJECT_WORKFLOWS_SCHEMES = $PROJECT_WORKFLOWS_SCHEMES
        }
    }
    Return $JIRA_PROJECTS | ConvertTo-Json -Depth 100 -Compress
}
