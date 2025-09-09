$ErrorActionPreference = 'Stop'; $DebugPreference = 'Continue'

# ret neg is reverse order of ret pos
function Get-RequisitePowerKitModules {
    $AtlassianPowerKitRequiredModules = @('PowerShellGet', 'Microsoft.PowerShell.SecretManagement', 'Microsoft.PowerShell.SecretStore')
    $AtlassianPowerKitRequiredModules | ForEach-Object {
        # Import or install the required module
        if (-not (Get-Module -Name $_ -ErrorAction Continue)) {
            try {
                if (-not (Get-Module -Name $_ -ListAvailable)) {
                    Write-Debug "Module $_ not found. Installing..."
                    Install-Module -Name $_ -Force -Scope CurrentUser | Write-Debug
                }            
            } catch {
                Write-Error "Module $_ not found and installation failed. Exiting."
                throw "Dependency module $_ unanable to install, try manual install, Exiting for now."
            }
            Import-Module -Name $_ -Force | Write-Debug
        }
    }
    return $true
}
function Import-NestedModules {
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$NESTED_MODULES
    )
    $NESTED_MODULES | ForEach-Object {
        $MODULE_NAME = $_
        #Write-Debug "Importing nested module: $MODULE_NAME"
        #Find-Module psd1 file in the subdirectory and import it
        $PSD1_FILE = Get-ChildItem -Path ".\$MODULE_NAME" -Filter "$MODULE_NAME.psd1" -Recurse -ErrorAction SilentlyContinue
        if (-not $PSD1_FILE) {
            Write-Error "Module $MODULE_NAME not found. Exiting."
            throw "Nested module $MODULE_NAME not found. Exiting."
        } elseif ($PSD1_FILE.Count -gt 1) {
            Write-Error "Multiple module files found for $MODULE_NAME. Exiting."
            throw "Multiple module files found for $MODULE_NAME. Exiting."
        }
        Write-Debug "Importing nested module: $PSD1_FILE"
        Import-Module $PSD1_FILE.FullName -Force
        Write-Debug "Imported nested module: $PSD1_FILE,  -- $($PSD1_FILE.BaseName)"
        #Write-Debug "Importing nested module: .\$($_.BaseName)\$($_.Name)"
        # Validate the module is imported
        if (-not (Get-Module -Name $MODULE_NAME)) {
            Write-Error "Module $MODULE_NAME not found. Exiting."
            throw "Nested module $MODULE_NAME not found. Exiting."
        }
    }
    return $NESTED_MODULES
}
# Create OSM dirs
$OSM_DIRS = @('OSM_HOME', 'OSM_INSTALL')
function Confirm-OSMDirs {
    $VALIDATED_DIRS = $OSM_DIRS | ForEach-Object {
        # Check if $env: variable exists
        $ENVAR_NAME = 'env:' + $_
        if (-not (Get-Item -Path $ENVAR_NAME -ErrorAction SilentlyContinue)) {
            if ($IsLinux) {
                $DIR_PATH = '/opt/osm'
            } else {
                $DIR_PATH = $(Get-ItemProperty -Path .).FullName
            }
            $SetEnvar = '$' + $ENVAR_NAME + ' = "' + $DIR_PATH + '"'
            Invoke-Expression -Command $SetEnvar | Write-Debug
            #Write-Debug "Envar set: $SetEnvar"
        }
        # Get the path from the $env: variable and create the directory if it does not exist
        $EXISING_ENVAR = Get-Item -Path $ENVAR_NAME
        $EXPECTED_DIR = $EXISING_ENVAR.Value
        if (-not (Test-Path $EXPECTED_DIR)) {
            New-Item -ItemType Directory -Path $EXPECTED_DIR -Force | Write-Debug
            #Write-Debug "Directory created: $EXPECTED_DIR"
        } else {
            #Write-Debug "Good news, $ENVAR_NAME already set and directory already exists: $EXPECTED_DIR"
        }
        $ENVAR_NAME
    }
    return $VALIDATED_DIRS
}
function Invoke-AtlassianPowerKitFunction {
    param (
        [Parameter(Mandatory = $true)]
        [string]$FunctionName,
        [Parameter(Mandatory = $false)]
        [hashtable]$FunctionParameters
    )
    $TEMP_DIR = "$env:OSM_HOME\$env:AtlassianPowerKit_PROFILE_NAME\.temp"
    if (-not (Test-Path $TEMP_DIR)) {
        New-Item -ItemType Directory -Path $TEMP_DIR -Force | Write-Debug
    }
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $stopwatch.Start() | Write-Debug
            
    try {
        if ($FunctionParameters) {
            # Safely construct a debug message with hashtable keys and values
            $singleLineDefinition = $FunctionParameters.Keys | ForEach-Object { '- ' + $_ + ": $($FunctionParameters[$_])" }
            Write-Debug "Running function: $FunctionName with parameters: $singleLineDefinition"
                    
            # Use Splatting (@) to pass parameters
            $RETURN_OBJECT = & $FunctionName @FunctionParameters
        } else {
            Write-Debug "Running function: $FunctionName without parameters"
            $RETURN_OBJECT = & $FunctionName
        }
                
        # Stop timing the function execution
        $stopwatch.Stop() | Out-Null
        Write-Debug "Function $FunctionName completed - execution time: $($stopwatch.Elapsed.TotalSeconds) seconds"
                
        # Convert the returned object to JSON
        $RETURN_JSON = $RETURN_OBJECT
        Write-Debug "Returning JSON of size: $($RETURN_JSON.Length) characters"
    } catch {
        Write-Debug "Error occurred while invoking function: $FunctionName"
        Write-Debug $_
        $RETURN_JSON = "{'error': 'An error occurred while executing the function.', 'details': '$($_.Exception.Message)'}"
    }
            
    return $RETURN_JSON
}
        
