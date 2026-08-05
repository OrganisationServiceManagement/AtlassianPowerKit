<#
.SYNOPSIS
    Atlassian Cloud PowerShell Module - AtlassianPowerKit-JIRAGRCosmDeploy - module for creating new issue types, workflows, fields, screens, screen schemes, issue type screen schemes, and issue type screen scheme associations using the Atlassian Jira Cloud REST API.See https://developer.atlassian.com/cloud/jira/platform/rest/v3/ for more information.

.DESCRIPTION
    Atlassian Cloud PowerShell Module - AtlassianPowerKit-JIRAGRCosmDeploy
    - Dependencies: AtlassianPowerKit-Shared
        - New-AtlassianAPIEndpoint
    For list of functions and cmdlets, run Get-Command -Module AtlassianPowerKit-JIRAGRCosmDeploy.psm1

.EXAMPLE
    New-JiraIssueType -JiraCloudProjectKey 'OSM' -JiraIssueTypeName 'Test Issue Type' -JiraIssueTypeDescription 'This is a test issue type.' -JiraIssueTypeAvatarId '10000'

.LINK
GitHub: https://github.com/OrganisationServiceManagement/AtlassianPowerKit.git

#>

$ErrorActionPreference = 'Stop'; $DebugPreference = 'Continue'
# Directory of this file 
Import-Module "$env:OSM_INSTALL\AtlassianPowerKit\AtlassianPowerKit-Shared\AtlassianPowerKit-Shared.psd1" -Force
Import-Module "$env:OSM_INSTALL\AtlassianPowerKit\AtlassianPowerKit-Jira\AtlassianPowerKit-Jira.psd1" -Force
$RETRY_AFTER = 10

# Function to create a new Jira Issue Typess
function New-JiraIssueType {
    param (
        [Parameter(Mandatory = $true)]
        [string]$JiraIssueTypeName,
        [Parameter(Mandatory = $true)]
        [string]$JiraIssueTypeDescription,
        [Parameter(Mandatory = $true)]
        [string]$JiraIssueTypeAvatarId,
        [Parameter(Mandatory = $true)]
        [int]$JiraIssueHierarchyLevel,
        [Parameter(Mandatory = $false)]
        [string]$ExistingJiraIssueTypeList = $null
    )
    # First check if the issue type already exists by name
    $ExistingJiraIssueType = $null
    if ( ! $ExistingJiraIssueTypeList ) {
        Write-Debug 'Getting existing Jira Issue Type list as it was not provided...'
        $ExistingJiraIssueTypeList = Invoke-RestMethod -Method Get -Uri "https://$($env:AtlassianPowerKit_ENDPOINT)/rest/api/3/issuetype" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders)
    }
    Write-Debug "Existing Jira Issue Type Count: $($ExistingJiraIssueTypeList.Count)"
    $ExistingJiraIssueType = $ExistingJiraIssueTypeList | ConvertFrom-Json | Where-Object { $_.name -eq "$JiraIssueTypeName" }
    Write-Debug "Existing Jira Issue Type Count [MATCH]: $ExistingJiraIssueType"
    if ($ExistingJiraIssueType) {
        Write-Debug "Issue type $($JiraIssueType.name) already exists. Returning existing issue type."
        # Ensure the ExistingJiraIssueType object is a single object
        if ($ExistingJiraIssueType.Count -gt 1) {
            Write-Warn "Multiple issue types found with the name: $JiraIssueTypeName. Returning the first issue type."
            $ExistingJiraIssueType = $ExistingJiraIssueType[0]
        }
    } else {
        # Create a JSON object for the new issue type using the $JiraIssueType fields: name, description, hierarchyLevel, avatarId (removing the other fields)
        $NewJiraIssueType = @{
            name           = $JiraIssueTypeName
            description    = $JiraIssueTypeDescription
            heirarchyLevel = $JiraIssueHierarchyLevel
        }
        Write-Debug "Creating issue type $($JiraIssueType.name)...: "
        $NewJiraIssueType | ConvertTo-Json -Depth 10 | Write-Debug
        $CreatedJiraIssueType = Invoke-RestMethod -Method Post -Uri "https://$($env:AtlassianPowerKit_ENDPOINT)/rest/api/3/issuetype" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Body $($NewJiraIssueType | ConvertTo-Json -Depth 10) -ContentType 'application/json'
        Write-Debug "Issue type $($CreatedJiraIssueType.name) created."
        # Update the Avatar for the new issue type
        $JiraIssueAvatarUpdateBody = @{
            avatarId = $JiraIssueTypeAvatarId
        }
        $JiraIssueAvatarUpdateBody = $JiraIssueAvatarUpdateBody | ConvertTo-Json -Depth 10
        $CreatedJiraIssueType = Invoke-RestMethod -Method Put -Uri "https://$($env:AtlassianPowerKit_ENDPOINT)/rest/api/3/issuetype/$($CreatedJiraIssueType.id)" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Body $($NewJiraIssueType | ConvertTo-Json -Depth 10) -ContentType 'application/json'
        Write-Debug "Issue type $JiraIssueTypeName avatar updated."
        $ExistingJiraIssueType = $CreatedJiraIssueType
    }
    return $ExistingJiraIssueType | ConvertTo-Json -Depth 100 -Compress
}

