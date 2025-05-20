<#
.SYNOPSIS
    Atlassian Cloud PowerShell Module for handy functions to interact with Attlassian Cloud APIs.

.DESCRIPTION
    Atlassian Cloud PowerShell Module for Jira Cloud and Opsgenie API functions.
    - Key functions are:
        - Setup:
            -             - New-AtlassianAPIEndpoint -AtlassianAPIEndpoint 'https://yourdomain.atlassian.net'
        - JIRA
            - Issues
                - Get-JiraCloudJQLQueryResult -JQL_STRING $JQL_STRING -JSON_FILE_PATH $JSON_FILE_PATH
                - Get-JiraIssueJSON -Key $Key
                - Get-JiraIssueChangeNullsFromJQL -JQL_STRING $JQL_STRING
                    - Get-JiraIssueChangeNulls -Key $Key
                - Get-JiraIssueChangeLog -Key $Key
                - Get-JiraFields
                - Set-JiraIssueField -ISSUE_KEY $ISSUE_KEY -Field_Ref $Field_Ref -New_Value $New_Value -FIELD_TYPE $FIELD_TYPE
                - Set-JiraCustomField -FIELD_NAME $FIELD_NAME -FIELD_TYPE $FIELD_TYPE
            - Project
                - Get-JiraProjectProperty
                - Get-JiraProjectProperties
                    - Set-JiraProjectProperty
                    - Clear-JiraProjectProperty
            - Other
                - Get-OpsgenieServices -Output ready for Set-JiraProjectProperty
            - Users and Groups
                - Get-AtlassianGroupMembers
                - Get-AtlassianUser
    - To list all functions in this module, run: Get-Command -Module AtlassianPowerKit
    - Debug output is enabled by default. To disable, set $DisableDebug = $true before running functions.

.PARAMETER AtlassianAPIEndpoint
    The Jira Cloud API endpoint for your Jira Cloud instance. This is required for all functions that interact with the Jira Cloud API. E.g.: 'yourdomain.atlassian.net'

.PARAMETER OpsgenieAPIEndpoint
    The Opsgenie API endpoint for your Opsgenie instance. This is required for all functions that interact with the Opsgenie API. Defaults to: 'api.opsgenie.com'

.EXAMPLE
    New-AtlassianAPIEndpoint -AtlassianAPIEndpoint 'https://yourdomain.atlassian.net'
    
    This example sets the Jira Cloud API endpoint and then gets the Jira Cloud API endpoint.

.EXAMPLE
    Get-JiraCloudJQLQueryResult -JQL_STRING 'project = "OSM" AND status = "Open"' -JSON_FILE_PATH 'C:\Temp\OSM-Open-Issues.json'

    This example gets the Jira Cloud JQL query results for all open issues in the OSM project and exports the results to a JSON file at 'C:\Temp\OSM-Open-Issues.json'.

.EXAMPLE
    Get-JiraIssueJSON -Key 'OSM-123'

    This example gets the Jira issue with the key 'OSM-123' and exports the results to a JSON file at '.\OSM-123.json'.

.EXAMPLE
    Get-JiraIssueChangeNullsFromJQL -JQL_STRING 'project = "OSM" AND status = "Open"'

    This example gets the Jira Cloud JQL query results for all open issues in the OSM project and then gets the change nulls for each issue.

.EXAMPLE
    Get-Jira-CloudJQLQueryResults -JQL_STRING 'project is not EMPTY' -JSON_FILE_PATH 'All-Issues.json'
    This example gets the Jira Cloud JQL query results for all issues in all projects.

.LINK
GitHub: https://github.com/markz0r/AtlassianPowerKit

#>
$ErrorActionPreference = 'Stop'; $DebugPreference = 'Continue'
# Directory of this file 
$RETRY_AFTER = 10
#function Convert-JiraIssueToTableRow {
#    param (
#        [Parameter(Mandatory = $true)]
#        [array]$RAW_ROW
#    )
#    $TABLE_ROW = '<tr>'
#    $RAW_ROW | ForEach-Object {
#        $ROW_VAL = $_
#        if ($ROW_VAL) {
#            $TABLE_ROW += "<td><p>$ROW_VAL</p></td>"
#        }
#        else {
#            $TABLE_ROW += '<td><p>N/A</p></td>'
#        }
#    }
#    $TABLE_ROW += '</tr>'
#    $TABLE_ROW 
#    return $TABLE_ROW
#}

function ConvertTo-JSONMarkdownList {
    param (
        [Parameter(Mandatory = $true)]
        [string]$JSON_DATA_STRING
    )
    # Convert JSON to PowerShell Object
    $data = $JSON_DATA_STRING | ConvertFrom-Json

    # Initialize Markdown content
    $markdown = ''

    # Iterate over JSON keys and build Markdown
    foreach ($key in $data.PSObject.Properties.Name) {
        $markdown += "* *$($key)*:`n" # Add the top-level heading
        foreach ($item in $data.$key) {
            $markdown += "** [$item|$item|smart-link] `n" # Add the nested bullet point with a link
        }
    }
    Write-Debug "Markdown: $markdown"
    # Output Markdown
    return $markdown
}

function Export-RestorableJiraBackupJQL {
    param (
        [Parameter(Mandatory = $false)]
        [string]$JQL_STRING = 'project in (GRCOSM)'
    )
    $OUTPUT_DIR = "$($env:OSM_HOME)\$($env:AtlassianPowerKit_PROFILE_NAME)\JIRA\Exported-Backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    if (-not (Test-Path $OUTPUT_DIR)) {
        New-Item -ItemType Directory -Path $OUTPUT_DIR -Force | Out-Null
    }
    Write-Debug "$($MyInvocation.MyCommand.Name) Getting JIRA issues to for JQL: $JQL_STRING ..."
    $JIRA_ISSUES = Get-JiraCloudJQLQueryResult -JQL_STRING $JQL_STRING -ReturnJSONOnly
    Write-Debug "$($MyInvocation.MyCommand.Name) - JQL Results Received from  Get-JiraCloudJQLQueryResult..."
    $JIRA_ISSUES | ForEach-Object {
        $ISSUE = $_
        $ISSUE_KEY = $ISSUE.key
        Write-Debug "Exporting issue: $ISSUE_KEY to $OUTPUT_DIR\$ISSUE_KEY ..."
        if (-not (Test-Path "$OUTPUT_DIR\$ISSUE_KEY")) {
            New-Item -ItemType Directory -Path "$OUTPUT_DIR\$ISSUE_KEY" -Force | Out-Null
        }
        $ISSUE | ConvertTo-Json -Depth 100 | Out-File -FilePath "$OUTPUT_DIR\$ISSUE_KEY\$ISSUE_KEY.json" -Force
        if ($ISSUE.fields.attachment) {
            $ATTACHMENTS = $ISSUE.fields.attachment
            $ATTACHMENTS | ForEach-Object {
                $ATTACHMENT = $_
                $ATTACHMENT_ID = $ATTACHMENT.id
                $ATTACHMENT_FILENAME = $ATTACHMENT.filename
                Write-Debug "Exporting attachment: $OUTPUT_DIR\$ISSUE_KEY\$ATTACHMENT_FILENAME ..."
                Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/attachment/content/$ATTACHMENT_ID" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get -ContentType $Attachment.mimeType -OutFile "$OUTPUT_DIR\$ISSUE_KEY\$ATTACHMENT_FILENAME"
                Write-Debug "Exporting attachment: $OUTPUT_DIR\$ISSUE_KEY\$ATTACHMENT_FILENAME ... Done"
            }
        }
    }
    #Write-Debug "Raw JSON file exported to: $OUTPUT_DIR\Full.json"
    $JIRA_ISSUES_JSON = $JIRA_ISSUES | ConvertFrom-Json -Depth 1024
    Write-Debug "Exporting $($JIRA_ISSUES_JSON.Count) JIRA issues to: $OUTPUT_DIR ..."
    $JIRA_ISSUES_JSON | ForEach-Object {
        $ISSUE = $_
        $ISSUE_KEY = $ISSUE.key
        Write-Debug "Exporting issue: $ISSUE_KEY to $OUTPUT_DIR\$ISSUE_KEY ..."
        if (-not (Test-Path "$OUTPUT_DIR\$ISSUE_KEY")) {
            New-Item -ItemType Directory -Path "$OUTPUT_DIR\$ISSUE_KEY" -Force | Out-Null
        }
        $ISSUE | ConvertTo-Json -Depth 100 | Out-File -FilePath "$OUTPUT_DIR\$ISSUE_KEY\$ISSUE_KEY.json" -Force
        if ($ISSUE.fields.attachment) {
            $ATTACHMENTS = $ISSUE.fields.attachment
            $ATTACHMENTS | ForEach-Object {
                $ATTACHMENT = $_
                $ATTACHMENT_ID = $ATTACHMENT.id
                $ATTACHMENT_FILENAME = $ATTACHMENT.filename
                Write-Debug "Exporting attachment: $OUTPUT_DIR\$ISSUE_KEY\$ATTACHMENT_FILENAME ..."
                Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/attachment/content/$ATTACHMENT_ID" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get -ContentType $Attachment.mimeType -OutFile "$OUTPUT_DIR\$ISSUE_KEY\$ATTACHMENT_FILENAME"
                Write-Debug "Exporting attachment: $OUTPUT_DIR\$ISSUE_KEY\$ATTACHMENT_FILENAME ... Done"
            }
        }
    }
}

function Import-JIRAIssueFromJSONBackup {
    param (
        [Parameter(Mandatory = $true)]
        [string]$JSON_FILE_PATH,
        [Parameter(Mandatory = $true)]
        [string]$DEST_PROJECT_KEY,
        [Parameter(Mandatory = $true)]
        [string]$DEST_ISSUE_TYPE,
        [Parameter(Mandatory = $false)]
        [string]$FIELD_MAP_JSON
    )
    $ISSUE = Get-Content -Path $JSON_FILE_PATH | ConvertFrom-Json -Depth 100 -NoEnumerate
    ## HACKE
    # Change content objects of type = mediaSingle or mediaGroup to code block
    $ISSUE.fields.description.content | Where-Object { $_.type -eq 'mediaSingle' -or $_.type -eq 'mediaGroup' } | ForEach-Object {
        $_.type = 'codeBlock'
        $COMPRESSED_CONTENT = $_.content | ConvertTo-Json -Depth 100 -Compress
        $_.content = @(
            @{
                type = 'text'
                text = $COMPRESSED_CONTENT
            },
            @{
                type = 'text'
                text = '# Attachment removed by OSM Power Kit Restore, will be re-attached but not re-embedded, see attachments below.'
            }
        )
    }

    if ($FIELD_MAP_JSON) {
        Write-Debug "Field map provided: $FIELD_MAP_JSON"
    } else {
        Write-Debug 'Using manual mapping...'
        $POST_ISSUE = @{
            fields = @{
                project     = @{
                    key = $DEST_PROJECT_KEY
                }
                issuetype   = @{
                    name = $DEST_ISSUE_TYPE
                }
                summary     = $ISSUE.fields.summary                  # Summary of the issue
                description = $ISSUE.fields.description          # Description of the issue
            }
        }
    }
    

    $ISSUE_SOURCE_INFO = "Source: $($ISSUE.fields.project.key) - $($ISSUE.key) -  $($ISSUE.fields.issuetype.name) - $($ISSUE.self)"
    $ISSUE_KEY = $ISSUE.key
    Write-Debug "Importing issue: $ISSUE_KEY to $DEST_PROJECT_KEY as $DEST_ISSUE_TYPE ..."

    $POST_COMMENT_JSON = "{
        'version': 1,
        'type': 'doc',
        'content': [
        {
            'type': 'bulletList',
            'content': [
            {
                'type': 'listItem',
                'content': [
                {
                    'type': 'paragraph',
                    'content': [
                    {
                        'type': 'text',
                        'text': 'Importing Issue using AtlassianPowerKit, ``$ISSUE_SOURCE_INFO``'
                    }
                    ]
                }
                ]
            }
            ]
        }
        ]
    }"
    # Write-Debug 'Converting fields from issue json:'
    # $ISSUE | ConvertTo-Json -Depth 100 | Write-Debug
    # $ISSUE.fields | ForEach-Object {
    #     $FIELD = $_
    #     $FIELD_NAME = $FIELD.Key
    #     $FIELD_VALUE = $FIELD.Value
    #     if ($FIELD_MAP.ConvertToComments -contains $FIELD_NAME) {
    #         Write-Debug "Converting field to comment: $FIELD_NAME"
    #         $POST_ISSUE.fields.$FIELD_NAME = @{
    #             body = $FIELD_VALUE
    #         }
    #     }
    #     elseif ($FIELD_MAP.IgnorePatterns -contains $FIELD_NAME) {
    #         Write-Debug "Ignoring field: $FIELD_NAME"
    #     }
    #     else {
    #         Write-Debug "Adding field: $FIELD_NAME"
    #         $POST_ISSUE.fields.$FIELD_NAME = $FIELD_VALUE
    #     }
    # }
    # https://your-domain.atlassian.net/rest/api/3/issue/createmeta/{projectIdOrKey}/issuetypes' 
    # Write-Debug 'CREATE ISSUE METADATA: '
    # $CREATE_ISSUE_METADATA = Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/issue/createmeta/$DEST_PROJECT_KEY/issuetypes" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get -ContentType 'application/json'
    # $CREATE_ISSUE_METADATA | ConvertTo-Json -Depth 100 | Write-Debug
    # return

    
    Write-Debug "POSTING ISSUE: $($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/issue"
    $POST_ISSUE | ConvertTo-Json -Depth 100 -EscapeHandling Default | Write-Debug
    try {
        $POST_REST_RESPONSE = Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/issue" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Post -ContentType 'application/json' -Body $($POST_ISSUE | ConvertTo-Json -EscapeHandling Default -Depth 100)
    } catch {
        Write-Debug "Error importing issue: $ISSUE_KEY to $DEST_PROJECT_KEY as $DEST_ISSUE_TYPE"
        # Write full errordetails to terminal, ensuring $ErrorDetails returned as json is fully written to terminal and not truncated
        Write-Debug ($_.ErrorDetails.ErrorMessages | ConvertFrom-Json -Depth 100 -NoEnumerate | ConvertTo-Json -Depth 100)

        Write-Debug ($_ | Select-Object -Property * -ExcludeProperty psobject | Out-String)
        Write-Error $_.Exception.Message
    }
    $NEW_ISSUE_KEY = $POST_REST_RESPONSE.key
    Write-Debug "Successfully imported issue, new issue key: $NEW_ISSUE_KEY"
    $ATTACHMENT_POST_HEADERS = $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders)
    $ATTACHMENT_POST_HEADERS.Add('X-Atlassian-Token', 'no-check')

    if ($ISSUE.fields.attachment) {
        $ATTACHMENTS = $ISSUE.fields.attachment
        $ATTACHMENTS | ForEach-Object {
            $ATTACHMENT = $_
            $ATTACHMENT_ID = $ATTACHMENT.id
            $ATTACHMENT_FILENAME = $ATTACHMENT.filename
            Write-Debug "Importing attachment: $OUTPUT_DIR\$ISSUE_KEY\$ATTACHMENT_FILENAME ..."
            Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/issue/$NEW_ISSUE_KEY/attachments/$ATTACHMENT_ID" -Headers $ATTACHMENT_POST_HEADERS -Method Post -ContentType $Attachment.mimeType -InFile "$OUTPUT_DIR\$ISSUE_KEY\$ATTACHMENT_FILENAME"
            Write-Debug "Importing attachment: $OUTPUT_DIR\$ISSUE_KEY\$ATTACHMENT_FILENAME ... Done"

        }
    }
    # Add comment
    Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/issue/$NEW_ISSUE_KEY/comment" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Post -ContentType 'application/json' -Body $POST_COMMENT_JSON
}

