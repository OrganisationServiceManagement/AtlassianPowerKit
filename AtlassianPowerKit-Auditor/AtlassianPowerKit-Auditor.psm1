$ErrorActionPreference = 'Stop'; $DebugPreference = 'Continue'
<#
.SYNOPSIS
    Atlassian Cloud Audit Log Module.

.LINK
GitHub: https://github.com/OrganisationServiceManagement/AtlassianPowerKit
https://support.atlassian.com/security-and-access-policies/docs/audit-log-activities-database/

#>
class AuditLogE {
    [string] $FILE_NAME
    [string] $VIEW_URL
    [string] $DOWNLOAD_URL
    [string] $UNIQUE_ID
    [string] $EMBED_URL
    [string] $LOCAL_ID
    [string] $MACRO_ID
    [string] $CONFLUENCE_PARENT
    [string[]] $LABELS
    
    # Shared initializer method
    [void] Init([hashtable]$Properties) {
        foreach ($Property in $Properties.Keys) {
            $this.$Property = $Properties.$Property
        }
    }
    # Constructors
    ConfluenceMetadataObject() { $this.Init(@{}) }
    ConfluenceMetadataObject([hashtable]$Properties) {
        $this.Init($Properties)
    }
    # Contructor with named parameters
    ConfluenceMetadataObject([string]$FILE_NAME, [string]$VIEW_URL, [string]$DOWNLOAD_URL, [string]$UNIQUE_ID, [string]$EMBED_URL, [string]$LOCAL_ID, [string]$MACRO_ID, [string]$CONFLUENCE_PARENT, [string[]]$LABELS) {
        $this.Init(@{
                FILE_NAME         = $FILE_NAME
                VIEW_URL          = $VIEW_URL
                DOWNLOAD_URL      = $DOWNLOAD_URL
                UNIQUE_ID         = $UNIQUE_ID
                EMBED_URL         = $EMBED_URL
                LOCAL_ID          = $LOCAL_ID
                MACRO_ID          = $MACRO_ID
                CONFLUENCE_PARENT = $CONFLUENCE_PARENT
                LABELS            = $LABELS
            })
    }
}

function Get-AuditLogActionList {
    $AUDIT_LOG_ENDPOINT = 'https://api.atlassian.com/admin/v1/orgs/$'
    $AUDIT_LOG_ACTIONS = $AUDIT_LOG | Select-String -Pattern 'action":".*?"' -AllMatches | ForEach-Object { $_.Matches.Value } | Sort-Object -Unique
    Write-Debug "AUDIT_LOG_ACTIONS: $($AUDIT_LOG_ACTIONS)"
    return $AUDIT_LOG_ACTIONS
}

function Get-OrgID {
    $ORG_LIST_ENDPOINT = 'https://api.atlassian.com/admin/v1/orgs'
    Invoke-RestMethod -Uri $ORG_LIST_ENDPOINT -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get -ContentType 'application/json'
    return $ORG_ID
}