function Set-OrgAdminUser {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ORG_ADMIN_USER,
        [Parameter(Mandatory = $false)]
        [string]$ORG_ID,
        [Parameter(Mandatory = $false)]
        [string]$ADMIN_API_KEY = $env:AtlassianPowerKit_AdminAPIKey
    )
    if (-not $ORG_ID) {
        $ORG_ID = Get-AtlassianAdminOrgId -ADMIN_API_KEY $ADMIN_API_KEY
    }

    $ACCOUNT_ID = $ORG_ADMIN_USER
    if ($ORG_ADMIN_USER -match '@') {
        $ORG_ADMIN_ACCOUNT = Get-AtlassianOrganizationUser -EMAIL $ORG_ADMIN_USER -ORG_ID $ORG_ID -ADMIN_API_KEY $ADMIN_API_KEY
        if (-not $ORG_ADMIN_ACCOUNT) {
            throw "Could not resolve account ID for user '$ORG_ADMIN_USER' in organization '$ORG_ID'."
        }
        $ACCOUNT_ID = $ORG_ADMIN_ACCOUNT.accountId
    }

    Invoke-AtlassianAdminAPIRequest -URI "https://api.atlassian.com/admin/v1/orgs/$ORG_ID/users/$ACCOUNT_ID/role-assignments/assign" -METHOD 'Post' -BODY @{ role = 'atlassian/org-admin' } -ADMIN_API_KEY $ADMIN_API_KEY | Out-Null

    return @{
        STATUS     = 'SUCCESS'
        ORG_ID     = $ORG_ID
        ACCOUNT_ID = $ACCOUNT_ID
        ROLE       = 'atlassian/org-admin'
    } | ConvertTo-Json -Depth 10 -Compress

}

# Atlassian Administration APIs require a bearer API key and do not accept the
# Jira-style Basic auth header used elsewhere in this module set.
function Get-AtlassianAdminAPIHeaders {
    param (
        [Parameter(Mandatory = $false)]
        [string]$ADMIN_API_KEY = $env:AtlassianPowerKit_AdminAPIKey
    )

    if ([string]::IsNullOrWhiteSpace($ADMIN_API_KEY)) {
        throw 'Atlassian admin API key not configured. Set $env:AtlassianPowerKit_AdminAPIKey or pass -ADMIN_API_KEY.'
    }

    return @{
        Authorization = "Bearer $ADMIN_API_KEY"
        Accept        = 'application/json'
    }
}

function Invoke-AtlassianAdminAPIRequest {
    param (
        [Parameter(Mandatory = $true)]
        [string]$URI,
        [Parameter(Mandatory = $false)]
        [ValidateSet('Get', 'Post', 'Put', 'Delete')]
        [string]$METHOD = 'Get',
        [Parameter(Mandatory = $false)]
        [object]$BODY,
        [Parameter(Mandatory = $false)]
        [string]$ADMIN_API_KEY = $env:AtlassianPowerKit_AdminAPIKey
    )

    $HEADERS = Get-AtlassianAdminAPIHeaders -ADMIN_API_KEY $ADMIN_API_KEY
    $ATTEMPT = 0
    while ($true) {
        try {
            if ($null -ne $BODY) {
                $JSON_BODY = if ($BODY -is [string]) { $BODY } else { $BODY | ConvertTo-Json -Depth 20 -Compress }
                return Invoke-RestMethod -Uri $URI -Headers $HEADERS -Method $METHOD -Body $JSON_BODY -ContentType 'application/json' -ErrorAction Stop
            }

            return Invoke-RestMethod -Uri $URI -Headers $HEADERS -Method $METHOD -ContentType 'application/json' -ErrorAction Stop
        } catch {
            $STATUS_CODE = $null
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                $STATUS_CODE = [int]$_.Exception.Response.StatusCode
            }

            if ($STATUS_CODE -eq 429 -and $ATTEMPT -lt 2) {
                $ATTEMPT++
                Write-Warn "Atlassian admin API rate limited. Waiting $RETRY_AFTER seconds before retrying."
                Start-Sleep -Seconds $RETRY_AFTER
                continue
            }

            throw
        }
    }
}

function Get-AtlassianAdminOrgId {
    param (
        [Parameter(Mandatory = $false)]
        [string]$ADMIN_API_KEY = $env:AtlassianPowerKit_AdminAPIKey
    )

    $ORG_RESPONSE = Invoke-AtlassianAdminAPIRequest -URI 'https://api.atlassian.com/admin/v1/orgs' -ADMIN_API_KEY $ADMIN_API_KEY
    $ORGS = @($ORG_RESPONSE.data)
    if ($ORGS.Count -eq 0) {
        throw 'No Atlassian organizations were returned for the supplied admin API key.'
    }

    if ($ORGS.Count -gt 1) {
        Write-Warn "Multiple Atlassian organizations were returned. Using the first org ID '$($ORGS[0].id)'."
    }

    return $ORGS[0].id
}

function Get-AtlassianOrganizationUser {
    param (
        [Parameter(Mandatory = $true)]
        [string]$EMAIL,
        [Parameter(Mandatory = $true)]
        [string]$ORG_ID,
        [Parameter(Mandatory = $false)]
        [string]$ADMIN_API_KEY = $env:AtlassianPowerKit_AdminAPIKey
    )

    $SEARCH_TERM = [uri]::EscapeDataString($EMAIL)
    $USER_RESPONSE = Invoke-AtlassianAdminAPIRequest -URI "https://api.atlassian.com/admin/v2/orgs/$ORG_ID/directories/-/users?limit=100&searchTerm=$SEARCH_TERM" -ADMIN_API_KEY $ADMIN_API_KEY
    return @($USER_RESPONSE.data | Where-Object { $_.email -and $_.email.ToLowerInvariant() -eq $EMAIL.ToLowerInvariant() }) | Select-Object -First 1
}

function Get-AtlassianVerifiedDomains {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ORG_ID,
        [Parameter(Mandatory = $false)]
        [string]$ADMIN_API_KEY = $env:AtlassianPowerKit_AdminAPIKey
    )

    $DOMAIN_RESULTS = @()
    $NEXT_URI = "https://api.atlassian.com/admin/v1/orgs/$ORG_ID/domains"
    while ($NEXT_URI) {
        $DOMAIN_RESPONSE = Invoke-AtlassianAdminAPIRequest -URI $NEXT_URI -ADMIN_API_KEY $ADMIN_API_KEY
        if ($DOMAIN_RESPONSE.data) {
            $DOMAIN_RESULTS += $DOMAIN_RESPONSE.data
        }
        $NEXT_URI = $DOMAIN_RESPONSE.links.next
    }

    return $DOMAIN_RESULTS
}

