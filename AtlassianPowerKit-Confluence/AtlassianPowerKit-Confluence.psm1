$ErrorActionPreference = 'Stop'; $DebugPreference = 'Continue'

function Invoke-ConfluenceRestGetWithRetry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [uri]$Uri,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Headers,
        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 10)]
        [int]$MaximumRetryCount = 4,
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 300)]
        [int]$MaximumBackoffSeconds = 30
    )

    $retryCount = 0
    while ($true) {
        try {
            # Disable cmdlet debug output because it can include Authorization headers.
            return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method Get -Debug:$false
        } catch {
            $requestError = $_
            $response = $requestError.Exception.Response
            $statusCode = if ($null -ne $response) {
                try { [int]$response.StatusCode } catch { $null }
            } else {
                $null
            }

            $retryAfterSeconds = $null
            if ($null -ne $response -and $null -ne $response.Headers) {
                $retryAfter = $null
                try {
                    $retryAfter = $response.Headers['Retry-After']
                } catch {
                    # HttpResponseHeaders does not expose its values through an indexer on every PowerShell version.
                }

                if ($null -ne $response.Headers.PSObject.Properties['RetryAfter']) {
                    $typedRetryAfter = $response.Headers.RetryAfter
                    if ($null -ne $typedRetryAfter) {
                        if ($null -ne $typedRetryAfter.Delta) {
                            $retryAfterSeconds = [math]::Max(0, [math]::Ceiling($typedRetryAfter.Delta.TotalSeconds))
                        } elseif ($null -ne $typedRetryAfter.Date) {
                            $retryAfterSeconds = [math]::Max(0, [math]::Ceiling(($typedRetryAfter.Date - [DateTimeOffset]::UtcNow).TotalSeconds))
                        }
                    }
                }

                if ($null -eq $retryAfterSeconds -and $null -ne $retryAfter) {
                    $retryAfterText = [string](@($retryAfter)[0])
                    [double]$retryAfterNumber = 0
                    if ([double]::TryParse($retryAfterText, [Globalization.NumberStyles]::Number, [Globalization.CultureInfo]::InvariantCulture, [ref]$retryAfterNumber)) {
                        $retryAfterSeconds = [math]::Max(0, [math]::Ceiling($retryAfterNumber))
                    } else {
                        [DateTimeOffset]$retryAfterDate = [DateTimeOffset]::MinValue
                        if ([DateTimeOffset]::TryParse($retryAfterText, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$retryAfterDate)) {
                            $retryAfterSeconds = [math]::Max(0, [math]::Ceiling(($retryAfterDate - [DateTimeOffset]::UtcNow).TotalSeconds))
                        }
                    }
                }
            }

            $isRateLimited = $statusCode -eq 429
            $isRetryableServiceUnavailable = $statusCode -eq 503 -and $null -ne $retryAfterSeconds
            if ((-not $isRateLimited -and -not $isRetryableServiceUnavailable) -or $retryCount -ge $MaximumRetryCount) {
                throw $requestError
            }

            $retryCount++
            $baseDelaySeconds = if ($null -ne $retryAfterSeconds) {
                # Retry-After is authoritative and is not capped by the local exponential-backoff ceiling.
                [double]$retryAfterSeconds
            } else {
                [math]::Min([double]$MaximumBackoffSeconds, 5.0 * [math]::Pow(2, $retryCount - 1))
            }
            $jitterSeconds = $baseDelaySeconds * 0.2 * [System.Random]::new().NextDouble()
            $delayMilliseconds = [long][math]::Ceiling(($baseDelaySeconds + $jitterSeconds) * 1000)

            Write-Warning "Confluence returned HTTP $statusCode for '$Uri'. Retrying in $([math]::Round($delayMilliseconds / 1000, 3)) seconds (retry $retryCount of $MaximumRetryCount)."
            Start-Sleep -Milliseconds $delayMilliseconds
        }
    }
}

function Export-ConfluenceSpacePagesToRichHtml {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$CONFLUENCE_SPACE_KEY,
        [Parameter(Mandatory = $false)]
        [ValidateSet('view', 'atlas_doc_format', 'storage')]
        [string]$CONFLUENCE_PAGE_FORMAT = 'view',
        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 10)]
        [int]$CONFLUENCE_MAX_RETRY_COUNT = 4,
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 300)]
        [int]$CONFLUENCE_MAX_BACKOFF_SECONDS = 30
    )

    $requiredEnvironmentVariables = @(
        'OSM_HOME'
        'AtlassianPowerKit_PROFILE_NAME'
        'AtlassianPowerKit_ENDPOINT'
        'AtlassianPowerKit_AtlassianAPIHeaders'
    )
    $missingEnvironmentVariables = $requiredEnvironmentVariables | Where-Object {
        [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($_, 'Process'))
    }
    if ($missingEnvironmentVariables) {
        throw "Missing required environment variable(s): $($missingEnvironmentVariables -join ', ')."
    }

    try {
        $requestHeaders = ConvertFrom-Json -InputObject $env:AtlassianPowerKit_AtlassianAPIHeaders -AsHashtable
    } catch {
        throw "AtlassianPowerKit_AtlassianAPIHeaders is not valid JSON: $($_.Exception.Message)"
    }
    if ($requestHeaders -isnot [System.Collections.IDictionary]) {
        throw 'AtlassianPowerKit_AtlassianAPIHeaders must contain a JSON object.'
    }

    $configuredEndpoint = $env:AtlassianPowerKit_ENDPOINT.Trim().TrimEnd('/')
    $baseUri = if ($configuredEndpoint -match '^https?://') {
        [uri]$configuredEndpoint
    } else {
        [uri]"https://$configuredEndpoint"
    }
    if ($baseUri.Scheme -ne 'https' -or [string]::IsNullOrWhiteSpace($baseUri.Host) -or $baseUri.UserInfo) {
        throw 'AtlassianPowerKit_ENDPOINT must be an HTTPS URI or hostname without embedded credentials.'
    }

    $encodedSpaceKey = [uri]::EscapeDataString($CONFLUENCE_SPACE_KEY)
    $spaceEndpoint = [uri]::new($baseUri, "/wiki/api/v2/spaces?keys=$encodedSpaceKey&limit=2")
    try {
        $spaceResponse = Invoke-ConfluenceRestGetWithRetry -Uri $spaceEndpoint -Headers $requestHeaders -MaximumRetryCount $CONFLUENCE_MAX_RETRY_COUNT -MaximumBackoffSeconds $CONFLUENCE_MAX_BACKOFF_SECONDS
    } catch {
        $statusCode = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { $null }
        $statusText = if ($null -ne $statusCode) { " (HTTP $statusCode)" } else { '' }
        throw "Failed to resolve Confluence space '$CONFLUENCE_SPACE_KEY'${statusText}: $($_.Exception.Message)"
    }

    $matchingSpaces = @($spaceResponse.results | Where-Object { $_.key -eq $CONFLUENCE_SPACE_KEY })
    if ($matchingSpaces.Count -eq 0) {
        throw "Confluence space '$CONFLUENCE_SPACE_KEY' was not found or is not visible to the authenticated user."
    }
    if ($matchingSpaces.Count -gt 1) {
        throw "Confluence returned multiple spaces for key '$CONFLUENCE_SPACE_KEY'."
    }

    $spaceId = [string]$matchingSpaces[0].id
    $pages = [System.Collections.Generic.List[object]]::new()
    $nextUri = [uri]::new($baseUri, "/wiki/api/v2/spaces/$spaceId/pages?limit=250")

    try {
        while ($null -ne $nextUri) {
            Write-Debug "Retrieving Confluence pages from: $nextUri"
            $pageResponse = Invoke-ConfluenceRestGetWithRetry -Uri $nextUri -Headers $requestHeaders -MaximumRetryCount $CONFLUENCE_MAX_RETRY_COUNT -MaximumBackoffSeconds $CONFLUENCE_MAX_BACKOFF_SECONDS
            foreach ($page in @($pageResponse.results)) {
                [void]$pages.Add($page)
            }

            $nextLink = [string]$pageResponse._links.next
            $nextUri = if ([string]::IsNullOrWhiteSpace($nextLink)) {
                $null
            } else {
                [uri]::new($baseUri, $nextLink)
            }
        }
    } catch {
        $statusCode = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { $null }
        $statusText = if ($null -ne $statusCode) { " (HTTP $statusCode)" } else { '' }
        throw "Failed to list pages in Confluence space '$CONFLUENCE_SPACE_KEY'${statusText}: $($_.Exception.Message)"
    }

    Write-Debug "Found $($pages.Count) pages in space '$CONFLUENCE_SPACE_KEY'."
    $pageTitleById = @{}
    foreach ($spacePage in $pages) {
        if (-not [string]::IsNullOrWhiteSpace([string]$spacePage.id) -and
            -not [string]::IsNullOrWhiteSpace([string]$spacePage.title)) {
            $pageTitleById[[string]$spacePage.id] = [string]$spacePage.title
        }
    }

    $exportResults = [System.Collections.Generic.List[object]]::new()
    foreach ($page in $pages) {
        $exportParameters = @{
            CONFLUENCE_SPACE_ID        = $spaceId
            CONFLUENCE_SPACE_KEY       = $CONFLUENCE_SPACE_KEY
            CONFLUENCE_PAGE_ID         = [string]$page.id
            CONFLUENCE_PAGE_FORMAT     = $CONFLUENCE_PAGE_FORMAT
            CONFLUENCE_PAGE_TITLE_BY_ID = $pageTitleById
            CONFLUENCE_MAX_RETRY_COUNT = $CONFLUENCE_MAX_RETRY_COUNT
            CONFLUENCE_MAX_BACKOFF_SECONDS = $CONFLUENCE_MAX_BACKOFF_SECONDS
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$page.parentId)) {
            $exportParameters.PARENT_PAGE_ID = [string]$page.parentId
        }

        $exportResult = Export-ConfluencePage @exportParameters | ConvertFrom-Json
        [void]$exportResults.Add($exportResult)
    }

    $outputDirectory = Join-Path -Path $env:OSM_HOME -ChildPath $env:AtlassianPowerKit_PROFILE_NAME
    $outputDirectory = Join-Path -Path $outputDirectory -ChildPath 'CONFLUENCE'
    $outputDirectory = Join-Path -Path $outputDirectory -ChildPath $CONFLUENCE_SPACE_KEY
    $exportedCount = @($exportResults | Where-Object { $_.EXPORT_STATUS -eq 'Exported' }).Count
    $skippedCount = @($exportResults | Where-Object { $_.EXPORT_STATUS -eq 'SkippedCurrentVersion' }).Count
    $relocatedCount = @($exportResults | Where-Object { $_.EXPORT_STATUS -eq 'RelocatedCurrentVersion' }).Count
    $archivedCount = @($exportResults | ForEach-Object { @($_.ARCHIVED_FILES).Count } | Measure-Object -Sum).Sum
    if ($null -eq $archivedCount) {
        $archivedCount = 0
    }
    Write-Debug "Processed $($exportResults.Count) pages from space '$CONFLUENCE_SPACE_KEY': exported $exportedCount, skipped $skippedCount, relocated $relocatedCount, archived $archivedCount deprecated files. Output: '$outputDirectory'."

    $exportResultsArray = [object[]]$exportResults
    return ConvertTo-Json -InputObject $exportResultsArray -Depth 10
}