$ret_pos = [string](@(92, 40, 94, 45, 94, 41, 47) | ForEach-Object { [char]$_ })
function Show-AdminFunctions {
    param (
        [Parameter(Mandatory = $false)]
        [string[]]$AdminModules = @('AtlassianPowerKit-Shared', 'AtlassianPowerKit-UsersAndGroups')
    )
    # Clear current screen
    Clear-Host
    Show-AtlassianPowerKitFunctions -NESTED_MODULES $AdminModules
}

function Update-OSMPKFunctionsMarkDownDoc {
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$NESTED_MODULES
    )
    # Creates or updates a markdown document with all functions in the module, their descriptions, and parameters
    $MARKDOWN_FILE = "$env:OSM_HOME\AtlassianPowerKit\AtlassianPowerKit-Functions.md"
    if (-not (Test-Path $MARKDOWN_FILE)) {
        New-Item -ItemType File -Path $MARKDOWN_FILE -Force | Write-Debug
    } else {
        Clear-Content -Path $MARKDOWN_FILE | Write-Debug
    }
    $NESTED_MODULES | ForEach-Object {
        $MODULE_NAME = $_
        Write-Output "# Module: $MODULE_NAME" | Out-File -FilePath $MARKDOWN_FILE -Append
        Write-Debug "Updating markdown document for module: $MODULE_NAME"
        $MODULE_FUNCTIONS = (Get-Module -Name $MODULE_NAME -All).ExportedFunctions.Keys
        $MODULE_FUNCTIONS | ForEach-Object {
            $FUNCTION_NAME = $_
            $FUNCTION_PARAMS = $FUNCTION_NAME.Parameters 
            Write-Output "## Function: $FUNCTION_NAME" | Out-File -FilePath $MARKDOWN_FILE -Append
            Write-Output '### Params' | Out-File -FilePath $MARKDOWN_FILE -Append
            foreach ($PARAM in $FUNCTION_PARAMS) {
                $PARAM_DETAILS = $FUNCTION_PARAMS[$PARAM]
                $PARAM_NAME = $PARAM
                $PARAM_TYPE = $PARAM_DETAILS.ParameterType.Name
                $PARAM_MANDATORY = $PARAM_DETAILS.IsMandatory
                $PARAM_DEFAULT = $PARAM_DETAILS.DefaultValue
                $PARAM_DETAILS = "    - **$PARAM_NAME** ($PARAM_TYPE)"
                if ($PARAM_MANDATORY) {
                    $PARAM_DETAILS += ' - Mandatory'
                }
                if ($PARAM_DEFAULT) {
                    $PARAM_DETAILS += " - Default: $PARAM_DEFAULT"
                }
                Write-Output $PARAM_DETAILS | Out-File -FilePath $MARKDOWN_FILE -Append
            }
            $FUNCTION_DETAILS | Out-File -FilePath $MARKDOWN_FILE -Append
        }
    }
    return $MARKDOWN_FILE
}