function Test-AtlassianVerifiedEmailDomain {
    param (
        [Parameter(Mandatory = $true)]
        [string]$EMAIL,
        [Parameter(Mandatory = $true)]
        [string]$ORG_ID,
        [Parameter(Mandatory = $false)]
        [string]$ADMIN_API_KEY = $env:AtlassianPowerKit_AdminAPIKey
    )

    $EMAIL_DOMAIN = $EMAIL.Split('@')[-1].ToLowerInvariant()
    $VERIFIED_DOMAIN = Get-AtlassianVerifiedDomains -ORG_ID $ORG_ID -ADMIN_API_KEY $ADMIN_API_KEY | Where-Object {
        $_.attributes -and $_.attributes.name -and $_.attributes.claim -and $_.attributes.claim.status -eq 'verified' -and $_.attributes.name.ToLowerInvariant() -eq $EMAIL_DOMAIN
    } | Select-Object -First 1

    return [bool]$VERIFIED_DOMAIN
}

function Get-AtlassianWorkspaceResourceId {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ORG_ID,
        [Parameter(Mandatory = $false)]
        [string]$WORKSPACE_HOST_URL = $(if ($env:AtlassianPowerKit_ENDPOINT) { "https://$($env:AtlassianPowerKit_ENDPOINT)" } else { $null }),
        [Parameter(Mandatory = $false)]
        [string]$ADMIN_API_KEY = $env:AtlassianPowerKit_AdminAPIKey
    )

    if (-not [string]::IsNullOrWhiteSpace($env:AtlassianPowerKit_CloudID)) {
        return "ari:cloud:jira::site/$($env:AtlassianPowerKit_CloudID)"
    }

    if ([string]::IsNullOrWhiteSpace($WORKSPACE_HOST_URL)) {
        throw 'Workspace host URL could not be determined. Pass -WORKSPACE_HOST_URL or set AtlassianPowerKit_ENDPOINT.'
    }

    $WORKSPACE_RESPONSE = Invoke-AtlassianAdminAPIRequest -URI "https://api.atlassian.com/admin/v2/orgs/$ORG_ID/workspaces" -METHOD 'Post' -BODY @{ limit = 100 } -ADMIN_API_KEY $ADMIN_API_KEY
    $WORKSPACE = @($WORKSPACE_RESPONSE.data | Where-Object { $_.attributes -and $_.attributes.hostUrl -eq $WORKSPACE_HOST_URL }) | Select-Object -First 1
    if (-not $WORKSPACE) {
        throw "Could not resolve a workspace resource ID for host URL '$WORKSPACE_HOST_URL'."
    }

    return $WORKSPACE.id
}

function New-AtlassianEmergencyAdminUser {
    param (
        [Parameter(Mandatory = $true)]
        [string]$EMAIL,
        [Parameter(Mandatory = $false)]
        [string]$ORG_ID,
        [Parameter(Mandatory = $false)]
        [string]$ADMIN_API_KEY = $env:AtlassianPowerKit_AdminAPIKey,
        [Parameter(Mandatory = $false)]
        [string]$WORKSPACE_RESOURCE_ID,
        [Parameter(Mandatory = $false)]
        [string]$WORKSPACE_HOST_URL = $(if ($env:AtlassianPowerKit_ENDPOINT) { "https://$($env:AtlassianPowerKit_ENDPOINT)" } else { $null }),
        [Parameter(Mandatory = $false)]
        [ValidateSet('atlassian/user', 'atlassian/admin', 'atlassian/guest', 'atlassian/customer', 'atlassian/contributor', 'atlassian/basic', 'atlassian/stakeholder', 'atlassian/viewer')]
        [string]$PRODUCT_ROLE = 'atlassian/admin',
        [Parameter(Mandatory = $false)]
        [string[]]$ADDITIONAL_GROUP_IDS = @(),
        [Parameter(Mandatory = $false)]
        [bool]$GRANT_ORG_ADMIN = $true,
        [Parameter(Mandatory = $false)]
        [bool]$SEND_NOTIFICATION = $true,
        [Parameter(Mandatory = $false)]
        [string]$NOTIFICATION_TEXT,
        [Parameter(Mandatory = $false)]
        [switch]$SKIP_PRODUCT_ACCESS
    )

    if (-not $ORG_ID) {
        $ORG_ID = Get-AtlassianAdminOrgId -ADMIN_API_KEY $ADMIN_API_KEY
    }

    $EMAIL_DOMAIN_IS_VERIFIED = Test-AtlassianVerifiedEmailDomain -EMAIL $EMAIL -ORG_ID $ORG_ID -ADMIN_API_KEY $ADMIN_API_KEY
    if ($EMAIL_DOMAIN_IS_VERIFIED) {
        Write-Warn "Email domain '$($EMAIL.Split('@')[-1])' is verified in Atlassian. This account will still follow SSO unless you move it into a non-SSO authentication policy."
    }

    if (-not $SKIP_PRODUCT_ACCESS -and [string]::IsNullOrWhiteSpace($WORKSPACE_RESOURCE_ID)) {
        $WORKSPACE_RESOURCE_ID = Get-AtlassianWorkspaceResourceId -ORG_ID $ORG_ID -WORKSPACE_HOST_URL $WORKSPACE_HOST_URL -ADMIN_API_KEY $ADMIN_API_KEY
    }

    $INVITE_BODY = @{
        emails           = @($EMAIL)
        sendNotification = $SEND_NOTIFICATION
    }

    if (-not $SKIP_PRODUCT_ACCESS) {
        $INVITE_BODY.permissionRules = @(@{
                resource = $WORKSPACE_RESOURCE_ID
                role     = $PRODUCT_ROLE
            })
    }

    if ($ADDITIONAL_GROUP_IDS -and $ADDITIONAL_GROUP_IDS.Count -gt 0) {
        $INVITE_BODY.additionalGroups = $ADDITIONAL_GROUP_IDS
    }

    if (-not [string]::IsNullOrWhiteSpace($NOTIFICATION_TEXT)) {
        $INVITE_BODY.notificationText = $NOTIFICATION_TEXT
    }

    $INVITE_RESPONSE = Invoke-AtlassianAdminAPIRequest -URI "https://api.atlassian.com/admin/v2/orgs/$ORG_ID/users/invite" -METHOD 'Post' -BODY $INVITE_BODY -ADMIN_API_KEY $ADMIN_API_KEY
    $ACCOUNT_ID = $INVITE_RESPONSE.data[0].id

    if ($GRANT_ORG_ADMIN) {
        Set-OrgAdminUser -ORG_ADMIN_USER $ACCOUNT_ID -ORG_ID $ORG_ID -ADMIN_API_KEY $ADMIN_API_KEY | Out-Null
    }

    $LOCAL_AUTH_GUIDANCE = if ($EMAIL_DOMAIN_IS_VERIFIED) {
        'Use a non-SSO authentication policy for this account, or invite an address from an unverified domain, before treating it as a local-auth break-glass account.'
    } else {
        'This email domain is not verified in Atlassian, so the invited user can use native Atlassian authentication after accepting the invite and setting a password.'
    }

    return @{
        STATUS                   = 'SUCCESS'
        ORG_ID                   = $ORG_ID
        EMAIL                    = $EMAIL
        ACCOUNT_ID               = $ACCOUNT_ID
        INVITE_RESPONSE          = $INVITE_RESPONSE.data
        PRODUCT_ACCESS_ASSIGNED  = (-not $SKIP_PRODUCT_ACCESS)
        WORKSPACE_RESOURCE_ID    = $WORKSPACE_RESOURCE_ID
        PRODUCT_ROLE             = if ($SKIP_PRODUCT_ACCESS) { $null } else { $PRODUCT_ROLE }
        ORG_ADMIN_ASSIGNED       = $GRANT_ORG_ADMIN
        VERIFIED_DOMAIN_DETECTED = $EMAIL_DOMAIN_IS_VERIFIED
        LOCAL_AUTH_GUIDANCE      = $LOCAL_AUTH_GUIDANCE
    } | ConvertTo-Json -Depth 20 -Compress

}