function Convert-PageIDToTitle {
    param (
        [Parameter(Mandatory = $true)]
        [string]$CONFLUENCE_PAGE_ID
    )
    $PAGE = Get-ConfluencePageByID -CONFLUENCE_PAGE_ID $CONFLUENCE_PAGE_ID
    if ($PAGE) {
        return $PAGE.title
    } else {
        Write-Debug "Page ID: $CONFLUENCE_PAGE_ID not found in space: $CONFLUENCE_SPACE_KEY"
        return $null
    }
}

function Export-ConfluencePage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$CONFLUENCE_SPACE_KEY,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^\d+$')]
        [string]$CONFLUENCE_PAGE_ID,
        [Parameter(Mandatory = $false)]
        [ValidateSet('view', 'atlas_doc_format', 'storage')]
        [string]$CONFLUENCE_PAGE_FORMAT = 'view',
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [ValidateScript({ [string]::IsNullOrEmpty($_) -or $_ -match '^\d+$' })]
        [string]$PARENT_PAGE_ID,
        [Parameter(Mandatory = $false)]
        [ValidatePattern('^\d+$')]
        [string]$CONFLUENCE_SPACE_ID,
        [Parameter(Mandatory = $false, DontShow = $true)]
        [System.Collections.IDictionary]$CONFLUENCE_PAGE_TITLE_BY_ID,
        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 10)]
        [int]$CONFLUENCE_MAX_RETRY_COUNT = 4,
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 300)]
        [int]$CONFLUENCE_MAX_BACKOFF_SECONDS = 30
    )

    $requiredEnvironmentVariables = @(
        'OSM_HOME'
        'AtlassianPowerKit_PROFILE_NAME'
        'AtlassianPowerKit_ENDPOINT'
        'AtlassianPowerKit_AtlassianAPIHeaders'
    )
    $missingEnvironmentVariables = $requiredEnvironmentVariables | Where-Object {
        [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($_, 'Process'))
    }
    if ($missingEnvironmentVariables) {
        throw "Missing required environment variable(s): $($missingEnvironmentVariables -join ', ')."
    }

    try {
        $requestHeaders = ConvertFrom-Json -InputObject $env:AtlassianPowerKit_AtlassianAPIHeaders -AsHashtable
    } catch {
        throw "AtlassianPowerKit_AtlassianAPIHeaders is not valid JSON: $($_.Exception.Message)"
    }
    if ($requestHeaders -isnot [System.Collections.IDictionary]) {
        throw 'AtlassianPowerKit_AtlassianAPIHeaders must contain a JSON object.'
    }

    $configuredEndpoint = $env:AtlassianPowerKit_ENDPOINT.Trim().TrimEnd('/')
    $baseUri = if ($configuredEndpoint -match '^https?://') {
        [uri]$configuredEndpoint
    } else {
        [uri]"https://$configuredEndpoint"
    }
    if ($baseUri.Scheme -ne 'https' -or [string]::IsNullOrWhiteSpace($baseUri.Host) -or $baseUri.UserInfo) {
        throw 'AtlassianPowerKit_ENDPOINT must be an HTTPS URI or hostname without embedded credentials.'
    }
    $encodedPageId = [uri]::EscapeDataString($CONFLUENCE_PAGE_ID)
    $pageEndpoint = [uri]::new($baseUri, "/wiki/api/v2/pages/${encodedPageId}?body-format=${CONFLUENCE_PAGE_FORMAT}&include-version=true")

    Write-Debug "Exporting Confluence page '$CONFLUENCE_PAGE_ID' in '$CONFLUENCE_PAGE_FORMAT' format from '$pageEndpoint'."
    try {
        $restResults = Invoke-ConfluenceRestGetWithRetry -Uri $pageEndpoint -Headers $requestHeaders -MaximumRetryCount $CONFLUENCE_MAX_RETRY_COUNT -MaximumBackoffSeconds $CONFLUENCE_MAX_BACKOFF_SECONDS
    } catch {
        $statusCode = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { $null }
        $statusText = if ($null -ne $statusCode) { " (HTTP $statusCode)" } else { '' }
        throw "Failed to retrieve Confluence page '$CONFLUENCE_PAGE_ID'${statusText}: $($_.Exception.Message)"
    }

    if ($CONFLUENCE_SPACE_ID -and $restResults.spaceId -and ([string]$restResults.spaceId -ne $CONFLUENCE_SPACE_ID)) {
        throw "Confluence page '$CONFLUENCE_PAGE_ID' belongs to space ID '$($restResults.spaceId)', not '$CONFLUENCE_SPACE_ID'."
    }
    if ([string]::IsNullOrWhiteSpace([string]$restResults.title)) {
        throw "Confluence returned no title for page '$CONFLUENCE_PAGE_ID'."
    }
    [long]$pageVersion = 0
    if (-not [long]::TryParse([string]$restResults.version.number, [ref]$pageVersion) -or $pageVersion -lt 1) {
        throw "Confluence returned no valid current version number for page '$CONFLUENCE_PAGE_ID'."
    }

    $bodyRepresentation = switch ($CONFLUENCE_PAGE_FORMAT) {
        'view' { $restResults.body.view; break }
        'atlas_doc_format' { $restResults.body.atlas_doc_format; break }
        'storage' { $restResults.body.storage; break }
    }
    $bodyValueProperty = if ($null -ne $bodyRepresentation) {
        $bodyRepresentation.PSObject.Properties['value']
    } else {
        $null
    }
    $sourceBodyFormat = $CONFLUENCE_PAGE_FORMAT

    if ($null -eq $bodyValueProperty -and $CONFLUENCE_PAGE_FORMAT -eq 'view') {
        Write-Debug "Confluence REST v2 did not return body.view.value for page '$CONFLUENCE_PAGE_ID'; trying body.export_view through content search."
        $encodedCql = [uri]::EscapeDataString("id = $CONFLUENCE_PAGE_ID")
        $exportViewEndpoint = [uri]::new($baseUri, "/wiki/rest/api/content/search?cql=${encodedCql}&expand=body.export_view&limit=1")

        try {
            $exportViewResponse = Invoke-ConfluenceRestGetWithRetry -Uri $exportViewEndpoint -Headers $requestHeaders -MaximumRetryCount $CONFLUENCE_MAX_RETRY_COUNT -MaximumBackoffSeconds $CONFLUENCE_MAX_BACKOFF_SECONDS
            $exportViewResult = @($exportViewResponse.results | Where-Object { [string]$_.id -eq $CONFLUENCE_PAGE_ID }) | Select-Object -First 1
            if ($null -eq $exportViewResult) {
                throw 'The content search response did not contain the requested page.'
            }
            $bodyRepresentation = $exportViewResult.body.export_view
            $bodyValueProperty = if ($null -ne $bodyRepresentation) {
                $bodyRepresentation.PSObject.Properties['value']
            } else {
                $null
            }
            if ($null -eq $bodyValueProperty) {
                Write-Debug "The export_view response also contained no value for page '$CONFLUENCE_PAGE_ID'; treating it as a valid blank page."
                $bodyValueProperty = [pscustomobject]@{ Value = '' }
            }
            $sourceBodyFormat = 'export_view'
        } catch {
            throw "Confluence returned no body.view.value for page '$CONFLUENCE_PAGE_ID', and the export_view fallback failed: $($_.Exception.Message)"
        }
    }

    if ($null -eq $bodyValueProperty) {
        $availableBodyFormats = @($restResults.body.PSObject.Properties.Name) -join ', '
        if ([string]::IsNullOrWhiteSpace($availableBodyFormats)) {
            $availableBodyFormats = 'none'
        }
        throw "Confluence returned no '$CONFLUENCE_PAGE_FORMAT' representation for page '$CONFLUENCE_PAGE_ID'. Available body formats: $availableBodyFormats."
    }

    # An existing representation with an empty value is a valid blank Confluence page.
    $pageContent = if ($null -eq $bodyValueProperty.Value) { '' } else { $bodyValueProperty.Value }

    $makeSafeFileName = {
        param (
            [string]$Name,
            [string]$Fallback
        )

        $safeName = ($Name -replace '[<>:"/\\|?*\x00-\x1F]', '_').Trim().TrimEnd('.')
        if ([string]::IsNullOrWhiteSpace($safeName)) {
            $safeName = $Fallback
        }
        if ($safeName.Length -gt 120) {
            $safeName = $safeName.Substring(0, 120).TrimEnd().TrimEnd('.')
        }
        if ($safeName -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') {
            $safeName = "_$safeName"
        }
        return $safeName
    }

    $spaceOutputDirectory = Join-Path -Path $env:OSM_HOME -ChildPath $env:AtlassianPowerKit_PROFILE_NAME
    $spaceOutputDirectory = Join-Path -Path $spaceOutputDirectory -ChildPath 'CONFLUENCE'
    $spaceOutputDirectory = Join-Path -Path $spaceOutputDirectory -ChildPath (& $makeSafeFileName $CONFLUENCE_SPACE_KEY 'space')
    $archiveRoot = Join-Path -Path $spaceOutputDirectory -ChildPath 'Archive'
    $fileExtension = switch ($CONFLUENCE_PAGE_FORMAT) {
        'view' { 'html'; break }
        'atlas_doc_format' { 'json'; break }
        'storage' { 'xml'; break }
    }

    $outputDirectory = $spaceOutputDirectory
    $ancestorChain = [System.Collections.Generic.List[object]]::new()
    $ancestorIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $ancestorRequestSucceeded = $false
    $nextAncestorUri = [uri]::new($baseUri, "/wiki/api/v2/pages/$encodedPageId/ancestors?limit=250")
    $requestedAncestorUris = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    try {
        while ($null -ne $nextAncestorUri) {
            if (-not $requestedAncestorUris.Add($nextAncestorUri.AbsoluteUri)) {
                throw "Confluence returned a cyclic ancestor pagination link: $nextAncestorUri"
            }

            $ancestorResponse = Invoke-ConfluenceRestGetWithRetry -Uri $nextAncestorUri -Headers $requestHeaders -MaximumRetryCount $CONFLUENCE_MAX_RETRY_COUNT -MaximumBackoffSeconds $CONFLUENCE_MAX_BACKOFF_SECONDS
            foreach ($ancestor in @($ancestorResponse.results)) {
                $ancestorId = [string]$ancestor.id
                if (-not [string]::IsNullOrWhiteSpace($ancestorId) -and $ancestorIds.Add($ancestorId)) {
                    [void]$ancestorChain.Add($ancestor)
                }
            }

            $nextAncestorLink = [string]$ancestorResponse._links.next
            $nextAncestorUri = if ([string]::IsNullOrWhiteSpace($nextAncestorLink)) {
                $null
            } else {
                [uri]::new($baseUri, $nextAncestorLink)
            }
        }
        $ancestorRequestSucceeded = $true
    } catch {
        Write-Warning "Could not retrieve the complete ancestor chain for page '$CONFLUENCE_PAGE_ID'; falling back to the supplied parent when available. $($_.Exception.Message)"
    }

    if (-not $ancestorRequestSucceeded -and
        -not [string]::IsNullOrWhiteSpace($PARENT_PAGE_ID) -and
        $PARENT_PAGE_ID -ne '0') {
        [void]$ancestorChain.Add([pscustomobject]@{ id = $PARENT_PAGE_ID; type = 'page' })
    }

    $ancestorResourceSegments = @{
        page       = 'pages'
        folder     = 'folders'
        whiteboard = 'whiteboards'
        database   = 'databases'
        embed      = 'embeds'
    }
    $hierarchyDirectories = [System.Collections.Generic.List[string]]::new()
    foreach ($ancestor in $ancestorChain) {
        $ancestorId = [string]$ancestor.id
        $ancestorType = if ([string]::IsNullOrWhiteSpace([string]$ancestor.type)) {
            'page'
        } else {
            ([string]$ancestor.type).ToLowerInvariant()
        }
        $ancestorTitle = $null

        if ($ancestorType -eq 'page' -and
            $null -ne $CONFLUENCE_PAGE_TITLE_BY_ID -and
            $CONFLUENCE_PAGE_TITLE_BY_ID.Contains($ancestorId)) {
            $ancestorTitle = [string]$CONFLUENCE_PAGE_TITLE_BY_ID[$ancestorId]
        }

        if ([string]::IsNullOrWhiteSpace($ancestorTitle) -and $ancestorResourceSegments.ContainsKey($ancestorType)) {
            $ancestorResourceSegment = $ancestorResourceSegments[$ancestorType]
            $encodedAncestorId = [uri]::EscapeDataString($ancestorId)
            $ancestorDetailEndpoint = [uri]::new($baseUri, "/wiki/api/v2/$ancestorResourceSegment/$encodedAncestorId")
            try {
                $ancestorDetail = Invoke-ConfluenceRestGetWithRetry -Uri $ancestorDetailEndpoint -Headers $requestHeaders -MaximumRetryCount $CONFLUENCE_MAX_RETRY_COUNT -MaximumBackoffSeconds $CONFLUENCE_MAX_BACKOFF_SECONDS
                $ancestorTitle = if (-not [string]::IsNullOrWhiteSpace([string]$ancestorDetail.title)) {
                    [string]$ancestorDetail.title
                } else {
                    [string]$ancestorDetail.name
                }
            } catch {
                Write-Warning "Could not resolve the title for $ancestorType ancestor '$ancestorId'; using an ID-based folder. $($_.Exception.Message)"
            }
        }

        if ([string]::IsNullOrWhiteSpace($ancestorTitle)) {
            $ancestorTitle = "$ancestorType-$ancestorId"
        }
        $ancestorDirectoryName = & $makeSafeFileName "$ancestorTitle-$ancestorId" "$ancestorType-$ancestorId"
        $outputDirectory = Join-Path -Path $outputDirectory -ChildPath $ancestorDirectoryName
        [void]$hierarchyDirectories.Add($ancestorDirectoryName)
    }

    $pageTitleFileName = & $makeSafeFileName ([string]$restResults.title) "page-$CONFLUENCE_PAGE_ID"
    $outputFile = Join-Path -Path $outputDirectory -ChildPath "$pageTitleFileName-$CONFLUENCE_PAGE_ID-v$pageVersion.$fileExtension"

    $archivedFiles = [System.Collections.Generic.List[string]]::new()
    $currentVersionFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    if (Test-Path -LiteralPath $spaceOutputDirectory -PathType Container) {
        $escapedPageId = [regex]::Escape($CONFLUENCE_PAGE_ID)
        $versionedExportPattern = "-$escapedPageId-v(?<version>\d+)(?:-\d{8}-\d{9})?\.(?<extension>html|json|xml)$"
        $unversionedExportPattern = "-$escapedPageId-\d{8}-\d{9}\.(?<extension>html|json|xml)$"
        $archivePrefix = [System.IO.Path]::GetFullPath($archiveRoot).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
        $activePageExports = Get-ChildItem -LiteralPath $spaceOutputDirectory -Filter "*-$CONFLUENCE_PAGE_ID-*" -File -Recurse | Where-Object {
            -not $_.FullName.StartsWith($archivePrefix, [System.StringComparison]::OrdinalIgnoreCase)
        }

        foreach ($existingExport in $activePageExports) {
            $existingVersion = $null
            $existingExtension = $null
            $archiveVersionDirectory = $null

            if ($existingExport.Name -match $versionedExportPattern) {
                $existingVersion = [long]$Matches.version
                $existingExtension = $Matches.extension
                if ($existingVersion -eq $pageVersion) {
                    if ($existingExtension -eq $fileExtension) {
                        [void]$currentVersionFiles.Add($existingExport)
                    }
                    continue
                }
                if ($existingVersion -gt $pageVersion) {
                    Write-Warning "Export '$($existingExport.FullName)' has version $existingVersion, which is newer than Confluence version $pageVersion; leaving it in place."
                    continue
                }
                $archiveVersionDirectory = "v$existingVersion"
            } elseif ($existingExport.Name -match $unversionedExportPattern) {
                $archiveVersionDirectory = 'unversioned'
            } else {
                continue
            }

            $archiveDirectory = Join-Path -Path $archiveRoot -ChildPath $CONFLUENCE_PAGE_ID
            $archiveDirectory = Join-Path -Path $archiveDirectory -ChildPath $archiveVersionDirectory
            if (-not (Test-Path -LiteralPath $archiveDirectory -PathType Container)) {
                New-Item -ItemType Directory -Path $archiveDirectory -Force | Out-Null
            }

            $archiveDestination = Join-Path -Path $archiveDirectory -ChildPath $existingExport.Name
            if (Test-Path -LiteralPath $archiveDestination) {
                $archiveSuffix = "$(Get-Date -Format 'yyyyMMdd-HHmmssfff')-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
                $archiveName = "$($existingExport.BaseName)-archived-$archiveSuffix$($existingExport.Extension)"
                $archiveDestination = Join-Path -Path $archiveDirectory -ChildPath $archiveName
            }

            Move-Item -LiteralPath $existingExport.FullName -Destination $archiveDestination
            [void]$archivedFiles.Add($archiveDestination)
            Write-Debug "Archived deprecated Confluence page export '$($existingExport.FullName)' to '$archiveDestination'."
        }
    }

    if ($currentVersionFiles.Count -gt 0) {
        $existingCurrentExport = $currentVersionFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $currentExportPath = $existingCurrentExport.FullName
        $exportStatus = 'SkippedCurrentVersion'
        if (-not $currentExportPath.Equals($outputFile, [System.StringComparison]::OrdinalIgnoreCase)) {
            if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
                New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
            }
            if (Test-Path -LiteralPath $outputFile -PathType Leaf) {
                $currentExportPath = (Get-Item -LiteralPath $outputFile).FullName
            } else {
                Move-Item -LiteralPath $existingCurrentExport.FullName -Destination $outputFile
                $currentExportPath = $outputFile
                $exportStatus = 'RelocatedCurrentVersion'
                Write-Debug "Relocated current Confluence page '$CONFLUENCE_PAGE_ID' version $pageVersion into its full hierarchy at '$outputFile'."
            }
        } else {
            Write-Debug "Skipping Confluence page '$CONFLUENCE_PAGE_ID' version $pageVersion; current '$CONFLUENCE_PAGE_FORMAT' export already exists at '$currentExportPath'."
        }
        $returnObject = [ordered]@{
            CONFLUENCE_PAGE_TITLE   = [string]$restResults.title
            CONFLUENCE_PAGE_ID      = $CONFLUENCE_PAGE_ID
            CONFLUENCE_PAGE_VERSION = $pageVersion
            CONFLUENCE_PAGE_FORMAT  = $CONFLUENCE_PAGE_FORMAT
            SOURCE_BODY_FORMAT      = $sourceBodyFormat
            EXPORT_STATUS           = $exportStatus
            FILE_NAME               = $currentExportPath
            HIERARCHY_PATH           = $outputDirectory
            ANCESTOR_DIRECTORIES     = [string[]]$hierarchyDirectories
            ARCHIVED_FILES          = [string[]]$archivedFiles
        }
        return ConvertTo-Json -InputObject $returnObject -Depth 10
    }

    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }

    if ($CONFLUENCE_PAGE_FORMAT -eq 'view') {
        $encodedTitle = [System.Net.WebUtility]::HtmlEncode([string]$restResults.title)
        $encodedBaseUri = [System.Net.WebUtility]::HtmlEncode([uri]::new($baseUri, '/wiki/').AbsoluteUri)
        $pageContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <base href="$encodedBaseUri">
    <title>$encodedTitle</title>
</head>
<body>
$pageContent
</body>
</html>
"@
    } elseif ($CONFLUENCE_PAGE_FORMAT -eq 'atlas_doc_format' -and $pageContent -isnot [string]) {
        $pageContent = ConvertTo-Json -InputObject $pageContent -Depth 100
    }

    Set-Content -LiteralPath $outputFile -Value $pageContent -Encoding utf8 -NoNewline
    Write-Debug "Exported Confluence page '$CONFLUENCE_PAGE_ID' to '$outputFile'."

    $returnObject = [ordered]@{
        CONFLUENCE_PAGE_TITLE   = [string]$restResults.title
        CONFLUENCE_PAGE_ID      = $CONFLUENCE_PAGE_ID
        CONFLUENCE_PAGE_VERSION = $pageVersion
        CONFLUENCE_PAGE_FORMAT  = $CONFLUENCE_PAGE_FORMAT
        SOURCE_BODY_FORMAT      = $sourceBodyFormat
        EXPORT_STATUS           = 'Exported'
        FILE_NAME               = $outputFile
        HIERARCHY_PATH           = $outputDirectory
        ANCESTOR_DIRECTORIES     = [string[]]$hierarchyDirectories
        ARCHIVED_FILES          = [string[]]$archivedFiles
    }
    return ConvertTo-Json -InputObject $returnObject -Depth 10
}