function Get-JiraFilterResults {
    param (
        [Parameter(Mandatory = $true)]
        [string]$FILTER_ID,
        [Parameter(Mandatory = $false)]
        [switch]$ReturnJSONOnly
    )
    $FILTER_INFO = Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/filter/$($FILTER_ID)" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get -ContentType 'application/json'

    $FILTER_COLUMNS = Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/filter/$($FILTER_ID)/columns" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get -ContentType 'application/json'
    Write-Debug "Filter Columns: $($FILTER_COLUMNS | ConvertTo-Json -Depth 10)"
    $COLUMN_VALS = $FILTER_COLUMNS | ForEach-Object { $_.Value }
    $JSON_ISSUE_SEARCH_RESPONSE = Get-JiraCloudJQLQueryResult -JQL_STRING $FILTER_INFO.jql -RETURN_FIELDS $COLUMN_VALS | ConvertFrom-Json
    # Write-Debug "JSON_ISSUE_SEARCH_RESPONSE: $($JSON_ISSUE_SEARCH_RESPONSE | ConvertTo-Json -Depth 10)"
    # For each Value in $FILTER_COLUMNS find in $JSON_ISSUE_SEARCH_RESPONSE.output_file and replace with $FILTER_COLUMNS.label
    # Do a simple find and replace of the contents of the output file, dont need to convert to json
    # Read the file contents once
    $FILE_CONTENTS = Get-Content -Path $JSON_ISSUE_SEARCH_RESPONSE.output_file -Raw

    # Perform all replacements
    $FILTER_COLUMNS | ForEach-Object {
        $COLUMN = $_
        Write-Debug "Replacing $($COLUMN.value) with $($COLUMN.label) in $($JSON_ISSUE_SEARCH_RESPONSE.output_file)"
        $FILE_CONTENTS = $FILE_CONTENTS -replace [regex]::Escape($COLUMN.value), $COLUMN.label
    }

    # Write the updated contents back to the file once
    Set-Content -Path $($JSON_ISSUE_SEARCH_RESPONSE.output_file) -Value $FILE_CONTENTS -Force
    if ($ReturnJSONOnly) {
        return $FILE_CONTENTS
    } else {
        return $JSON_ISSUE_SEARCH_RESPONSE.output_file
    }
}

function Get-JiraFilterResultsAsConfluenceTable {
    param (
        [Parameter(Mandatory = $true)]
        [string]$FILTER_ID
    )
    $FILTER_INFO = Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/filter/$($FILTER_ID)" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get -ContentType 'application/json'

    $FILTER_COLUMNS = Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/filter/$($FILTER_ID)/columns" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get -ContentType 'application/json'
    $COLUMN_VALS = $FILTER_COLUMNS | ForEach-Object { $_.Value }
        
    $TABLE_HEADERS = '<tbody><tr>'
    #$CONFLUENCE_STORAGE_RAW_FOOTER = "</tbody><hr /><ul><li><p>Updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p></li><li><p>Source: <a href=""$($FILTER_INFO.viewURL)"">$($FILTER_INFO.name)</a></p></li></ul><hr />"
    # Write-Debug "Filter Columns [$( $($FILTER_COLUMNS).count)]"
    Write-Debug "Filter Columns: $($FILTER_COLUMNS | ConvertTo-Json -Depth 10)"
    $FILTER_COLUMNS | ForEach-Object {
        $TABLE_HEADERS += "<th><p>$($_.label)</p></th>"
    }
    $TABLE_HEADERS += '</tr>'
    Write-Debug "TABLE_HEADERS: $TABLE_HEADERS"
    Write-Debug '########################################################## Get-JiraFilterResultsAsConfluenceTable calling Get-JiraCloudJQLQueryResult'
    $JSON_ISSUE_SEARCH_RESPONSE = Get-JiraCloudJQLQueryResult -JQL_STRING $FILTER_INFO.jql -RETURN_FIELDS $COLUMN_VALS
    Write-Debug '########################################################## Get-JiraFilterResultsAsConfluenceTable returned from Get-JiraCloudJQLQueryResult - Done'
    Write-Debug '########################################################## Get-JiraFilterResultsAsConfluenceTable - Read JSON File'
    Write-Debug "JSON_ISSUE_SEARCH_RESPONSE: $JSON_ISSUE_SEARCH_RESPONSE"
    $JSON_ISSUE_ARRAY_FILE = $($JSON_ISSUE_SEARCH_RESPONSE | ConvertFrom-Json).output_file
    $HASH_ARRAYLIST = Get-Content -Path $JSON_ISSUE_ARRAY_FILE | ConvertFrom-Json
    Write-Debug "HASH_ARRAYLIST: $($HASH_ARRAYLIST.GetType())"
    Write-Debug "HASH_ARRAYLIST Count: $($HASH_ARRAYLIST.Count)"
    Write-Debug '########################################################## Get-JiraFilterResultsAsConfluenceTable - HASH_ARRAYLIST: '
    $TABLE_HEADER_NAMES = $FILTER_COLUMNS | ForEach-Object { $_.value }
    Write-Debug "TABLE_HEADER_NAMES: $($TABLE_HEADER_NAMES)"
    $HASH_ARRAYLIST | ForEach-Object {
        $ROW_HASH = $_
        Write-Debug '####################'
        Write-Debug "ISSUE: $($ROW_HASH.Key)"
        Write-Debug 'FIELDS: '
        $($ROW_HASH.fields) | ConvertTo-Json -Depth 10 | Write-Debug
    }
    Write-Debug '##########################################################'
    Write-Debug 'THIS FUNCTION IS ABANDONED - use Export-PrintableJiraFilterResults instead'
    exit
    #$flattenedIssues = $HASH_ARRAYLIST | ForEach-Object {
    ##    [PSCustomObject]@{
            
    
    #$TABLE_ROWS = @($HASH_ARRAYLIST | ForEach-Object {
    #        $ROW_HASH = $_
    #        Write-Debug '####################'

    #        Write-Debug "ISSUE: $($ROW_HASH.Key)"
    #        #Write-Debug 'FIELDS: ' 
    #        #$($ROW_HASH.fields) | ConvertTo-Json -Depth 10 | Write-Debug
    #        $ORDERED_FIELD_VALUES = @()
    #        Write-Debug 'Filter Columns: '
    #        Write-Debug $FILTER_COLUMNS
    #        foreach ($FILTER_COLUMN in $FILTER_COLUMNS) {
    #            $FIELD_NAME = $FILTER_COLUMN.value
    #            $FIELD_VALUE = $ROW_HASH.Fields[$FIELD_NAME]
    #            # Add the field value to the ordered list
    #            $ORDERED_FIELD_VALUES += $FIELD_VALUE
    #        }
    #        Write-Debug 'Get-JiraFilterResultsAsConfluenceTable: Starting Convert-JiraIssueToTableRow...with ORDERED_FIELD_VALUES: '
    #        Convert-JiraIssueToTableRow -RAW_ROW $ORDERED_FIELD_VALUES
    #    }
    #)
        
    #$CONFLUENCE_STORAGE_RAW = $TABLE_HEADERS + $TABLE_ROWS + $CONFLUENCE_STORAGE_RAW_FOOTER
    #return $CONFLUENCE_STORAGE_RAW
}