function Update-GRCosmConfRegister {
    param (
        [Parameter(Mandatory = $true)]
        [string]$CONFLUENCE_SPACE_KEY,
        [Parameter(Mandatory = $true)]
        [string]$CONF_PAGE_ID,
        [Parameter(Mandatory = $true)]
        [string]$FILTER_ID,
        [Parameter(Mandatory = $true)]
        [string]$REGISTER_STORAGE_TEMPLATE_PATH,
        [Parameter(Mandatory = $false)]
        [string]$TEMPLATE_PLACEHOLDER_MAP
    )
    if (-not $TEMPLATE_PLACEHOLDER_MAP) {
        $TEMPLATE_PLACEHOLDER_MAP = @{
            'GRCOSM_REGISTER_TABLE_DATA' = 'Get-JiraFilterResultsAsConfluenceTable -FILTER_ID $FILTER_ID'
        }
    }
    # Check template file exists
    if (-not (Test-Path $REGISTER_STORAGE_TEMPLATE_PATH)) {
        Write-Error "Update-GRCosmConfRegister: Template file not found: $REGISTER_STORAGE_TEMPLATE_PATH"
    }
    # Backup the Confluence page storage format
    $BACKUP_FILE = Export-ConfluencePageStorageFormat -CONFLUENCE_SPACE_KEY $CONFLUENCE_SPACE_KEY -CONFLUENCE_PAGE_ID $CONF_PAGE_ID
    Write-Debug "Backup file: $BACKUP_FILE"

    # Split $BACKUP_FILE on _ and drop the last element
    $BACKUP_FILE_BASE = $($BACKUP_FILE -split '_2')[0]

    # Get JIRA filter data - Fields are determined by the JIRA filter
    # Write-Debug '############################################################################################'
    Write-Debug 'Update-GRCosmConfRegister: Getting JIRA filter results as Confluence table...'
    $CONF_REGISTER_TABLE_DATA = Get-JiraFilterResultsAsConfluenceTable -FILTER_ID $FILTER_ID
    Write-Debug 'Update-GRCosmConfRegister: Jira filter results as Confluence table returned'
    # Write-Debug "Type: $($CONF_REGISTER_TABLE_DATA.GetType())'
    # Write-Debug 'Length: $($CONF_REGISTER_TABLE_DATA.Length)'
    # Write-Debug 'Content: `n $($CONF_REGISTER_TABLE_DATA)"
    Write-Debug 'Update-GRCosmConfRegister: Getting Confluence template data...'
    # ([string]::join("",$CONTENT.Split("`n").Trim()))
    $UPDATED_PAGE_STORAGE_DATA = Get-Content $REGISTER_STORAGE_TEMPLATE_PATH -Raw
    Write-Debug 'Update-GRCosmConfRegister: Confluence template data returned'
    # Write-Debug "Type: $($UPDATED_PAGE_STORAGE_DATA.GetType())'
    # Write-Debug 'Length: $($UPDATED_PAGE_STORAGE_DATA.Length)'
    # Write-Debug 'Content: `n $($UPDATED_PAGE_STORAGE_DATA)"
    Write-Debug 'Update-GRCosmConfRegister: Replacing GRCOSM_REGISTER_TABLE_DATA PLA with JIRA filter results...'
    $UPDATED_PAGE_STORAGE_DATA = $UPDATED_PAGE_STORAGE_DATA -replace 'GRCOSM_REGISTER_TABLE_DATA', $CONF_REGISTER_TABLE_DATA 
    Write-Debug 'Update-GRCosmConfRegister: GRCOSM_REGISTER_TABLE_DATA replaced'
    Write-Debug "Type: $($UPDATED_PAGE_STORAGE_DATA.GetType())"
    Write-Debug '############################  STORAGE FORMAT TO SEND ################################################'
    $UPDATED_PAGE_STORAGE_DATA | Out-File "$BASTORAGE FORMAT TO SEND ################################################ `n `n `n"
    Write-Debug "$BACKUP_FILE_BASE-LATEST.xml"
    Set-ConfluencePageContent -CONFLUENCE_SPACE_KEY $CONFLUENCE_SPACE_KEY -CONFLUENCE_PAGE_ID $CONF_PAGE_ID -CONFLUENCE_PAGE_STORAGE_FILE "$BACKUP_FILE_BASE-LATEST.xml"

}

function Get-OSMPlaceholdersJira {
    param (
        [Parameter(Mandatory = $true)]
        [string]$PATH_TO_STORAGE_EXPORTS,
        [Parameter(Mandatory = $false)]
        [array]$PATTERNS_TO_FIND
    )
    if (-not $PATTERNS_TO_FIND) {
        $PATTERNS_TO_FIND = @('&lt;&lt;.*?&gt;&gt;', 'zoak-osm.([^\s,]+)', '([^\s,]+)to(.*)be(.*)replaced([^\s,]+)')
        Write-Debug "No pattern provided, using default: $PATTERNS_TO_FIND"
    }
    Write-Debug "Checking path $PATH_TO_STORAGE_EXPORTS for files..."
    # Check if the directory exists and contains files
    if (-not (Test-Path $PATH_TO_STORAGE_EXPORTS)) {
        Write-Debug "Directory does not exist or is empty: $PATH_TO_STORAGE_EXPORTS"
        return
    }
    # For each file in the directory, get the content and extract the placeholders
    $PLACEHOLDERS = @()
    $CLEAN_FILES = @()
    Get-ChildItem -Path $PATH_TO_STORAGE_EXPORTS -Recurse -Filter *.json | ForEach-Object {
        $FILE = $_
        $content = Get-Content $FILE.FullName
        $PATTERNS_TO_FIND | ForEach-Object {
            $placeholder = $content | Select-String -Pattern $_ -AllMatches | ForEach-Object { $_.Matches.Value } | Sort-Object -Unique
            Write-Debug '++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++'
            if ($placeholder) {
                $placeholder | ForEach-Object { 
                    # Write output in red
                    Write-Output "#### PLACEHOLDER FOUND!!! See: $($FILE.FullName): $_"
                    $PLACEHOLDERS += , ($($FILE.NAME), $_) }
            } else {
                Write-Debug "No placeholders found in file: $($FILE.FullName)"
                $CLEAN_FILES += $FILE
            }
            Write-Debug '++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++'
        }
    }
    Write-Debug '++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++'
    Write-Debug '++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++'
    Write-Debug 'CLEAN FILES:'
    $CLEAN_FILES | ForEach-Object { Write-Debug $_.FullName }
    Write-Debug '++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++'
    Write-Debug '++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++'
    Write-Debug 'FULL LIST:'
    $PLACEHOLDERS | ForEach-Object { Write-Debug "$($_[0]): $($_[1])" }
    Write-Debug '++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++'
    Write-Debug '++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++'
}