function Export-ConfluencePageAllChildren {
    param (
        [Parameter(Mandatory = $true)]
        [string]$CONFLUENCE_SPACE_KEY,
        [Parameter(Mandatory = $true)]
        [int64]$CONFLUENCE_PAGE_ID,
        [Parameter(Mandatory = $false)]
        [string]$CONFLUENCE_PAGE_FORMAT = 'atlas_doc_format',
        [Parameter(Mandatory = $false)]
        [int]$DepthLimit = 10,
        [Parameter(Mandatory = $false)]
        [int]$DepthCount = 0
    )
    $PARENT_PAGE = $null
    try {
        $PARENT_PAGE = Get-ConfluencePageByID -CONFLUENCE_PAGE_ID $CONFLUENCE_PAGE_ID
    } catch {
        Write-Debug "Parent page lookup failed: $($_.Exception.Message) — proceeding with children fetch using provided ID."
    }
    Write-Debug '##############################################'
    if ($PARENT_PAGE) {
        Write-Debug "Parent Page Type: $($PARENT_PAGE.GetType())"
        Write-Debug "Parent Page Count: $($PARENT_PAGE.Count)"
        $PARENT_PAGE | ConvertTo-Json -Depth 20 | Write-Debug
    }
    Write-Debug '##############################################'
    $PARENT_PAGE_ID = if ($PARENT_PAGE) { $PARENT_PAGE.id } else { $CONFLUENCE_PAGE_ID }
    $CONFLUENCE_PARENT_PAGE_TITLE = if ($PARENT_PAGE) { $PARENT_PAGE.title } else { "(unknown title)" }
    Write-Debug "Parent Page ID: $PARENT_PAGE_ID, Title: $CONFLUENCE_PARENT_PAGE_TITLE, DepthCount: $DepthCount, DepthLimit: $DepthLimit - getting child pages..."
    $CHILD_PAGES = $(Get-ConfluenceChildPages -CONFLUENCE_SPACE_KEY $CONFLUENCE_SPACE_KEY -PARENT_ID $PARENT_PAGE_ID)
    $CHILD_PAGES | ConvertTo-Json -Depth 20 | Write-Debug
    Write-Debug "Found $($CHILD_PAGES.results.count) child pages..."
    $CHILD_PAGES.results | ForEach-Object {
        Write-Debug "Exporting page format: $CONFLUENCE_PAGE_FORMAT for page ID: $($_.id)..."
        Export-ConfluencePage -CONFLUENCE_SPACE_KEY $CONFLUENCE_SPACE_KEY -CONFLUENCE_PAGE_ID $($_.id) -CONFLUENCE_PAGE_FORMAT $CONFLUENCE_PAGE_FORMAT
        if (($DepthLimit -eq 0) -or ($DepthCount -lt $DepthLimit)) {
            $DepthCount++
            Export-ConfluencePageAllChildren -CONFLUENCE_SPACE_KEY $CONFLUENCE_SPACE_KEY -CONFLUENCE_PAGE_ID $($_.id) -CONFLUENCE_PAGE_FORMAT $CONFLUENCE_PAGE_FORMAT -DepthLimit $DepthLimit -DepthCount $DepthCount
        }
    }
}

