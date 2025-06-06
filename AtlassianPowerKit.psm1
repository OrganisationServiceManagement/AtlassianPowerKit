$ErrorActionPreference = 'Stop'; $DebugPreference = 'Continue'
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
function New-AtlassianPowerKitProfile {
    param (
        [Parameter(Mandatory = $false)]
        [string]$PROFILE_NAME = $null
    )
    if (!$PROFILE_NAME) {
        $PROFILE_NAME = Read-Host -Prompt 'Enter a name for the new profile'
    }
    $PROFILE_NAME = $PROFILE_NAME.Trim().ToLower()
    $API_ENDPOINT = Read-Host -Prompt 'Enter the Atlassian API endpoint (e.g. https://your-domain.atlassian.net)'
    $API_CREDPAIR = Get-Credential -Message 'Enter your Atlassian API credentials (email and API token)'
    $REGISTERED_PROFILE = Register-AtlassianPowerKitProfileInVault -ProfileName $PROFILE_NAME -AtlassianAPIEndpoint $API_ENDPOINT -AtlassianAPICredentialPair $API_CREDPAIR
    $ENVAR_ARRAY = Import-AtlassianPowerKitProfile -selectedProfile $REGISTERED_PROFILE
    return $ENVAR_ARRAY

}
# Function to list availble profiles with number references for interactive selection or 'N' to create a new profile
function Import-AtlassianPowerKitProfile {
    param (
        [Parameter(Mandatory = $false)]
        [switch]$NoVault = $false,
        [Parameter(Mandatory = $false)]
        [string]$selectedProfile = $false
    )
    if ($NoVault) {
        #Write-Debug "$($MyInvocation.InvocationName) -NoVault flag set, attempting to load profile from environment variables"
        $ENVAR_ARRAY = Set-AtlassianPowerKitProfile -NoVault
    } elseif ($selectedProfile -ne $false) {
        #Write-Debug "$($MyInvocation.InvocationName) -ProfileName profided, attempting to load profile: $selectedProfile from the vault"
        $ENVAR_ARRAY = Set-AtlassianPowerKitProfile -ProfileName $selectedProfile
        if (!$ENVAR_ARRAY -or $ENVAR_ARRAY.Count -lt 3) {
            Write-Host "Could not load profile: $selectedProfile from the vault. Requesting values to add it to vault."
            $ENVAR_ARRAY = New-AtlassianPowerKitProfile -PROFILE_NAME $selectedProfile
        }
    } else {
        #Write-Debug "$($MyInvocation.InvocationName) -NoVault flag not set and no profile selected, checking for existing profiles in the vault"
        $VAULT_PROFILES = Get-AtlassianPowerKitProfileList
        if ($VAULT_PROFILES) {
            if ($VAULT_PROFILES.Count -eq 1) {
                $selectedProfile = $VAULT_PROFILES[0]
                Write-Debug "Only one profile found in the vault, selecting $selectedProfile"
                $ENVAR_ARRAY = Set-AtlassianPowerKitProfile -ProfileName $selectedProfile
            } else {
                Write-Output 'Multiple profiles found in the vault but no profile provided, please use the -OSMProfile parameter to specify the desired profile'
                foreach ($OSMProfileNAME in $VAULT_PROFILES) {
                    Write-Output "      AtlassianPowerkit -OSMProfileNAME $OSMProfileNAME"
                }
                Throw 'Ambiguous profile state'
            }
        } else {
            Write-Output 'No profiles found in the vault, please create a new profile.'
            $ENVAR_ARRAY = New-AtlassianPowerKitProfile
        }
    }
    return $ENVAR_ARRAY
}

