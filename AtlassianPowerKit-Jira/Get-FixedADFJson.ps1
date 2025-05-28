param (
    [Parameter(Mandatory = $true)]
    [string]$INPUT_FILE_PATH,
    [Parameter(Mandatory = $false)]
    [switch]$DownloadSchema = $false
)
$ErrorActionPreference = 'Stop'; $DebugPreference = 'Continue'

$JIRA_ADF_SCHEMA_URL = 'http://go.atlassian.com/adf-json-schema'
$JIRA_ADF_SCHEMA_FILE = "$env:OSM_INSTALL\AtlassianPowerKit\AtlassianPowerKit-Jira\JiraADFJsonSchema.json"

function Get-SchemaDefinition {
    param(
        [string]$SchemaUrl
    )
    Invoke-RestMethod -Uri $SchemaUrl -OutFile $JIRA_ADF_SCHEMA_FILE
}

function Test-JSONFileAgainstSchemaFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$JsonInputFilePath,
        [Parameter(Mandatory = $true)]
        [string]$SchemaFilePath
    )
    Write-Debug "Validating JSON file: $JsonInputFilePath ..."
    if (! (Test-Json -Path $JsonInputFilePath)) {
        throw "Invalid JSON file: $JsonInputFilePath"
    }
    Write-Debug "`t ... $JsonInputFilePath is a valid JSON file."
    Write-Debug "Validating JSON file against schema file: $SchemaFilePath ..."
    if (! (Test-Json -Path $SchemaFilePath)) {
        throw "Invalid JSON schema file: $SchemaFilePath"
    }
    Write-Debug "`t ... $SchemaFilePath is a valid JSON schema file."
    Write-Debug 'Validating JSON file against schema file ...'
    Test-Json -Path "$JsonInputFilePath" -SchemaFile "$SchemaFilePath"
}

#################### MAIN ####################
if ($DownloadSchema) {
    Get-SchemaDefinition -SchemaUrl $JIRA_ADF_SCHEMA_URL
}
if ($INPUT_FILE_PATH) {
    Test-JSONFileAgainstSchemaFile -JsonInputFilePath $INPUT_FILE_PATH -SchemaFilePath $JIRA_ADF_SCHEMA_FILE
}