# Function to export Confluence page to a file Word document, with templating
function Export-ConfluencePageWord {
    param (
        [Parameter(Mandatory = $true)]
        [string]$CONFLUENCE_SPACE_KEY,
        [Parameter(Mandatory = $true)]
        [int64]$CONFLUENCE_PAGE_ID,
        [Parameter(Mandatory = $true)]
        [string]$CONFLUENCE_PAGE_TITLE,
        [Parameter(Mandatory = $false)]
        [string]$TEMPLATE_FILEPATH = ".\$($env:AtlassianPowerKit_PROFILE_NAME)\$($env:AtlassianPowerKit_PROFILE_NAME)_Document_Template.dotx"
    )
    $CONFLUENCE_PAGE_TITLE = $CONFLUENCE_PAGE_TITLE -replace ' ', ''
    $CONFLUENCE_PAGE_TITLE = $CONFLUENCE_PAGE_TITLE -replace '[\\\/\:\*\?\"\<\>\|]', ''
    $CONFLUENCE_PAGE_FORMAT = 'view'
    $CONFLUENCE_PAGE_ENDPOINT = "https://$($env:AtlassianPowerKit_ENDPOINT)/wiki/api/v2/pages/$($CONFLUENCE_PAGE_ID)?body-format=$CONFLUENCE_PAGE_FORMAT"
    $directoryString = "$($env:OSM_HOME)\$($env:AtlassianPowerKit_PROFILE_NAME)\CONFLUENCE\$CONFLUENCE_SPACE_KEY\CONFLUENCE_WORD_EXPORTS"
    if (-not (Test-Path $directoryString)) {
        New-Item -ItemType Directory -Path $directoryString -Force | Out-Null
    }
    $directoryPath = Get-Item -Path $directoryString
    if (-not (Test-Path $TEMPLATE_FILEPATH)) {
        Write-Error "Template file does not exist: $TEMPLATE_FILEPATH"
    }
    $TEMPLATE_FILE_NAME = $(Get-Item -Path $TEMPLATE_FILEPATH).FullName
    $VIEW_FILE_NAME = "$($directoryPath.FullName)\$CONFLUENCE_PAGE_TITLE.html"
    $DOWNLOAD_FILE_NAME = "$VIEW_FILE_NAME.download"
    $DOCX_FILE_NAME = "$($directoryPath.FullName)\$CONFLUENCE_PAGE_TITLE.docx"
    try {
        $requestHeaders = ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders
        $requestHeaders['Accept'] = 'application/json'

        # Disable cmdlet debug output because it includes Authorization.
        Write-Debug "Invoking web request to Confluence page endpoint: $CONFLUENCE_PAGE_ENDPOINT"
        $response = Invoke-WebRequest -Uri $CONFLUENCE_PAGE_ENDPOINT -Headers $requestHeaders -Method Get -Debug:$false

        $statusCode = [int]$response.StatusCode
        $wafAction = $response.Headers['x-amzn-waf-action'] -join ','
        $contentType = $response.Headers['Content-Type'] -join ','

        if ($wafAction -match '^(?i:challenge|captcha)$') {
            throw "Confluence page export was blocked by AWS WAF ($wafAction). The REST endpoint did not return the requested '$CONFLUENCE_PAGE_FORMAT' representation."
        }
        if ([int]$statusCode -lt 200 -or [int]$statusCode -ge 300) {
            throw "Confluence page export returned HTTP status $statusCode."
        }
        if ($contentType -notmatch '^(?i:application/(?:[^;,]+\+)?json)(?:;|,|$)') {
            throw "Confluence page export returned unexpected content type '$contentType' instead of JSON."
        }

        $page = $response.Content | ConvertFrom-Json
        $pageViewContent = $page.body.view.value
        if ([string]::IsNullOrWhiteSpace($pageViewContent)) {
            throw "Confluence returned no body.view.value content for page $CONFLUENCE_PAGE_ID."
        }

        $pageTitle = if ([string]::IsNullOrWhiteSpace($page.title)) { $CONFLUENCE_PAGE_TITLE } else { $page.title }
        $encodedPageTitle = [System.Net.WebUtility]::HtmlEncode($pageTitle)
        $encodedBaseUrl = [System.Net.WebUtility]::HtmlEncode("https://$($env:AtlassianPowerKit_ENDPOINT)/wiki/")
        $viewDocument = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <base href="$encodedBaseUrl">
    <title>$encodedPageTitle</title>
</head>
<body>
$pageViewContent
</body>
</html>
"@

        Set-Content -LiteralPath $DOWNLOAD_FILE_NAME -Value $viewDocument -Encoding UTF8
        Move-Item -LiteralPath $DOWNLOAD_FILE_NAME -Destination $VIEW_FILE_NAME -Force
    } catch {
        if ($_.InvocationInfo.PositionMessage) {
            Write-Debug $_.InvocationInfo.PositionMessage.Trim()
        }
        throw "Failed to export Confluence page $CONFLUENCE_PAGE_ID in '$CONFLUENCE_PAGE_FORMAT' format: $($_.Exception.Message)"
    } finally {
        if (Test-Path -LiteralPath $DOWNLOAD_FILE_NAME -PathType Leaf) {
            Remove-Item -LiteralPath $DOWNLOAD_FILE_NAME -Force
        }
    }
    $VIEW_FILE_NAME = (Get-Item -LiteralPath $VIEW_FILE_NAME).FullName
    Write-Debug "Confluence page exported in '$CONFLUENCE_PAGE_FORMAT' format to: $VIEW_FILE_NAME"
    Write-Debug "Applying template: $TEMPLATE_FILE_NAME to $VIEW_FILE_NAME..."
    $wordApp = $null
    $wordApp2 = $null
    $doc = $null
    $sourceDoc = $null
    $templateDoc = $null
    try {
        $wordApp = New-Object -ComObject Word.Application
        $wordApp.Visible = $false
        $wordApp.DisplayAlerts = 0
        $wordApp2 = New-Object -ComObject word.application
        $wordApp2.Visible = $false
        $wordApp2.DisplayAlerts = 0
        Write-Debug '   - Converting to docx...'
        $doc = $wordApp.Documents.Open($VIEW_FILE_NAME)
        # wdFormatDocumentDefault (16) converts the rendered HTML to .docx.
        $doc.SaveAs2($DOCX_FILE_NAME, 16)
        $doc.Close(0)
        $doc = $null
        Write-Debug '   - Prepping template...'
        # Add-Type -AssemblyName office
        # [ref]$SaveFormat = 'microsoft.office.interop.word.WdSaveFormat' -as [type]
        $sourceDoc = $wordApp.Documents.Open($DOCX_FILE_NAME)
        # Check if the template file exists
        ################# Clean up and get Copy of the source document
        # Select from the beginning of the document to the end the second heading level 1
        $what = 11 # wdGoToHeading https://learn.microsoft.com/en-us/office/vba/api/word.wdgotoitem
        $which = 1 # wdGoToAbsolute https://learn.microsoft.com/en-us/office/vba/api/word.wdgotoitem
        $count = 2
        #$wordApp.Activate()
        $rangeEnd = $sourceDoc.GoTo($what, $which, $count)
        $selection = $wordApp.Selection
        $selection.SetRange(0, $rangeEnd.Start)
        $selection.Delete()
        # Select remaining text and copy it
        $range = $sourceDoc.Range()
        $range.Copy()
        #################
        ################# Paste the copied text into the new document based on the template
        $templateDoc = $wordApp2.Documents.Add($TEMPLATE_FILE_NAME)
        #$wordApp2.Activate()
        $what = 1 # wdGoToPage https://learn.microsoft.com/en-us/office/vba/api/word.wdgotoitem
        $which = 1 # wdGoToAbsolute https://learn.microsoft.com/en-us/office/vba/api/word.wdgotoitem
        $count = 4
        $selection = $templateDoc.GoTo($what, $which, $count)
        # Paste the copied text from range.Copy() into the template
        $selection.Paste()
        #################
        ################# Clean up the templated document
        $STRINGS_TO_REMOVE = @('﻿﻿')
        $STRINGS_TO_REMOVE | ForEach-Object {
            $templateDoc.Content.Find.Execute($_, $false, $false, $false, $false, $false, $true, 1, $true, '', 2)
        }  
        
        #################
        ################# Save the new document
        $templateDoc.SaveAs2("$directoryPath\$CONFLUENCE_PAGE_TITLE-Templated.docx", 16)
        # Also print as PDF
        $templateDoc.ExportAsFixedFormat("$directoryPath\$CONFLUENCE_PAGE_TITLE-Templated.pdf", 17)
        $sourceDoc.Close(0)
        $sourceDoc = $null
        $templateDoc.Close(0)
        $templateDoc = $null
    } catch {
        Write-Debug 'AtlassianPowerKit-Confluence.psm1:Export-ConfluencePageWord - Errored!'
        if ($_.InvocationInfo.PositionMessage) {
            Write-Debug $_.InvocationInfo.PositionMessage.Trim()
        }
        throw "Failed to convert or template Confluence page $CONFLUENCE_PAGE_ID in Word: $($_.Exception.Message)"
    } finally {
        if ($null -ne $templateDoc) {
            try { $templateDoc.Close(0) } catch { Write-Debug "Unable to close the template document: $($_.Exception.Message)" }
        }
        if ($null -ne $sourceDoc) {
            try { $sourceDoc.Close(0) } catch { Write-Debug "Unable to close the source document: $($_.Exception.Message)" }
        }
        if ($null -ne $doc) {
            try { $doc.Close(0) } catch { Write-Debug "Unable to close the exported document: $($_.Exception.Message)" }
        }
        if ($null -ne $wordApp2) {
            try { $wordApp2.Quit() } catch { Write-Debug "Unable to quit the template Word process: $($_.Exception.Message)" }
        }
        if ($null -ne $wordApp) {
            try { $wordApp.Quit() } catch { Write-Debug "Unable to quit the source Word process: $($_.Exception.Message)" }
        }
    }
}