function Get-JiraIssueChangeNullsFromJQL {
    param (
        [Parameter(Mandatory = $true)]
        [string]$JQL_STRING
    )
    $FIELD_NAME_OR_ID_OR_NULL = Read-Host 'OPTIONALLY, Enter a custom field name or ID (customfield_\d+) to check for nulls, or press Enter to skip...'
    Write-Debug "JQL Query: $JQL_STRING running..."
    $NULL_CHANGE_ITEMS = @()
    $REST_RESULTS = Get-JiraCloudJQLQueryResult -JQL_STRING $JQL_STRING
    if (!$FIELD_NAME_OR_ID_OR_NULL) {
        #Get-JiraIssueChangeNulls -Key $_.key
        Write-Debug 'No field name or ID provided, checking all fields...'
        $NULL_CHANGE_ITEMS = $REST_RESULTS.issues | ForEach-Object {
            Get-JiraIssueChangeNulls -Key $_.key
        }
    } else {
        Write-Debug "Field name or ID provided: $FIELD_NAME_OR_ID_OR_NULL"
        $NULL_CHANGE_ITEMS = $REST_RESULTS.issues | ForEach-Object {
            Get-JiraIssueChangeNulls -Key $_.key -SELECTOR "$FIELD_NAME_OR_ID_OR_NULL"
        }
    }
    # Write formated list of null changes to terminal
    $NULL_CHANGE_ITEMS | ForEach-Object {
        Write-Debug "$($_.key) - Field: $($_.field) (ID: $($_.fieldId)), Type: $($_.FIELD_TYPE) --- Value nulled: $($_.from) [Created: $($_.created) - Author: $($_.author)]'
            #Write-Debug 'Restore with: Set-JiraIssueField -ISSUE_KEY $($_.key) -Field_Ref $($_.fieldId) -New_Value $($_.from) -FIELD_TYPE $($_.fieldtype)"
    }
    $ATTEMPT_RESTORE = Read-Host 'Do you want to attempt to restore the nulled values? Y/N [N]'
    if ($ATTEMPT_RESTORE -eq 'Y') {
        # if $($_.fromString) appears to be an array, restore as an array
        $NULL_CHANGE_ITEMS | ForEach-Object {
            if ($_.fieldtype -eq 'custom') {
                if ($_.fieldId -ne 'customfield_10163') {
                    $New_Value = $_.fromString
                } else {
                    $New_Value = $_.from
                }
                $New_Value = $New_Value -replace '[\[\]\s]', ''
                $New_Value = $New_Value.Split(',')
            } else {
                $New_Value = , @($_.from)
            }
            if ($_.fieldId -eq 'customfield_10163') {
                $TARGET_FIELD = 'customfield_10370'
            } else {
                $TARGET_FIELD = $_.fieldId
            }

            Set-JiraIssueField -ISSUE_KEY $_.key -Field_Ref $TARGET_FIELD -New_Value $New_Value -FIELD_TYPE $_.fieldtype
            Write-Debug "Updated: $($_.issue) - Field: $($_.field): Value restored: $($_.fromString) --- data_val:[$($_.from)]"
        }

    }
}
# Function to list all JSON fields in a JSON object array only if the field contains a value that is not null in at least one object, include example of the field value, don't repeat the field name
function Get-JSONFieldsWithData {
    param (
        [Parameter(Mandatory = $true)]
        [string]$FILE_PATH
    )
    # TO BE MOVED TO CONFIG
    $EXCLUDED_FIELDS = @('Time to resolution', 'Time to first response', 'customfield_10062', 'assignee', 'aggregatetimeoriginalestimate',
        'aws-json-field__ad4c4b0c-406f-47c1-a8e3-df46e38dabf2', 'customfield_10291', 'customfield_10292', 'customfield_10294', 'customfield_10295', 'reporter'
        'progress', 'issuetype', 'project', 'customfield_10036', 'watches', 'customfield_10018', 'customfield_10019', 'updated', 'customfield_10010', 'customfield_10011', 'currentStatus', 'timetracking',
        'aws-json-field__b72236ec-c3c4-43ea-a646-84d08f224ab5', 'statuscategorychangedate', 'versions', 'timeestimate', 'status', 'creator', 'aggregateprogress', 'workratio', 'issuerestriction', 'created', 'votes', 'customfield_10022', 'lastViewed', 'customfield_10074', 'customfield_10073', 'customfield_10061', 'customfield_10060', 'customfield_10142')
    $DATA_FIELD_LIST = @{}
    $JIRA_FIELD_ARRAY = Get-JiraFields
    Write-Output "JIRA_FIELD_ARRAY: $($JIRA_FIELD_ARRAY.Count)"
    $JIRA_FIELD_ARRAY | ForEach-Object {
        Write-Debug "JIRA_FIELD_ARRAY: $($_.name), $($_.id), $($_.custom)"
    } 
    # For each json file in the directory, get the content and extract the fields
    # Write a sub-function that gets all fields in a JSON object array that are not null, adding the field to a hash table with key as the field name and value as the field value, if the key already exists, skip, the function takes a JSON object array as a parameter if the field is an object, write the field name and object type is an object, if the field is an array, write the field name and object type is an array, call self with the array as a parameter
    function Search-JSONObjectArray {
        param (
            [Parameter(Mandatory = $true)]
            [string]$RAW_JSON
        )
        #Write-Debug "Processing JSON_OBJECT: $($JSON_OBJECT.GetType())"
        $JSON_OBJECT = $RAW_JSON | ConvertFrom-Json -Depth 40
        Write-Debug "Processing JSON_OBJECT: $($($JSON_OBJECT).GetType())'
            Write-Debug 'Search-JSONObjectArray -- Issues Count: $($JSON_OBJECT.issues.Count)"
        
        $JSON_OBJECT.issues.fields | ForEach-Object {
            $FIELDS = $_
            #Write-Debug "Processing fields: $($FIELDS.GetType())'
            #Write-Debug 'Fields: $($FIELDS.Count)'
            #Write-Debug 'Fields: $($FIELDS)"
            Write-Debug 'Converting to Hashtable...'
        
            $FIELDSHashtable = @{}
            $FIELDS | ForEach-Object { $_.psobject.properties } | ForEach-Object { $FIELDSHashtable[$_.Name] = $_.Value }
            Write-Debug "FieldsHashtable Type: $($FIELDSHashtable.GetType())'
                Write-Debug 'FieldsHashtable Count: $($FIELDSHashtable.Count)"
            Write-Output $FIELDSHashtable
            
            #Write-Debug 'Skipping enumeration...'
            #return $false
            $FIELDSHashtable.GetEnumerator() | ForEach-Object {
                $FIELD = $_
                Write-Debug "Processing field: $FIELD"
                if ((!$FIELD.Value) -or ($FIELD.Key -in $EXCLUDED_FIELDS)) {
                    Write-Debug "Field without data: $FIELD)"
                } else {
                    Write-Debug '######'
                    Write-Debug "Field with data: $($FIELD | ConvertTo-Json -Depth 10)"
                    $FIELD_INFO = $JIRA_FIELD_ARRAY | Where-Object { $_.id -eq $FIELD.Key }
                    Write-Debug "Field with data, field info name: $($FIELD_INFO.name)'
                        Write-Debug '$($($FIELD.Name, $FIELD_INFO, $($FIELD.Value)).ToString())"
                    if (!(($DATA_FIELD_LIST.Count -gt 0) -and ($DATA_FIELD_LIST.ContainsKey($FIELD_INFO.Key)))) {
                        Write-Debug "Adding new field to DATA_FIELD_LIST: $FIELD.Name ----> $FIELD_INFO.name"
                        $DATA_FIELD_LIST[$($FIELD_INFO.name)] = "$($FIELD_INFO.name), $($FIELD.Name), $($($FIELD_INFO | ConvertTo-Json -Depth 2 -Compress) -replace (',', ' ')), $($($($FIELD.Value) | ConvertTo-Json -Depth 1 -Compress) -replace (',', ' '))"
                    }
                }
            }
        }
        return $DATA_FIELD_LIST
    }
    # Check file exists and is valid json
    Write-Debug "Processing file: $($FILE_PATH)"
    if (-not (Test-Path $FILE_PATH)) {
        Write-Error "File not found: $($FILE_PATH)"
    } else {
        $RAW_JSON_STRING = Get-Content -Path $FILE_PATH -Raw
        Write-Debug "Raw JSON String: $($RAW_JSON_STRING.GetType())"
        $JSON_OBJECT_ARRAY = $RAW_JSON_STRING | ConvertFrom-Json -Depth 40
        Write-Debug "JSON_OBJECT_ARRAY: $JSON_OBJECT_ARRAY.GetType()'
            Write-Output 'Issue Count: $($JSON_OBJECT_ARRAY.issues.Count)"
        Write-Debug 'FILE_CONTENT read successfully on surface. Processing JSON_OBJECT_ARRAY...'
        Search-JSONObjectArray -RAW_JSON $RAW_JSON_STRING
    }


    # Write $DATA_FIELD_LIST to a file
    $OUTPUT_FILE = "$($env:OSM_HOME)\$($env:AtlassianPowerKit_PROFILE_NAME)\JIRA\$env:AtlassianPowerKit_PROFILE_NAME-FieldsWithData-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
    if (-not (Test-Path $OUTPUT_FILE)) {
        New-Item -ItemType File -Path $OUTPUT_FILE -Force | Out-Null
    }
    # Write the field list to a CSV file with headers
    $CSV_DATA = @() 
    $CSV_DATA += 'Field Name, Field ID, Field Info, Field Value'
    # sort the data field list by field name and write values to the CSV file
    Write-Debug "DATA_FIELD_LIST: $($DATA_FIELD_LIST.GetType())'
        Write-Debug 'Fields with data: $($DATA_FIELD_LIST.Count)"
    $DATA_FIELD_LIST.GetEnumerator() | Sort-Object -Property Name | ForEach-Object {
        # Write each of the array values to the CSV file
        # Make a csv entry for the value object
        $Entry = $_.Value
        Write-Debug "Entry: $Entry"
        Write-Debug "Entry Type: $($Entry.GetType())"
        $CSV_DATA += $Entry
    }
    Write-Debug "CSV_DATA: $CSV_DATA"
    Write-Debug "CSV_DATA: $($CSV_DATA.GetType())"
    $CSV_DATA | Out-File -FilePath $OUTPUT_FILE -Append
    Write-Debug "Fields with data written to: $((Get-Item -Path $OUTPUT_FILE).Directory.FullName)"
}

# Function to check if a Jira issue exists by key or ID
function Test-JiraIssueExists {
    param (
        [Parameter(Mandatory = $true)]
        [string]$KeyOrID
    )
    # Invoke-RestMethod and capture the response to $ISSUE_KEY, even if it is an error
    try {
        $ISSUE_RESPONSE = Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/issue/$($KeyOrID)?fields=null" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get -ContentType 'application/json'
    } catch {
        Write-Debug ($_ | Select-Object -Property * -ExcludeProperty psobject | Out-String)
        $ISSUE_RESPONSE = ($_ | Select-Object -Property * -ExcludeProperty psobject | Out-String)
    }
    Write-Debug "Response: $($ISSUE_RESPONSE | ConvertTo-Json -Depth 10)"
    if ($ISSUE_RESPONSE.id) {
        Write-Debug "Jira issue $KeyOrID exists."
        return $true
    } else {
        Write-Debug "Jira issue $KeyOrID does not exist."
        return $false
    }
}

# Function to get JSON object for a Jira issue
function Get-JiraIssue {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Key
    )
    $ISSUE = Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/issue/$($Key)" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get -ContentType 'application/json'
    $ISSUE | ConvertTo-Json -Depth 30
}

# Function to get the issuelinks field from a Jira issue
function Get-JiraIssueLinks {
    param (
        [Parameter(Mandatory = $true)]
        [string]$IssueKey,
        [Parameter(Mandatory = $false)]
        [switch]$NoExport = $false,
        [Parameter(Mandatory = $false)]
        [string]$filter_link_type
    )
    try {
        $ISSUE_LINKS = Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/2/issue/$($IssueKey)?fields=issuelinks" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get -ContentType 'application/json'
    } catch {
        Write-Debug ($_ | Select-Object -Property * -ExcludeProperty psobject | Out-String)
        Write-Error "Error updating field: $($_.Exception.Message)"
    }
    $ISSUE_LINKS_JSON_ARRAY = $ISSUE_LINKS.fields.issuelinks
    return $ISSUE_LINKS_JSON_ARRAY | ConvertTo-Json -Depth 60
}

function Clear-EmptyFields {
    param (
        [Parameter(Mandatory = $true)]
        [string]$JSONString
    )
    $JSON_OBJECT = $JSONString | ConvertFrom-Json -Depth 100
    $JSON_OBJECT | ForEach-Object {
        $FIELD = $_
        if ($null -eq $FIELD) {
            $FIELD = $null
        }
    }
    return $JSON_OBJECT | ConvertTo-Json -Depth 100 -Compress
}
function Update-FieldNamesRaw {
    param (
        [Parameter(Mandatory = $true)]
        [string]$JSON_FILE_PATH
    )

    # Get Jira fields and create a mapping hashtable
    $JIRA_FIELDS = Get-JiraFields
    $JIRA_FIELD_MAPS = @{}
    $JIRA_FIELDS | ForEach-Object {
        $JIRA_FIELD_MAPS[$_.id] = $_.name
    }

    # Read the JSON file as a string
    $jsonContent = Get-Content -Path $JSON_FILE_PATH -Raw

    # Perform raw find and replace for each field
    foreach ($key in $JIRA_FIELD_MAPS.Keys) {
        $jsonContent = $jsonContent -replace "`"$key`"", "`"$($JIRA_FIELD_MAPS[$key])`""
    }
    $UPDATED_FILE = $JSON_FILE_PATH -replace '.json', '-updated.json'

    # Save the updated JSON content back to the file
    $jsonContent | Out-File -FilePath $UPDATED_FILE -Force
    return $UPDATED_FILE
}