# Function display console interface to run any function in the module
function Show-AtlassianPowerKitFunctions {
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$NESTED_MODULES
    )
    $selectedFunction = $null
    # Remove AtlassianPowerKit-Shard and AtlassianPowerKit-UsersAndGroups from the nested modules
    #$NESTED_MODULES = $NESTED_MODULES | Where-Object { $_ -ne 'AtlassianPowerKit-UsersAndGroups' -and $_ -ne 'AtlassianPowerKit-Shared' }
    $NESTED_MODULES = $NESTED_MODULES | Where-Object { $_ -ne 'AtlassianPowerKit-Shared' }
    # List nested modules and their exported functions to the console in a readable format, grouped by module
    $colors = @('Green', 'Cyan', 'Red', 'Magenta', 'Yellow', 'Blue', 'Gray')
    $colorIndex = 0
    $functionReferences = @()
    $functionReferences += 'Return'
    $NESTED_MODULES | ForEach-Object {
        $MODULE_NAME = $_
        #Write-Debug "DISPLAYING Module: $_"
        # Select a color from the list
        $color = $colors[$colorIndex % $colors.Count]
        $spaces = ' ' * (51 - $_.Length)
        Write-Host '' -BackgroundColor Black
        Write-Host "Module: $($_)" -BackgroundColor $color -ForegroundColor White -NoNewline
        Write-Host $spaces -BackgroundColor $color -NoNewline
        Write-Host ' ' -BackgroundColor Black
        $spaces = ' ' * 40
        Write-Host " Exported Commands:$spaces" -BackgroundColor "Dark$color" -ForegroundColor White -NoNewline
        Write-Host ' ' -BackgroundColor Black
        $colorIndex++
        #Write-Debug $MODULE_NAME
        #Get-Module -Name $MODULE_NAME 
        $FunctionList = (Get-Module -Name $MODULE_NAME -All).ExportedFunctions.Keys
        $FunctionList | ForEach-Object {
            $functionReferences += $_
            Write-Host ' ' -NoNewline -BackgroundColor "Dark$color"
            Write-Host '   ' -NoNewline -BackgroundColor Black
            Write-Host "$($functionReferences.Length - 1) -> " -NoNewline -BackgroundColor Black
            Write-Host "$_" -NoNewline -BackgroundColor Black -ForegroundColor $color
            # Calculate the number of spaces needed to fill the rest of the line
            $spaces = ' ' * (50 - ($_.Length + (($functionReferences.Length - 1 ).ToString().Length)))
            Write-Host $spaces -NoNewline -BackgroundColor Black
            Write-Host ' ' -NoNewline -BackgroundColor "Dark$color"
            Write-Host ' ' -BackgroundColor Black
            # Increment the color index for the next function
        }
        $colorIndex++
        $spaces = ' ' * 59
        Write-Host $spaces -BackgroundColor "Dark$color" -NoNewline
        Write-Host ' ' -BackgroundColor Black
    }
    Write-Host '[A] Admin (danger) functions'
    Write-Host '[Q / Return] Quit'
    Write-Host '++++++++++++++++++++++++++++++++++++++++++++++++++++++++++' -ForegroundColor DarkGray
    # Write separator for readability
    Write-Host "`n"
    # Ask the user which function they want to run
    # if the user hits enter, exit the function
    # Attempt to convert the input string to a char
    $selectedFunction = Read-Host -Prompt "`nSelect a function by number or name to run (or hit enter to exit)"
    if ($selectedFunction -match '^\d+$') {
        Write-Debug "Selected function by num: $selectedFunction"
        $SelectedFunctionName = ($functionReferences[[int]$selectedFunction])
    } elseif ($selectedFunction -match '^(?i)[a-z]*-[a-z]*$') {
        # Test if the function exists
        $selectedFunction = $selectedFunction
        Write-Debug "Selected function by name: $selectedFunction"
        #Write-Debug "Function references: $($functionReferences.GetType())"
        if ($functionReferences.Contains($selectedFunction)) {
            $SelectedFunctionName = $selectedFunction
        } else {
            Write-Error "Function $selectedFunction does not exist in the function references."
        }
    }
    if ($SelectedFunctionName -eq 'A') {
        Show-AdminFunctions
    }
    # if selected function is Return, exit the function
    elseif (!$SelectedFunctionName -or ($SelectedFunctionName -eq 0 -or $SelectedFunctionName -eq 'Return')) {
        #Write-Debug 'No function selected. Exiting'
        return $null
    }
    # Run the selected function timing the execution
    Write-Host "`n"
    Write-Host "Invoking AtlassingPowerKit Function:  $SelectedFunctionName" -ForegroundColor Green
    return $SelectedFunctionName
}

