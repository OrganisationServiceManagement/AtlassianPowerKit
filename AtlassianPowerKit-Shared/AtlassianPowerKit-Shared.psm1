<#
.SYNOPSIS
    Atlassian Cloud PowerShell Module - Shared - for shared functions to interact with Attlassian Cloud APIs.

.DESCRIPTION
    Atlassian Cloud PowerShell Module - Shared
    - Dependencies: None
    - Shared Module Functions
        - Get-AtlassianAPIEndpoint
        - Get-OpsgenieAPIEndpoint
        - Clear-AtlassianPowerKitGlobalVariables
    - To list all functions in this module, run: `Get-Command -Module AtlassianPowerKit-Shared`
    - Debug output is enabled by default. To disable, set $DisableDebug = $true before running functions.

.EXAMPLE
    Get-AtlassianAPIEndpoint

    This example checks if the Jira Cloud API endpoint, username, and authentication token are defined, printing the values if they are, else advise to run New-AtlassianAPIEndpoint.

.EXAMPLE
    Get-OpsgenieAPIEndpoint

    This example checks if the Opsgenie API endpoint and authentication token are defined, printing the values if they are, else advise to run New-OpsgenieAPIEndpoint.

.EXAMPLE
    Clear-AtlassianPowerKitGlobalVariables

    This example clears all global variables where names start with 'PK_'.

.LINK
GitHub: https://github.com/markz0r/AtlassianPowerKit

#>

$ErrorActionPreference = 'Stop'; $DebugPreference = 'Continue'
$RETRY_AFTER = 60

function Clear-AtlassianPowerKitProfile {
    # Clear all environment variables starting with AtlassianPowerKit_
    Get-ChildItem env:AtlassianPowerKit_* | ForEach-Object {
        Write-Debug "Removing environment variable: $_"
        Remove-Item "env:$($_.Name)" -ErrorAction Continue
    }
}

# Function to iterate through profile directories and clear contents by 
function Clear-AtlassianPowerKitProfileDirs {
    $PROFILE_DIRS = Get-AtlassianPowerKitProfileList | Get-Item
    $EXCLUDED_BACKUP_PATTERNS = @('*.zip')
    $EXCLUDED_DELETE_PATTERNS = @('*.zip', '*.md', '*.dotx', '*pdf', '*.doc', '*.docx', '*templates', '*ARCHIVE')
    # Get all subdirectories in the AtlassianPowerKit profile directory that dont match $EXCLUDED_FILENAME_PATTERNS
    foreach ($dir in $PROFILE_DIRS) {
        $ARCHIVE_NAME = "$($dir.BaseName)_ARCHIVE_$(Get-Date -Format 'yyyyMMdd').zip"
        $ARCHIVE_PATH = Join-Path -Path $dir.FullName -ChildPath $ARCHIVE_NAME

        # Collecting items excluding the patterns
        $itemsToArchive = Get-ChildItem -Path $dir.FullName -Recurse -File -Exclude $EXCLUDED_BACKUP_PATTERNS
        Write-Debug "Items to archive: $($itemsToArchive.FullName) ..."

        if ($itemsToArchive.Count -eq 0) {
            Write-Debug "Profile directory $dir. FullName has nothing to archive. Skipping..."
        } else {
            # Archiving items
            Compress-Archive -Path $itemsToArchive.FullName -DestinationPath $ARCHIVE_PATH -Force
            Write-Debug "Archiving $($dir.BaseName) to $ARCHIVE_NAME in $($dir.FullName)...."
            # Delete any directories with no files or subdirectories
            Get-ChildItem -Path $dir.FullName -Recurse -Directory | Where-Object { $_.GetFileSystemInfos().Count -eq 0 } | Remove-Item -Force
            # Write-Debug "Profile directory $dir.FullName cleared and archived to $ARCHIVE_NAME."
        }
        Get-ChildItem -Path $dir.FullName -Recurse -File -Exclude $EXCLUDED_DELETE_PATTERNS | Remove-Item -Force
        Get-ChildItem -Path $dir.FullName -Recurse -Directory -Exclude $EXCLUDED_DELETE_PATTERNS | Remove-Item -Force
    }
    # Optionally, clear the directory after archiving
    Write-Debug 'Profile directories cleared.'
}