# Function to load issue types from a JSON file
function Import-JiraIssueTypes {
    param (
        [Parameter(Mandatory = $true)]
        [string]$JiraIssueTypesJSONFile
    )
    $ExistingJiraIssueTypes = Invoke-RestMethod -Method Get -Uri "https://$($env:AtlassianPowerKit_ENDPOINT)/rest/api/3/issuetype" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) | ConvertTo-Json -Depth 100 -Compress
    $ImportIssueList = Get-Content -Path $JiraIssueTypesJSONFile | ConvertFrom-Json -AsHashtable
    $DeployedIssueTypes = $ImportIssueList | ForEach-Object {
        $NewIssueType = $_
        New-JiraIssueType -JiraIssueTypeName $NewIssueType.name -JiraIssueTypeDescription $NewIssueType.description -JiraIssueTypeAvatarId $NewIssueType.avatarId -JiraIssueHierarchyLevel $NewIssueType.heirarchyLevel -ExistingJiraIssueTypeList $ExistingJiraIssueTypes
    }
    return $DeployedIssueTypes | ConvertFrom-Json -AsHashtable -NoEnumerate | ConvertTo-Json -Depth 100 -Compress
}

# Function to create 
function Test-ExistingConfigJSON {
    param (
        [Parameter(Mandatory = $true)]
        [string]$CONFIG_FILE_PATHPATTERN
    )
    $CONFIG_FILE = Get-ChildItem -Path $CONFIG_FILE_PATHPATTERN | Where-Object { $_.LastWriteTime -gt (Get-Date).AddHours(-12) }
    if ($CONFIG_FILE) {
        $CONFIG_FILE
    } else {
        $null
    }
}
# Returns JSON path that can be loaded with Get-Content $(Import-JSONConfigExport) | ConvertFrom-Json -AsHashtable -NoEnumerate
function Import-JSONConfigExport {
    
    $FULL_CONFIG_OUTPUT_JSONFILE = $null
    # Advise user of the age of the existing JSON export and ask if they want to use it defaulting to 'Yes'
    while (! $FULL_CONFIG_OUTPUT_JSONFILE) {
        $EXISTING_JSON_EXPORT_LIST = Get-ChildItem -Path "$OUTPUT_PATH\FULL-$PROFILE_NAME-*.json" | Sort-Object -Property LastWriteTime -Descending
        if ($EXISTING_JSON_EXPORT_LIST -and $EXISTING_JSON_EXPORT_LIST.Count -gt 0) {
            # If LastWriteTime is less than 12 hours ago, use it
            if ($EXISTING_JSON_EXPORT_LIST[0].LastWriteTime -gt (Get-Date).AddHours(-12)) {
                $LATEST_EXISTING_JSON_EXPORT = $EXISTING_JSON_EXPORT_LIST[0]
                Write-Debug "Fresh, existing JSON export: $($LATEST_EXISTING_JSON_EXPORT.FullName)"
                $FULL_CONFIG_OUTPUT_JSONFILE = $LATEST_EXISTING_JSON_EXPORT.FullName
            }
        } else {
            Write-Debug "$($MyInvocation.MyCommand.Name): Creating new FULL DEPLOYMENT CONFIG json file using: Get-OSMDeploymentConfigsJIRA -PROFILE_NAME $PROFILE_NAME"
            $RAW_CONFIG_JSON = Get-OSMDeploymentConfigsJIRA -PROFILE_NAME $PROFILE_NAME  | ConvertFrom-Json -Depth 100
            $FULL_CONFIG_OUTPUT_JSONFILE = "$OUTPUT_PATH\FULL-$PROFILE_NAME-$(Get-Date -Format 'yyyyMMdd-HHmm').json"
            $RAW_CONFIG_JSON | ConvertTo-Json -Depth 100 | Out-File -FilePath $FULL_CONFIG_OUTPUT_JSONFILE -Force | Out-Null
            Write-Debug "Output written to $FULL_CONFIG_OUTPUT_JSONFILE"
        }
    }
    return $FULL_CONFIG_OUTPUT_JSONFILE
}