function Get-OSMPlaceholdersConfluence {
    param (
        [Parameter(Mandatory = $true)]
        [string]$PATH_TO_STORAGE_EXPORTS,
        [Parameter(Mandatory = $false)]
        [array]$PATTERNS_TO_FIND
    )
    if (-not $PATTERNS_TO_FIND) {
        $PATTERNS_TO_FIND = @('&lt;&lt;.*?&gt;&gt;', 'zoak-osm.([^\s,]+)', '([^\s,]+)to(.*)be(.*)replaced([^\s,]+)')
        Write-Debug "No pattern provided, using default: $PATTERNS_TO_FIND"
    }
    Write-Debug "Checking path $PATH_TO_STORAGE_EXPORTS for files..."
    # Check if the directory exists and contains files
    if (-not (Test-Path $PATH_TO_STORAGE_EXPORTS)) {
        Write-Debug "Directory does not exist or is empty: $PATH_TO_STORAGE_EXPORTS"
        return
    }
    # For each file in the directory, get the content and extract the placeholders
    Write-Debug "Getting placeholders from files in: $($(Get-ChildItem -Recurse -Path $PATH_TO_STORAGE_EXPORTS -Filter *.xml ).FullName)"
    $PLACEHOLDERS = @()
    $CLEAN_FILES = @()
    Get-ChildItem -Path $PATH_TO_STORAGE_EXPORTS -Recurse -Filter *.xml | ForEach-Object {
        $FILE = $_
        $content = Get-Content $FILE.FullName
        $PATTERNS_TO_FIND | ForEach-Object {
            $placeholder = $content | Select-String -Pattern $_ -AllMatches | ForEach-Object { $_.Matches.Value } | Sort-Object -Unique
            if ($_ -eq '&lt;&lt;.*?&gt;&gt;') {
                if ($placeholder) {
                    $placeholder_ref = $placeholder | ForEach-Object { $_ -replace '&lt;&lt;', 'PLACEHOLDER_' -replace '&gt;&gt;', ' ' }
                    $placeholder = "$placeholder_ref ($placeholder)"
                }
            }
            Write-Debug '++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++'
            if ($placeholder) {
                $placeholder | ForEach-Object { 
                    # Write output in red
                    Write-Output "#### PLACEHOLDER FOUND!!! See: $($FILE.FullName): $_"
                    $PLACEHOLDERS += , ($($FILE.NAME), $_) }
            } else {
                Write-Debug "No placeholders found in file: $($FILE.FullName)"
                $CLEAN_FILES += $FILE
            }
            Write-Debug '++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++'
        }
    }
    Write-Debug '++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++'
    Write-Debug '++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++'
    Write-Debug 'CLEAN FILES:'
    $CLEAN_FILES | ForEach-Object { Write-Debug $_.FullName }
    Write-Debug '++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++'
    Write-Debug '++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++'
    Write-Debug 'FULL LIST:'
    $PLACEHOLDERS | ForEach-Object { Write-Debug "$($_[0]): $($_[1])" }
    Write-Debug '++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++'
    Write-Debug '++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++'
}



