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
# Vault path: $env:LOCALAPPDATA\Microsoft\PowerShell\secretmanagement\localstore\
$1PASSWORD_PROFILE_URL = if ($env:OSMAtlassianProfilesVaultPath) {
    Write-Debug "Using custom 1Password vault path for Atlassian profiles: $env:OSMAtlassianProfilesVaultPath"
    $env:OSMAtlassianProfilesVaultPath
} else {
    $DEFAULT_1PASSWORD_VAULT_PATH = 'op://Employee/OSMAtlassianProfiles/notesPlain'
    Write-Debug "Using default 1Password vault path for Atlassian profiles: $DEFAULT_1PASSWORD_VAULT_PATH"
    $DEFAULT_1PASSWORD_VAULT_PATH
}
$RETRY_AFTER = 60
$ENVAR_PREFIX = 'AtlassianPowerKit_'
$REQUIRED_ENV_VARS = @('AtlassianAPIEndpoint', 'AtlassianAPIUserName', 'AtlassianAPIAuthString', 'PROFILE_NAME')

#Example format for 1Password json: 
#{
#    "AtlassianProfile1": {    
#        "OSMAtlassianEndpoint": "example.atlassian.net",
#        "OSMAtlassianUsername": "example@example.com",
#        "OSMAtlassianAPIKey": "your_api_key"
#    }  
#    "AtlassianProfile2": {

# Function to ensure 1password CLI is installed and signed in
function Test-1PasswordCLI {
    if (-not (Get-Command op -ErrorAction SilentlyContinue)) {
        Write-Warning '1Password CLI (op) is not installed or not in PATH. Please install it from https://developer.1password.com/docs/cli/get-started/installation'
        return $false
    }
    try {
        op whoami | Write-Debug
        return $true
    } catch {
        Write-Warning "1Password CLI is not signed in. Please sign in using 'op signin'."
        return $false
    }
}

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