function Get-PaginatedJSONResults {
    param (
        [Parameter(Mandatory = $true)]
        [string]$URI,
        [Parameter(Mandatory = $true)]
        [string]$METHOD,
        [Parameter(Mandatory = $false)]
        [string]$POST_BODY,
        [Parameter(Mandatory = $false)]
        [string]$RESPONSE_JSON_OBJECT_FILTER_KEY,
        [Parameter(Mandatory = $false)]
        [string]$API_HEADERS = $env:AtlassianPowerKit_AtlassianAPIHeaders
    )
    
    function Get-PageResult {
        param (
            [Parameter(Mandatory = $true)]
            [string]$URI,
            [Parameter(Mandatory = $false)]
            [string]$METHOD = 'GET',
            [Parameter(Mandatory = $false)]
            [string]$ONE_POST_BODY
        )
        try {
            if ($METHOD -eq 'POST') {
                $PAGE_RESULTS = Invoke-RestMethod -Uri $URI -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method $METHOD -Body $ONE_POST_BODY -ContentType 'application/json'
            } else {
                $PAGE_RESULTS = Invoke-RestMethod -Uri $URI -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method $METHOD -ContentType 'application/json'
                #$PAGE_RESULTS | ConvertTo-Json -Depth 100 | Write-Debug
            }
        } catch {
            # Catch 429 errors and wait for the retry-after time
            if ($_.Exception.Response.StatusCode -eq 429) {
                Write-Warn "429 error, waiting for $RETRY_AFTER seconds..."
                Start-Sleep -Seconds $RETRY_AFTER
                Get-PageResult -URI $URI -ONE_POST_BODY $ONE_POST_BODY
            } else {
                Write-Error "Error: $($_.Exception.Message)"
                throw 'Get-PageResult failed'
            }
        }
        if ($PAGE_RESULTS.isLast -eq $false) {
            # if PAGE_RESULTS has a value for key 'nextPageToken' then set it 
            #Write-Debug 'More pages to get, getting next page...'
            if ($PAGE_RESULTS.nextPageToken) {
                #Write-Debug "Next page token: $($PAGE_RESULTS.nextPageToken)"
                # Update if the method is POST, update the ONE_POST_BODY with the nextPageToken
                if ($METHOD -eq 'POST') {
                    $ONE_POST_BODY = $ONE_POST_BODY | ConvertFrom-Json
                    $ONE_POST_BODY.nextPageToken = $PAGE_RESULTS.nextPageToken
                    #$ONE_POST_BODY = $ONE_POST_BODY | ConvertTo-Json
                } else {
                    $URI = $URI + "&nextPageToken=$($PAGE_RESULTS.nextPageToken)"
                }
            } elseif ($PAGE_RESULTS.nextPage) {
                Write-Debug "Next page: $($PAGE_RESULTS.nextPage)"
                if ($METHOD -eq 'POST') {
                    Write-Error "$($MyInvocation.InvocationName) does not support POST method with nextPage. Exiting..."
                } else {
                    $URI = $PAGE_RESULTS.nextPage
                }
            }
            Get-PageResult -URI $URI -METHOD $METHOD
        }
        if ($RESPONSE_JSON_OBJECT_FILTER_KEY) {
            $PAGE_RESULTS = $PAGE_RESULTS.$RESPONSE_JSON_OBJECT_FILTER_KEY
        }
        $PAGE_RESULTS
    }
    if ($POST_BODY) {
        $RESULTS_ARRAY = Get-PageResult -URI $URI -METHOD $METHOD -ONE_POST_BODY $POST_BODY
    } else {
        $RESULTS_ARRAY = Get-PageResult -URI $URI -METHOD $METHOD
    }
    Write-Debug "$($MyInvocation.InvocationName) results:"
    # $RESULTS_ARRAY | ConvertTo-Json -Depth 100 -Compress | Write-Debug
    return $RESULTS_ARRAY | ConvertTo-Json -Depth 100 -Compress
}

function Get-LevenshteinDistance {
    param (
        [string]$s,
        [string]$t
    )

    if ($s.Length -eq 0) { return $t.Length }
    if ($t.Length -eq 0) { return $s.Length }

    $d = @()
    for ($i = 0; $i -le $s.Length; $i++) {
        $d += , @(0..$t.Length)
    }

    for ($i = 0; $i -le $s.Length; $i++) { $d[$i][0] = $i }
    for ($j = 0; $j -le $t.Length; $j++) { $d[0][$j] = $j }

    for ($i = 1; $i -le $s.Length; $i++) {
        for ($j = 1; $j -le $t.Length; $j++) {
            $cost = if ($s[$i - 1] -eq $t[$j - 1]) { 0 } else { 1 }
            $d[$i][$j] = [math]::Min([math]::Min($d[$i - 1][$j] + 1, $d[$i][$j - 1] + 1), $d[$i - 1][$j - 1] + $cost)
        }
    }

    return $d[$s.Length][$t.Length]
}

function Get-ClosureOut {
    param (
        [Parameter(Mandatory = $true)]
        [string]$R1,
        [Parameter(Mandatory = $true)]
        [string]$R2,
        [Parameter(Mandatory = $false)]
        [Int16]$DUR = 4,
        [Parameter(Mandatory = $false)]
        [Int16]$INTR = 200
    )
    $S1 = '`r'; $S2 = '########'
    # Timer Setup
    $timer = [System.Timers.Timer]::new($INTR)  # interval in ms
    $timer.AutoReset = $true
    $b = $true; $timer.add_Elapsed({ Write-Host "$($S1)$S2   $(if($script:b){$R1}else{$R2})   $S2 $(if($script:b){$R2}else{$R1}) $S2" -NoNewline; $script:b = !$script:b }); $timer.Start(); Start-Sleep -Seconds $DUR; $timer.Stop(); $timer.Dispose(); Write-Host "$S1$S2   $R1   $S2 $R2 $S2"  
}

function Set-AtlassianAPIHeaders {
    # check if there is a profile loaded
    if (!$(Test-VaultProfileLoaded)) {
        Write-Debug "$($MyInvocation.InvocationName) failed. Profile not loaded. Exiting..."
        throw "$($MyInvocation.InvocationName) failed. Profile not loaded. Exiting..."
    } else {
        $HEADERS = @{
            Authorization = "Basic $($env:AtlassianPowerKit_AtlassianAPIAuthString)"
            Accept        = 'application/json'
        }
        # Add atlassian headers to the profile data
        $API_HEADERS = $HEADERS | ConvertTo-Json -Compress       
    }
    Return $API_HEADERS
}