# Listing issue Types 
function Get-OSMConfigAsMarkdown {
    param (
        [Parameter(Mandatory = $false)]
        [string]$OUTPUT_PATH = "$($env:OSM_HOME)\$($env:AtlassianPowerKit_PROFILE_NAME)\JIRA",
        [Parameter(Mandatory = $false)]
        [string]$PROFILE_NAME = $env:AtlassianPowerKit_PROFILE_NAME
    )
    $OUTPUT_FILE = "$OUTPUT_PATH\$PROFILE_NAME-OSM-Config_$(Get-Date -Format 'yyyyMMdd-HHmm').md"
    $INPUT_JSON_FILE = Import-JSONConfigExport
    $RAW_CONFIG_JSON = Get-Content -Path "$INPUT_JSON_FILE" -Raw | ConvertFrom-Json -Depth 100
    # Write the markdown file
    $RAW_CONFIG_JSON | ForEach-Object {
        if ($_ -ne $null) {
            $PROJECT_NAME = if ($null -ne $_.PROJECT_NAME) { $_.PROJECT_NAME } else { 'Unknown Project' }
            $PROJECT_KEY = if ($null -ne $_.PROJECT_KEY) { $_.PROJECT_KEY } else { 'Unknown Key' }
            $PROJECT_ISSUE_TYPE_SCHEMA = if ($null -ne $_.PROJECT_ISSUE_TYPE_SCHEMA -and $null -ne $_.PROJECT_ISSUE_TYPE_SCHEMA.self) { $null -ne $_.PROJECT_ISSUE_TYPE_SCHEMA } else { @{ self = '#' } }
            $PROJECT_ISSUE_TYPES = if ($null -ne $_.PROJECT_ISSUE_TYPES) { $_.PROJECT_ISSUE_TYPES } else { @() }
            $PROJECT_REQUEST_TYPES = if ($null -ne $_.PROJECT_REQUEST_TYPES) { $_.PROJECT_REQUEST_TYPES } else { @() }
            $PROJECT_WORKFLOWS_SCHEMES = if ($null -ne $_.PROJECT_WORKFLOWS_SCHEMES) { $_.PROJECT_WORKFLOWS_SCHEMES } else { @() }
            # Write output for project details
            Write-Output "## [$PROJECT_NAME]($($PROJECT_ISSUE_TYPE_SCHEMA.self)) - [Show All Instances](https://$($env:AtlassianPowerKit_ENDPOINT)/jira/servicedesk/projects/$PROJECT_KEY/issues/?jql=project%20%3D%20$PROJECT_KEY)"
            # Write Issue Types
            Write-Output '### Issue Types'
            $PROJECT_ISSUE_TYPES | ForEach-Object {
                if ($_ -ne $null -and $null -ne $_.Name -and $null -ne $_.self) {
                    Write-Output "- [$($_.Name)]($($_.self)) - [Show All Instances](https://$($env:AtlassianPowerKit_ENDPOINT)/jira/servicedesk/projects/$PROJECT_KEY/issues/?jql=project%20%3D%20$PROJECT_KEY%20AND%20issuetype%20%3D%20%22$($_.name.replace(' ','%20'))%22)"
                } else {
                    Write-Output '- Invalid or missing issue type'
                }
            }
            # Write Request Types
            Write-Output '### Request Types'
            $PROJECT_REQUEST_TYPES | ForEach-Object {
                if ($_ -ne $null -and $null -ne $_.Name -and $null -ne $_.self) {
                    Write-Output "- [$($_.Name)]($($_.self)) - [Show All Instances](https://$($env:AtlassianPowerKit_ENDPOINT).atlassian.net/jira/servicedesk/projects/$PROJECT_KEY/issues/?jql=project%20%3D%20$PROJECT_KEY%20AND%20issuetype%20%3D%20%22$($_.name.replace(' ','%20'))%22)"
                } else {
                    Write-Output '- Invalid or missing request type'
                }
            }
            # Write Workflow Schemes
            Write-Output '### Workflow Schemes'
            $PROJECT_WORKFLOWS_SCHEMES | ForEach-Object {
                if ($_ -ne $null -and $null -ne $_.Name -and $null -ne $_.self) {
                    Write-Output "- [$($_.Name)]($($_.self)) - [Show All Instances](https://$($env:AtlassianPowerKit_ENDPOINT).atlassian.net/jira/servicedesk/projects/$PROJECT_KEY/issues/?jql=project%20%3D%20$PROJECT_KEY%20AND%20issuetype%20%3D%20%22$($_.name.replace(' ','%20'))%22)"
                }
            }
        } 
    } | Out-File -FilePath $OUTPUT_FILE -Force
    Write-Debug "Output written to $OUTPUT_FILE"
    $JSON_RETURN = @{ OUTPUT_FILE = $OUTPUT_FILE 
        OUTPUT_PATH               = $OUTPUT_PATH 
        STATUS                    = 'SUCCESS' 
        PROFILE_NAME              = $PROFILE_NAME 
    }

    return $JSON_RETURN | ConvertTo-Json -Depth 100 -Compress
}