function Get-UserActivitiesSince {
    param (
        [Parameter(Mandatory = $true)]
        [string]$USERNAME,
        [Parameter(Mandatory = $false)]
        [datetime]$SINCE = (Get-Date).AddMonths(-1),
        [Parameter(Mandatory = $false)]
        [datetime]$UNTIL = (Get-Date),
        [Parameter(Mandatory = $false)]
        [array]$PRODUCTS = @('jira', 'confluence')
    )
    Write-Debug "Getting activities for user: $USERNAME since $SINCE until $UNTIL for products: $PRODUCTS"
    if (-not $PRODUCTS -or $PRODUCTS.Count -eq 0) {
        Write-Warning 'No products specified, returning empty result.'
        return @()
    }
    $ORG_ID = Get-OrgID
    $ACTIVITIES = @()
    foreach ($PRODUCT in $PRODUCTS) {
        $ACTIVITY_ENDPOINT = "https://api.atlassian.com/admin/v1/orgs/$ORG_ID/auditlog/$PRODUCT/activities?filter=actor eq '$USERNAME' and createdDate ge '$($SINCE.ToString('o'))' and createdDate le '$($UNTIL.ToString('o'))'&limit=1000"
        Write-Debug "Activity endpoint: $ACTIVITY_ENDPOINT"
        $PAGE = 1
        do {
            Write-Debug "Getting page $PAGE of activities for product: $PRODUCT"
            $RESPONSE = Invoke-RestMethod -Uri $ACTIVITY_ENDPOINT -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get -ContentType 'application/json'
            if ($RESPONSE.values) {
                $ACTIVITIES += $RESPONSE.values
            }
            $ACTIVITY_ENDPOINT = $RESPONSE._links.next.href
            $PAGE++
        } while ($ACTIVITY_ENDPOINT)
    }
    return $ACTIVITIES
}
# ...existing code...

function Get-UserActivityConfluenceSpace {
    <#
      Queries activity for the authenticated user (API key owner) across one or more Confluence spaces.
      - Accepts multiple space keys via -SpaceKeys
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('SpaceKey')]                       # backward compatibility
        [string[]]$SpaceKeys,
        [datetime]$Since = (Get-Date).ToUniversalTime().AddDays(-30),
        [datetime]$Until = (Get-Date).ToUniversalTime(),
        [int]$MaxPage = 100,
        [int]$LimitPerSpace = 500,
        [string]$OutFile
    )
    if (-not $env:AtlassianPowerKit_AtlassianAPIHeaders) { throw 'API headers not initialized.' }
    if (-not $env:AtlassianPowerKit_ENDPOINT) { throw 'Endpoint env var not set.' }
    $headers = ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders
    $base = $env:AtlassianPowerKit_ENDPOINT

    $sinceIso = $Since.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    $untilIso = $Until.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")

    $all = [System.Collections.Generic.List[object]]::new()

    foreach ($space in $SpaceKeys) {
        $cql = "space=$space AND lastmodified >= $sinceIso AND lastmodified <= $untilIso AND (creator = currentUser() OR contributor = currentUser())"
        $enc = [System.Web.HttpUtility]::UrlEncode($cql)
        $start = 0
        $collectedForSpace = 0
        while ($true) {
            if ($collectedForSpace -ge $LimitPerSpace) { break }
            $remain = $LimitPerSpace - $collectedForSpace
            $pageSize = [Math]::Min($MaxPage, $remain)
            $url = "https://$base/wiki/rest/api/search?cql=$enc&limit=$pageSize&start=$start&expand=content.version,content.history.lastUpdated,content.history.createdBy"
            $resp = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -ErrorAction Stop
            if (-not $resp.results) { break }
            foreach ($r in $resp.results) {
                $c = $r.content
                $all.Add([pscustomobject]@{
                        Source          = 'Confluence'
                        SpaceKey        = $space
                        ContentId       = $c.id
                        Type            = $c.type
                        Title           = $c.title
                        Version         = $c.version.number
                        LastUpdatedUtc  = ($c.history.lastUpdated.when | Get-Date).ToUniversalTime()
                        LastUpdatedById = $c.history.lastUpdated.by.accountId
                        CreatedById     = $c.history.createdBy.accountId
                        Link            = "https://$base/wiki$($c._links.webui)"
                    })
            }
            $got = $resp.results.Count
            $collectedForSpace += $got
            if ($got -lt $pageSize) { break }
            $start += $got
        }
    }

    if ($OutFile) {
        $ext = [IO.Path]::GetExtension($OutFile).ToLower()
        if ($ext -eq '.csv') {
            $all | Export-Csv -Path $OutFile -NoTypeInformation -Encoding UTF8
        } else {
            $all | ConvertTo-Json -Depth 6 | Out-File -FilePath $OutFile -Encoding UTF8
        }
    }
    return $all
}