function Get-AtlassianPowerKitProfileList {
    Write-Debug 'Skipping..'

    #$vaultPath = if ($env:OSMAtlassianProfilesVaultPath) {
    #    $env:OSMAtlassianProfilesVaultPath
    #} else {
    #    $DEFAULT_1PASSWORD_VAULT_PATH
    #}

    #Write-Debug "Getting Atlassian profiles from vault path: $vaultPath"
    ## Esnure 1password is signed in
    #try {
    #    if (-not (Get-Command op -ErrorAction SilentlyContinue)) {
    #        Write-Warning '1Password CLI (op) is not installed or not in PATH. Please install it from https://developer.1password.com/docs/cli/get-started/installation'
    #        return @()
    #    }
    #    & op whoami | Out-Null
    #} catch {
    #    Write-Warning "1Password CLI is not signed in. Please sign in using 'op signin'."
    #    return @()
    #}

    #try {
    #    # Test if the 1Password item exists
    #    $profileJson = op read $vaultPath -ErrorAction Continue
    #    if ($profileJson) {
    #        $profileMap = $profileJson | ConvertFrom-Json -ErrorAction Stop
    #        $profileList = $profileMap.PSObject.Properties.Name
    #    } else {
    #        Write-Debug "No profiles found in 1Password at $vaultPath... create a new profile."
    #        New-AtlassianPowerKitProfile
    #        <# Action when all if and elseif conditions are false #>

    #    }
    #} catch {
    #    Write-Warning "❌ Failed to read or parse profiles from 1Password: $_"
    #    Write-Warning "Running 'New-AtlassianPowerKitProfile' to create a new profile."
    #    return @()
    #}

    #Write-Debug "Found profiles: $($profileList -join ', ')"
    #return $profileList
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
# Function to set the Atlassian Cloud API headers
function Test-VaultProfileLoaded {
    # Check if all of the $REQUIRED_ENV_VARS are set
    $PROFILE_LOADED = $true
    foreach ($envVar in $REQUIRED_ENV_VARS) {
        $envVarNameKey = $ENVAR_PREFIX + $envVar
        $ENV_STATE = Get-Item -Path "env:$envVarNameKey" -ErrorAction SilentlyContinue
        if (!$ENV_STATE) {
            Write-Debug "Profile is missing required environment variable: $envVarNameKey"
            $PROFILE_LOADED = $false
            break
        } else {
            #Write-Debug "Found required environment variable: $envVarNameKey already set."
            $ENV_STATE = $null
        }
    }
    return $PROFILE_LOADED
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
        return $API_HEADERS
    }
}
# Consolidated Set-AtlassianPowerKitProfile function
function Set-AtlassianPowerKitProfile {
    param (
        [Parameter(Mandatory = $false)]
        [string]$OSMProfileName,
        [Parameter(Mandatory = $false)]
        [switch]$Vault = $false
    )

    #$OSMprofile = $null
    #$runningInDocker = Test-Path -Path '/.dockerenv' -or $env:IN_DOCKER

    ## --- OPTION 1: Docker ---
    #if ($runningInDocker -and $env:AtlassianPowerKit_PROFILE_NAME) {
    #    try {
    #        $profileMap = $env:OSMAtlassianProfiles | ConvertFrom-Json -ErrorAction Stop
    #        $OSMprofile = $profileMap.$OSMProfileName | ConvertTo-Json -ErrorAction Stop
    #    } catch {
    #        throw "Invalid JSON in OSMAtlassianProfiles env var: $_"
    #    }
    #    if (-not $OSMprofile) {
    #        throw "Profile '$OSMProfileName' not found in Docker env OSMAtlassianProfiles."
    #    }
    #}

    ## --- OPTION 2: Host with OSMAtlassianProfiles env ---
    #elseif ($env:OSMAtlassianProfiles) {
    #    try {
    #        $profileMap = $env:OSMAtlassianProfiles | ConvertFrom-Json -ErrorAction Stop
    #        $OSMprofile = $profileMap.$OSMProfileName | ConvertTo-Json -ErrorAction Stop
    #    } catch {
    #        throw "Invalid JSON in OSMAtlassianProfiles env var: $_"
    #    }
    #    if (-not $OSMprofile) {
    #        throw "Profile '$OSMProfileName' not found in host OSMAtlassianProfiles env."
    #    }
    #}

    ## --- OPTION 3: Read from user ---
    #else {
    if (-not $env:AtlassianPowerKit_PROFILE_NAME) {
        $OSMProfileName = Read-Host 'Enter OSM Profile Name'
        $OSMProfileName = $OSMProfileName.Trim().ToLower()
        $env:AtlassianPowerKit_PROFILE_NAME = $OSMProfileName
    }
    if (-not $env:AtlassianPowerKit_AtlassianAPIEndpoint) {
        $OSMEndpoint = Read-Host "Enter Atlassian Endpoint (e.g. $OSMProfileName.atlassian.net)"
        $OSMEndpoint = $OSMEndpoint.Trim().ToLower()
        $env:AtlassianPowerKit_AtlassianAPIEndpoint = $OSMEndpoint
    }
    if (-not $env:AtlassianPowerKit_AtlassianAPIUserName) {
        $OSMUsername = Read-Host 'Enter Atlassian Username (email)'
        $OSMUsername = $OSMUsername.Trim().ToLower()
        $env:AtlassianPowerKit_AtlassianAPIUserName = $OSMUsername
    }
    if (-not $env:AtlassianPowerKit_AtlassianAPIAuthString) {
        $OSMAPIKey = Read-Host 'Enter Atlassian API Key (base64 encoded)'
        $OSMAPIKey = $OSMAPIKey.Trim()
        $CredPair = "${OSMUsername}:${OSMAPIKey}"
        $AtlassianAPIAuthToken = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($CredPair))
        $env:AtlassianPowerKit_AtlassianAPIAuthString = $AtlassianAPIAuthToken
    }
    Write-Debug "Setting Atlassian PowerKit profile environment variables for $OSMProfileName..."
    $env:AtlassianPowerKit_AtlassianAPIHeaders = Set-AtlassianAPIHeaders
    $env:AtlassianPowerKit_CloudID = $(Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/_edge/tenant_info").cloudId
    Return Get-Item -Path "env:$ENVAR_PREFIX*"
}