function Export-ProjectProformaFormTemplates {
    param (
        [Parameter(Mandatory = $true)]
        [string]$PROJECT_KEY,
        [Parameter(Mandatory = $false)]
        [string]$OUTPUT_PATH = "$($env:OSM_HOME)\$($env:AtlassianPowerKit_PROFILE_NAME)\JIRA"
    )
    Import-Module "$env:OSM_INSTALL\AtlassianPowerKit\AtlassianPowerKit-Jira\AtlassianPowerKit-Jira.psd1" -Force | Out-Null
    $TIME_STAMP = Get-Date -Format 'yyyyMMdd-HHmm'
    $PROFILE_NAME = $env:AtlassianPowerKit_PROFILE_NAME
    $FORMLIST_FILE = "$OUTPUT_PATH\$PROFILE_NAME-$PROJECT_KEY-ProformaFormList-$TIME_STAMP.json"
    # Get List of Forms for the project
    $FORMS_ALL = Get-FormsForJiraProject -PROJECT_KEY $PROJECT_KEY
    $FORM_LIST = $FORMS_ALL | ConvertFrom-Json | Where-Object { $_.name -notcontains 'z_Archive' }
    $FORM_LIST | ConvertTo-Json -Depth 100 | Out-File -FilePath $FORMLIST_FILE -Force | Out-Null
    $FORM_LIST | ForEach-Object {
        $FORM_ID = $_.id
        $FORM_NAME = $_.name
        Write-Debug "======================= Processing Form: $FORM_NAME"
        $FORM_ENDPOINT = "https://$($env:AtlassianPowerKit_ENDPOINT)/rest/proforma/1.0/form/$FORM_ID/schema"
        $REST_RESULTS = Invoke-RestMethod -Uri $FORM_ENDPOINT -Method Get -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders)
        $REST_RESULTS | ConvertTo-Json -Depth 100 | Write-Debug
        exit
        $FORM_TEMPLATE | ConvertTo-Json -Depth 100 | Out-File -FilePath "$OUTPUT_PATH\$PROFILE_NAME-$PROJECT_KEY-$FORM_NAME-FormTemplate-$(Get-Date -Format 'yyyyMMdd-HHmm').json" -Force
    }
    
    $PROFORMA_API_ENDPOINT = "https://$($env:AtlassianPowerKit_ENDPOINT)/rest/proforma/1.0"
    return $OUTPUT_FILE

}