# Function to export Confluence Child Pages to word documents
function Export-ConfluencePageWordForChildren {
    param (
        [Parameter(Mandatory = $true)]
        [string]$CONFLUENCE_SPACE_KEY,
        [Parameter(Mandatory = $true)]
        [string]$CONFLUENCE_PARENT_PAGE_TITLE
    )
    $PARENT_PAGE = Get-ConfluencePageByTitle -CONFLUENCE_SPACE_KEY $CONFLUENCE_SPACE_KEY -CONFLUENCE_PAGE_TITLE $CONFLUENCE_PARENT_PAGE_TITLE
    if (!$PARENT_PAGE) {
        throw "Parent page does not exist: $CONFLUENCE_PARENT_PAGE_TITLE"
    }
    $PARENT_PAGE_ID = $PARENT_PAGE.results[0].id
    Write-Debug "Parent Page ID: $PARENT_PAGE_ID, Title: $CONFLUENCE_PARENT_PAGE_TITLE - getting child pages..."
    $CHILD_PAGES = $(Get-ConfluenceChildPages -CONFLUENCE_SPACE_KEY $CONFLUENCE_SPACE_KEY -PARENT_ID $PARENT_PAGE_ID)
    Write-Debug "Found $($CHILD_PAGES.results.count) child pages..."
    $CHILD_PAGES.results | ForEach-Object {
        $CONFLUENCE_PAGE_ID = $_.id
        Export-ConfluencePageStorageFormat -CONFLUENCE_SPACE_KEY $CONFLUENCE_SPACE_KEY -CONFLUENCE_PAGE_ID $CONFLUENCE_PAGE_ID
    }
}

# Function to get a Confluence page's storage format export by the page ID, writing to a file in ./PROFILE_NAME/spacekey/pageid_<YYYMMDD-HHMMSS>.xml
function Export-ConfluencePageStorageFormat {
    param (
        [Parameter(Mandatory = $true)]
        [string]$CONFLUENCE_SPACE_KEY,
        [Parameter(Mandatory = $true)]
        [int64]$CONFLUENCE_PAGE_ID
    )
    $CONFLUENCE_PAGE_ENDPOINT = "https://$($env:AtlassianPowerKit_ENDPOINT)/wiki/api/v2/pages/$($CONFLUENCE_PAGE_ID)?body-format=storage"
    Write-Debug "Exporting page storage format for page ID: $CONFLUENCE_PAGE_ID ... URL: $CONFLUENCE_PAGE_ENDPOINT ..."
    try {
        Write-Debug '++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++'
        Write-Debug "Confluence Page exporting: $CONFLUENCE_PAGE_ENDPOINT"
        $REST_RESULTS = Invoke-RestMethod -Uri $CONFLUENCE_PAGE_ENDPOINT -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get
        Write-Debug $REST_RESULTS.getType()
        #Write-Debug "Rest Result Fields, Recursive: $($REST_RESULTS | Get-Member -MemberType Properties -Force)"
        #Write-Debug (ConvertTo-Json $REST_RESULTS -Depth 10)
        Write-Debug '++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++'
    } catch {
        $functionName = (Get-PSCallStack)[0].FunctionName
        Write-Debug "$functionName errored: $($_.Exception.Message)"
        Write-Error "$functionName errored: $($_.Exception.Message)"
    }
    $CONFLUENCE_PAGE_DIR = "$($env:OSM_HOME)\$($env:AtlassianPowerKit_PROFILE_NAME)\CONFLUENCE"
    # Get the calue of the PSObject property storage, give $REST_RESULT | Get-Member -Property ... body=@{storage=} ..
    $CONFLUENCE_PAGE_STORAGE = $REST_RESULTS.body.storage
    $CONFLUENCE_PAGE_TITLE = $REST_RESULTS.title
    $CONFLUENCE_PAGE_TITLE_FILENAME = $CONFLUENCE_PAGE_TITLE -replace ' ', '_' -replace ':', '-' -replace '[^a-zA-Z0-9_-]', ''
    #$CONFLUENCE_PAGE_TITLE_ENCODED = [System.Web.HttpUtility]::UrlEncode($CONFLUENCE_PAGE_TITLE)
    $CURRENT_DATE_TIME = Get-Date -Format 'yyyyMMdd-HHmmss'

    $OUTFILE = "$CONFLUENCE_PAGE_DIR\$($CONFLUENCE_PAGE_TITLE_FILENAME)_$CURRENT_DATE_TIME.xml"
    if (-not (Test-Path $CONFLUENCE_PAGE_DIR)) {
        New-Item -ItemType Directory -Path $CONFLUENCE_PAGE_DIR -Force | Out-Null
    }
    Write-Debug 'Confluence Page Storage:'
    Write-Debug $CONFLUENCE_PAGE_STORAGE.Value
    $CONFLUENCE_PAGE_STORAGE.Value | Set-Content -Path $OUTFILE -Encoding UTF8 -Force
    $FILE_NAME = $(Get-Item $OUTFILE).FullName
    Write-Debug "Page storage format exported to: $FILE_NAME"
    return $FILE_NAME
}