# Function to return JQL query results as a PowerShell object that includes a loop to ensure all results are returned even if the
# number of results exceeds the maximum number of results returned by the Jira Cloud API
function Get-JiraCloudJQLQueryResult {
    param (
        [Parameter(Mandatory = $true)]
        [string]$JQL_STRING,
        [Parameter(Mandatory = $false)]
        [switch]$MapFieldNames = $false,
        [Parameter(Mandatory = $false)]
        [string[]]$RETURN_FIELDS,
        [Parameter(Mandatory = $false)]
        [switch]$ClearEmptyFields = $false,
        [Parameter(Mandatory = $false)]
        [switch]$ReturnJSONOnly = $false
    )
    if (! $ReturnJSONOnly) {
        $OUTPUT_DIR = "$($env:OSM_HOME)\$($env:AtlassianPowerKit_PROFILE_NAME)\JIRA"
        $OUTPUT_FILE = "$OUTPUT_DIR\JIRA-Query-Results-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
        if (-not (Test-Path $OUTPUT_DIR)) {
            New-Item -ItemType Directory -Path $OUTPUT_DIR -Force | Out-Null
        }
    }
    $POST_BODY = @{
        jql = "$JQL_STRING"
    }
    # Get total number of results for the JQL query
    $WARNING_LIMIT = 2000
    Write-Debug "Validating JQL query: $JQL_STRING ..."
    $VALIDATE_QUERY = Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/search/approximate-count" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Post -Body ($POST_BODY | ConvertTo-Json) -ContentType 'application/json' -StatusCodeVariable 'scv'
    Write-Debug "Total results for JQL query: $VALIDATE_QUERY"
    $DYN_LIMIT = $VALIDATE_QUERY.count
    if ($DYN_LIMIT -eq 0) {
        Write-Debug 'No results found for the JQL query...'
        return
    } elseif ($DYN_LIMIT -gt $WARNING_LIMIT) {
        # Advise the user that the number of results exceeds $WARNING_LIMIT and ask if they want to continue
        Write-Warning "The number of results for the JQL query exceeds $WARNING_LIMIT. Do you want to continue? [Y/N]"
        $continue = Read-Host
        if ($continue -ne 'Y') {
            Write-Debug 'Exiting...'
            return
        }
    }
    $POST_BODY = @{
        jql        = "$JQL_STRING"
        expand     = 'names'
        maxResults = 250
    }
    if ($RETURN_FIELDS -and $null -ne $RETURN_FIELDS -and $RETURN_FIELDS.Count -gt 0) {
        $POST_BODY.fields = $RETURN_FIELDS
    } else {
        Write-Debug 'RETURN_FIELDS not provided, using default fields...'
        $POST_BODY.fields = @('*all', '-issuelinks', '-subtasks', '-worklog', '-changelog', '-comment')
    }
    Write-Debug 'Getting JQL results via /rest/api/3/search/jql...'
    $NEXT_PAGE = $null
    $COMPLETE = $false
    $ISSUE_ARRAY = @()
    $PAGE_COUNT = 0
    try {
        do {
            $PAGE_COUNT++
            if ($NEXT_PAGE) {
                $POST_BODY.nextPageToken = $NEXT_PAGE
            }
            $REST_RESPONSE = Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/search/jql" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Post -Body $($POST_BODY | ConvertTo-Json -Depth 10) -ContentType 'application/json' -StatusCodeVariable 'scv'
            Write-Debug "REST_RESPONSE received: $($REST_RESPONSE.GetType()), StatusCode: $scv"
            #Write-Debug "REST_RESPONSE: $($REST_RESPONSE | ConvertTo-Json -Depth 10)"
            if ($scv -eq 429) {
                Write-Debug "429 response, waiting $RETRY_AFTER seconds..."
                Start-Sleep -Seconds $RETRY_AFTER
                $COMPLETE = $false
            }
            # elseif rest response contains nextPageToken, set $NEXT_PAGE to nextPageToken and continue
            elseif ($REST_RESPONSE.nextPageToken) {
                Write-Debug "Next page token found: $($REST_RESPONSE.nextPageToken), adding this page to the results..."
                $NEXT_PAGE = $REST_RESPONSE.nextPageToken
                $COMPLETE = $false
            } else {
                $NEXT_PAGE = $null
                $COMPLETE = $true
            }
            #$REST_RESPONSE.issues | ForEach-Object {
            #    Write-Output $_ | ConvertTo-Json -Depth 100 | Out-File -FilePath "$($OUTPUT_FILE)-$($PAGE_COUNT)-stream.json" -Append
            #}
            $ISSUE_ARRAY += $REST_RESPONSE.issues
            Write-Debug "ISSUE_ARRAY Count: $($ISSUE_ARRAY.Count)"
            Write-Debug "$($MyInvocation.MyCommand.Name): End of loop, Collected Issue count: $($ISSUE_ARRAY.Count)...Completed?: $COMPLETE"
        } while (! $COMPLETE)
    } catch {
        Write-Debug 'Error getting jql results with Request details:'
        Write-Debug '##############################################'
        Write-Debug "-Uri https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/search/jql -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Post -Body $($POST_BODY | ConvertTo-Json -Depth 10) "
        Write-Debug ($_ | Select-Object -Property * -ExcludeProperty psobject | Out-String)
        Write-Error "$($MyInvocation.MyCommand.Name): Error getting jql : $($_.Exception.Message)"
        Write-Debug '##############################################'
    }
    Write-Debug "$($MyInvocation.MyCommand.Name): COMPLETED COLLECTION of JQL query results received to ISSUE_ARRAY: $($ISSUE_ARRAY.Count) ... Processing..." 
    if ($ClearEmptyFields -eq $true) {
        Write-Debug 'Cleaning empty fields...'
        $CLEAN_ISSUES = $ISSUE_ARRAY | ForEach-Object {
            $ISSUE = $_
            #Write-Debug "Processing issue: $($ISSUE.key)"
            #$ISSUE | ConvertTo-Json -Depth 100 | Write-Debug
            $FIELDS_ARRAY = $ISSUE.fields
            #Write-Debug "FIELDS ARRAY TYPE IS: $($FIELDS_ARRAY.GetType())'
            #Write-Debug 'FIELD COUNT FOR ISSUE: $($FIELDS_ARRAY.Count)'
            Write-Debug "Cleaning fields for issue: $($ISSUE.key)"
            #Write-Debug "FIELDS_ARRAY: $($FIELDS_ARRAY.GetType())"
            #Write-Debug "FIELDS_ARRAY Count: $($FIELDS_ARRAY.Count)"
            # Replace the fields array with the cleaned fields array in the issue object
            #Write-Debug "Updating Issue.fields using CLEAN_FILED_ARRAY: $($CLEAN_FIELD_ARRAY.GetType())"
            $ISSUE.fields = $(Clear-EmptyFields -JSONString ($FIELDS_ARRAY | ConvertTo-Json -Depth 100)) | ConvertFrom-Json
            return $ISSUE
        }
        # Replace the combined issues array with the cleaned issues array
        $ISSUE_ARRAY = $CLEAN_ISSUES
    }
    if ($ReturnJSONOnly) {
        if ($MapFieldNames) {
            Write-Warning 'MapFieldNames not supported with ReturnJSONOnly, ignoring...'
        }
        Write-Debug 'Returning JSON only...'
        #Write-Debug "########## $($MyInvocation.MyCommand.Name) completed, returning JSON..:"
        #$ISSUE_ARRAY | ConvertTo-Json -Depth 100 | Write-Debug
        #Write-Debug "########## $($MyInvocation.MyCommand.Name) completed, returning JSON ^^^"
        return $($ISSUE_ARRAY | ConvertTo-Json -Depth 100 -Compress)

    } else {
        $ISSUE_ARRAY | ConvertTo-Json -Depth 100 -Compress | Out-File -FilePath $OUTPUT_FILE
        Write-Debug "JIRA COMBINED Query results written to: $OUTPUT_FILE"
        #Write-Debug '########## Get-JiraCloudJQLQueryResult completed, OUTPUT_FILE_LIST: '
        #$OUTPUT_FILE_LIST | Write-Debug
        # Combine raw, compressed JSON files into a single JSON file that is valid JSON
        if ($MapFieldNames) {
            # Get the field mappings from Jira
            Write-Debug "JIRA COMBINED Query results written to: $OUTPUT_FILE"
            $FINAL_FILE = Update-FieldNamesRaw -JSON_FILE_PATH $OUTPUT_FILE
        }
        $RESULT_JSON = @{
            result      = 'success'
            issue_count = $VALIDATE_QUERY.count
            output_file = $FINAL_FILE
            output_dir  = $OUTPUT_DIR
        }
        return $RESULT_JSON | ConvertTo-Json
    }
}


# Function to get change log for a Jira issue
function Get-JiraIssueChangeLog {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Key
    )
    $CHANGE_LOG = Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/issue/$Key/changelog" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get
    #Write-Debug "Change log for issue: $Key"
    #Write-Debug $($CHANGE_LOG | ConvertTo-Json -Depth 10)
    return $CHANGE_LOG

}

# Function to edit a Jira issue field given the issue key, field name, and new value
function Set-JiraIssueField {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ISSUE_KEY,
        [Parameter(Mandatory = $true)]
        [string]$FIELD_REF,
        [Parameter(Mandatory = $true)]
        [array]$NEW_VALUE,
        [Parameter(Mandatory = $false)]
        [string]$FIELD_TYPE = 'text'
    )
    $FIELD_PAYLOAD = @{}
    function Set-MutliSelectPayload {
        @{
            fields = @{
                $Field_Ref = @(
                    $New_Value | ForEach-Object {
                        @{ 'accountId' = "$_" }
                    }
                )
            }
        }
    }
    #$FIELD_PAYLOAD = $FIELD_PAYLOAD | ConvertTo-Json -Depth 10
    Write-Debug "### UPDATING ISSUE: https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/browse/$ISSUE_KEY"
    Write-Debug "Field Type: $FIELD_TYPE"
    switch -regex ($FIELD_TYPE) {
        'custom' { $FIELD_PAYLOAD = $(Set-MutliSelectPayload) }
        'multi-select' { $FIELD_PAYLOAD = $(Set-MutliSelectPayload) }
        'single-select' { $FIELD_PAYLOAD = @{fields = @{"$Field_Ref" = @{value = "$New_Value" } } } }
        'text' { $FIELD_PAYLOAD = @{fields = @{"$Field_Ref" = "$New_Value" } } }
        'null' { $FIELD_PAYLOAD = @{fields = @{"$Field_Ref" = null } } }
        Default { $FIELD_PAYLOAD = @{fields = @{"$Field_Ref" = "$New_Value" } } }
    }
    $REQUEST_URL = "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/2/issue/$($ISSUE_KEY)" 
    # Run the REST API call to update the field with verbose debug output
    Write-Debug "Field Payload: $($FIELD_PAYLOAD | ConvertTo-Json -Depth 10)"
    #Write-Debug "Trying: Invoke-RestMethod -Uri $REQUEST_URL -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Put -Body $FIELD_PAYLOAD -ContentType 'application/json'"
    try {
        $UPDATE_ISSUE_RESPONSE = Invoke-RestMethod -Uri $REQUEST_URL -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Put -Body $($FIELD_PAYLOAD | ConvertTo-Json -Depth 30) -ContentType 'application/json'
    } catch {
        $_ | Select-Object -Property * -ExcludeProperty psobject | Out-String | Write-Debug
        Write-Error "Error updating field: $($_.Exception.Message)"
    }
    return $UPDATE_ISSUE_RESPONSE
}


function Set-StatementOfApplicabilityRefs {
    param (
        [Parameter(Mandatory = $true)]
        [string]$JQL_STRING,
        [Parameter(Mandatory = $true)]
        [hashtable[]]$REF_MAP_HASHTABLE_ARRAY
    )
    # enssure that the hashtable array has at least one element and all elements are hashtable with 4 keys: FIELD_ID, FIELD_NAME, LINK_TYPE, LINK_DIRECTION



    $ISSUES = Get-JiraCloudJQLQueryResult -JQL_STRING $JQL_STRING
    $ISSUES.issues | ForEach-Object {
        $ISSUE = $_
        $ISSUE_KEY = $ISSUE.key
        Write-Debug "Updating fields for issue: $($_.key)"
        Set-JiraIssueField -ISSUE_KEY $ISSUE_KEY -Field_Ref $FIELD_REF -New_Value $NEW_VALUE -FIELD_TYPE $FIELD_TYPE
    }
}

# Function to set-jiraissuefield for a Jira issue field for all issues in JQL query results gibven the JQL query string, field name, and new value
function Set-JiraIssueFieldForJQLQueryResults {
    param (
        [Parameter(Mandatory = $true)]
        [string]$JQL_STRING,
        [Parameter(Mandatory = $true)]
        [string]$FIELD_REF,
        [Parameter(Mandatory = $true)]
        [string]$FIELD_TYPE,
        [Parameter(Mandatory = $true)]
        [string]$NEW_VALUE,
        [Parameter(Mandatory = $false)]
        [Switch]$DryRun = $false

        # [Parameter(Mandatory = $true)]
        # [string]$JSON_TEMPLATE_FILE
    )
    $ISSUES = Get-JiraCloudJQLQueryResult -JQL_STRING $JQL_STRING
    $ISSUES.issues | ForEach-Object {
        $ISSUE = $_
        $ISSUE_KEY = $ISSUE.key
        $ISSUE_SUMMARY = $ISSUE.fields.summary
        Write-Debug "Updating fields for issue: $($_.key - $ISSUE_SUMMARY)"
        if (! $DryRun) {
            Set-JiraIssueField -ISSUE_KEY $ISSUE_KEY -Field_Ref $FIELD_REF -New_Value $NEW_VALUE -FIELD_TYPE $FIELD_TYPE
        } else {
            Write-Debug "Dry Run: Set-JiraIssueField -ISSUE_KEY $ISSUE_KEY -Field_Ref $FIELD_REF -New_Value $NEW_VALUE"
        }
    }
}

function Set-OSMPortalLinkForJQLQueryResults {
    param (
        [Parameter(Mandatory = $false)]
        [string]$JQL_STRING = 'project = GRCosm and issueType not in subTaskIssueTypes()',
        [Parameter(Mandatory = $true)]
        [string]$FIELD_REF,
        [Parameter(Mandatory = $false)]
        [string]$FIELD_TYPE = 'text',
        [Parameter(Mandatory = $false)]
        [string[]]$NEW_VALUE = @('<p><a href="https://auda.atlassian.net/servicedesk/customer/portal/7/GRCOSM-2125" title="smart-link" class="external-link" rel="nofollow noreferrer">https://auda.atlassian.net/servicedesk/customer/portal/7/', '</a> </p></customfieldvalue>'),
        [Parameter(Mandatory = $false)]
        [Switch]$DryRun = $false
    )
    $ISSUES = Get-JiraCloudJQLQueryResult -JQL_STRING $JQL_STRING
    $ISSUES.issues | ForEach-Object {
        $ISSUE = $_
        $ISSUE_KEY = $ISSUE.key
        Write-Debug "Updating fields for issue: $($_.key)"
        if (! $DryRun) {
            Set-JiraIssueField -ISSUE_KEY $ISSUE_KEY -Field_Ref $FIELD_REF -New_Value $NEW_VALUE -FIELD_TYPE $FIELD_TYPE
        } else {
            Write-Debug "Dry Run: Set-JiraIssueField -ISSUE_KEY $ISSUE_KEY -Field_Ref $FIELD_REF -New_Value $NEW_VALUE"
        }
    }
}

function Set-OSMRelationFieldBulkSQL {
    param (
        [Parameter(Mandatory = $true)]
        [string]$JQL_STRING,
        [Parameter(Mandatory = $true)]
        [string]$FieldRef
    )
    
    $ISSUES = Get-JiraCloudJQLQueryResult -JQL_STRING $JQL_STRING -ReturnJSONOnly -RETURN_FIELDS @('key', 'summary')
    $ISSUES = $ISSUES | ConvertFrom-Json
    $ISSUES | ForEach-Object {
        $ISSUE_KEY = $_.key
        $ISSUE_SUMMARY = $_.fields.summary
        Write-Debug "Updating fields for issue: $ISSUE_KEY - $ISSUE_SUMMARY"
        Set-OSMRelationFieldIssueKey -IssueKey $ISSUE_KEY -FieldRef $FieldRef
    }
}

