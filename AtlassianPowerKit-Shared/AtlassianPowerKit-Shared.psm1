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

# Vault path: $env:LOCALAPPDATA\Microsoft\PowerShell\secretmanagement\localstore\
$ErrorActionPreference = 'Stop'; $DebugPreference = 'Continue'
$VAULT_NAME = 'AtlassianPowerKitProfileVault'
$VAULT_KEY_PATH = "$($env:OSM_HOME)\vault_key.xml"
$RETRY_AFTER = 60
$ENVAR_PREFIX = 'AtlassianPowerKit_'
$REQUIRED_ENV_VARS = @('AtlassianAPIEndpoint', 'AtlassianAPIUserName', 'AtlassianAPIAuthString', 'PROFILE_NAME')

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

function Clear-AtlassianPowerKitVault {
    Unregister-SecretVault -Name $VAULT_NAME -ErrorAction Continue
    Write-Debug "Vault $VAULT_NAME cleared."
    $VAULT_KEY = Get-VaultKey
    $storeConfiguration = @{
        Authentication  = 'Password'
        Password        = $VAULT_KEY
        PasswordTimeout = 3600
        Interaction     = 'None'
    }
    Reset-SecretStore @storeConfiguration -Force
    Clear-AtlassianPowerKitProfile
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
    Write-Debug "$($MyInvocation.InvocationName) getting profile list from vault: $VAULT_NAME..."
    if (!$(Get-SecretVault -Name $VAULT_NAME -ErrorAction SilentlyContinue)) {
        Write-Debug "$($MyInvocation.InvocationName) vault not found, registering..."
        Register-AtlassianPowerKitVault
        Write-Debug "$($MyInvocation.InvocationName) vault registered successfully."
        $PROFILE_LIST = @()
    } else {
        #Write-Debug 'Vault already registered, getting profiles...'
        unlock-vault -VaultName $VAULT_NAME | Write-Debug
        $PROFILE_LIST = (Get-SecretInfo -Vault $VAULT_NAME -Name '*').Name
    }
    return $PROFILE_LIST
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

# Function Update-ContentPlaceholderAll, takes a file path and a hashtable of placeholders and values, returning the content with the placeholders replaced (not updating the file)

function Get-VaultKey {
    if (-not (Test-Path $VAULT_KEY_PATH)) {
        Write-Debug 'No vault key file found. Please register a vault first.'
        return $false
    }
    $VAULT_KEY = Import-Clixml -Path $VAULT_KEY_PATH
    return $VAULT_KEY
}

function Unlock-Vault {
    param (
        [Parameter(Mandatory = $true)]
        [string]$VaultName
    )
    try {
        if ((Get-SecretVault | Where-Object IsDefault).Name -ne $VAULT_NAME) {
            Write-Debug "$VAULT_NAME is not the default vault. Setting as default..."
            Set-SecretVaultDefault -Name $VAULT_NAME | Write-Debug
        }
        # Attempt to get a non-existent secret. If the vault is locked, this will throw an error.
        $VAULT_KEY = Get-VaultKey
        if (! $VAULT_KEY -or $VAULT_KEY -eq $false) {
            Write-Debug 'Unlock-Vault failed. Exiting.'
            throw 'Unlock-Vault failed. Exiting.'
        }
        Unlock-SecretStore -Password $VAULT_KEY | Write-Debug
    } catch {
        # If an error is thrown, the vault is locked.
        Write-Debug "Unlock-Vault failed: $_ ..."
        throw 'Unlock-Vault failed Exiting'
    }
    # If no error is thrown, the vault is unlocked.
    Write-Debug 'Vault is unlocked.'
    Return $true
}

# Function to update the vault with the new profile data
function Update-AtlassianPowerKitVault {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ProfileName,
        [Parameter(Mandatory = $true)]
        [hashtable]$ProfileData
    )
    Write-Debug "Writing profile data to vault for $ProfileName..."
    Unlock-Vault -VaultName $VAULT_NAME | Write-Debug
    try {
        Set-Secret -Name $ProfileName -Secret $ProfileData -Vault $VAULT_NAME | Write-Debug
    } catch {
        Write-Debug "Update of vault failed for $ProfileName."
        throw "Update of vault failed for $ProfileName."
    }
    Write-Debug "Vault entruy for $ProfileName updated successfully."
}