# Function to export Confluence page storage format to a file for all child pages of a parent page
function Export-ConfluencePageStorageFormatForChildren {
    param (
        [Parameter(Mandatory = $true)]
        [string]$CONFLUENCE_SPACE_KEY,
        [Parameter(Mandatory = $true)]
        [string]$CONFLUENCE_PARENT_PAGE_TITLE,
        [Parameter(Mandatory = $false)]
        [int]$DepthLimit = 10,
        [Parameter(Mandatory = $false)]
        [int]$DepthCount = 0
    )
    $PARENT_PAGE = Get-ConfluencePageByTitle -CONFLUENCE_SPACE_KEY $CONFLUENCE_SPACE_KEY -CONFLUENCE_PAGE_TITLE $CONFLUENCE_PARENT_PAGE_TITLE
    if (!$PARENT_PAGE) {
        throw "Parent page does not exist: $CONFLUENCE_PARENT_PAGE_TITLE"
    }
    $PARENT_PAGE_ID = $PARENT_PAGE.results[0].id
    Write-Debug "Parent Page ID: $PARENT_PAGE_ID, Title: $CONFLUENCE_PARENT_PAGE_TITLE, DepthCount: $DepthCount, DepthLimit: $DepthLimit - getting child pages..."
    $CHILD_PAGES = $(Get-ConfluenceChildPages -CONFLUENCE_SPACE_KEY $CONFLUENCE_SPACE_KEY -PARENT_ID $PARENT_PAGE_ID)
    Write-Debug "Found $($CHILD_PAGES.results.count) child pages..."
    $CHILD_PAGES.results | ForEach-Object {
        Write-Debug "Exporting page storage format for page ID: $($_.id)..."
        Export-ConfluencePageStorageFormat -CONFLUENCE_SPACE_KEY $CONFLUENCE_SPACE_KEY -CONFLUENCE_PAGE_ID $($_.id)
        if (($DepthLimit -eq 0) -or ($DepthCount -lt $DepthLimit)) {
            $DepthCount++
            Export-ConfluencePageStorageFormatForChildren -CONFLUENCE_SPACE_KEY $CONFLUENCE_SPACE_KEY -CONFLUENCE_PARENT_PAGE_TITLE $($_.title) -DepthLimit $DepthLimit -DepthCount $DepthCount
        }
    }
}

# Function to export a confluence page as attlasion doc format

# FUNCTION to get Confluence page by ID
function Get-ConfluencePageByID {
    param (
        [Parameter(Mandatory = $true)]
        [int64]$CONFLUENCE_PAGE_ID
    )
    if (-not $CONFLUENCE_PAGE_ID -or $CONFLUENCE_PAGE_ID -eq 0) {
        Write-Error 'You must provide a Confluence Page ID'
    }
    $CONFLUENCE_PAGE_V2_ENDPOINT = "https://$($env:AtlassianPowerKit_ENDPOINT)/wiki/api/v2/pages/$($CONFLUENCE_PAGE_ID.ToString())"
    Write-Debug "Confluence Page ID: $CONFLUENCE_PAGE_ID"
    Write-Debug "Confluence Page Endpoint (v2): $CONFLUENCE_PAGE_V2_ENDPOINT"
    $REQUEST_HEADERS = $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders)
    try {
        $REST_RESULTS = Invoke-RestMethod -Uri $CONFLUENCE_PAGE_V2_ENDPOINT -Headers $REQUEST_HEADERS -Method Get
        $REST_RESULTS | ConvertTo-Json -Depth 20 | Write-Debug
        return $REST_RESULTS
    } catch {
        # Capture detailed error info
        $statusCode = $null
        $statusDesc = $null
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode.value__
            $statusDesc = $_.Exception.Response.StatusDescription
        }
        Write-Debug "Get-ConfluencePageByID (v2) error: $($_.Exception.Message)"
        if ($statusCode) { Write-Debug "StatusCode: $statusCode, StatusDescription: $statusDesc" }

        # If v2 returns 404, try Confluence v1 REST API as fallback
        if ($statusCode -eq 404) {
            $CONFLUENCE_PAGE_V1_ENDPOINT = "https://$($env:AtlassianPowerKit_ENDPOINT)/wiki/rest/api/content/$($CONFLUENCE_PAGE_ID.ToString())?expand=body.storage,version"
            Write-Debug "Confluence Page Endpoint (v1 fallback): $CONFLUENCE_PAGE_V1_ENDPOINT"
            try {
                $restV1 = Invoke-RestMethod -Uri $CONFLUENCE_PAGE_V1_ENDPOINT -Headers $REQUEST_HEADERS -Method Get
                # Normalize a minimal shape similar to v2 for downstream functions
                $normalized = [pscustomobject]@{
                    id      = [int64]$restV1.id
                    title   = $restV1.title
                    version = $restV1.version
                    body    = @{ storage = @{ value = $restV1.body.storage.value } }
                }
                $normalized | ConvertTo-Json -Depth 20 | Write-Debug
                return $normalized
            } catch {
                Write-Debug "Get-ConfluencePageByID (v1 fallback) error: $($_.Exception.Message)"
                if ($_.Exception.Response) {
                    Write-Debug "StatusCode: $($_.Exception.Response.StatusCode.value__), StatusDescription: $($_.Exception.Response.StatusDescription)"
                }
                Write-Error "Get-ConfluencePageByID: $($_.Exception.Message)"
            }
        } else {
            Write-Error "Get-ConfluencePageByID: $($_.Exception.Message)"
        }
    }
}

# Function get page by title
function Get-ConfluencePageByTitle {
    param (
        [Parameter(Mandatory = $true)]
        [string]$CONFLUENCE_SPACE_KEY,
        [Parameter(Mandatory = $true)]
        [string]$CONFLUENCE_PAGE_TITLE
    )
    $CONFLUENCE_PAGE_TITLE_ENCODED = [System.Web.HttpUtility]::UrlEncode($CONFLUENCE_PAGE_TITLE)
    Write-Debug "Confluence Space Key: $CONFLUENCE_SPACE_KEY"
    Write-Debug "Confluence Page Title: $CONFLUENCE_PAGE_TITLE"
    Write-Debug "Confluence Page Title Encoded: $CONFLUENCE_PAGE_TITLE_ENCODED"
    $LIST_OF_SPACE_IDS = Get-ConfluenceSpaceList | ConvertFrom-Json
    $SPACE_ID = $LIST_OF_SPACE_IDS.results | Where-Object { $_.key -eq $CONFLUENCE_SPACE_KEY } | Select-Object -ExpandProperty id
    $CONFLUENCE_PAGE_ENDPOINT = "https://$($env:AtlassianPowerKit_ENDPOINT)/wiki/api/v2/pages?space-id=$SPACE_ID&title=$CONFLUENCE_PAGE_TITLE_ENCODED"
    Write-Debug "Confluence Page Endpoint: $CONFLUENCE_PAGE_ENDPOINT"
    try {
        $REST_RESULTS = Invoke-RestMethod -Uri $CONFLUENCE_PAGE_ENDPOINT -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get
        #Write-Debug $REST_RESULTS.getType()
        Write-Debug (ConvertTo-Json $REST_RESULTS -Depth 10)
    } catch {
        Write-Debug ($_ | Select-Object -Property * -ExcludeProperty psobject | Out-String)
        Write-Error "Error updating field: $($_.Exception.Message)"
    }
    Write-Debug "Found $($REST_RESULTS.results.count) pages..."
    $REST_RESULTS
}

# Function to create a mapping of Confluence spaces and their IDs, that is accessible to all functions
function Get-ConfluenceSpaceList {
    $CONFLUENCE_SPACES_ENDPOINT = "https://$($env:AtlassianPowerKit_ENDPOINT)/wiki/api/v2/spaces"
    try {
        Write-Debug "Confluence Spaces Endpoint: $CONFLUENCE_SPACES_ENDPOINT"
        $REST_RESULTS = Invoke-RestMethod -Uri $CONFLUENCE_SPACES_ENDPOINT -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get -ContentType 'application/json'
    } catch {
        Write-Debug 'StatusCode:' $_.Exception.Response.StatusCode.value__
        Write-Debug 'StatusDescription:' $_.Exception.Response.StatusDescription
    }
    $CONFLUENCE_PAGE_TITLE = "ConfluenceSpaces"
    $OUTPUT_DIR = "$($env:OSM_HOME)\$($env:AtlassianPowerKit_PROFILE_NAME)\CONFLUENCE"
    $OUTPUT_FILE_NAME = "ConfluenceSpaces_$($env:AtlassianPowerKit_PROFILE_NAME)_$CURRENT_DATE_TIME.json"
    Write-Debug "Exporting space list for $($env:AtlassianPowerKit_PROFILE_NAME) to file: $OUTPUT_DIR\$OUTPUT_FILE_NAME ..."
    if (-not (Test-Path $OUTPUT_DIR)) {
        Write-Debug "Creating output directory: $OUTPUT_DIR ..."
        New-Item -ItemType Directory -Path $OUTPUT_DIR -Force | Out-Null
    }
    Write-Debug 'Confluence Page Content:'
    $REST_RESULTS | ConvertTo-Json -Depth 10 | Set-Content -Path $OUTPUT_DIR\$OUTPUT_FILE_NAME -Encoding UTF8 -Force
    Write-Debug "Confluence space list exported to: $OUTPUT_DIR\$OUTPUT_FILE_NAME"
    $RET_OBJ = $REST_RESULTS | ConvertTo-Json -Depth 10
    return $RET_OBJ
}

# function to get Confluence space properties by space ID, printing as json
function Get-ConfluenceSpacePropertiesBySpaceID {
    param (
        [Parameter(Mandatory = $false)]
        [string]$CONFLUENCE_SPACE_ID
    )
    if (-not $CONFLUENCE_SPACE_ID) {
        $CONFLUENCE_SPACE_ID = Read-Host 'Enter Confluence Space ID'
    }
    $CONFLUENCE_SPACE_ENDPOINT = "https://$($env:AtlassianPowerKit_ENDPOINT)/wiki/api/v2/spaces/$CONFLUENCE_SPACE_ID"
    try {
        $REST_RESULTS = Invoke-RestMethod -Uri $CONFLUENCE_SPACE_ENDPOINT -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get -ContentType 'application/json'
        Write-Debug $REST_RESULTS.getType()
        Write-Debug (ConvertTo-Json $REST_RESULTS -Depth 10)
    } catch {
        Write-Debug 'StatusCode:' $_.Exception.Response.StatusCode.value__
        Write-Debug 'StatusDescription:' $_.Exception.Response.StatusDescription
    }
    $REST_RESULTS
}