# Function Get Deployment
function Get-OSMDeploymentConfigsJIRA {
    param (
        [Parameter(Mandatory = $false)]
        [string]$PROFILE_NAME = $env:AtlassianPowerKit_PROFILE_NAME,
        [Parameter(Mandatory = $false)]
        [string]$OUTPUT_PATH = "$($env:OSM_HOME)\$PROFILE_NAME\JIRA"
    )
    $OUTPUT_FILE = "$OUTPUT_PATH\FULL-$PROFILE_NAME-$(Get-Date -Format 'yyyyMMdd-HHmm').json"
    Write-Host "Processing profile: $PROFILE_NAME"
    # If there is a env:AtlassianPowerKit_PROFILE_NAME-ProjectList-*.json that was created in the last 12 hours, use it
    $PROFILE_PROJECT_LIST = Test-ExistingConfigJSON -CONFIG_FILE_PATHPATTERN "$($env:OSM_HOME)\$PROFILE_NAME\$PROFILE_NAME-ProjectList-*.json"
    if ($PROFILE_PROJECT_LIST) {
        $PROJECT_LIST = Get-Content $PROFILE_PROJECT_LIST.FullName | ConvertFrom-Json -AsHashtable -NoEnumerate
    } else {
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
        } else {
            $PROFILE_PROJECT_PROPERTIES = AtlassianPowerKit -Profile $PROFILE_NAME -FunctionName 'Get-JiraProjectProperties' -FunctionParameters @{ PROJECT_KEY = $PROJECT_KEY } | ConvertFrom-Json -AsHashtable -NoEnumerate
        }
        # PROJECT_ISSUE_TYPE_SCHEMA
        $PROJECT_ISSUE_TYPE_SCHEMA = Test-ExistingConfigJSON -CONFIG_FILE_PATHPATTERN "$($env:OSM_HOME)\$PROFILE_NAME\$PROFILE_NAME-$PROJECT_KEY-IssueTypeSchema-*.json"
        if ($PROJECT_ISSUE_TYPE_SCHEMA) {
            $PROJECT_ISSUE_TYPE_SCHEMA = Get-Content $PROJECT_ISSUE_TYPE_SCHEMA.FullName | ConvertFrom-Json -AsHashtable -NoEnumerate
        } else {
            $PROJECT_ISSUE_TYPE_SCHEMA = AtlassianPowerKit -Profile $PROFILE_NAME -FunctionName 'Get-JiraCloudIssueTypeSchema' -FunctionParameters @{ PROJECT_KEY = $PROJECT_KEY } | ConvertFrom-Json -AsHashtable -NoEnumerate
        }
        # 
        # PROJECT_ISSUE_TYPES
        $PROJECT_ISSUE_TYPES = Test-ExistingConfigJSON -CONFIG_FILE_PATHPATTERN "$($env:OSM_HOME)\$PROFILE_NAME\$PROFILE_NAME-$PROJECT_KEY-ProjectIssueTypes-*.json"
        if ($PROJECT_ISSUE_TYPES) {
            $PROJECT_ISSUE_TYPES = Get-Content $PROJECT_ISSUE_TYPES.FullName | ConvertFrom-Json -AsHashtable -NoEnumerate
        } else {
            $PROJECT_ISSUE_TYPES = AtlassianPowerKit -Profile $PROFILE_NAME -FunctionName 'Get-JiraProjectIssueTypes' -FunctionParameters @{ PROJECT_KEY_OR_ID = $PROJECT_KEY } | ConvertFrom-Json -AsHashtable -NoEnumerate
        }
        $PROJECT_REQUEST_TYPES = Test-ExistingConfigJSON -CONFIG_FILE_PATHPATTERN "$($env:OSM_HOME)\$PROFILE_NAME\$PROFILE_NAME-$PROJECT_KEY-RequestTypeSchema-*.json"
        if ($PROJECT_REQUEST_TYPES) {
            $PROJECT_REQUEST_TYPES = Get-Content $PROJECT_REQUEST_TYPES.FullName | ConvertFrom-Json -AsHashtable -NoEnumerate
        } else {
            $PROJECT_REQUEST_TYPES = AtlassianPowerKit -Profile $PROFILE_NAME -FunctionName 'Get-JiraServiceDeskRequestTypes' -FunctionParameters @{ PROJECT_KEY = $PROJECT_KEY } | ConvertFrom-Json -AsHashtable -NoEnumerate
        }
        
        # FORMS
        $PROJECT_FORMS = Test-ExistingConfigJSON -CONFIG_FILE_PATHPATTERN "$($env:OSM_HOME)\$PROFILE_NAME\$PROFILE_NAME-$PROJECT_KEY-Forms-*.json"
        if ($PROJECT_FORMS) {
            $PROJECT_FORMS = Get-Content $PROJECT_FORMS.FullName | ConvertFrom-Json -AsHashtable -NoEnumerate
        } else {
            $PROJECT_FORMS = AtlassianPowerKit -Profile $PROFILE_NAME -FunctionName 'Get-FormsForJiraProject' -FunctionParameters @{ PROJECT_KEY = $PROJECT_KEY } | ConvertFrom-Json -AsHashtable -NoEnumerate
        }

        # $FORMS = AtlassianPowerKit -Profile $PROFILE_NAME -FunctionName 'Get-FormsForJiraProject' -FunctionParameters @{ PROJECT_KEY = $PROJECT_KEY }
        # WORKFLOW_SCHEMES
        $PROJECT_WORKFLOWS_SCHEMES = Test-ExistingConfigJSON -CONFIG_FILE_PATHPATTERN "$($env:OSM_HOME)\$PROFILE_NAME\$PROFILE_NAME-$PROJECT_KEY-ProjectWorkflowSchemes-*.json"
        if ($PROJECT_WORKFLOWS_SCHEMES) {
            $PROJECT_WORKFLOWS_SCHEMES = Get-Content $PROJECT_WORKFLOWS_SCHEMES.FullName | ConvertFrom-Json -AsHashtable -NoEnumerate
        } else {
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
    $JIRA_PROJECTS | ConvertTo-Json -Depth 100 -Compress | Out-File -FilePath $OUTPUT_FILE -Force | Out-Null
    return $OUTPUT_FILE
}
    
# Funtion to list project properties (JIRA entities)
function Get-JiraProjectIssueTypes {
    param (
        [Parameter(Mandatory = $true)]
        [string]$PROJECT_KEY_OR_ID,
        [Parameter(Mandatory = $false)]
        [string]$OUTPUT_PATH = "$($env:OSM_HOME)\$($env:AtlassianPowerKit_PROFILE_NAME)\JIRA"
    )
    # If the AtlassianPowerKit-J
    if ($PROJECT_KEY_OR_ID -match '^\d+$') {
        $PROJECT_ID = $PROJECT_KEY_OR_ID
    } else {
        # Get the most recent auda-ProjectList-*.json in the $OUTPUT_PATH or run Get-JiraProjectList and check again for the file
        $PROJECT_LIST_FILE = Get-ChildItem -Path $OUTPUT_PATH -Filter "$env:AtlassianPowerKit_PROFILE_NAME-ProjectList-*.json" | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1
        while (-not $PROJECT_LIST_FILE) {
            Write-Debug 'No Project List file found, running Get-JiraProjectList...'
            Get-JiraProjectList -OUTPUT_PATH $OUTPUT_PATH
            $PROJECT_LIST_FILE = Get-ChildItem -Path $OUTPUT_PATH -Filter "$env:AtlassianPowerKit_PROFILE_NAME-ProjectList-*.json" | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1
        }
        $PROJECT_ID = (Get-Content -Path $PROJECT_LIST_FILE.FullName | ConvertFrom-Json | Where-Object { $_.key -eq $PROJECT_KEY_OR_ID }).id
    }
    $FILENAME = "$env:AtlassianPowerKit_PROFILE_NAME-$PROJECT_KEY_OR_ID-IssueTypes-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    if (-not (Test-Path $OUTPUT_PATH)) {
        New-Item -ItemType Directory -Path $OUTPUT_PATH -Force | Out-Null
    }
    $OUTPUT_FILE = "$OUTPUT_PATH\$FILENAME"
    # Use Get-PaginatedResults to get all issues types for the project
    Write-Debug "Getting Jira Project Issue Types for project: $PROJECT_ID ..."
    $REST_RESULTS = Get-PaginatedJSONResults -URI "https://$($env:AtlassianPowerKit_ENDPOINT)/rest/api/3/issuetype/project?projectId=$PROJECT_ID" -Method Get
    Write-Debug "Jira Project Issue Types for project: $PROJECT_ID received... writing to file..."
    $REST_RESULTS | ConvertTo-Json -Depth 50 | Out-File -FilePath $OUTPUT_FILE
    Write-Debug "Jira Project Issue Types written to: $OUTPUT_FILE"
    return $REST_RESULTS | ConvertTo-Json -Depth 100 -Compress
}

# Function to get issue type metadata for a Jira Cloud project
function Get-JiraCloudIssueTypeMetadata {
    param (
        [Parameter(Mandatory = $true)]
        [string]$PROJECT_KEY,
        [Parameter(Mandatory = $false)]
        [string]$OUTPUT_PATH = "$($env:OSM_HOME)\$($env:AtlassianPowerKit_PROFILE_NAME)\JIRA"
    )
    $FILENAME = "$env:AtlassianPowerKit_PROFILE_NAME-$PROJECT_KEY-IssueTypeMetadata-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $REST_RESULTS = Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_ENDPOINT)/rest/api/3/issue/createmeta/$PROJECT_KEY&expand=projects.issuetypes.fields" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get
    ConvertTo-Json $REST_RESULTS -Depth 50 | Out-File -FilePath "$OUTPUT_PATH\$FILENAME"
    Write-Debug "Issue Type Metadata JSON file created: $OUTPUT_PATH\$FILENAME"
    return $REST_RESULTS
}