function Set-OSMRelationFieldIssueKey {
    param (
        [Parameter(Mandatory = $true)]
        [string]$IssueKey,
        [Parameter(Mandatory = $true)]
        [string]$FieldRef
    )
    $textInfo = (Get-Culture).TextInfo
    $LINKED_ISSUES_HASHTABLE = @{}
    $ISSUE_LINKS = Get-JiraIssueLinks -IssueKey $IssueKey
    # For each link type, create a nested list of linked issues
    $ISSUE_LINKS | ConvertFrom-Json | ForEach-Object {
        # if the $_ contains an inwardIssue, the linked issue is the inwardIssue, otherwise it is the outwardIssue
        if ($_.inwardIssue) {
            $LINK_TYPE_NAME = $_.type.inward
            $LINKED_ISSUE = $_.inwardIssue.key
        } else {
            $LINK_TYPE_NAME = $_.type.outward
            $LINKED_ISSUE = $_.outwardIssue.key
        }
        $LINK_TYPE_NAME = $textInfo.ToTitleCase($LINK_TYPE_NAME.ToLower())
        Write-Debug "Link Type: $LINK_TYPE_NAME, Linked Issue: $LINKED_ISSUE"
        if ($LINKED_ISSUES_HASHTABLE.ContainsKey($LINK_TYPE_NAME)) {
            $LINKED_ISSUES_HASHTABLE[$LINK_TYPE_NAME] += @("https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/browse/$LINKED_ISSUE")
        } else {
            $LINKED_ISSUES_HASHTABLE[$LINK_TYPE_NAME] = @("https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/browse/$LINKED_ISSUE")
        }
    }
    # Output the linked issues hashtable sorted by link type and convert to JSON
    $JSON_STRING = $LINKED_ISSUES_HASHTABLE | ConvertTo-Json -Depth 10
    Write-Debug "JSON_STRING: $JSON_STRING"
    $MARKDOWN_TEXT = ConvertTo-JSONMarkdownList -JSON_DATA_STRING $JSON_STRING
    Write-Debug "MARKDOWN_TEXT: $MARKDOWN_TEXT"
    #$MARKDOWN_TEXT | Write-Debug
    $UPDATE_RESPONSE = Set-JiraIssueField -ISSUE_KEY $IssueKey -Field_Ref $FieldRef -New_Value $MARKDOWN_TEXT -FIELD_TYPE 'text'
    return $UPDATE_RESPONSE
}

# function to get changes from a Jira issue change log that are from a value to null
function Get-JiraIssueChangeNulls {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [Parameter(Mandatory = $false)]
        [string]$SELECTOR
    )
    $CHECK_MONTHS = -6
    $EXCLUDED_FIELDS = @('Category', 'BCMS: Disaster Recovery Procedures', 'BCMS: Backup Description', 'Incident Contacts', 'Internal / Third Party service', 'BCMS: RPO', 'BCMS: RTO', 'BCMS: MTDP', 'BCMS: MBCO', 'Persistent data stored', 'Monitoring and Alerting', 'SLA/OLA/OKRs', 'Endpoints', 'Service Criticality', 'Service Type', 'Service Status')
    $INCLDUED_VALUES = @($null, '[]', '')
    $CHANGE_LOG = Get-JiraIssueChangeLog -Key $Key
    #$CHANGE_LOG | Get-Member
    if (! $CHANGE_LOG.isLast) {
        Write-Warning 'There are more than 100 changes for this issue. This function only returns the first 100 changes.'
    }
    $ISSUE_LINK = "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/browse/$Key"
    #Write-Debug $($CHANGE_LOG | ConvertTo-Json -Depth 10)
    $NULL_CHANGE_ITEMS = @()
    $FINAL_ITEMS = @()
    $CHANGE_LOG.values | ForEach-Object {
        $MAMMA = $_
        if (!$SELECTOR) {
            $NULL_CHANGE_ITEMS += $MAMMA.items | Where-Object {
                ($MAMMA.created -gt (Get-Date).AddMonths($CHECK_MONTHS)) -and ((-not $_.toString) -and ( -not $_.to)) -and (-not $_.field.StartsWith('BCMS')) -and (-not $EXCLUDED_FIELDS.Contains($_.field))
            }
        } else {
            $NULL_CHANGE_ITEMS += $MAMMA.items | Where-Object {
                (($SELECTOR -eq $($_.fieldId)) -and ($INCLDUED_VALUES.Contains($_.toString)))
                #Write-Debug "Selector: $SELECTOR"
                #Write-Debug "changelog: $($_.fieldId)'
                #Write-Debug 'changelog: $($_.field)'
                #Write-Debug 'changelog: $($_.toString)'
                #Write-Debug 'changelog: $($_.to)'
            }
            
        }
    }
    Write-Debug "Selector: $SELECTOR"
    Write-Debug "Change Nulls identified: $($NULL_CHANGE_ITEMS.count) for issue: $Key"
    if ($NULL_CHANGE_ITEMS) {
        #Write-Debug "Nulled Change log entry items found for issue [$ISSUE_LINK] in $CHECK_MONTHS months --> $($NULL_CHANGE_ITEMS.count) -- ..."
        $NULL_CHANGE_ITEMS | ForEach-Object {
            #Write-Debug "Change log entry item for field: $($_.field) - $($_.fieldId) found for issue [$ISSUE_LINK] in $CHECK_MONTHS months..."
            $_ | Add-Member -MemberType NoteProperty -Name 'issue' -Value $ISSUE_LINK
            $_ | Add-Member -MemberType NoteProperty -Name 'key' -Value $Key
            $_ | Add-Member -MemberType NoteProperty -Name 'id' -Value $MAMMA.id
            $_ | Add-Member -MemberType NoteProperty -Name 'created' -Value $MAMMA.created
            $_ | Add-Member -MemberType NoteProperty -Name 'author' -Value $MAMMA.author.emailAddress
            #Write-Debug $_ | Select-Object -Property * -ExcludeProperty psobject
            $FINAL_ITEMS += $_
            # $FIELD_TYPE = ''
            # $fieldRef = ''
            # switch -regex ($_.field) {
            #     'Service Categories' { $FIELD_TYPE = 'multi-select'; $fieldRef = 'customfield_10316' }
            #     'Sensitivity Classification' { $FIELD_TYPE = 'single-select'; $fieldRef = 'customfield_10275' }
            #     Default { $FIELD_TYPE = 'text' }
            # }
            # Write-Debug "Set-JiraIssueField -ISSUE_KEY $($_.key) -Field_Ref $fieldRef -New_Value $($_.fromString) -FIELD_TYPE $FIELD_TYPE"
        }
    }
    $FINAL_ITEMS
}

# Function to list statuses for a Jira Cloud instance
function Get-JiraStatuses {
    param (
        [Parameter(Mandatory = $false)]
        [switch]$JSONOnly = $false,
        [Parameter(Mandatory = $false)]
        [switch]$GetDuplicates = $false
    )
    $REST_RESULTS = Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/status" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get -ContentType 'application/json'
    function Get-DuplicateJiraStatusNames {
        param (
            [Parameter(Mandatory = $true)]
            [psobject[]]$JIRA_STATUSES,
            [Parameter(Mandatory = $false)]
            [switch]$WriteOutput = $false,
            [Parameter(Mandatory = $false)]
            [int]$Threshold = 3  # Levenshtein distance threshold for considering names as similar
        )

        $JIRA_STATUS_NAMES = @()

        # Initialize the duplicate properties for each status
        $JIRA_STATUSES | ForEach-Object {
            Add-Member -InputObject $_ -MemberType NoteProperty -Name 'duplicate' -Value $false
            Add-Member -InputObject $_ -MemberType NoteProperty -Name 'duplicate_ids' -Value @()
        }

        $JIRA_STATUSES | ForEach-Object {
            $statusName = $_.name
            $statusId = $_.id
            $isDuplicate = $false

            foreach ($existingStatus in $JIRA_STATUS_NAMES) {
                $distance = Get-LevenshteinDistance -s $statusName -t $existingStatus.name
                if ($distance -le $Threshold) {
                    $_.duplicate = $true
                    $_.duplicate_ids += $existingStatus.id
                    $existingStatus.duplicate = $true
                    $existingStatus.duplicate_ids += $statusId
                    $isDuplicate = $true
                    break
                }
            }

            if (-not $isDuplicate) {
                $JIRA_STATUS_NAMES += $_
            }
        }

        if ($WriteOutput) {
            $JIRA_STATUSES | ForEach-Object { Write-Output $_ }
        }
        return $JIRA_STATUSES
    }
    if (! $JSONOnly) {
        $OUTPUT_FILE = "$env:OSM_HOME\$env:AtlassianPowerKit_PROFILE_NAME\JIRA\$env:AtlassianPowerKit_PROFILE_NAME-JIRAStatuses-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
        if (-not (Test-Path $OUTPUT_FILE)) {
            New-Item -ItemType File -Path $OUTPUT_FILE -Force | Out-Null
        }
        $REST_RESULTS | ConvertTo-Json -Depth 100 | Out-File -FilePath $OUTPUT_FILE
        Write-Debug "Jira Statuses written to: $OUTPUT_FILE"
    }
    if ($GetDuplicates) {
        $DUPLICATES = (Get-DuplicateJiraStatusNames -JIRA_STATUSES $REST_RESULTS | Where-Object { $_.duplicate -eq $true } | Sort-Object -Property name)
        Write-Debug "Jira Statuses with duplicates: $($DUPLICATES.Count)"
        $DUPLICATES | ForEach-Object {
            Write-Debug "$($_.name) - $($_.id) - $($_.duplicate) - $($_.duplicate_ids)"
        } | Out-File -FilePath "$env:OSM_HOME\$env:AtlassianPowerKit_PROFILE_NAME\JIRA\$env:AtlassianPowerKit_PROFILE_NAME-JIRAStatusesDuplicates-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
        Write-Debug 'Dulplicate list: '

    }
    return $REST_RESULTS | ConvertTo-Json -Depth 100 -Compress
}

function Get-JiraProjectWorkflowSchemes {
    param (
        [Parameter(Mandatory = $false)]
        [string]$PROJECT_KEY = $false,
        [Parameter(Mandatory = $false)]
        [string]$OUTPUT_DIR = "$env:OSM_HOME\$env:AtlassianPowerKit_PROFILE_NAME\JIRA"
    )
    if ($PROJECT_KEY) {
        $OUTPUT_FILE = "$OUTPUT_DIR\$env:AtlassianPowerKit_PROFILE_NAME-$PROJECT_KEY-JIRAProjectWorkflowSchemes-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
        Write-Debug "Project Key passed: $PROJECT_KEY ... getting project ID..."
        $PROJECT_OBJECT = Get-JiraProjectByKey -PROJECT_KEY $PROJECT_KEY | ConvertFrom-Json -AsHashtable -NoEnumerate
        ConvertTo-Json $PROJECT_OBJECT -Depth 50 | Write-Debug
        if ($PROJECT_OBJECT.id) {
            $PROJECT_ID = $PROJECT_OBJECT.id
        } else {
            Write-Error "Project ID not found for project key: $PROJECT_KEY"
        }
        $URL = "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/workflowscheme/project?projectId=$PROJECT_ID"
    } else {
        Write-Debug 'No project key passed, getting all project workflow schemes...disables'
        # $OUTPUT_FILE = "$OUTPUT_DIR\$env:AtlassianPowerKit_PROFILE_NAME-ALL-JIRAProjectWorkflowSchemes-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
        # $URL = "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/workflowscheme"
    }
    $WORKFLOW_SCHEMES = Invoke-RestMethod -Uri $URL -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get -ContentType 'application/json'
    $WORKFLOW_SCHEMES | ConvertTo-Json -Depth 100 | Out-File -FilePath $OUTPUT_FILE
    Write-Debug "Jira Project Workflow Schemes written to: $OUTPUT_FILE"
    return $WORKFLOW_SCHEMES | ConvertTo-Json -Depth 100 -Compress
}

    

# Get-JiraActiveWorkflows
function Get-JiraActiveWorkflows {
    $WORKFLOW_ENDPOINT = "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/workflow/search?isActive=true&expand=statuses"
    Write-Debug "Workflow Endpoint: $WORKFLOW_ENDPOINT"
    Invoke-RestMethod -Uri $WORKFLOW_ENDPOINT -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get -ContentType 'application/json' -Verbose -Debug
    $WORKFLOWS = Invoke-RestMethod -Uri $WORKFLOW_ENDPOINT -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get -ContentType 'application/json' -Verbose -Debug
    $RESULT_ITEMS = $WORKFLOWS.values

    $DUPLICATE_FIELD_NAMES = Get-DuplicateJiraFieldNames

    $CSV_DATA = @()
    $CSV_DATA += 'Workflow Name, Description, Statuses, Created, Updated, AmbiguousDup'

    $RESULT_ITEMS | ForEach-Object {
        $WORKFLOW = $_
        Write-Debug "Workflow: $($WORKFLOW.id.name)"
        $AMIBIGUOUS_FIELDS = ''
        foreach ($STATUS in $WORKFLOW.statuses) {
            Write-Debug "Status: $($STATUS.name)"
            $AMIBIGUOUS_FIELDS += $DUPLICATE_FIELD_NAMES | Where-Object { $STATUS.name -eq $_ }
        }
        if ($AMIBIGUOUS_FIELDS) {
            $AMIBIGUOUS_FIELDS = $AMIBIGUOUS_FIELDS -join ', '
            $WORKFLOW | Add-Member -MemberType NoteProperty -Name 'AmbiguousDup' -Value $AMIBIGUOUS_FIELDS
        } else {
            $WORKFLOW | Add-Member -MemberType NoteProperty -Name 'AmbiguousDup' -Value 'No'
        }
        $OUTPUT_FILE = "$env:OSM_HOME\$env:AtlassianPowerKit_PROFILE_NAME\JIRA\$env:AtlassianPowerKit_PROFILE_NAME-JIRAWorkflows-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
        if (-not (Test-Path $OUTPUT_FILE)) {
            New-Item -ItemType File -Path $OUTPUT_FILE -Force | Out-Null
        }
        $CSV_DATA += "$($WORKFLOW.id.name), $($WORKFLOW.description), $($WORKFLOW.statuses | ConvertTo-Csv -UseQuotes Never -Delimiter '-' -NoHeader)"
            
    }
    $CSV_DATA | Out-File -FilePath $OUTPUT_FILE
    Write-Debug "Jira Workflows written to: $OUTPUT_FILE"
    return $true
}