# Function to return child pages of a parent page
function Get-ConfluenceChildPages {
    param (
        [Parameter(Mandatory = $true)]
        [string]$CONFLUENCE_SPACE_KEY,
        [Parameter(Mandatory = $true)]
        [int64]$PARENT_ID
    )
    $REQUEST_HEADERS = $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders)
    $GET_CHILD_PAGE_V2_ENDPOINT = "https://$($env:AtlassianPowerKit_ENDPOINT)/wiki/api/v2/pages/$PARENT_ID/children?limit=250"
    try {
        $allResults = [System.Collections.Generic.List[object]]::new()
        $nextUrl = $GET_CHILD_PAGE_V2_ENDPOINT
        do {
            Write-Debug "Get-ConfluenceChildPages (v2) requesting: $nextUrl"
            $pageResponse = Invoke-RestMethod -Uri $nextUrl -Headers $REQUEST_HEADERS -Method Get
            if ($pageResponse.results) {
                foreach ($item in $pageResponse.results) {
                    [void]$allResults.Add($item)
                }
            }

            $nextUrl = $null
            if ($pageResponse._links -and $pageResponse._links.next) {
                if ($pageResponse._links.next -match '^https?://') {
                    $nextUrl = $pageResponse._links.next
                }
                else {
                    $nextUrl = "https://$($env:AtlassianPowerKit_ENDPOINT)$($pageResponse._links.next)"
                }
            }
        } while ($nextUrl)

        $REST_RESULTS = [pscustomobject]@{
            results = @($allResults)
            size    = $allResults.Count
        }
        Write-Debug "Get-ConfluenceChildPages (v2) consolidated results count: $($REST_RESULTS.results.Count)"
        Write-Debug (ConvertTo-Json $REST_RESULTS -Depth 10)
        return $REST_RESULTS
    } catch {
        $statusCode = $null
        if ($_.Exception.Response) { $statusCode = $_.Exception.Response.StatusCode.value__ }
        Write-Debug "Get-ConfluenceChildPages (v2) error: $($_.Exception.Message)"
        # Fallback to v1 REST API for children
        if ($statusCode -in @(403,404)) {
            $GET_CHILD_PAGE_V1_ENDPOINT = "https://$($env:AtlassianPowerKit_ENDPOINT)/wiki/rest/api/content/$PARENT_ID/child/page?limit=250"
            Write-Debug "Get-ConfluenceChildPages fallback (v1): $GET_CHILD_PAGE_V1_ENDPOINT"
            try {
                $v1Results = [System.Collections.Generic.List[object]]::new()
                $nextUrl = $GET_CHILD_PAGE_V1_ENDPOINT
                do {
                    Write-Debug "Get-ConfluenceChildPages (v1 fallback) requesting: $nextUrl"
                    $restV1Page = Invoke-RestMethod -Uri $nextUrl -Headers $REQUEST_HEADERS -Method Get
                    foreach ($r in $restV1Page.results) {
                        [void]$v1Results.Add([pscustomobject]@{
                            id    = [int64]$r.id
                            title = $r.title
                        })
                    }

                    $nextUrl = $null
                    if ($restV1Page._links -and $restV1Page._links.next) {
                        if ($restV1Page._links.next -match '^https?://') {
                            $nextUrl = $restV1Page._links.next
                        }
                        else {
                            $nextUrl = "https://$($env:AtlassianPowerKit_ENDPOINT)$($restV1Page._links.next)"
                        }
                    }
                } while ($nextUrl)

                # Normalize to v2-like shape: consolidated results array with id and title at minimum
                $normalized = [pscustomobject]@{
                    results = @($v1Results)
                    size    = $v1Results.Count
                }
                Write-Debug "Get-ConfluenceChildPages (v1 fallback) consolidated results count: $($normalized.results.Count)"
                $normalized | ConvertTo-Json -Depth 10 | Write-Debug
                return $normalized
            } catch {
                Write-Debug "Get-ConfluenceChildPages (v1 fallback) error: $($_.Exception.Message)"
                if ($_.Exception.Response) {
                    Write-Debug "StatusCode: $($_.Exception.Response.StatusCode.value__), StatusDescription: $($_.Exception.Response.StatusDescription)"
                }
                throw
            }
        } else {
            throw
        }
    }
}

# Function to remove all attachments from a Confluence page given the page ID and optionally and exclude list of attachment names
function Remove-AttachmentsFromConfPage {
    param (
        [Parameter(Mandatory = $true)]
        [int64]$CONFLUENCE_PAGE_ID,
        [Parameter(Mandatory = $false)]
        [array]$EXCLUDE_ATTACHMENT_NAMES
    )
    $CONFLUENCE_PAGE_ATTACHMENTS_ENDPOINT = "https://$($env:AtlassianPowerKit_ENDPOINT)/wiki/api/v2/pages/$CONFLUENCE_PAGE_ID/attachments"
    try {
        $REST_RESULTS = Invoke-RestMethod -Uri $CONFLUENCE_PAGE_ATTACHMENTS_ENDPOINT -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Get
        Write-Debug $REST_RESULTS.getType()
        Write-Debug (ConvertTo-Json $REST_RESULTS -Depth 10)
    } catch {
        Write-Debug 'StatusCode:' $_.Exception.Response.StatusCode.value__
        Write-Debug 'StatusDescription:' $_.Exception.Response.StatusDescription
    }
    $REST_RESULTS.results | ForEach-Object {
        if ($EXCLUDE_ATTACHMENT_NAMES -contains $_.title) {
            Write-Debug "Excluding attachment: $($_.title)"
        } else {
            $CONFLUENCE_PAGE_ATTACHMENT_DELETE_ENDPOINT = "https://$($env:AtlassianPowerKit_ENDPOINT)/wiki/api/v2/attachments/$($_.id)"
            Write-Debug "Deleting attachment: $($_.title)"
            Invoke-RestMethod -Uri $CONFLUENCE_PAGE_ATTACHMENT_DELETE_ENDPOINT -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Delete
        }
    }
}

function Set-AttachmentForConfluencePage {
    param (
        [Parameter(Mandatory = $true)]
        [int64]$CONFLUENCE_PAGE_ID,
        [Parameter(Mandatory = $true)]
        [string]$ATTACHMENT_FILE_PATH
    )

    # Validate the file path
    if (-not (Test-Path $ATTACHMENT_FILE_PATH)) {
        Write-Error "Attachment file does not exist: $ATTACHMENT_FILE_PATH"
        return
    }

    # API endpoint
    $CONFLUENCE_PAGE_V1_ATTACHMENTS_ENDPOINT = "https://$($env:AtlassianPowerKit_ENDPOINT)/wiki/rest/api/content/$CONFLUENCE_PAGE_ID/child/attachment"

    # Request headers
    $REQUEST_HEADERS = @{
        'Authorization'     = "Basic $env:AtlassianPowerKit_AtlassianAPIAuthString"
        'X-Atlassian-Token' = 'no-check'
    }

    # File preparation
    $FileName = [System.IO.Path]::GetFileName($ATTACHMENT_FILE_PATH)
    $Boundary = [System.Guid]::NewGuid().ToString()
    $FileContent = [System.IO.File]::ReadAllBytes($ATTACHMENT_FILE_PATH)

    # Construct multipart form-data
    $Body = @(
        "--$Boundary"
        "Content-Disposition: form-data; name=`"file`"; filename=`"$FileName`""
        'Content-Type: application/pdf'
        ''
        ([System.Text.Encoding]::UTF8.GetString($FileContent))
        "--$Boundary--"
    ) -join "`r`n"

    try {
        # POST the attachment
        $REST_RESULTS = Invoke-RestMethod -Uri $CONFLUENCE_PAGE_V1_ATTACHMENTS_ENDPOINT `
            -Headers $REQUEST_HEADERS `
            -Method Post `
            -ContentType "multipart/form-data; boundary=$Boundary" `
            -Body ([System.Text.Encoding]::UTF8.GetBytes($Body))

        # Output results
        Write-Debug 'Attachment uploaded successfully.'
        Write-Debug (ConvertTo-Json $REST_RESULTS -Depth 10)
        return $REST_RESULTS | ConvertTo-Json
    } catch {
        # Handle exceptions
        Write-Error "Failed to upload attachment: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            Write-Error "Response Status Code: $($_.Exception.Response.StatusCode)"
            Write-Error "Response Status Description: $($_.Exception.Response.StatusDescription)"
        }
    }
}

# Function to set confluence space properties by space ID
function Set-ConfluenceSpacePropertyByID {
    param (
        [Parameter(Mandatory = $true)]
        [string]$CONFLUENCE_SPACE_ID,
        [Parameter(Mandatory = $true)]
        [string]$CONFLUENCE_SPACE_PROPERTY_ID,
        [Parameter(Mandatory = $true)]
        [string]$CONFLUENCE_SPACE_PROPERTY_VALUE
    )
    $CONFLUENCE_SPACE_ENDPOINT = "https://$($env:AtlassianPowerKit_ENDPOINT)/wiki/api/v2/spaces/$CONFLUENCE_SPACE_ID"
    $CONFLUENCE_SPACE_PROPERTIES = @{
        key   = $CONFLUENCE_SPACE_PROPERTY_ID
        value = $CONFLUENCE_SPACE_PROPERTY_VALUE
    }
    try {
        $REST_RESULTS = Invoke-RestMethod -Uri $CONFLUENCE_SPACE_ENDPOINT -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) -Method Put -ContentType 'application/json' -Body $CONFLUENCE_SPACE_PROPERTIES
        Write-Debug $REST_RESULTS.getType()
        Write-Debug (ConvertTo-Json $REST_RESULTS -Depth 10)
    } catch {
        Write-Debug 'StatusCode:' $_.Exception.Response.StatusCode.value__
        Write-Debug 'StatusDescription:' $_.Exception.Response.StatusDescription
    }
    $REST_RESULTS
}