function New-AtlassianPowerKitProfile {
    param (
        [Parameter(Mandatory = $false)]
        [string]$opEntry = 'OSMAtlassianProfiles',
        [Parameter(Mandatory = $true)]
        [string]$OSMProfileName,
        [Parameter(Mandatory = $true)]
        [string]$OSMEndpoint,
        [Parameter(Mandatory = $true)]
        [string]$OSMUsername,
        [Parameter(Mandatory = $true)]
        [string]$OSMAPIKey
    )
    # Ensure all provided parameters are strings with no leading/trailing/internal whitespace and are lowercase
    $endpoint = $OSMEndpoint.Trim().ToLower()
    $username = $OSMUsername.Trim().ToLower()
    $apiKey = $OSMAPIKey.Trim()
    $profileName = $OSMProfileName.Trim().ToLower()

    # Build temporary env for testing
    $env:AtlassianPowerKit_PROFILE_NAME = $profileName
    $env:AtlassianPowerKit_AtlassianAPIEndpoint = $endpoint
    $env:AtlassianPowerKit_AtlassianAPIUserName = $username
    $env:AtlassianPowerKit_AtlassianAPIAuthString = $apiKey
    $env:AtlassianPowerKit_AtlassianAPIHeaders = Set-AtlassianAPIHeaders

    try {
        $cloudId = $(Invoke-RestMethod -Uri "https://$endpoint/_edge/tenant_info").cloudId
        $env:AtlassianPowerKit_CloudID = $cloudId
        Test-AtlassianPowerKitProfile | Out-Null
        Write-Host "`n✅ Profile connection test succeeded."
    } catch {
        Write-Warning "`n❌ Connection test failed: $_"
        return
    }

    try {
        $existingJson = op read "$1PASSWORD_PROFILE_URL" -ErrorAction Continue
        $profileMap = $existingJson | ConvertFrom-Json -ErrorAction Continue
        if ($profileMap.$profileName) {
            $overwrite = Read-Host "Profile '$profileName' already exists. Overwrite? (Y/N)"
            if ($overwrite -ne 'Y') {
                Write-Host '❌ Aborted.'
                return
            }
        }
    } catch {
        Write-Debug "🔐 1Password item '$1PASSWORD_PROFILE_URL' does not exist. Creating new profile store."
    }
    
    # Add/overwrite profile entry
    $profileMap = @{}
    $profileMap.$profileName = @{
        OSMAtlassianEndpoint = $endpoint
        OSMAtlassianUsername = $username
        OSMAtlassianAPIKey   = $apiKey
    }

    # Write back to 1Password
    $tempPath = [System.IO.Path]::GetTempFileName()
    $profileMap | ConvertTo-Json -Depth 10 | Set-Content -Path $tempPath

    # Get vault and title for 1Password item
    # op://Employee/OSMAtlassianProfiles/notesPlain -- assumed pattern
    $1PASSWORD_SPLIT_ARRAY = ( $1PASSWORD_PROFILE_URL).Split('/')
    $1PASSWORD_VAULT = $1PASSWORD_SPLIT_ARRAY[2]
    $1PASSWORD_TITLE = $1PASSWORD_SPLIT_ARRAY[3]
    $1PASSWORD_FIELD = $1PASSWORD_SPLIT_ARRAYS[4]

    try {
        if ($existingJson) {
            & op item edit "op://$1PASSWORD_VAULT/$1PASSWORD_TITLE" $1PASSWORD_FIELD="$(Get-Content $tempPath -Raw)" | Write-Debug
            Write-Host "`n✅ Updated existing 1Password item $1PASSWORD_PROFILE_URL."
        } else {
            & op item create --category 'Secure Note' --vault $1PASSWORD_VAULT --title $1PASSWORD_TITLE $1PASSWORD_FIELD="$(Get-Content $tempPath -Raw)" | Write-Debug
            Write-Host "`n✅ Created new 1Password item '$opEntry'."
        }
    } finally {
        Remove-Item -Path $tempPath -Force
    }
    $RAW_JSON = op read $1PASSWORD_PROFILE_URL
    Return $RAW_JSON
}
function Edit-AtlassianPowerKitProfile {
    param (
        [Parameter(Mandatory = $false)]
        [string]$ProfileName,
        [Parameter(Mandatory = $false)]
        [string]$opEntry = 'OSMAtlassianProfiles'
    )

    # Load profiles
    try {
        $rawJson = op read "op://employee/$opEntry/notesPlain"
        $profileMap = $rawJson | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "❌ Failed to read or parse 1Password item '$opEntry'."
    }

    # Default selection logic
    if (-not $ProfileName) {
        $keys = $profileMap.PSObject.Properties.Name
        if ($keys.Count -eq 1) {
            $ProfileName = $keys[0]
            Write-Host "ℹ️ Defaulting to only available profile: '$ProfileName'"
        } elseif ($keys.Count -gt 1) {
            Write-Host 'Available profiles:'
            $keys | ForEach-Object { Write-Host "  - $_" }
            $ProfileName = Read-Host 'Enter the profile name to edit'
        } else {
            throw "❌ No profiles found in $opEntry."
        }
    }

    if (-not $profileMap.ContainsKey($ProfileName)) {
        throw "❌ Profile '$ProfileName' not found."
    }

    $OSMProfileData = $profileMap.$ProfileName

    Write-Host "`nEditing profile '$ProfileName'..."
    Write-Host 'Select field to update:'
    Write-Host '1) Endpoint'
    Write-Host '2) Username'
    Write-Host '3) API Key'

    $choice = Read-Host 'Enter 1, 2, or 3'
    switch ($choice) {
        '1' {
            $newValue = Read-Host 'Enter new Atlassian Endpoint'
            $OSMProfileData.OSMAtlassianEndpoint = $newValue
        }
        '2' {
            $newValue = Read-Host 'Enter new Atlassian Username'
            $OSMProfileData.OSMAtlassianUsername = $newValue
        }
        '3' {
            $newSecure = Read-Host 'Enter new Atlassian API Key' -AsSecureString
            $newPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($newSecure)
            )
            $OSMProfileData.OSMAtlassianAPIKey = $newPlain
        }
        default {
            Write-Host '❌ Invalid selection. Aborting.'
            return
        }
    }

    # Save updated profile back
    $profileMap.$ProfileName = $OSMProfileData
    $tempPath = [System.IO.Path]::GetTempFileName()
    $profileMap | ConvertTo-Json -Depth 10 | Set-Content -Path $tempPath

    try {
        & op item edit "$opEntry" notesPlain="$(Get-Content $tempPath -Raw)" | Out-Null
        Write-Host "`n✅ Profile '$ProfileName' updated successfully."
    } finally {
        Remove-Item $tempPath -Force
    }
}
function Export-AtlassianPowerKitProfiles {
    param (
        [Parameter(Mandatory = $false)]
        [switch]$AsShellExport
    )
    try {
        # Ensure 1Password CLI is installed and authenticated
        if (-not (Get-Command op -ErrorAction SilentlyContinue)) {
            throw '1Password CLI (op) is not installed or not in PATH. Please install it from https://1password.com/downloads/cli/'
        }
        op signin | Write-Debug
        # Load profiles from 1Password
        $1PASSWORD_JSON = op read $1PASSWORD_PROFILE_URL
        $compactJson = $1PASSWORD_JSON | ConvertTo-Json -Depth 10 -Compress
        if ($AsShellExport) {
            Write-Output "export OSMAtlassianProfiles='$compactJson'"
        }
    } catch {
        Write-Debug "No entry found at $1PASSWORD_PROFILE_URL. Creating new profile store."
    }
    return $compactJson
}
# Function to test if AtlassianPowerKit profile authenticates successfully
function Test-AtlassianPowerKitProfile {
    Write-Debug 'Testing Atlassian Cloud PowerKit Profile...'
    ##Write-Debug "API Headers: $($script:AtlassianAPIHeaders | Format-List * | Out-String)'
    #Write-Debug "API Endpoint: $($env:AtlassianPowerKit_AtlassianAPIEndpoint) ..."
    #Write-Debug "API Headers: $($env:AtlassianPowerKit_AtlassianAPIHeaders) ..."
    $HEADERS = ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders
    $TEST_ENDPOINT = 'https://' + $env:AtlassianPowerKit_AtlassianAPIEndpoint + '/rest/api/2/myself'
    try {
        #Write-Debug "Running: Invoke-RestMethod -Uri https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/rest/api/2/myself -Headers $($env:AtlassianPowerKit_AtlassianAPIHeaders | ConvertFrom-Json -AsHashtable) -Method Get"
        $REST_RESPONSE = Invoke-RestMethod -Method Get -Uri $TEST_ENDPOINT -Headers $HEADERS -StatusCodeVariable REST_STATUS
        #Write-Debug "Results: $($REST_RESULTS | ConvertTo-Json -Depth 10) ..."
        Write-Debug "$($MyInvocation.InvocationName) returned status code: $($REST_STATUS)"
    } catch {
        Write-Debug "$($MyInvocation.InvocationName) failed: with $_"
        Write-Debug 'Rest response: '
        $REST_RESPONSE | ConvertTo-Json -Depth 10 | Write-Debug
        throw "$($MyInvocation.InvocationName) failed. Exiting..."
    }
    Return $true
}
function Remove-AtlassianPowerKitProfile {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ProfileName,
        [Parameter(Mandatory = $false)]
        [string]$opEntry = 'OSMAtlassianProfiles'
    )

    try {
        $rawJson = op read "op://employee/$opEntry/notesPlain"
        $profileMap = $rawJson | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "❌ Failed to read 1Password item '$opEntry'."
    }

    if (-not $profileMap.ContainsKey($ProfileName)) {
        Write-Host "⚠️ Profile '$ProfileName' not found. Nothing to remove."
        return
    }

    $confirm = Read-Host "Are you sure you want to delete profile '$ProfileName'? (Y/N)"
    if ($confirm -ne 'Y') {
        Write-Host '❌ Deletion aborted.'
        return
    }

    $profileMap.Remove($ProfileName)

    # Write back updated JSON
    $tempPath = [System.IO.Path]::GetTempFileName()
    $profileMap | ConvertTo-Json -Depth 10 | Set-Content -Path $tempPath

    try {
        & op item edit "$opEntry" notesPlain="$(Get-Content $tempPath -Raw)" | Out-Null
        Write-Host "`n✅ Profile '$ProfileName' removed from '$opEntry'."
    } finally {
        Remove-Item $tempPath -Force
    }
}