function AtlassianPowerKit {
    param (
        [Parameter(Mandatory = $false)]
        [string]$OSMProfile,
        [Parameter(Mandatory = $false)]
        [switch]$ArchiveProfileDirs,
        [Parameter(Mandatory = $false)]
        [switch]$ResetVault,
        [Parameter(Mandatory = $false)]
        [string]$FunctionName,
        [Parameter(Mandatory = $false)]
        [hashtable]$FunctionParameters,
        [Parameter(Mandatory = $false)]
        [switch]$ClearProfile,
        [Parameter(Mandatory = $false)]
        [switch]$ListProfiles,
        [Parameter(Mandatory = $false)]
        [switch]$NoVault = $false,
        [Parameter(Mandatory = $false)]
        [string]$RemoveVaultProfile = $false,
        [Parameter(Mandatory = $false)]
        [switch]$NewVaultProfile = $false,
        [Parameter(Mandatory = $false)]
        [switch]$DocFunctions = $false
    )
    if (!$env:AtlassianPowerKit_RequisiteModules) {
        $env:AtlassianPowerKit_RequisiteModules = Get-RequisitePowerKitModules
        Write-Debug 'AtlassianPowerKit_RequisiteModules - Required modules imported'
    }
    $NESTED_MODULES = Import-NestedModules -NESTED_MODULES @('AtlassianPowerKit-Shared', 'AtlassianPowerKit-Jira', 'AtlassianPowerKit-Confluence', 'AtlassianPowerKit-GRCosm', 'AtlassianPowerKit-JSM', 'AtlassianPowerKit-UsersAndGroups', 'AtlassianPowerKit-Admin')
    try {
        #Push-Location -Path $PSScriptRoot -ErrorAction Continue
        Write-Debug "Starting AtlassianPowerKit, running from $((Get-Item -Path $PSScriptRoot).FullName)"
        #Write-Debug 'OSM Directories: '
        foreach ($OSM_DIR in Confirm-OSMDirs) {
            Get-Item -Path "$OSM_DIR" | Write-Debug
        }
        # If current directory is not the script root, push the script root to the stack
        if ($ResetVault) {
            Write-Debug '-ResetVault flagged Clearing the AtlassianPowerKit vault, ignoring any other parameters'
            Clear-AtlassianPowerKitVault | Write-Debug
            return $true
        } elseif ($ListProfiles) {
            Write-Debug '$ListProfiles flaged, Listing AtlassianPowerKit profiles, ignoring any other parameters'
            $PROFILE_LIST = Get-AtlassianPowerKitProfileList
            return $PROFILE_LIST
        } elseif ($ArchiveProfileDirs) {
            Write-Debug '-ArchiveProfileDirs flagged, Clearing the AtlassianPowerKit profile directories, ignoring any other parameters'
            Clear-AtlassianPowerKitProfileDirs | Write-Debug
            return $true
        } elseif ($ClearProfile) {
            Write-Debug '-ClearProfile flagged, Clearing the AtlassianPowerKit profile, ignoring any other parameters'
            Clear-AtlassianPowerKitProfile | Write-Debug
            return $true
        } elseif ($RemoveVaultProfile -ne $false) {
            Write-Debug '-RemoveVaultProfile flagged, Removing the AtlassianPowerKit profile from the vault, ignoring any other parameters'
            Remove-AtlassianPowerKitProfile -ProfileName $RemoveVaultProfile | Write-Debug
            return $true
        } elseif ($DocFunctions) {
            Write-Debug '-DocFunctions flagged, Creating a markdown document of all AtlassianPowerKit functions, ignoring any other parameters'
            Update-OSMPKFunctionsMarkDownDoc -NESTED_MODULES $NESTED_MODULES
            return $true
        } elseif ($NewVaultProfile) {
            Write-Debug '-NewVaultProfile flagged, Creating a new AtlassianPowerKit profile in the vault, ignoring any other parameters'
            New-AtlassianPowerKitProfile | Write-Debug
            return $true
        } elseif ($NoVault) {
            Write-Debug '-NoVault flagged, attempting to load profile from environment variables'
            $PROFILE_ARRAY = Import-AtlassianPowerKitProfile -NoVault 
        } elseif ($OSMProfile) {
            Write-Debug "Profile provided: $OSMProfile"
            $ProfileName = $OSMProfile.Trim().ToLower()
            $PROFILE_ARRAY = Import-AtlassianPowerKitProfile -selectedProfile $ProfileName
        } else {
            Write-Debug 'No profile provided, checking if vault has only 1 profile'
            $PROFILE_ARRAY = Import-AtlassianPowerKitProfile
        }
        Write-Debug "Profile set to: $env:AtlassianPowerKit_PROFILE_NAME"
        $PROFILE_ARRAY | ForEach-Object {
            Write-Output "   $_" | Out-Null
        }
        if (!$FunctionName) {
            $FunctionName = Show-AtlassianPowerKitFunctions -NESTED_MODULES $NESTED_MODULES
        }
        #Write-Debug "Function selected: $FunctionName"
        if ($FunctionParameters) {
            Write-Debug '-FunctionParameters provided !'
            if ($FunctionParameters.GetType() -ne [hashtable]) {
                Write-Debug '-FunctionParameters must be a hashtable, e.g.:' 
                Write-Debug '    @{ key1 = "value1"; key2 = "value2" }'
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
    } catch {
        # Write call stack and sub-function error messages to the debug output
        Write-Debug "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ $((Get-Item -Path $PSScriptRoot).FullName) $($MyInvocation.InvocationName) FAILED: "
        # Write full call stack to the debug output and error message to the console
        Get-PSCallStack
        Write-Debug "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ $((Get-Item -Path $PSScriptRoot).FullName) $($MyInvocation.InvocationName)"
        Write-Error $_.Exception.Message
    }
    if (!$RET_VAL) {
        Write-Output 'Nothing to return, have a nice day.'
    } else {      
        return $RET_VAL
    }
}