function Initialize-AtlassianPowerKitProfile {
    if ($env:AtlassianPowerKit_PROFILE_NAME) {
        $profileName = $env:AtlassianPowerKit_PROFILE_NAME
    } else {
        Write-Output 'NOTE: you can pre-set the following environment variables:'
        Write-Output "  AtlassianPowerKit_PROFILE_NAME - The name of the profile to use (default: 'default')"
        Write-Output "  AtlassianPowerKit_ENDPOINT - The Atlassian API endpoint (default: 'profile_name.atlassian.net')"
        Write-Output "  AtlassianPowerKit_UserName - The Atlassian user name for the profile (default: 'profile_name@endpoint')"
        Write-Output '  AtlassianPowerKit_APIKey - The Atlassian API key for the profile (default: read from /run/secrets/api_key or prompted)'
        $profileName = Read-Host -Prompt 'Enter the profile name'
    }
    $profileName = $profileName.Trim().ToLower()
    $env:AtlassianPowerKit_PROFILE_NAME = $profileName

    if ($env:AtlassianPowerKit_ENDPOINT) {
        $endpoint = $env:AtlassianPowerKit_ENDPOINT
    } else {
        $endpoint = Read-Host -Prompt "Enter the Atlassian API endpoint [$profileName.atlassian.net]"
        if ([string]::IsNullOrWhiteSpace($endpoint)) {
            $endpoint = "$profileName.atlassian.net"
        }
    }
    $endpoint = $endpoint.Trim().ToLower()
    $env:AtlassianPowerKit_ENDPOINT = $endpoint
    
    if ($env:AtlassianPowerKit_UserName) {
        $userName = $env:AtlassianPowerKit_UserName
    } else {
        $userName = Read-Host -Prompt "Enter the Atlassian user name for profile '$profileName' [$profileName@$endpoint]"
        if ([string]::IsNullOrWhiteSpace($userName)) {
            $userName = "$profileName@$endpoint"
        }
    }
    $userName = $userName.Trim().ToLower()
    $env:AtlassianPowerKit_UserName = $userName

    try {
        $apiKey = Get-Content '/run/secrets/api_key'
    } catch {
        Write-Debug 'No API key found in /run/secrets/api_key, prompting checking for environment variable'
        if ($env:AtlassianPowerKit_APIKey) {
            $apiKey = $env:AtlassianPowerKit_APIKey
        } else {
            $apiKey = Read-Host -Prompt "Enter the Atlassian API key for profile '$profileName'"
        }
    }
    $authString = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${userName}:$apiKey"))
    $env:AtlassianPowerKit_AtlassianAPIAuthString = $authString
    $HEADERS = @{
        Authorization = "Basic $($env:AtlassianPowerKit_AtlassianAPIAuthString)"
        Accept        = 'application/json'
    }
    $env:AtlassianPowerKit_AtlassianAPIHeaders = $HEADERS | ConvertTo-Json -Compress
    try {
        $cloudId = $(Invoke-RestMethod -Uri "https://$endpoint/_edge/tenant_info").cloudId
        $env:AtlassianPowerKit_CloudID = $cloudId
        Write-Debug "Cloud ID for profile '$profileName' is: $cloudId"
        Write-Debug "`n✅ Profile connection test succeeded for $env:AtlassianPowerKit_PROFILE_NAME."
    } catch {
        Write-Warning "`n❌ Connection test failed: $_"
        return $false
    }
    return $true
}