function Get-UserActivityJiraProject {
    <#
      Queries issues the authenticated user touched (reporter/assignee) across multiple Jira projects.
      - Accepts multiple project keys via -ProjectKeys
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('ProjectKey')]
        [string[]]$ProjectKeys,
        [datetime]$Since = (Get-Date).ToUniversalTime().AddDays(-30),
        [datetime]$Until = (Get-Date).ToUniversalTime(),
        [int]$MaxPerPage = 100,
        [int]$Limit = 1000,              # total issues across all projects
        [switch]$IncludeChangelog,
        [string]$OutFile
    )
    if (-not $env:AtlassianPowerKit_AtlassianAPIHeaders) { throw 'API headers not initialized.' }
    if (-not $env:AtlassianPowerKit_ENDPOINT) { throw 'Endpoint env var not set.' }
    $headers = ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders
    $base = $env:AtlassianPowerKit_ENDPOINT

    $me = Invoke-RestMethod -Uri "https://$base/rest/api/3/myself" -Headers $headers -Method Get -ErrorAction Stop
    $acctId = $me.accountId

    $sinceStr = $Since.ToUniversalTime().ToString('yyyy/MM/dd HH:mm')
    $projClause = '(' + ($ProjectKeys | ForEach-Object { "project = `"$($_)`"" }) -join ' OR ' + ')'
    $userClause = "(reporter = $acctId OR assignee = $acctId)"
    $jql = "$projClause AND updated >= `"$sinceStr`" AND $userClause ORDER BY updated DESC"
    $enc = [System.Web.HttpUtility]::UrlEncode($jql)

    $expand = if ($IncludeChangelog) { 'changelog' } else { '' }
    $startAt = 0
    $issues = [System.Collections.Generic.List[object]]::new()

    while ($true) {
        if ($issues.Count -ge $Limit) { break }
        $remain = $Limit - $issues.Count
        $pageSize = [Math]::Min($MaxPerPage, $remain)
        $url = "https://$base/rest/api/3/search?jql=$enc&startAt=$startAt&maxResults=$pageSize&fields=summary,project,issuetype,updated,created,reporter,assignee,status&expand=$expand"
        $resp = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -ErrorAction Stop
        if (-not $resp.issues) { break }
        foreach ($i in $resp.issues) {
            $updated = (Get-Date $i.fields.updated).ToUniversalTime()
            if ($updated -gt $Until.ToUniversalTime()) { continue }
            $issues.Add([pscustomobject]@{
                    Source     = 'Jira'
                    Key        = $i.key
                    Project    = $i.fields.project.key
                    IssueType  = $i.fields.issuetype.name
                    Summary    = $i.fields.summary
                    Status     = $i.fields.status.name
                    ReporterId = $i.fields.reporter.accountId
                    AssigneeId = $i.fields.assignee.accountId
                    UpdatedUtc = $updated
                    CreatedUtc = (Get-Date $i.fields.created).ToUniversalTime()
                    BrowseLink = "https://$base/browse/$($i.key)"
                    Changelog  = if ($IncludeChangelog) { $i.changelog } else { $null }
                })
        }
        $got = $resp.issues.Count
        if ($got -lt $pageSize) { break }
        $startAt += $got
    }

    if ($OutFile) {
        $ext = [IO.Path]::GetExtension($OutFile).ToLower()
        if ($ext -eq '.csv') {
            $issues | Select-Object Source, Key, Project, IssueType, Summary, Status, ReporterId, AssigneeId, UpdatedUtc, CreatedUtc, BrowseLink |
            Export-Csv -Path $OutFile -NoTypeInformation -Encoding UTF8
        } else {
            $issues | ConvertTo-Json -Depth 8 | Out-File -FilePath $OutFile -Encoding UTF8
        }
    }
    return $issues
}

# ...existing code...
# ...existing code...

### SHAREPOINT FUNCTIONS
# # Function to generate SharePoint - Confluence object mapping
# function New-SharePointConfluenceObjectMapping {
#     param (
#         [Parameter(Mandatory = $false)]
#         [string]$PATH_TO_OUTPUT = "$env:AtlassianPowerKit_PROFILE_NAME\AtlasianPowerKit-GRCosm\$env:AtlassianPowerKit_PROFILE_NAME-config.json",
#         [Parameter(Mandatory = $true)]
#         [string]$TenantName,
#         [Parameter(Mandatory = $true)]
#         [string]$SiteName,
#         [Parameter(Mandatory = $true)]
#         [string]$FOLDER_NAME,
#         [Parameter(Mandatory = $true)]
#         [string]$CANDIDATE_FILE_PATTERN
#     )
#     # Find all files in the SharePoint folder that match the CANDIDATE_FILE_PATTERN, then call Get-SharePointFileMetadata to get the metadata for each file
#     $SHAREPOINT_FILES = Get-SharePointFileMetadata -TenantName $TenantName -SiteName $SiteName -FOLDER_PATH_OR_NAME $FOLDER_NAME -SOURCE_FILENAME $CANDIDATE_FILE_PATTERN
# }
# Authenticate to MS Graph using interactive login, scope is for listing SharePoint documents and retrieving the unique identifier
# function Connect-MgGraphScoped {
#     param(
#         [Parameter(Mandatory = $true)]
#         [string[]] $RequiredScopes,
#         [Parameter(Mandatory = $true)]
#         [string] $TenantName,
#         [Parameter(Mandatory = $false)]
#         [switch] $ReAuth = $false
#     )
#     # Get the current context
#     $context = Get-MgContext
#     # Check if the context and its scopes are not null
#     if (($null -ne $context) -and ($null -ne $context.Scopes) -and (-not $ReAuth)) {
#         # Check if the context's scopes include all the required scopes
#         $hasRequiredScopes = ($RequiredScopes | ForEach-Object { $context.Scopes -contains $_ } | Where-Object { $_ -eq $false } | Measure-Object | Select-Object -ExpandProperty Count) -eq 0
#         if (-not $hasRequiredScopes) {
#             # If the context doesn't have all the required scopes, authenticate again
#             Disconnect-MgGraph -ErrorAction SilentlyContinue
#             Connect-MgGraph -Scopes $RequiredScopes -TenantId $TenantName -NoWelcome
#         }
#     }
#     else {
#         # If there's no context or its scopes are null, authenticate
#         Connect-MgGraph -Scopes $RequiredScopes -TenantId $TenantName
#     }
#     Get-MgContext
# }
# function Get-SharePointFileMetadata {
#     param (
#         [Parameter(Mandatory = $true)]
#         [string]$TenantName,
#         [Parameter(Mandatory = $true)]
#         [string]$SiteName,
#         [Parameter(Mandatory = $true)]
#         [string]$FOLDER_PATH_OR_NAME,
#         [Parameter(Mandatory = $false)]
#         [string]$SOURCE_FILENAME,
#         [Parameter(Mandatory = $false)]
#         [string]$REGEX_MULTI_SEARCH = $false
#     )
#     [ConfluenceMetadataObject[]] $CONFLUENCE_METADATA_OBJECTS = @()
#     # Declare FILE_ITEMS as an array of objects
#     [object[]] $FILE_ITEMS = @()
#     $SiteWebUrl = "https://$TenantName.sharepoint.com/sites/$SiteName"
#     Connect-MgGraphScoped -RequiredScopes $MS_GRAPH_SCOPES -TenantName $TenantName
#     # Get the site ID by the site name
#     $Site = Get-MgSite -Search "$SiteWebUrl"
#     # Display all sites and their properties
#     $SiteId = $Site.Id
#     if (-not $SiteId) {
#         Write-Error "Site not found: $SiteName"
#     }
#     else {
#         Write-Debug "SiteId: $SiteId (SiteName: $SiteName)"
#     }
#     # Check if the site exists
#     $Site = Get-MgSite -SiteId $SiteId
#     # Ensure the necessary Microsoft Graph connection
#     $Drive = Get-MgSiteDrive -SiteId $SiteId
#     # Validate the $Drive.DriveType = 'documentLibrary'
#     $DriveId = $Drive.Id
#     if (-not $DriveId) {
#         Write-Error "Drive not found: $DriveId"
#     }
#     else {
#         Write-Debug "DriveId: $DriveId"
#     }
#     #Encode the folder name
#     # Get the string after the last '/' in the folder path (if there are any '/'s)
#     $FOLDER_NAME = $FOLDER_PATH_OR_NAME.Split('/')[-1]
#     Write-Debug "Folder Name: $FOLDER_NAME"
#     $folder = Search-MgDrive -DriveId $DriveId -Q $FOLDER_NAME | Where-Object { $_.Name -eq $FOLDER_NAME }
#     Write-Debug 'Folder found: '
#     Write-Debug $folder.ToJson($null, 'IncludeAll')
#     # If more than one folder is found, select the first one
#     if ($folder.Count -gt 1) {
#         Write-Debug 'Folders found: '
#         $folder | ForEach-Object { Write-Debug "Folder: $($_.Name), ID: $($_.Id), WebUrl: $($_.WebUrl)" }
#         Write-Warning 'More than one folder found. Selecting the first one.'
#         $folder = $folder[0]
#     }
#     # Check if the folder exists
#     if ($null -eq $folder) {
#         Write-Error 'Folder not found.'
#         return
#     }
#     else {
#         Write-Debug "Folder: $($folder.Name), ID: $($folder.Id), WebUrl: $($folder.WebUrl)"
#     }
#     if ($REGEX_MULTI_SEARCH) {
#         Write-Debug "Searching for files with search string: $SOURCE_FILENAME and regex: $REGEX_MULTI_SEARCH"
#         $FILE_ITEMS = Search-MgDriveItem -DriveId $DriveId -DriveItemId $folder.Id -Q $SOURCE_FILENAME | Where-Object { $_.Name -match $REGEX_MULTI_SEARCH }
#         Write-Debug "File Items: $($file_items.Count)"
#         if ($($file_items.Count) -eq 0) {
#             Write-Error "No files found: $SOURCE_FILENAME with regex: $REGEX_MULTI_SEARCH"
#         }
#     }
#     else {
#         $FILE_ITEMS = Search-MgDriveItem -DriveId $DriveId -DriveItemId $folder.Id -Q $SOURCE_FILENAME | Where-Object { $_.Name.EndsWith($SOURCE_FILENAME) }
#         Write-Debug "File Items: $($file_items.Count)"
#         if ($($file_items.Count) -eq 0) {
#             Write-Debug 'Query: Search-MgDriveItem -DriveId $DriveId -DriveItemId $($folder.Id) -Q $SOURCE_FILENAME -Property name, Id, File.... | Where-Object { $_.Name -match $SOURCE_FILENAME }'
#             Write-Error 'No files found: $SOURCE_FILENAME'
#         }
#         elseif ($($file_items.Count) -gt 1) {
#             Write-Warning "More than one file found: $($file_items.Count)"
#             Write-Debug 'Query: Search-MgDriveItem -DriveId $DriveId -DriveItemId $($folder.Id) -Q $SOURCE_FILENAME -Property name, Id, File, .... | Where-Object { $_.Name -match $SOURCE_FILENAME }'
#             $file_items | ForEach-Object { Write-Debug '##############################################'; Write-Debug $($_.ToJSON($null, 'IncludeAll')); Write-Debug '##############################################' }
#             Write-Debug 'Defaulting to the first file'
#             $FILE_ITEM = $file_items[0]
#         }
#     }
#     $FILE_ITEMS | ForEach-Object {
#         $FILE_ITEM = Get-MgDriveItem -DriveId $DriveId -DriveItemId $($_.Id)
#         $CONFLUENCE_METADATA_OBJECTS += [ConfluenceMetadataObject]::new(@{
#                 FILE_NAME    = $($FILE_ITEM.Name)
#                 VIEW_URL     = $($FILE_ITEM.WebUrl)
#                 DOWNLOAD_URL = $($($FILE_ITEM)['@microsoft.graph.downloadUrl'])
#                 UNIQUE_ID    = $DOWNLOAD_URL.Split('UniqueId=')[1].Split('&')[0]
#                 EMBED_URL    = "https://$TenantName.sharepoint.com/sites/$SiteName/_layouts/15/embed.aspx?UniqueId=$UNIQUE_ID"
#                 LOCAL_ID     = $AC_LOCAL_ID
#                 MACRO_ID     = $AC_MACRO_ID
#             })
#         # Write-Debug $CONFLUENCE_METADATA_OBJECT
#         # $actualPath = $FILE_ITEM.ParentReference.Path -replace '^.*root:', ''
#         # $fullPath = Join-Path -Path $actualPath -ChildPath $FILE_ITEM.Name
#         # $FILE_ITEM_PATH = Join-Path -Path "sites/$SiteName/Shared Documents/" -ChildPath $fullPath
#         # $FILE_ITEM_PATH.GetType()
#         # Write-Debug $FILE_ITEM_PATH
#     }
#     return $CONFLUENCE_METADATA_OBJECTS
# }
#Install-AtlassianPowerKitGRCosmDependencies
# if ($ReAuth) {
#     if (!$TenantName) {
#         $TenantName = Read-Host -Prompt 'Enter the Tenant Name'
#     }
#     Connect-MgGraphScoped -RequiredScopes $MS_GRAPH_SCOPES -TenantName $TenantName
#}
# # Function to create Confluence Page in Storage Format based on template, for viewing SharePoint Document (embedded in Confluence)
# function New-ConfluencePolicyViewerSharePoint {
#     param (
#         [Parameter(Mandatory = $false)]
#         [string]$PATH_TO_TEMPLATE = 'templates\confluence\GRCosm-SharePointViewer-Template.confluence',
#         [Parameter(Mandatory = $true)]
#         [string]$CONFLUENCE_PARENT,
#         [Parameter(Mandatory = $true)]
#         [ConfluenceMetadataObject]$CONFLUENCE_METADATA_OBJECT,
#         [Parameter(Mandatory = $false)]
#         [string]$PATH_TO_OUTPUT = "$env:AtlassianPowerKit_PROFILE_NAME\snapshots\confluence\latest\"
#     )
#     # Read the template
#     try {
#         $TEMPLATE = Get-Content $PATH_TO_TEMPLATE
#     }
#     catch {
#         Write-Error "Error reading template: $PATH_TO_TEMPLATE"
#     }
#     # Add CONFULENCE_PARENT to ConfluenceMetadataObject
#     $CONFLUENCE_METADATA_OBJECT.CONFLUENCE_PARENT = $CONFLUENCE_PARENT
#     # Check for null values in ConfluenceMetadataObject Properties
#     $CONFLUENCE_METADATA_OBJECT | Get-Member -MemberType Properties | ForEach-Object {
#         $property = $_.Name
#         $value = $CONFLUENCE_METADATA_OBJECT.$property
#         if (-not $value) {
#             Write-Error "Property $property is null"
#         }
#         Write-Debug "$property : $value"
#     }
#     # Create variable for the basename of the file from the ConfluenceMetadataObject.FILE_NAME, remove the file extension ensuring handling filename with multiple '.'s, throw error if number of characters removed is not 2-5 characters
#     $BASENAME = $CONFLUENCE_METADATA_OBJECT.FILE_NAME -replace '\.[^.]*$', ''
#     $CHARS_REMOVED = $CONFLUENCE_METADATA_OBJECT.FILE_NAME.Length - $BASENAME.Length
#     if ($CHARS_REMOVED -lt 2 -or $CHARS_REMOVED -gt 5) {
#         Write-Debug "BASENAME from FILE_NAME: $CONFLUENCE_METADATA_OBJECT.FILE_NAME"
#         Write-Warning "Extension removed was abnormal, check FILE_NAME: $CONFLUENCE_METADATA_OBJECT.FILE_NAME"
#     }
#     # Create array of placeholders in the template which can be identified by pattern: '{{ .*? }}'
#     $PLACEHOLDERS = $TEMPLATE | Select-String -Pattern '{{ .*? }}' -AllMatches | ForEach-Object { $_.Matches.Value } | Sort-Object -Unique
#     Write-Debug "PLACEHOLDERS: $($PLACEHOLDERS)"
#     # If there are PLACEHOLDERS that are not defined in the ConfluenceMetadataObject, throw an error
#     $PLACEHOLDERS | ForEach-Object {
#         $placeholder = $_
#         $value = $CONFLUENCE_METADATA_OBJECT.$($_ -replace '{{ ', '' -replace ' }}', '')
#         if (-not $value) {
#             Write-Error "Placeholder $placeholder is not defined in ConfluenceMetadataObject"
#         }
#     }
#     # Replace the placeholders in the template with the values from the ConfluenceMetadataObject
#     $TEMPLATE_INPUT_ARRAY = $TEMPLATE | ForEach-Object {
#         $line = $_
#         $PLACEHOLDERS | ForEach-Object {
#             $placeholder = $_
#             $value = $CONFLUENCE_METADATA_OBJECT.$($_ -replace '{{ ', '' -replace ' }}', '')
#             $line = $line -replace $placeholder, $value
#         }
#         $line
#     }
#     # Write the output to a file and console as debug and advise user of the file location
#     $OUTPUT_FILE = "$PATH_TO_OUTPUT\$($CONFLUENCE_METADATA_OBJECT.FILE_NAME).confluence"
#     # Write the TEMPLATE_INPUT_ARRAY to the OUTPUT_FILE, create the directory if it does not exist and overwrite the file if it does
#     $TEMPLATE_INPUT_ARRAY | Set-Content -Path $OUTPUT_FILE -Force
# }