function Register-AtlassianPowerKitVault {
    param (
        [Parameter(Mandatory = $false)]
        [Int]$ATTEMPT = 0
    )
    # Register the secret vault
    # Cheking if the vault is already registered
    while (-not (Test-Path $VAULT_KEY_PATH)) {
        Write-Debug 'No vault key file found. Removing any existing vaults and re-creating...'
        Unregister-SecretVault -Name $VAULT_NAME -ErrorAction SilentlyContinue
        # Create a random secure key to use as the vault key as protected data
        $VAULT_KEY = $null
        while (-not $VAULT_KEY -or $VAULT_KEY.Length -lt 16) {
            # Generate a random byte array
            $randomBytes = New-Object byte[] 32
            [System.Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($randomBytes)

            # Convert the byte array to a secure string
            $secureString = New-Object -TypeName System.Security.SecureString
            foreach ($byte in $randomBytes) {
                $secureString.AppendChar([char]$byte)
            }
            $VAULT_KEY = $secureString
        }
        $VAULT_KEY | Export-Clixml -Path $VAULT_KEY_PATH
        # Write the vault key to a temporary file
        Write-Debug 'Vault key file created successfully.'
    }
    if (Get-SecretVault -Name $VAULT_NAME -ErrorAction SilentlyContinue) {
        Write-Debug "Vault $VAULT_NAME already exists."
    } else {
        Write-Debug "Registering vault $VAULT_NAME..."
        $VAULT_KEY = Get-VaultKey
        $storeConfiguration = @{
            Authentication  = 'Password'
            Password        = $VAULT_KEY
            PasswordTimeout = 3600
            Interaction     = 'None'
        }
        Set-SecretVaultDefault -ClearDefault
        Reset-SecretStore @storeConfiguration -Force
        Register-SecretVault -Name $VAULT_NAME -ModuleName Microsoft.PowerShell.SecretStore -VaultParameters $storeConfiguration -DefaultVault -AllowClobber
        Write-Debug "Vault $VAULT_NAME registered successfully."
        Write-Debug "Checking if vault $VAULT_NAME is the default vault..."
        if ((Get-SecretVault | Where-Object IsDefault).Name -ne $VAULT_NAME) {
            Write-Debug "$VAULT_NAME is not the default vault. Setting as default..."
            Set-SecretVaultDefault -Name $VAULT_NAME
        }
        Write-Debug "Vault $VAULT_NAME configured successfully."
    }
    # Unlock the vault if it is locked
    try {
        $VAULT_KEY = Get-VaultKey
        Unlock-Vault -VaultName $VAULT_NAME | Write-Debug
    } catch {
        Write-Debug "Failed to unlock vault $VAULT_NAME. Please check the vault key file."
        Write-Debug "De-registering vault $VAULT_NAME... and resetting vault key file."
        Unregister-SecretVault -Name $VAULT_NAME | Write-Debug
        Remove-Item -Path $VAULT_KEY_PATH -Force | Write-Debug
        Write-Debug "Vault $VAULT_NAME de-registered and vault key file removed, starting from scratch..."
        Write-Debug "$($MyInvocation.InvocationName) failed retrying, attempt: $ATTEMPT"
    }
    if ($ATTEMPT -gt 5) {
        Write-Debug "$($MyInvocation.InvocationName) failed after $ATTEMPT attempts. Exiting..."
        throw "$($MyInvocation.InvocationName) failed!"
    } else {
        Register-AtlassianPowerKitVault -ATTEMPT ($ATTEMPT + 1)
    }
    Return $true
} 

function Register-AtlassianPowerKitProfileInVault {
    param(
        [Parameter(Mandatory = $false)]
        [string]$ProfileName,
        [Parameter(Mandatory = $false)]
        [string]$AtlassianAPIEndpoint,
        [Parameter(Mandatory = $false)]
        [PSCredential]$AtlassianAPICredentialPair
    )

    try {
        Register-AtlassianPowerKitVault | Write-Debug
    } catch {
        Write-Debug "$($MyInvocation.InvocationName) failed to register vault. Exiting"
        throw "$($MyInvocation.InvocationName) failed to register vault. Exiting"
    }
    Write-Debug "$($MyInvocation.InvocationName) vault registered successfully."
    $VAULT_PROFILES_LIST = Get-AtlassianPowerKitProfileList
    # Check if the profile already exists in the secret vault
    if ($null -ne $VAULT_PROFILES_LIST -and $VAULT_PROFILES_LIST.Count -gt 0 -and $VAULT_PROFILES_LIST.Contains($ProfileName)) {
        Write-Debug "$($MyInvocation.InvocationName) Profile $ProfileName already exists in the vault. You must run AtlssianPowerKit -RemoveVaultProfile $ProfileName or AtlssianPowerKit -ResetVault to remove it first."
        throw "$($MyInvocation.InvocationName) Profile $ProfileName already exists in the vault. You must run AtlssianPowerKit -RemoveVaultProfile $ProfileName or AtlssianPowerKit -ResetVault to remove it first."
    } else {
        #Write-Debug "Profile $ProfileName does not exist. Creating..."
        Write-Debug "Preparing profile data for $ProfileName..."
        $CredPair = "$($AtlassianAPICredentialPair.UserName):$($AtlassianAPICredentialPair.GetNetworkCredential().password)"
        Write-Debug "CredPair: $CredPair"
        $AtlassianAPIAuthToken = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($CredPair))
        $ProfileData = @{
            'PROFILE_NAME'           = $ProfileName
            'AtlassianAPIEndpoint'   = $AtlassianAPIEndpoint
            'AtlassianAPIUserName'   = $AtlassianAPICredential.UserName
            'AtlassianAPIAuthString' = $AtlassianAPIAuthToken
        }
        Write-Debug "$($MyInvocation.InvocationName) profile data prepared for $ProfileName, updating vault..."
        Set-Secret -Name $ProfileName -Secret $ProfileData -Vault $VAULT_NAME | Write-Debug
        Write-Debug "$($MyInvocation.InvocationName) profile data updated for $ProfileName."
        Clear-AtlassianPowerKitProfile | Out-Null
    }
    return $PROFILE_NAME
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
    }
    Return $API_HEADERS
}