# Fuction to get Issue Type schema for a Jira Cloud project
function Get-JiraCloudIssueTypeSchema {
    param (
        [Parameter(Mandatory = $true)]
        [string]$PROJECT_KEY_OR_ID,
        [Parameter(Mandatory = $false)]
        [string]$OUTPUT_PATH = "$($env:OSM_HOME)\$($env:AtlassianPowerKit_PROFILE_NAME)\JIRA"
    )
    # if the project key is passed, get the project ID (key is Alpha-numeric, ID is numeric)
    if ($PROJECT_KEY_OR_ID -match '^\d+$') {
        Write-Debug "Project ID passed: $PROJECT_KEY_OR_ID"
        $PROJECT_ID = $PROJECT_KEY_OR_ID
        $PROJECT_KEY = (Get-JiraProjectByKey -PROJECT_KEY $PROJECT_KEY_OR_ID | ConvertFrom-Json -AsHashtable -NoEnumerate).key
    } else {
        Write-Debug "Project Key passed: $PROJECT_KEY_OR_ID ... getting project ID..."
        $PROJECT_OBJECT = Get-JiraProjectByKey -PROJECT_KEY $PROJECT_KEY_OR_ID | ConvertFrom-Json -AsHashtable -NoEnumerate
        #ConvertTo-Json $PROJECT_OBJECT -Depth 50 | Write-Debug
        if ($PROJECT_OBJECT.id) {
            $PROJECT_ID = $PROJECT_OBJECT.id
        } else {
            Write-Error "Project ID not found for project key: $PROJECT_KEY_OR_ID"
        }
    }
    $FILENAME = "$env:AtlassianPowerKit_PROFILE_NAME-$PROJECT_KEY-IssueTypeSchema-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $REST_RESULTS = Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_ENDPOINT)/rest/api/3/issuetypescheme/project?projectId=$PROJECT_ID" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get
    ConvertTo-Json $REST_RESULTS -Depth 50 | Out-File -FilePath "$OUTPUT_PATH\$FILENAME"
    Write-Debug "Issue Type Schema JSON file created: $OUTPUT_PATH\$FILENAME"
    return $REST_RESULTS.values | ConvertTo-Json -Depth 50 -Compress
}

function Get-FilterJQL {
    param (
        [Parameter(Mandatory = $true)]
        [string]$FILTER_ID
    )
    # While response code is 429, wait and try again
    try {
        $REST_RESPONSE = Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_ENDPOINT)/rest/api/3/filter/$($FILTER_ID)" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get -ContentType 'application/json'
    } catch {
        # Catch 429 errors and wait for the retry-after time
        if ($_.Exception.Response.StatusCode -eq 429) {
            Write-Warn "429 error, waiting for $RETRY_AFTER seconds..."
            Start-Sleep -Seconds $RETRY_AFTER
            $REST_RESPONSE = Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_ENDPOINT)/rest/api/3/filter/$($FILTER_ID)" -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get -ContentType 'application/json'
        } else {
            Write-Debug "$($MyInvocation.MyCommand.Name): Error getting filter JQL: $($_.Exception.Message)'
            Write-Error 'Error getting filter JQL: $($_.Exception.Message)"
        }
    }
    return $REST_RESPONSE.jql
}

function Get-JiraOSMFilterList {
    param (
        [Parameter(Mandatory = $false)]
        [string[]]$PROJECT_KEYS = @('GRCOSM')
    )
    $FILTERS_SEARCH_URL = "https://$($env:AtlassianPowerKit_ENDPOINT)/rest/api/3/filter/search"
    $PROJECT_LIST = Get-JiraProjectList | ConvertFrom-Json
    # Get Project ID project with key GRCOSM
    Write-Debug "Getting filters for projects: $($PROJECT_KEYS -join ', ')"
    #$SEARCH_TERMS_FOR_FILTERS = @(
    #    @{ 'Name' = 'filterName'; 'Value' = 'osm' })
    $PROJECT_ID_SEARCHES = $PROJECT_KEYS | ForEach-Object {
        $PROJECT_KEY = $_
        $PROJECT_ID = $PROJECT_LIST | Where-Object { $_.key -eq $PROJECT_KEY } | Select-Object -ExpandProperty id
        if ($PROJECT_ID) {
            return @{ 
                'ProjectID'  = $PROJECT_ID
                'ProjectKey' = $PROJECT_KEY
            }
        }
    }
    $SEARCH_TERMS_FOR_FILTERS = $PROJECT_ID_SEARCHES
    # Write-Debug 'Searching for filters with search terms: '
    # $SEARCH_TERMS_FOR_FILTERS | ConvertTo-Json -Depth 100 | Write-Debug
    # Write-Debug 'Attempting to get results using Get-PaginatedJSONResults...'
    $FILTER_RESULTS = $SEARCH_TERMS_FOR_FILTERS | ForEach-Object {
        Write-Debug "Getting filters for project ID: $($_.ProjectID)..."
        $ONE_FILTER_SEARCH_URL = "$FILTERS_SEARCH_URL" + '?projectId=' + $_.PrjectID + '&expand=owner'
        Get-PaginatedJSONResults -URI $ONE_FILTER_SEARCH_URL -METHOD Get -RESPONSE_JSON_OBJECT_FILTER_KEY 'values' | ConvertFrom-Json -AsHashtable  
        Write-Debug "Done getting filters for project ID: $($_.ProjectID)."
        Write-Debug 'Total Filter results so far: ' + $FILTER_RESULTS.Count
    }
    Write-Debug 'Filter results received... processing...'
    $i = 1
    $FILTER_RESULTS = $FILTER_RESULTS | Group-Object id | ForEach-Object { $_.Group | Select-Object -First 1 }
    $FILTER_RESULTS | ForEach-Object {
        $FILTER_ID = $_.id
        $FILTER_NAME = $_.name
        $FILTER_JQL = "'" + $(Get-FilterJQL -FILTER_ID $FILTER_ID) + "'"
        Write-Debug "Filter in parsed results [$i]: $FILTER_NAME - $FILTER_ID - $FILTER_JQL"
        $i++
    }
    $FILTER_RESULTS_JSON = $FILTER_RESULTS | ConvertTo-Json -Depth 50 -Compress
    return $FILTER_RESULTS_JSON
}