function Get-JiraFieldDups {
    $JIRA_FIELDS = Get-JiraFields
    $JIRA_FIELD_NAMES = @()
    $DUPLICATE_FIELD_NAMES = @()
    $JIRA_FIELDS | ForEach-Object {
        if ($JIRA_FIELD_NAMES -contains $_.name) {
            $DUPLICATE_FIELD_NAMES += $_.name
        } else {
            $JIRA_FIELD_NAMES += $_.name
        }
    }
    return $DUPLICATE_FIELD_NAMES
}

# Function to list fields with field ID and field name for a Jira Cloud instance
function Get-JiraFields {
    param (
        [Parameter(Mandatory = $false)]
        [switch]$WriteOutput = $false
    )
    $REST_RESULTS = Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/field" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get -ContentType 'application/json'
    if ($WriteOutput) {
        $OUTPUT_FILE = "$env:OSM_HOME\$env:AtlassianPowerKit_PROFILE_NAME\JIRA\$env:AtlassianPowerKit_PROFILE_NAME-JIRAFields-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
        if (-not (Test-Path $OUTPUT_FILE)) {
            New-Item -ItemType File -Path $OUTPUT_FILE -Force | Out-Null
        }
        $CSV_DATA = @()
        $CSV_DATA += 'Field Name, Field ID, Custom, ClauseName, schema'
        $REST_RESULTS | ForEach-Object {
            $CSV_DATA += "$($_.name), $($_.id), $($_.custom), $($_.clauseNames), $($_.schema)"
        }
        $CSV_DATA | Out-File -FilePath $OUTPUT_FILE
        #$REST_RESULTS | ConvertTo-Json -Depth 10 | Out-File -FilePath $OUTPUT_FILE
        # Write results to a CSV file
        
        Write-Debug "Jira Fields written to: $OUTPUT_FILE"
    }
    return $REST_RESULTS
}

# Function to return list of duplicate Jira Field names
function Get-DuplicateJiraFieldNames {
    $JIRA_FIELDS = Get-JiraFields
    $JIRA_FIELD_NAMES = @()
    $DUPLICATE_FIELD_NAMES = @()
    $JIRA_FIELDS | ForEach-Object {
        if ($JIRA_FIELD_NAMES -contains $_.name) {
            $DUPLICATE_FIELD_NAMES += $_.name
        } else {
            $JIRA_FIELD_NAMES += $_.name
        }
    }
    return $DUPLICATE_FIELD_NAMES
}

# Function to list all users for a JSM cloud project
function Get-JSMServices {
    # https://community.atlassian.com/t5/Jira-Work-Management-Articles/How-to-automatically-populate-service-related-information-stored/ba-p/2240423
    $JSM_SERVICES_ENDPOINT = "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/service-registry-api/service?query="
    try {
        $REST_RESULTS = Invoke-RestMethod -Uri $JSM_SERVICES_ENDPOINT -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get -ContentType 'application/json'
        Write-Debug $REST_RESULTS.getType()
        Write-Debug (ConvertTo-Json $REST_RESULTS -Depth 10)
    } catch {
        Write-Debug ($_ | Select-Object -Property * -ExcludeProperty psobject | Out-String)
        # This functions name is $MyInvocation.MyCommand.Name
        $ERROR_MESSAGE = "Error from $($MyInvocation.MyCommand.Name) - $($_.Exception.Message)"
        Write-Error $ERROR_MESSAGE
    }
}

function Get-JSMService {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ServiceName
    )
    # https://community.atlassian.com/t5/Jira-Work-Management-Articles/How-to-automatically-populate-service-related-information-stored/ba-p/2240423
    $JSM_SERVICES_ENDPOINT = [uri]::EscapeUriString("https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/service-registry-api/service?query=$ServiceName")
    try {
        $REST_RESULTS = Invoke-RestMethod -Uri $JSM_SERVICES_ENDPOINT -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get -ContentType 'application/json'
        Write-Debug $REST_RESULTS.getType()
        Write-Debug (ConvertTo-Json $REST_RESULTS -Depth 10)
    } catch {
        Write-Debug ($_ | Select-Object -Property * -ExcludeProperty psobject | Out-String)
        Write-Error "Error updating field: $($_.Exception.Message)"
    }
}

function Get-JiraProjectByKey {
    param (
        [Parameter(Mandatory = $true)]
        [string]$PROJECT_KEY
    )
    # Check for $($env:OSM_HOME)\$PROFILE_NAME\$PROFILE_NAME-ProjectList-*.json" that was written in past 12 hours and use it to get the project ID, else run Get-JiraProjectList, then try again
    $PROJECT_LIST_FILE = Get-ChildItem -Path "$($env:OSM_HOME)\$env:AtlassianPowerKit_PROFILE_NAME\JIRA" -Filter "$env:AtlassianPowerKit_PROFILE_NAME-ProjectList-*.json" | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1
    While (-not $PROJECT_LIST_FILE) {
        Write-Debug 'No Project List file found, running Get-JiraProjectList...'
        Get-JiraProjectList | Out-Null
        $PROJECT_LIST_FILE = Get-ChildItem -Path "$($env:OSM_HOME)\$env:AtlassianPowerKit_PROFILE_NAME\JIRA" -Filter "$env:AtlassianPowerKit_PROFILE_NAME-ProjectList-*.json" | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1
    }
    $PROJECT = (Get-Content -Path $PROJECT_LIST_FILE.FullName | ConvertFrom-Json -AsHashtable -NoEnumerate) | Where-Object { $_.key -eq $PROJECT_KEY }
    return $PROJECT | ConvertTo-Json -Depth 50 -Compress
}
# Funtion to print the value project properties (JIRA entity)
function Get-JiraProjectList {
    param (
        [Parameter(Mandatory = $false)]
        [string]$OUTPUT_PATH = "$($env:OSM_HOME)\$($env:AtlassianPowerKit_PROFILE_NAME)\JIRA"
    )
    $FILENAME = "$env:AtlassianPowerKit_PROFILE_NAME-ProjectList-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $REST_RESULTS = @()
    $REST_RESPONSE = Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/project/search" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get
    $REST_RESULTS += $REST_RESPONSE.values
    Write-Debug 'Adding first page of projects to results...'
    while (!$REST_RESPONSE.isLast) {
        $REST_RESPONSE = Invoke-RestMethod -Uri $REST_RESPONSE.nextPage -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get
        Write-Debug "Adding next page of projects to results...[$($REST_RESPONSE.startAt) / $($REST_RESPONSE.total)]"
        $REST_RESULTS += $REST_RESPONSE.values
    }
    ConvertTo-Json $REST_RESULTS -Depth 50 | Out-File -FilePath "$OUTPUT_PATH\$FILENAME"
    Write-Debug "Project List JSON file created: $OUTPUT_PATH\$FILENAME"
    return $REST_RESULTS | ConvertTo-Json -Depth 50 -Compress
}
function Get-JiraProjectProperties {
    param (
        [Parameter(Mandatory = $true)]
        [string]$PROJECT_KEY
    )
    $REST_RESULTS = Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/project/$PROJECT_KEY/properties" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get
    $REST_RESULTS | ConvertTo-Json -Depth 100 | Out-File -FilePath "$env:OSM_HOME\$env:AtlassianPowerKit_PROFILE_NAME\JIRA\$env:AtlassianPowerKit_PROFILE_NAME-$PROJECT_KEY-ProjectProperties-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    return $REST_RESULTS | ConvertTo-Json -Depth 100 -Compress
}

# Funtion to print the value of a specific project property (JIRA entity)
function Get-JiraProjectProperty {
    param (
        [Parameter(Mandatory = $true)]
        [string]$PROJECT_KEY,
        [Parameter(Mandatory = $true)]
        [string]$PROPERTY_KEY
    )
    $REST_RESULTS = Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/project/$PROJECT_KEY/properties/$PROPERTY_KEY" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get
    Write-Debug $REST_RESULTS.getType()
    Write-Debug (ConvertTo-Json $REST_RESULTS -Depth 10)
}

# Funtion to put a project property (JIRA entity) - this overwrites!
function Set-JiraProjectProperty {
    param (
        [Parameter(Mandatory = $true)]
        [string]$PROJECT_KEY,
        [Parameter(Mandatory = $true)]
        [string]$PROPERTY_KEY,
        [Parameter(Mandatory = $true)]
        [string]$JSON_FILE
    )
    # If file contains valid JSON, send it to the API else error out
    if (-not (Test-Json -Path $JSON_FILE)) {
        Write-Debug "File not found or invalid JSON: $JSON_FILE"
        return
    }
    try {
        $content = Get-Content $JSON_FILE
        # validate the JSON content
        $content | ConvertFrom-Json | Out-Null
    } catch {
        Write-Debug "File not found or invalid JSON: $JSON_FILE"
        $content | ConvertFrom-Json | Out-Null
        return
    }
    $REST_RESULTS = Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/project/$PROJECT_KEY/properties/$PROPERTY_KEY" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Put -Body $content -ContentType 'application/json'
    Write-Debug $REST_RESULTS.getType()
    # Write all of the $REST_RESULTS to the console as PSObjects with all properties
    Write-Debug (ConvertTo-Json $REST_RESULTS -Depth 10)
    Write-Debug '###############################################'
    Write-Debug "Querying the property to confirm the value was set... $PROPERTY_KEY in $PROJECT_KEY via $($env:AtlassianPowerKit_AtlassianAPIEndpoint)"
    Get-JiraProjectProperty -PROJECT_KEY $PROJECT_KEY -PROPERTY_KEY $PROPERTY_KEY
    Write-Debug '###############################################'
}

function Set-JIRARegisterRefProperty {
    param (
        [Parameter(Mandatory = $true)]
        [string]$PROJECT_KEY,
        [Parameter(Mandatory = $false)]
        [string]$FILTER_ID # For JSON files just use Set-JiraProjectProperty -PROJECT_KEY $PROJECT_KEY -PROPERTY_KEY $PROPERTY_KEY -JSON_FILE $OUTPUT_FILE
    )
    # Get the Register values
    $REGISTER_JSON = Get-JiraCloudJQLQueryResult -JQL_STRING "filter=$FILTER_ID" -RETURN_FIELDS @('summary') -ReturnJSONOnly | ConvertFrom-Json
    # Build a JSON property object with the with id: issue.key and value: issue.fields.summary
    #Write-Debug "Register JSON: $REGISTER_JSON"
    $REGISTER_ARRAY = $REGISTER_JSON | ForEach-Object {
        Write-Debug "Register Object: $_"
        $REGISTER_OBJECT = @{
            'id'   = $_.key
            'name' = $_.fields.summary
        }
        $REGISTER_OBJECT
    }
    Write-Debug "Register Array: $($REGISTER_ARRAY | ConvertTo-Json)"
    $OUTPUT_FILE = "$env:OSM_HOME\$env:AtlassianPowerKit_PROFILE_NAME\JIRA\$env:AtlassianPowerKit_PROFILE_NAME-$PROJECT_KEY-$PROPERTY_KEY-Register-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $REGISTER_ARRAY | ConvertTo-Json -Compress | Out-File -FilePath $OUTPUT_FILE
    Set-JiraProjectProperty -PROJECT_KEY $PROJECT_KEY -PROPERTY_KEY $PROPERTY_KEY -JSON_FILE $OUTPUT_FILE
    #Set-JiraProjectProperty -PROJECT_KEY $PROJECT_KEY -PROPERTY_KEY $PROPERTY_KEY -JSON_FILE (ConvertTo-Json $REGISTER_ARRAY -Depth 10)
}

# Funtion to delete a project property (JIRA entity)
function Clear-JiraProjectProperty {
    param (
        [Parameter(Mandatory = $true)]
        [string]$PROJECT_KEY,
        [Parameter(Mandatory = $true)]
        [string]$PROPERTY_KEY
    )
    $REST_RESULTS = Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/project/$PROJECT_KEY/properties/$PROPERTY_KEY" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Delete
    Write-Debug $REST_RESULTS.getType()
    Write-Debug (ConvertTo-Json $REST_RESULTS -Depth 10)
    Write-Debug '###############################################'
    Write-Debug "Querying the propertues to confirm the value was deleted... $PROPERTY_KEY in $PROJECT_KEY via $($env:AtlassianPowerKit_AtlassianAPIEndpoint)"
    Get-JiraProjectProperties -JiraCloudProjectKey $PROJECT_KEY
    Write-Debug '###############################################'
}

function Get-JIRAFieldContextList {
    param (
        [Parameter(Mandatory = $true)]
        [string]$FIELD_ID
    )
    $REST_RESULTS = Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)//rest/api/3/field/$FIELD_ID/context" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get -ContentType 'application/json'
    #Write-Debug $REST_RESULTS.getType()
    #Write-Debug (ConvertTo-Json $REST_RESULTS -Depth 10)
    return $REST_RESULTS
}