function Set-AtlassianPowerKitProfileFromVault {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SelectedProfileName
    )
    $SKIP_LOAD = Test-VaultProfileLoaded
    if ($SKIP_LOAD) {
        Get-Item -Path "env:$ENVAR_PREFIX*" | Write-Debug
        Write-Debug "$($MyInvocation.InvocationName) profile already loaded. Skipping vault load..."
    } else {
        Write-Debug "Profile $SelectedProfileName not loaded. Loading from vault..."
        # Load all profiles from the secret vault
        if (!$(Get-SecretVault -Name $VAULT_NAME -ErrorAction SilentlyContinue)) {
            Register-AtlassianPowerKitVault
        }
        # Check if the profile exists
        $PROFILE_LIST = Get-AtlassianPowerKitProfileList
        if (!$PROFILE_LIST.Contains($SelectedProfileName)) {
            Write-Debug "Profiles found in vault: $($PROFILE_LIST | ConvertTo-Json -Depth 100) ..."
            Write-Debug 'Profiles found in vault: '
            $PROFILE_LIST | ConvertTo-Json -Depth 100 | Write-Debug
            Write-Error "$($MyInvocation.InvocationName) failed. Profile $SelectedProfileName not found in the vault. Exiting..."
            Throw "$($MyInvocation.InvocationName) failed. Profile $SelectedProfileName not found in the vault. Exiting..."
        } else {
            Write-Debug "Profile $SelectedProfileName exists in the vault, loading..."
            try {
                # if vault is locked, unlock it
                if (unlock-vault -VaultName $VAULT_NAME) {
                    $PROFILE_DATA = (Get-Secret -Name $SelectedProfileName -Vault $VAULT_NAME -AsPlainText)
                    #Create environment variables for each item in the profile data
                    Write-Debug "Successfully retrieved profile data for $SelectedProfileName : "
                    $PROFILE_DATA | ConvertTo-Json -Depth 100 | Write-Debug
                    $PROFILE_DATA.GetEnumerator() | ForEach-Object {
                        #Write-Debug "Setting environment variable: $($_.Key) = $($_.Value)"
                        # Create environment variable concatenated with AtlassianPowerKit_ 
                        $VAR_NAME = $ENVAR_PREFIX + $_.Key
                        $VAR_VALUE = $_.Value
                        Write-Debug "Setting environment variable: env:$VAR_NAME = $VAR_VALUE"
                        $SetEnvar = '$env:' + $VAR_NAME + ' = "' + $VAR_VALUE + '"'
                        Invoke-Expression -Command $SetEnvar
                        Get-Item -Path "env:$VAR_NAME" | Write-Debug
                    }
                }
            } catch {
                Write-Debug "Failed to load profile $SelectedProfileName. Please check the vault key file."
                throw "Failed to load profile $SelectedProfileName. Please check the vault key file."
            }
        }
    }
    $ENVVAR_ARRAY = Get-Item -Path "env:$ENVAR_PREFIX*"
    Return $ENVVAR_ARRAY
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