function AtlassianPowerKit {
    param (
        [Parameter(Mandatory = $false)]
        [switch]$Reload,
        [Parameter(Mandatory = $false)]
        [switch]$ArchiveProfileDirs,
        [Parameter(Mandatory = $false)]
        [string]$FunctionName,
        [Parameter(Mandatory = $false)]
        [hashtable]$FunctionParameters,
        [Parameter(Mandatory = $false)]
        [switch]$DocFunctions = $false,
        [Parameter(Mandatory = $false)]
        [switch]$ExitOSM = $false
    )
    if (!$env:AtlassianPowerKit_RequisiteModules) {
        $env:AtlassianPowerKit_RequisiteModules = Get-RequisitePowerKitModules
        Write-Debug 'AtlassianPowerKit_RequisiteModules - Required modules imported'
    }
    $NESTED_MODULES = Import-NestedModules -NESTED_MODULES @('AtlassianPowerKit-Shared', 'AtlassianPowerKit-Jira', 'AtlassianPowerKit-Confluence', 'AtlassianPowerKit-GRCosm', 'AtlassianPowerKit-JSM', 'AtlassianPowerKit-UsersAndGroups', 'AtlassianPowerKit-Admin')
    #Push-Location -Path $PSScriptRoot -ErrorAction Continue
    Write-Debug "Starting AtlassianPowerKit, running from $((Get-Item -Path $PSScriptRoot).FullName)"
    #Write-Debug 'OSM Directories: '
    if ($Reload) {
        Write-Debug '-Reload flagged, clearing the AtlassianPowerKit envars'
        Clear-AtlassianPowerKitProfile | Write-Debug
    }
    foreach ($OSM_DIR in Confirm-OSMDirs) {
        Get-Item -Path "$OSM_DIR" | Write-Debug
    }
    # If current directory is not the script root, push the script root to the stack
    if ($ArchiveProfileDirs) {
        Write-Debug '-ArchiveProfileDirs flagged, Clearing the AtlassianPowerKit profile directories, ignoring any other parameters'
        Clear-AtlassianPowerKitProfileDirs | Write-Debug
        return $true
    } elseif ($DocFunctions) {
        Write-Debug '-DocFunctions flagged, Creating a markdown document of all AtlassianPowerKit functions, ignoring any other parameters'
        Update-OSMPKFunctionsMarkDownDoc -NESTED_MODULES $NESTED_MODULES
        return $true
    }
    Write-Debug 'Loading AtlassianPowerKit profile'
    $PROFILE_STATUS = Initialize-AtlassianPowerKitProfile
    if (-not $PROFILE_STATUS) {
        Write-Error 'Failed to initialize AtlassianPowerKit profile. Exiting.'
        return $false
    } else {
        Write-Debug 'Profile set to: '
        @(
            "Profile Name: $env:AtlassianPowerKit_PROFILE_NAME",
            "Endpoint: $env:AtlassianPowerKit_ENDPOINT",
            "User Name: $env:AtlassianPowerKit_UserName",
            "Cloud ID: $env:AtlassianPowerKit_CloudID"
        ) | ForEach-Object { Write-Debug $_ }
        if (!$FunctionName) {
            $FunctionName = Show-AtlassianPowerKitFunctions -NESTED_MODULES $NESTED_MODULES
        }
        #Write-Debug "Function selected: $FunctionName"
        if ($FunctionParameters) {
            Write-Debug '-FunctionParameters provided !'
            if ($FunctionParameters.GetType() -ne [hashtable]) {
                Write-Debug '-@{ key1 = 'value1'; key2 = 'value2' }'
                throw 'Function parameters must be a hashtable. Exiting.'
            }
            # Iterate through the hashtable and display the key value pairs as "-key value"
            $FunctionParameters.GetEnumerator() | ForEach-Object {
                Write-Debug "       -$($_.Key) $_.Value"
            }
            $RET_VAL = Invoke-AtlassianPowerKitFunction -FunctionName $FunctionName -FunctionParameters $FunctionParameters
            Write-Debug "AtlassianPowerKit Main: Received JSON of size: $($RETURN_JSON.Length) characters"
        } elseif ($FunctionName) {
            Write-Debug "$($MyInvocation.InvocationName) attempting to run function: $FunctionName without parameters - most functions will handle this by requesting user input"
            $RET_VAL = Invoke-AtlassianPowerKitFunction -FunctionName $FunctionName

        }
    }
    if (!$RET_VAL) {
        Write-Output 'Nothing to return, have a nice day.'
    } else {      
        return $RET_VAL
    }
    $ret_neg = -join ($ret_pos.ToCharArray() | ForEach-Object { $_ })[-1..0]
    Write-Debug "AtlassianPowerKit Main: Received JSON of size: $($RETURN_JSON.Length) characters"
    Write-Output 'AtlassianPowerKit Main - DONE!!!'; Get-ClosureOut($ret_neg, $ret_pos)
}
    