function Get-JIRAFieldContextOptionList {
    param (
        [Parameter(Mandatory = $true)]
        [string]$FIELD_ID,
        [Parameter(Mandatory = $true)]
        [string]$CONTEXT_ID
    
    )
    $REQUEST_RESULTS = $()
    $REST_RESULTS = Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/field/$FIELD_ID/context/$CONTEXT_ID/option" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get -ContentType 'application/json'
    $REQUEST_RESULTS += $REST_RESULTS.values
    while (!$REST_RESULTS.isLast) {
        $nextPageStart = $REST_RESULTS.startAt + $REST_RESULTS.maxResults
        $APPEND_RESULTS = Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/field/$FIELD_ID/context/$CONTEXT_ID/option?startAt=$nextPageStart" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get -ContentType 'application/json'
        $REST_RESULTS.values += $APPEND_RESULTS.values
        $REST_RESULTS.startAt = $APPEND_RESULTS.startAt
        $REST_RESULTS.isLast = $APPEND_RESULTS.isLast
        $REQUEST_RESULTS += $APPEND_RESULTS.values
    }
    $REQUEST_RESULTS | ConvertTo-Json -Depth 50 | Write-Debug
    Write-Debug '^^^^^ Options found: '
    #ENSURE THE $REQUEST_RESULTS is flattened
    return $REQUEST_RESULTS | ConvertTo-Json -Depth 50 -Compress
}

function Set-JIRAFieldContextOptions {
    param (
        [Parameter(Mandatory = $true)]
        [string]$FIELD_ID,
        [Parameter(Mandatory = $true)]
        [string]$CONTEXT_ID,
        [Parameter(Mandatory = $true)]
        [string]$SOURCE_PROPERTIES_URL   
    )
    try {
        $SOURCE_PROPERTIES = Invoke-RestMethod -Uri $SOURCE_PROPERTIES_URL -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get -ContentType 'application/json'
        #Write-Debug $SOURCE_PROPERTIES.getType()
        #Write-Debug (ConvertTo-Json $SOURCE_PROPERTIES -Depth 10)
    } catch {
        Write-Debug ($_ | Select-Object -Property * -ExcludeProperty psobject | Out-String)
        Write-Error "Error updating field: $($_.Exception.Message)"
    }
    
    # Get the current options for the field context
    $EXISTING_OPTIONS = Get-JIRAFieldContextOptionList -FIELD_ID $FIELD_ID -CONTEXT_ID $CONTEXT_ID | ConvertFrom-Json -Depth 10
    # ConvertFrom-Json -Depth 40
    #Write-Debug "Existing Options: $($EXISTING_OPTIONS.values.count)"
    $RET_ARRAY = @()  # Initialize an empty array to store results

    foreach ($HOLDME in $SOURCE_PROPERTIES.value) {
        # Check if the option already exists
        $EXISTING_OPTION = $EXISTING_OPTIONS | Where-Object { $_.value -eq $HOLDME.name }

        if ($EXISTING_OPTION) {
            Write-Debug "Option found: $($HOLDME.name) - Updating it..."
            $EXISTING_OPTION | ConvertTo-Json -Depth 10 | Write-Debug

            # Construct the JSON payload for updating
            $JSON_PAYLOAD = @{
                'id'       = $EXISTING_OPTION.id
                'value'    = $HOLDME.name
                'disabled' = $false
            } | ConvertTo-Json -Depth 10

            $METHOD = 'Put'
        } else {
            Write-Debug "Option not found: $($HOLDME.name) - Adding it..."

            # Construct the JSON payload for adding
            $JSON_PAYLOAD = @{
                'value'    = $HOLDME.name
                'disabled' = $false
            } | ConvertTo-Json -Depth 10

            $METHOD = 'Post'
        }

        # Construct the full payload
        $FULL_PAYLOAD = "{`"options`": [$JSON_PAYLOAD]}"

        # Make the API request
        $REST_RESULTS = Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/field/$FIELD_ID/context/$CONTEXT_ID/option" `
            -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) `
            -Method $METHOD `
            -Body $FULL_PAYLOAD `
            -ContentType 'application/json' `
            -ErrorAction Continue

        # Store the result
        $RET_ARRAY += $REST_RESULTS
    }

    Write-Debug "Options processed for field context: $FIELD_ID - $CONTEXT_ID - ALL DONE!"

    # Return the results as JSON
    return $RET_ARRAY | ConvertTo-Json -Depth 10 -Compress

}
    
# Function to list all users for a JSM cloud project
function Remove-RemoteIssueLink {
    param (
        [Parameter(Mandatory = $true)]
        [string]$JQL_STRING,
        [Parameter(Mandatory = $true)]
        [string]$GLOBAL_LINK_ID
    )
    $GLOBAL_LINK_ID_ENCODED = [System.Web.HttpUtility]::UrlEncode($GLOBAL_LINK_ID)
    Write-Debug "Payload: $GLOBAL_LINK_ID_ENCODE"
    Write-Debug "Global Link ID: $GLOBAL_LINK_ID_ENCODED"

    try {
        $REST_RESULTS = Get-JiraCloudJQLQueryResult -JQL_STRING $JQL_STRING
        $REST_RESULTS.issues | ForEach-Object {
            Write-Debug "Issue Key: $($_.key)"
            Write-Debug "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/issue/$($_.key)/remotelink?globalId=$GLOBAL_LINK_ID_ENCODED"
            Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/issue/$($_.key)/remotelink?globalId=$GLOBAL_LINK_ID_ENCODED" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Delete
        }
    } catch {
        Write-Debug ($_ | Select-Object -Property * -ExcludeProperty psobject | Out-String)
        Write-Error "Error updating field: $($_.Exception.Message)"
    }
}

# Function get available JIRA issue link types
function Get-JiraIssueLinkTypes {
    $REST_RESULTS = Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/issueLinkType" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get
    #Write-Debug $REST_RESULTS.getType()
    #Write-Debug (ConvertTo-Json $REST_RESULTS -Depth 10)
    Write-Debug "Available JIRA Issue Link Types: $($REST_RESULTS.issueLinkTypes.name -join ', ')"
    return $REST_RESULTS
}

# Function to replace / remove JIRA issue links
# Remove  https://developer.atlassian.com/cloud/jira/platform/rest/v2/api-group-issue-links/#api-rest-api-2-issuelink-linkid-delete
# Add https://developer.atlassian.com/cloud/jira/platform/rest/v2/api-group-issue-links/#api-rest-api-2-issuelink-post
function Set-IssueLinkTypeByJQL {
    param (
        [Parameter(Mandatory = $true)]
        [string]$JQL_STRING,
        [Parameter(Mandatory = $false)]
        [string]$CURRNT_LINK_TYPE,
        [Parameter(Mandatory = $true)]
        [string]$NEW_LINK_TYPE_OR_NONE,
        [Parameter(Mandatory = $false)]
        [string]$LINK_DIRECTION_FOR_JQL = 'outward',
        [Parameter(Mandatory = $false)]
        [string]$TARGET_ISSUE_KEY,
        [Parameter(Mandatory = $false)]
        [switch]$force
    )
    $ISSUELINK_ENDPOINT = "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/issueLink"
    # INPUT VALIDATION
    ## PARAMTERS
    ### Issue links for JQL query results can be created, updated or deleted
    #### Where create, required parameters are JQL_STRING, NEW_LINK_TYPE_OR_NONE, LINK_DIRECTION_FOR_JQL and TARGET_ISSUE_KEY
    #### Where updated  or removed, required parameters are JQL_STRING, CURRNT_LINK_TYPE, NEW_LINK_TYPE_OR_NONE
    if ($NEW_LINK_TYPE_OR_NONE -and $JQL_STRING) {
        if ($NEW_LINK_TYPE_OR_NONE -ieq 'None') {
            # JUST REMOVE THE LINK
            Write-Output 'Removing link!'
            # Get link type to remove from user
            if (! $CURRNT_LINK_TYPE) {
                $CURRNT_LINK_TYPE = Read-Host -Prompt 'Please provide the link type to remove'
            }
            Write-Debug "Removing link type: $CURRNT_LINK_TYPE from JQL query results: $JQL_STRING"
            if (! $force) {
                Write-Warning "This will remove all links of type: $CURRNT_LINK_TYPE from the JQL query results: $JQL_STRING"
                $CONFIRM = Read-Host -Prompt 'Are you sure you want to continue? [Y/N]'
                if ($CONFIRM -ne 'Y') {
                    Write-Warning 'Operation cancelled...'
                    return
                } else {
                    Write-Warning 'Proceeding !'
                }
            } else {
                Write-Warning "Force flag set, removing all links of type: $CURRNT_LINK_TYPE from the JQL query results: $JQL_STRING"
            }
        } elseif ((! $CURRNT_LINK_TYPE) -and $NEW_LINK_TYPE_OR_NONE -and $JQL_STRING) {
            #JUST CREATE A NEW LINK
            # Read from user the target issue key (asking for it)
            if (! $TARGET_ISSUE_KEY) {
                $TARGET_ISSUE_KEY = Read-Host -Prompt 'Please provide the target issue key for the link'
            }
            if (! $LINK_DIRECTION_FOR_JQL) {
                $LINK_DIRECTION_FOR_JQL = Read-Host -Prompt 'Please provide the link direction for the JQL query results either inward or outward [inward]'
            }
            if ($LINK_DIRECTION_FOR_JQL -ne 'inward' -and $LINK_DIRECTION_FOR_JQL -ne 'outward') {
                Write-Error "Invalid link direction: $LINK_DIRECTION_FOR_JQL. Please provide either 'inward' or 'outward'"
                return
            }
            Write-Debug "Creating link type: $NEW_LINK_TYPE_OR_NONE from JQL query results: $JQL_STRING to $TARGET_ISSUE_KEY"
        } else {
            Write-Debug "Updating link type: $CURRNT_LINK_TYPE to $NEW_LINK_TYPE_OR_NONE from JQL query results: $JQL_STRING"
        }
    } else {        
        Write-Debug 'Issue links for JQL query results can be created, updated or deleted'
        Write-Debug 'To create a link, required parameters are JQL_STRING, NEW_LINK_TYPE_OR_NONE, LINK_DIRECTION_FOR_JQL and TARGET_ISSUE_KEY'
        Write-Debug 'To update or remove a link, required parameters are JQL_STRING, CURRNT_LINK_TYPE, NEW_LINK_TYPE_OR_NONE'
        Write-Error 'Invalid parameters. Please provide the required parameters for the operation you want to perform.'
        return
    }

    ## LINK TYPE
    $AVAILABLE_LINK_TYPES = Get-JiraIssueLinkTypes
    if ($NEW_LINK_TYPE_OR_NONE -ine 'None') {
        if (! $($AVAILABLE_LINK_TYPES.issueLinkTypes) | Where-Object { $_.name -eq $NEW_LINK_TYPE_OR_NONE }) {
            Write-Error "New link type: $NEW_LINK_TYPE_OR_NONE is not a valid link type. Please use one of the following: $($AVAILABLE_LINK_TYPES.name -join ', '), or 'None' to remove the link."
            return
        }
    }
    ## Check Target Issue Key
    if ($TARGET_ISSUE_KEY) {
        Write-Debug "Checking if target issue key: $TARGET_ISSUE_KEY exists..."
        if (! (Test-JiraIssueExists -KeyOrID $TARGET_ISSUE_KEY)) {
            Write-Error "Target issue key: $TARGET_ISSUE_KEY does not exist. Please provide a valid issue key."
            return
        }
    }

    # FUNCTION to create a new link
    function New-JiraIssueLink {
        param (
            [Parameter(Mandatory = $true)]
            [string]$LINK_TYPE,
            [Parameter(Mandatory = $true)]
            [string]$INWARD_ISSUE_KEY,
            [Parameter(Mandatory = $true)]
            [string]$OUTWARD_ISSUE_KEY
        )
        $PAYLOAD = @{
            type         = @{
                name = $LINK_TYPE
            }
            inwardIssue  = @{
                key = $INWARD_ISSUE_KEY
            }
            outwardIssue = @{
                key = $OUTWARD_ISSUE_KEY
            }
        }
        $LINK_EXISTS = Get-JiraIssueLinks -IssueKey $THIS_ISSUE.key | Where-Object { $_.type.name -eq $NEW_LINK_TYPE_OR_NONE -and $_.inwardIssue.key -eq $INWARD_ISSUE_KEY -and $_.outwardIssue.key -eq $OUTWARD_ISSUE_KEY }
        if (! $LINK_EXISTS) {
            Write-Debug "Creating new link [type = $NEW_LINK_TYPE_OR_NONE] from $INWARD_ISSUE_KEY to $OUTWARD_ISSUE_KEY"
            Invoke-RestMethod -Uri $ISSUELINK_ENDPOINT -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Post -Body ($PAYLOAD | ConvertTo-Json -Depth 10) -ContentType 'application/json'
        } else {
            Write-Debug 'Link already exists... skipping <---------------------------------------'
        }
    }

    function Remove-JiraIssueLink {
        param (
            [Parameter(Mandatory = $true)]
            [string]$LINK_ID
        )
        Write-Debug "Removing link: $LINK_ID"
        try {
            Invoke-RestMethod -Uri "$ISSUELINK_ENDPOINT/$LINK_ID" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Delete -ContentType 'application/json'
        } catch {
            Write-Debug ($_ | Select-Object -Property * -ExcludeProperty psobject | Out-String)
            Write-Error "Error updating field: $($_.Exception.Message)"
        }
        Write-Debug "Link removed: $LINK_ID"
    }
    ### JQL QUERY
    Write-Debug "Runniong JQL Query: $JQL_STRING"
    $REST_RESULTS = Get-JiraCloudJQLQueryResult -JQL_STRING $JQL_STRING -RETURN_FIELDS @('id', 'key')

    $REST_RESULTS.issues | ForEach-Object {
        $THIS_ISSUE = $_
        if ($NEW_LINK_TYPE_OR_NONE -ine 'None') {
            if ($LINK_DIRECTION_FOR_JQL -eq 'inward') {
                $INWARD_ISSUE_KEY = $THIS_ISSUE.key
                $OUTWARD_ISSUE_KEY = $TARGET_ISSUE_KEY
            } else {
                $INWARD_ISSUE_KEY = $TARGET_ISSUE_KEY
                $OUTWARD_ISSUE_KEY = $THIS_ISSUE.key
            }
            New-JiraIssueLink -LINK_TYPE $NEW_LINK_TYPE_OR_NONE -INWARD_ISSUE_KEY $INWARD_ISSUE_KEY -OUTWARD_ISSUE_KEY $OUTWARD_ISSUE_KEY
        }
        if ($CURRNT_LINK_TYPE) {
            # We are updating or removing a link
            $HALF_LINKS = Get-JiraIssueLinks -IssueKey $($THIS_ISSUE.key) | Where-Object { $_.type.name -eq $CURRNT_LINK_TYPE }
            $HALF_LINKS | ForEach-Object {
                $CURRNT_HALF_LINK = $_
                if ($NEW_LINK_TYPE_OR_NONE -ine 'None') {
                    try {
                        # First check if the new link type already exists
                        New-JiraIssueLink -LINK_TYPE $NEW_LINK_TYPE_OR_NONE -INWARD_ISSUE_KEY $INWARD_ISSUE_KEY -OUTWARD_ISSUE_KEY $OUTWARD_ISSUE_KEY
                    } catch {
                        Write-Debug ($_ | Select-Object -Property * -ExcludeProperty psobject | Out-String)
                        Write-Error "Error updating field: $($_.Exception.Message)"
                    }
                } else {
                    Write-Debug "Issue Key: $($THIS_ISSUE.key) - Link Type Name: $($_.type.name), no new link type specified, just removing..."
                }
                # Write-Debug "New was created: $($NEW_LINK | ConvertTo-Json -Depth 10)"
                Write-Debug '#################################################################'
                $CURRNT_LINK_FULL = Invoke-RestMethod -Uri $($CURRNT_HALF_LINK.self) -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get
                Write-Debug "Removing link: $($CURRNT_LINK_FULL.type.name) [$($CURRNT_LINK_FULL.id)] from $($CURRNT_LINK_FULL.inwardIssue.key) to $($CURRNT_LINK_FULL.outwardIssue.key)"
                try {
                    Remove-JiraIssueLink -LINK_ID $($CURRNT_LINK_FULL.id)
                } catch {
                    Write-Debug ($_ | Select-Object -Property * -ExcludeProperty psobject | Out-String)
                    Write-Error "Error updating field: $($_.Exception.Message)"
                }
                Write-Debug "Link removed: [type = $($CURRNT_LINK_FULL.type.name)] from $($CURRNT_LINK_FULL.inwardIssue.key) to $($CURRNT_LINK_FULL.outwardIssue.key)"
                Write-Debug '#################################################################'
            }
        }
    }
}