function Remove-AtlasianPowerKitProfile {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ProfileName
    )
    Write-Debug "Removing profile $ProfileName..."
    if ($ProfileName -eq $env:AtlassianPowerKit_PROFILE_NAME) {
        Clear-AtlassianPowerKitProfile | Write-Debug
    }
    Remove-Secret -Name $ProfileName -Vault $VAULT_NAME | Write-Debug
    Write-Debug "Profile $ProfileName removed."
}
function Set-AtlassianPowerKitProfile {
    param (
        [Parameter(Mandatory = $false)]
        [string]$ProfileName = $false,
        [Parameter(Mandatory = $false)]
        [switch]$NoVault = $false
    )
    if ($NoVault) {
        Write-Debug 'NoVault switch enabled. Skipping vault actions and checking required environment variables are present'
        foreach ($envVar in $REQUIRED_ENV_VARS) {
            $envVarNameKey = $ENVAR_PREFIX + $envVar
            $requiredEnvVar = $(Get-Item -Path "env:$envVarNameKey" -ErrorAction SilentlyContinue)
            if (!$requiredEnvVar) {
                Write-Error "Required environment variable $envVarNameKey not found. Exiting..."
                throw "Required environment variable $envVarNameKey not found. Exiting..."
            } else {
                Write-Debug "Required environment variable found: $($requiredEnvVar.Name) = $(($requiredEnvVar.Value).substring(0, [System.Math]::Min(20, $requiredEnvVar.Value.Length)))..."
                # if the environment variable is AtlassianAPIEndpoint, use the prefix as the profile name (setting as environment variable: AtlassianPowerKit_PROFILE_NAME)
                if ($requiredEnvVar.Name -eq 'AtlassianPowerKit_AtlassianAPIEndpoint') {
                    $ProfileName = $requiredEnvVar.Value -Split '.' | Select-Object -First 1
                    Write-Debug "Setting environment variable: PROFILE_NAME = $ProfileName"
                    # Create environment variable concatenated with AtlassianPowerKit_ prefix
                    $SetEnvar = '$env:' + $ENVAR_PREFIX + 'PROFILE_NAME = `"' + $ProfileName + '"`'
                    Invoke-Expression -Command $SetEnvar | Out-Null
                }
            }
        }
    } elseif ($ProfileName -ne $false) {
        $VAULT_LOADED_ARRAY = Set-AtlassianPowerKitProfileFromVault -SelectedProfileName $ProfileName
        $VAULT_LOADED_ARRAY | ForEach-Object { Write-Output "$($_.Name) = $($_.Value)" | Out-Null } 
    } else {
        Write-Error 'ProfileName is required. Exiting...'
        throw 'ProfileName is required. Exiting...'
    }
    #Write-Debug 'Vault loaded array:'
    #$VAULT_LOADED_ARRAY | ForEach-Object { Write-Debug "$($_.Name) = $($_.Value)" }
    $env:AtlassianPowerKit_AtlassianAPIHeaders = Set-AtlassianAPIHeaders
    #Write-Debug "API Headers set: $($env:AtlassianPowerKit_AtlassianAPIHeaders) calling https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/_edge/tenant_info to get CloudID..."
    $env:AtlassianPowerKit_CloudID = $(Invoke-RestMethod -Uri "https://$($env:AtlassianPowerKit_AtlassianAPIEndpoint)/_edge/tenant_info").cloudId
    #Write-Debug "CloudID set: $($env:AtlassianPowerKit_CloudID) ..."
    $PROFILE_ENVARS = Get-Item -Path "env:$ENVAR_PREFIX*"
    Write-Debug "ENVARS loaded, count: $($PROFILE_ENVARS.Count) ..."
    Return $PROFILE_ENVARS
}