function Set-ConfluencePageContentByXMLFile {
    param (
        [Parameter(Mandatory = $true)]
        [string]$CONFLUENCE_SPACE_KEY,
        [Parameter(Mandatory = $true)]
        [int64]$CONFLUENCE_PAGE_ID,
        [Parameter(Mandatory = $true)]
        [string]$CONFLUENCE_XML_FILE_PATH
    )
    
    if (-not (Test-Path $CONFLUENCE_XML_FILE_PATH)) {
        throw "Confluence page storage file does not exist: $CONFLUENCE_XML_FILE_PATH"
    }
    
    $EXISTING_PAGE = Get-ConfluencePageByID -CONFLUENCE_PAGE_ID $CONFLUENCE_PAGE_ID
    $TITLE = $EXISTING_PAGE.title
    $CURR_VERSION = $EXISTING_PAGE.version.number
    $CONFLUENCE_PAGE_ENDPOINT = "https://$($env:AtlassianPowerKit_ENDPOINT)/wiki/api/v2/pages/$CONFLUENCE_PAGE_ID"
    
    Write-Debug "Confluence Page Endpoint: $CONFLUENCE_PAGE_ENDPOINT"
    
    ## Read the XML content
    $CONFLUENCE_PAGE_CONTENT = Get-Content -Path $CONFLUENCE_XML_FILE_PATH -Raw -Encoding UTF8
    
    # Remove tabs and excessive whitespace BEFORE JSON escaping
    $CONFLUENCE_PAGE_CONTENT = $CONFLUENCE_PAGE_CONTENT -replace "`t", '' -replace ' {2,}', ' ' -replace '>\s+<', '><' -replace '\r\n|\n\r|\n|\r', ' '
    
    # Now escape for JSON
    $escapedContent = $CONFLUENCE_PAGE_CONTENT -replace '\\', '\\\\' -replace '"', '\"'
    
    # Build JSON manually
    $BODY = @"
{
    "id": $CONFLUENCE_PAGE_ID,
    "status": "current",
    "title": "$($TITLE -replace '"', '\"')",
    "body": {
        "representation": "storage",
        "value": "$escapedContent"
    },
    "version": {
        "number": $($CURR_VERSION + 1),
        "message": "Updated content"
    }
}
"@
    
    Write-Debug "Confluence Page Content: $BODY"
    
    try {
        Write-Debug "Setting Confluence page content for page ID: $CONFLUENCE_PAGE_ID ..."
        $REST_RESULTS = Invoke-RestMethod -Uri $CONFLUENCE_PAGE_ENDPOINT `
            -Headers $(ConvertFrom-Json -AsHashtable $env:AtlassianPowerKit_AtlassianAPIHeaders) `
            -Method Put `
            -ContentType 'application/json' `
            -Body $BODY
            
        Write-Debug (ConvertTo-Json $REST_RESULTS -Depth 10)
        return $REST_RESULTS
        
    } catch {
        Write-Debug "StatusCode: $($_.Exception.Response.StatusCode.value__)"
        Write-Debug "StatusDescription: $($_.Exception.Response.StatusDescription)"
        
        # Get detailed error message
        if ($_.Exception.Response) {
            $reader = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
            $errorContent = $reader.ReadToEnd()
            $reader.Close()
            Write-Debug "Error Response: $errorContent"
        }
        
        throw "Failed to update Confluence page: $_"
    }
}
function Set-ConfluenceYearMonthStructure {
    param (
        [Parameter(Mandatory = $true)]
        [string]$CONFLUENCE_SPACE_KEY,
        [Parameter(Mandatory = $true)]
        [int64]$CONFLUENCE_PAGE_ID
    )
    # If the page title does not match 'YYYY (.*)', throw an error and advise the user of this functions purpose
    $TEMP_FILE = New-TemporaryFile

    $CONFLUENCE_PAGE = Get-ConfluencePageByTitle -CONFLUENCE_SPACE_KEY $CONFLUENCE_SPACE_KEY -CONFLUENCE_PAGE_ID $CONFLUENCE_PAGE_ID
    if (!$CONFLUENCE_PAGE) {
        throw "Page does not exist: $CONFLUENCE_PAGE_ID"
    }
    $CONFLUENCE_PAGE_TITLE = $CONFLUENCE_PAGE.title
    if ($CONFLUENCE_PAGE_TITLE -notmatch '^\d { 4 } (.*)') {
        throw "Confluence page title does not match 'YYYY (.*)' format. This function is intended to be used on pages with titles in the format 'YYYY (.*)'"
    }
    $MATCH = $CONFLUENCE_PAGE_TITLE -match '(\d { 4 }) - (.*)'
    $CONFLUENCE_PAGE_YEAR = $MATCH[1]
    $CONFLUENCE_STRUCTURE_NAME = $MATCH[2].Trim()

    $PARENT_STORAGE_CONTENT = $CONFLUENCE_PAGE.body.storage.value
    $PARENT_STORAGE_CONTENT | Set-Content -Path $TEMP_FILE.FullName -Encoding UTF8 -Force
    # For MM in 01-12, create a new child page with the title 'YYYY[1-12] (.*)' - copy the content of the page to the new page
    
    1..12 | ForEach-Object {
        $CONFLUENCE_PAGE_MONTH = $_.ToString('00')
        $CONFLUENCE_PAGE_MONTH_TITLE = "$CONFLUENCE_PAGE_YEAR$CONFLUENCE_PAGE_MONTH - $CONFLUENCE_STRUCTURE_NAME"
        Write-Debug "Confluence Page Month Title: $CONFLUENCE_PAGE_MONTH_TITLE"
        $CONFLUENCE_PAGE_MONTH_PAGE = Get-ConfluencePageByTitle -CONFLUENCE_SPACE_KEY $CONFLUENCE_SPACE_KEY -CONFLUENCE_PAGE_TITLE $CONFLUENCE_PAGE_MONTH_TITLE
        if (!$CONFLUENCE_PAGE_MONTH_PAGE) {
            Write-Debug "Creating new page: $CONFLUENCE_PAGE_MONTH_TITLE"
            # Create new page
            $CONFLUENCE_PAGE_MONTH_PAGE = New-ConfluencePage -CONFLUENCE_SPACE_KEY $CONFLUENCE_SPACE_KEY -CONFLUENCE_PAGE_TITLE $CONFLUENCE_PAGE_MONTH_TITLE
            # Copy content from parent page
            Set-ConfluencePageContent -CONFLUENCE_SPACE_KEY $CONFLUENCE_SPACE_KEY -CONFLUENCE_PAGE_ID $CONFLUENCE_PAGE_MONTH_PAGE.id -CONFLUENCE_PAGE_STORAGE_FILE $TEMP_FILE.FullName
        } else {
            Write-Debug "Page already exists: $CONFLUENCE_PAGE_MONTH_TITLE"
        }
    } finally {
        Remove-Item -Path $TEMP_FILE.FullName -Force
    }
    # Get child pages of parent page
    $CHILD_PAGES = Get-ConfluenceChildPages -CONFLUENCE_SPACE_KEY $CONFLUENCE_SPACE_KEY -PARENT_ID $CONFLUENCE_PAGE_ID
    $CHILD_PAGES.results | ForEach-Object {
        $CHILD_PAGE_TITLE = $_.title
        $CHILD_PAGE_TITLE_MATCH = $CHILD_PAGE_TITLE -match '(\d { 4 })(\d { 2 })(\d+.*)'
        if ($CHILD_PAGE_TITLE_MATCH) {
            $CHILD_PAGE_YEAR = $Matches[1]
            $CHILD_PAGE_MONTH = $Matches[2]
            # Don't change the CHILD_PAGE_TITLE, we are just moving the page
            #$CHILD_PAGE_TITLE = $Matches[3]
            Write-Debug "Child Page Year: $CHILD_PAGE_YEAR, Month: $CHILD_PAGE_MONTH, Title: $CHILD_PAGE_TITLE"
            if ($CHILD_PAGE_YEAR -eq $CONFLUENCE_PAGE_YEAR) {
                Write-Debug "Child Page Year matches: $CHILD_PAGE_YEAR"
                if ($CHILD_PAGE_MONTH -eq $CONFLUENCE_PAGE_MONTH) {
                    Write-Debug

     
                    Write-Debug "Confluence Page Title: $CONFLUENCE_PAGE_TITLE , ID: $CONFLUENCE_PAGE_ID - Year: $CONFLUENCE_PAGE_YEAR - getting child pages..."
                    $CHILD_PAGES = Get-ConfluenceChildPages -CONFLUENCE_SPACE_KEY $CONFLUENCE_SPACE_KEY -PARENT_ID $CONFLUENCE_PAGE_ID
                    $CHILD_PAGES.results | ForEach-Object {
                        $CHILD_PAGE_TITLE = $_.title
                        $CHILD_PAGE_TITLE_MATCH = $CHILD_PAGE_TITLE -match '(\d{4})(\d{2})(\d+.*)'
                        if ($CHILD_PAGE_TITLE_MATCH) {
                            $CHILD_PAGE_YEAR = $Matches[1]
                            $CHILD_PAGE_MONTH = $Matches[2]
                            # Don't change the CHILD_PAGE_TITLE, we are just moving the page
                            #$CHILD_PAGE_TITLE = $Matches[3]
                            Write-Debug "Child Page Year: $CHILD_PAGE_YEAR, Month: $CHILD_PAGE_MONTH, Title: $CHILD_PAGE_TITLE"
                            if ($CHILD_PAGE_YEAR -eq $CONFLUENCE_PAGE_YEAR) {
                                Write-Debug "Child Page Year matches: $CHILD_PAGE_YEAR"
                                if ($CHILD_PAGE_MONTH -eq $CONFLUENCE_PAGE_MONTH) {
                                    Write-Debug "Child Page Month matches: $CHILD_PAGE_MONTH"
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