function Add-FormsFromJQLQueryResults {
    param (
        [Parameter(Mandatory = $true)]
        [string]$JQL_STRING,
        [Parameter(Mandatory = $true)]
        [string]$FORM_ID,
        [Parameter(Mandatory = $false)]
        [switch]$InternalOnlyVisible = $false
    )
    # /{issueIdOrKey}/form
    $COMBINED_ISSUES_JSON = Get-JiraCloudJQLQueryResult -JQL_STRING $JQL_STRING -RETURN_FIELDS @('id', 'key') -ReturnJSONOnly
    $COMBINED_ISSUES = $COMBINED_ISSUES_JSON | ConvertFrom-Json
    Write-Debug "JQL Query results: $($COMBINED_ISSUES.Count)"
    $COMBINED_ISSUES | ForEach-Object {
        $ISSUE = $_
        #https://api.atlassian.com/jira/forms/cloud/{cloudId}/issue/{issueIdOrKey}/form'
        $ISSUE_FORM_ID_URL = "https://api.atlassian.com/jira/forms/cloud/$($env:AtlassianPowerKit_CloudID)/issue/$($ISSUE.key)/form"
        Write-Debug "Attaching form ($FORM_ID) to issue: $($ISSUE.key)"
        Write-Debug "URL: $ISSUE_FORM_ID_URL"
        $PAYLOAD = @{
            formTemplate = @{
                id = $FORM_ID
            }
        }
        $PAYLOAD | ConvertTo-Json -Depth 10 | Write-Debug
        try {
            Invoke-RestMethod -Uri $ISSUE_FORM_ID_URL -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Post -Body ($PAYLOAD | ConvertTo-Json -Depth 10) -ContentType 'application/json'
        } catch {
            Write-Debug "$($MyInvocation.InvocationName) - Failed to attach form ($FORM_ID) to issue: $($ISSUE.key)"
            Write-Debug ($_ | Select-Object -Property * -ExcludeProperty psobject | Out-String)
            Write-Error "Error updating field: $($_.Exception.Message)"
        }
    }
}
function Set-AttachedFormsExternal {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ISSUE_KEY
    )
    # https://api.atlassian.com/jira/forms/cloud/{cloudId}/issue/{issueIdOrKey}/form
    $ISSUE_FORM_ATTACHMENTS_URL = "https://api.atlassian.com/jira/forms/cloud/$($env:AtlassianPowerKit_CloudID)/issue/$ISSUE_KEY/form"
    Write-Debug "Getting attached forms for issue: $ISSUE_KEY"
    Write-Debug "URL: $ISSUE_FORM_ATTACHMENTS_URL"
    $ATTACHED_FORMS = Invoke-RestMethod -Uri $ISSUE_FORM_ATTACHMENTS_URL -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get
    $ATTACHED_FORMS | ForEach-Object {
        $ATTACHED_FORM = $_
        if ($ATTACHED_FORM.internal -eq $true) {
            Write-Debug "Changing form ($($ATTACHED_FORM.id)) to external for issue: $ISSUE_KEY"             
            try {
                #https://api.atlassian.com/jira/forms/cloud/{cloudId}/issue/{issueIdOrKey}/form/{formId}/action/external' \
                Invoke-RestMethod -Uri "$ISSUE_FORM_ATTACHMENTS_URL/$($ATTACHED_FORM.id)/action/external" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Put
            } catch {
                Write-Debug ($_ | Select-Object -Property * -ExcludeProperty psobject | Out-String)
                Write-Error "Error updating field: $($_.Exception.Message)"
            }
        } else {
            Write-Debug "No form found for issue: $($ISSUE.key)"
        }
    }
}
function Set-AttachedFormsExternalJQLQuery {
    param (
        [Parameter(Mandatory = $true)]
        [string]$JQL_STRING
    )
    # /{issueIdOrKey}/form
    $COMBINED_ISSUES_JSON = Get-JiraCloudJQLQueryResult -JQL_STRING $JQL_STRING -RETURN_FIELDS @('id', 'key') -ReturnJSONOnly
    $COMBINED_ISSUES = $COMBINED_ISSUES_JSON | ConvertFrom-Json
    Write-Debug "JQL Query results: $($COMBINED_ISSUES.Count)"
    $COMBINED_ISSUES | ForEach-Object {
        $ISSUE = $_
        Set-AttachedFormsExternal -ISSUE_KEY $ISSUE.key
    }
}
function Get-FormsForJiraProject {
    param (
        [Parameter(Mandatory = $true)]
        [string]$PROJECT_KEY,
        [Parameter(Mandatory = $false)]
        [string]$OUTPUT_PATH = "$($env:OSM_HOME)\$($env:AtlassianPowerKit_PROFILE_NAME)\JIRA"
    )
    $FILENAME = "$env:AtlassianPowerKit_PROFILE_NAME-$PROJECT_KEY-Forms-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $REST_RESULTS = @()
    $REST_RESPONSE = Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/project/search" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get
    $REST_RESULTS += $REST_RESPONSE.values

    Write-Debug 'Adding first page of projects to results...'
    while (!$REST_RESPONSE.isLast) {
        $REST_RESPONSE = Invoke-RestMethod -Uri $REST_RESPONSE.nextPage -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get
        Write-Debug "Adding next page of projects to results...[$($REST_RESPONSE.startAt) / $($REST_RESPONSE.total)]"
        $REST_RESULTS += $REST_RESPONSE.values
    }
    ConvertTo-Json $REST_RESULTS -Depth 50 | Out-File -FilePath "$OUTPUT_PATH\$FILENAME"
    # https://api.atlassian.com/jira/forms/cloud/{cloudId}/project/{projectIdOrKey}/form
    $PROJECT_FORM_ID_URL = "https://api.atlassian.com/jira/forms/cloud/$($env:AtlassianPowerKit_CloudID)/project/$PROJECT_KEY/form"
    $PROJECT_FORM_INDEX = Invoke-RestMethod -Uri $PROJECT_FORM_ID_URL -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get
    $PROJECT_FORM_INDEX | ConvertTo-Json -Depth 30 | Out-File -FilePath "$OUTPUT_PATH\$FILENAME"
    Write-Debug "Project Form Index JSON file created: $OUTPUT_PATH\$FILENAME"
    return $PROJECT_FORM_INDEX | ConvertTo-Json -Depth 50 -Compress

    
}
function Get-FormsForJiraIssue {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ISSUE_KEY
    )
    # https://api.atlassian.com/jira/forms/cloud/{cloudId}/project/{projectIdOrKey}/form
    $ISSUE_FORM_ID_URL = "https://api.atlassian.com/jira/forms/cloud/$($env:AtlassianPowerKit_CloudID)/issue/$ISSUE_KEY/form"
    $REST_RESULTS = Invoke-RestMethod -Uri $ISSUE_FORM_ID_URL -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get
    $REST_RESULTS | ConvertTo-Json -Depth 10 | Write-Debug
}

function Reset-FormsFromJQLQueryResults {
    param (
        [Parameter(Mandatory = $true)]
        [string]$JQL_STRING,
        [Parameter(Mandatory = $true)]
        [string]$FORM_ID
    )
    Write-Debug "Expecting to reset form: $FORM_ID from JQL query results: $JQL_STRING"
    # Get JQL query results
    Remove-FormsFromJQLQueryResults -JQL_STRING $JQL_STRING
}

# Function to remove forms from JQL query results
function Remove-FormsFromJQLQueryResults {
    param (
        [Parameter(Mandatory = $true)]
        [string]$JQL_STRING,
        [Parameter(Mandatory = $false)]
        [switch]$DontReplace = $false
    )
    # /{issueIdOrKey}/form
    $COMBINED_ISSUES_JSON = Get-JiraCloudJQLQueryResult -JQL_STRING $JQL_STRING -RETURN_FIELDS @('id', 'key') -ReturnJSONOnly
    $COMBINED_ISSUES = $COMBINED_ISSUES_JSON | ConvertFrom-Json
    Write-Debug "JQL Query results: $($COMBINED_ISSUES.Count)"
    $COMBINED_ISSUES | ForEach-Object {
        $ISSUE = $_
        $ISSUE_FORM_ID_URL = "https://api.atlassian.com/jira/forms/cloud/$($env:AtlassianPowerKit_CloudID)/issue/$($ISSUE.key)/form"
        $ATTACHED_FORMS = Invoke-RestMethod -Uri "$ISSUE_FORM_ID_URL" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get
        if ($null -eq $ATTACHED_FORMS -or $ATTACHED_FORMS -eq 0) {
            Write-Debug "No form found for issue: $($ISSUE.key)"
        } else {
            Write-Debug "Issue Key: $($ISSUE.key) - ATTACHED_FORMS to remove: "
            Write-Debug "ATTACHED FORMS COUNT: $($ATTACHED_FORMS.Count)"
            $ATTACHED_FORMS | ConvertTo-Json -Depth 10 | Write-Debug
            $ATTACHED_FORMS | ForEach-Object {
                $ATTACHED_FORM = $_
                $FORM_TEMPLATE_ID = $ATTACHED_FORM.formTemplate.id
                Write-Debug "Issue Key: $($ISSUE.key) - Form ID: $($ATTACHED_FORM.id), FORM TEMPLATE ID: $($ATTACHED_FORM.formTemplate.id) - Removing..."
                try {
                    $DELETE_FORM_RESULT = Invoke-RestMethod -Uri "$ISSUE_FORM_ID_URL/$($ATTACHED_FORM.id)" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Delete
                    $DELETE_FORM_RESULT | ConvertTo-Json -Depth 10 | Write-Debug
                    if (! $DontReplace) {
                        $PAYLOAD = @{
                            formTemplate = @{
                                id = $FORM_TEMPLATE_ID
                            }
                        }
                        Write-Debug "Re-attaching form ($FORM_TEMPLATE_ID) to issue: $($ISSUE.key)"
                        Invoke-RestMethod -Uri $ISSUE_FORM_ID_URL -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Post -Body ($PAYLOAD | ConvertTo-Json -Depth 10) -ContentType 'application/json'
                        Set-AttachedFormsExternal -ISSUE_KEY $($ISSUE.key)
                    } else {
                        Write-Debug "Not re-attaching form to issue: $($ISSUE.key)"
                    }
                } catch {
                    Write-Debug ($_ | Select-Object -Property * -ExcludeProperty psobject | Out-String)
                    Write-Error "Error updating field: $($_.Exception.Message)"
                }
            }
        }
    }
}

# Function to list all roles for a JSM cloud project
function Show-JiraCloudJSMProjectRole {
    param (
        [Parameter(Mandatory = $true)]
        [string]$JiraCloudJSMProjectKey
    )
    $JiraProjectRoles = Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/3/project/$JiraCloudJSMProjectKey/role" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get
    Write-Debug $JiraProjectRoles.getType()
    $JiraProjectRoles | Get-Member -MemberType Properties | ForEach-Object {
        Write-Debug "$($_.Name) - $($_.Definition) - ID: $($_.Definition.split('/')[-1])"
    }
}