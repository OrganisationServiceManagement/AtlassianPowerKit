$ErrorActionPreference = 'Stop'
$DebugPreference = 'SilentlyContinue'
$repository = Split-Path -Parent $PSScriptRoot
$script:assertionCount = 0
$savedLastExitCode = $global:LASTEXITCODE

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
    $script:assertionCount++
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Pattern)
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_ }
    Assert-Condition ($null -ne $caught -and $caught.Exception.Message -like $Pattern) "Expected '$Pattern'; received '$caught'."
}

$environmentNames = @(
    'OSM_HOME', 'OSM_INSTALL', 'AtlassianPowerKit_PROFILE_NAME',
    'AtlassianPowerKit_ENDPOINT', 'AtlassianPowerKit_AtlassianAPIHeaders',
    'DOCKER_IMAGE_NAME', 'DOCKER_IMAGE_VERSION', 'DOCKER_PUSH',
    'DOCKER_LATEST', 'DOCKER_TEST_RUN', 'DOCKER_MULTI_ARCH'
)
$savedEnvironment = @{}
foreach ($name in $environmentNames) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('atlassian-powerkit-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null

try {
    $env:OSM_HOME = $testRoot
    $env:OSM_INSTALL = '.'
    $env:AtlassianPowerKit_PROFILE_NAME = 'offline'
    $env:AtlassianPowerKit_ENDPOINT = 'example.invalid'
    $env:AtlassianPowerKit_AtlassianAPIHeaders = '{}'

    foreach ($moduleFile in Get-ChildItem -LiteralPath $repository -Filter *.psm1 -Recurse) {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($moduleFile.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
        Assert-Condition ($parseErrors.Count -eq 0) "Parse $($moduleFile.FullName): $($parseErrors.Message -join '; ')"
    }

    Push-Location $testRoot
    try {
        foreach ($manifest in Get-ChildItem -LiteralPath $repository -Filter *.psd1 -Recurse | Where-Object { $_.Name -ne 'PSScriptAnalyzerSettings.psd1' }) {
            Import-Module $manifest.FullName -Force -WarningAction SilentlyContinue
        }
        Assert-Condition ($null -ne (Get-Command New-AtlassianEmergencyAdminUser -ErrorAction Stop)) 'Import Admin with OSM_INSTALL=. from outside the repository'
        Assert-Condition ($null -ne (Get-Command Export-JiraProjectIssues -ErrorAction Stop)) 'Import the current Jira module'
    } finally {
        Pop-Location
    }

    # Load only the functions under test so network and filesystem calls can be isolated.
    $tokens = $null
    $parseErrors = $null
    $jiraAst = [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $repository 'AtlassianPowerKit-Jira\AtlassianPowerKit-Jira.psm1'),
        [ref]$tokens, [ref]$parseErrors
    )
    foreach ($definition in $jiraAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -in @('Get-JiraIssue', 'Remove-JsonFields', 'Clear-EmptyFields')
    }, $true)) {
        . ([scriptblock]::Create($definition.Extent.Text))
    }

    & {
        $expectedIssueJson = @'
{
    "key": "TEST-1",
    "fields": {
        "summary": "Offline issue",
        "created": "2026-01-01T00:00:00Z",
        "updated": "2026-01-02T00:00:00Z",
        "description": { "type": "doc", "version": 1, "content": [{ "type": "paragraph", "content": [{ "type": "text", "text": "Keep avatarUrls in text" }] }] },
        "attachment": [{ "filename": "image.png", "mimeType": "image/png", "content": "https://example.invalid/attachment/content/1" }],
        "comment": { "comments": [{ "author": { "displayName": "Example", "active": false, "timeZone": "UTC" }, "body": "Keep this comment" }] },
        "customfield_10010": { "requestType": { "name": "Emailed request" } },
        "customfield_12345": { "name": "Unrelated custom field" },
        "count": 0
    }
}
'@
        $expectedIssueJson = ConvertFrom-Json -InputObject $expectedIssueJson -AsHashtable -Depth 100 |
            ConvertTo-Json -Depth 100 -Compress
        $issueFixture = ConvertFrom-Json -InputObject $expectedIssueJson -AsHashtable -Depth 100
        $expectedRemovalKeys = @(
            'avatarUrls', 'avatarId', 'iconUrl', 'iconUrls', 'icon', 'thumbnail',
            'customfield_10057', 'customfield_10058',
            'timetracking', 'timespent', 'timeestimate', 'timeoriginalestimate',
            'aggregatetimespent', 'aggregatetimeestimate', 'aggregatetimeoriginalestimate',
            'worklog', 'workratio', 'progress', 'aggregateprogress', 'lastViewed'
        )
        foreach ($key in $expectedRemovalKeys) {
            $issueFixture.fields[$key] = @{ marker = 'remove entire property' }
        }
        $issueFixture.fields.comment.comments[0].author['avatarUrls'] = @{ '48x48' = 'https://example.invalid/avatar.png' }
        $issueFixture.fields.attachment[0]['thumbnail'] = 'https://example.invalid/attachment/thumbnail/1'
        $issueFixture.fields.customfield_10010.requestType['icon'] = @{
            id = '1'; _links = @{ iconUrls = @{ '48x48' = 'https://example.invalid/icon.png' } }
        }
        $issueJson = ConvertTo-Json -InputObject $issueFixture -Depth 100 -Compress
        $filteredJson = $issueJson | Remove-JsonFields
        Assert-Condition ($filteredJson -ceq $expectedIssueJson) 'Remove the static image, SLA, time-tracking and last-viewed defaults recursively without changing other data'

        $override = $issueJson | Remove-JsonFields -REMOVE_KEYS_FROM_JSON @('summary') | ConvertFrom-Json -AsHashtable -Depth 100
        Assert-Condition (-not $override.fields.Contains('summary')) 'Remove explicitly selected fields'
        foreach ($key in $expectedRemovalKeys) {
            Assert-Condition ($override.fields.Contains($key)) "An explicit removal list replaces rather than extends the default for $key"
        }
        Assert-Condition ($override.fields.comment.comments[0].author.Contains('avatarUrls')) 'An explicit removal list also overrides nested defaults'
        Assert-Condition (($issueJson | Remove-JsonFields -REMOVE_KEYS_FROM_JSON @()) -ceq $issueJson) 'An empty removal list preserves all fields'
        Assert-Condition (('{"avatarUrls":{},"AvatarUrls":{},"text":"avatarUrls"}' | Remove-JsonFields) -ceq '{"AvatarUrls":{},"text":"avatarUrls"}') 'Match case-sensitive property names, not text values'
        Assert-Condition (('[{"iconUrl":"image","key":"TEST-1"}]' | Remove-JsonFields) -ceq '[{"key":"TEST-1"}]') 'Preserve a single-item root array while cleaning its objects'
        $pipelineResults = @('{"lastViewed":"date","id":1}', '{"timespent":30,"id":2}') | Remove-JsonFields
        Assert-Condition ($pipelineResults.Count -eq 2 -and $pipelineResults[0] -eq '{"id":1}' -and $pipelineResults[1] -eq '{"id":2}') 'Filter each pipeline input independently'
        Assert-Throws { '{invalid' | Remove-JsonFields } '*Conversion from JSON failed*'

        function Invoke-RestMethod {
            param([uri]$Uri, $Headers, $Method, $ContentType)
            Assert-Condition ($Uri.AbsoluteUri -eq 'https://example.invalid/rest/api/3/issue/TEST-1' -and $Method -eq 'Get') 'Fetch only the requested Jira issue without field-discovery requests'
            return $issueFixture
        }
        $returnedJson = @(Get-JiraIssue -Key 'TEST-1')
        $savedJson = Get-Content -LiteralPath (Join-Path $testRoot 'offline\JIRA\TEST-1.json') -Raw
        Assert-Condition ($returnedJson.Count -eq 1 -and $returnedJson[0] -ceq $expectedIssueJson) 'Get-JiraIssue returns only the filtered issue JSON'
        Assert-Condition ($savedJson.TrimEnd() -ceq $returnedJson[0]) 'Get-JiraIssue saves and returns the same filtered JSON'
        Assert-Condition ((ConvertTo-Json -InputObject $issueFixture -Depth 100 -Compress) -ceq $issueJson) 'Filtering leaves the original API response unchanged'
    }

    $tokens = $null
    $parseErrors = $null
    $confluenceAst = [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $repository 'AtlassianPowerKit-Confluence\AtlassianPowerKit-Confluence.psm1'),
        [ref]$tokens, [ref]$parseErrors
    )
    foreach ($definition in $confluenceAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -in @('Get-ConfluenceSpaceList', 'Export-ConfluencePage')
    }, $true)) {
        . ([scriptblock]::Create($definition.Extent.Text))
    }

    & {
        $script:spaceCallCount = 0
        $script:snapshotDates = [System.Collections.Generic.Queue[string]]::new()
        $script:snapshotDates.Enqueue('20260101-010203001')
        $script:snapshotDates.Enqueue('20260101-010203002')
        function Get-Date {
            param([string]$Format)
            Assert-Condition ($Format -eq 'yyyyMMdd-HHmmssfff') 'Use a timestamp with millisecond precision'
            return $script:snapshotDates.Dequeue()
        }
        function Invoke-RestMethod {
            $script:spaceCallCount++
            return [pscustomobject]@{ results = @([pscustomobject]@{ id = [string]$script:spaceCallCount; key = 'TEST' }) }
        }
        $first = Get-ConfluenceSpaceList | ConvertFrom-Json
        $second = Get-ConfluenceSpaceList | ConvertFrom-Json
        $snapshotDirectory = Join-Path $env:OSM_HOME 'offline\CONFLUENCE'
        $snapshots = @(Get-ChildItem -LiteralPath $snapshotDirectory -Filter 'ConfluenceSpaces_offline_*.json' | Sort-Object Name)
        Assert-Condition ($snapshots.Count -eq 2) 'Preserve both space-list snapshots'
        Assert-Condition ($snapshots[0].Name -eq 'ConfluenceSpaces_offline_20260101-010203001.json') 'Initialize the first filename timestamp'
        Assert-Condition ($snapshots[1].Name -eq 'ConfluenceSpaces_offline_20260101-010203002.json') 'Initialize each invocation independently'
        Assert-Condition ($first.results[0].id -eq '1' -and $second.results[0].id -eq '2') 'Preserve space-list return values'
    }

    function New-AncestorBatch {
        param([int[]]$Ids)
        return [pscustomobject]@{
            results = @($Ids | ForEach-Object { [pscustomobject]@{ id = [string]$_; type = 'page' } })
            _links = @{ next = 'https://unused.invalid/not-the-pagination-contract' }
        }
    }

    function Test-AncestorExport {
        param(
            [string]$Name,
            [object[]]$Responses,
            [int[]]$ExpectedIds,
            [string[]]$ExpectedRequests,
            [switch]$ExpectWarning
        )
        $script:ancestorResponses = [System.Collections.Generic.Queue[object]]::new()
        foreach ($response in $Responses) { $script:ancestorResponses.Enqueue($response) }
        $script:ancestorRequests = [System.Collections.Generic.List[string]]::new()
        $script:writtenExport = $null
        $titles = @{ '777' = 'a' }
        foreach ($response in $Responses) {
            foreach ($ancestor in @($response.results)) {
                if ($ancestor.id) { $titles[[string]$ancestor.id] = 'a' }
            }
        }
        function Invoke-ConfluenceRestGetWithRetry {
            param([uri]$Uri, $Headers, $MaximumRetryCount, $MaximumBackoffSeconds)
            Assert-Condition ($Uri.Host -eq 'example.invalid') 'Do not follow unrelated pagination links'
            if ($Uri.AbsolutePath -eq '/wiki/api/v2/pages/99999') {
                return [pscustomobject]@{
                    id = '99999'; title = 'Leaf'; version = @{ number = 1 }
                    body = [pscustomobject]@{ view = [pscustomobject]@{ value = '<p>Offline export</p>' } }
                }
            }
            if ($Uri.AbsolutePath.EndsWith('/ancestors')) {
                $script:ancestorRequests.Add($Uri.PathAndQuery)
                if ($script:ancestorResponses.Count -eq 0) { throw 'Unexpected ancestor request' }
                $response = $script:ancestorResponses.Dequeue()
                if ($response -is [Exception]) { throw $response }
                return $response
            }
            if ($Uri.AbsolutePath -match '^/wiki/api/v2/(pages|folders|whiteboards|databases|embeds)/\d+$') {
                return [pscustomobject]@{ title = 'a' }
            }
            throw "Unexpected request: $Uri"
        }
        function Test-Path { return $false }
        function New-Item { }
        function Set-Content {
            param($LiteralPath, $Value, $Encoding, [switch]$NoNewline)
            $script:writtenExport = $LiteralPath
        }
        $warnings = @()
        $result = Export-ConfluencePage -CONFLUENCE_SPACE_KEY TEST -CONFLUENCE_PAGE_ID 99999 -PARENT_PAGE_ID 777 -CONFLUENCE_PAGE_TITLE_BY_ID $titles -WarningVariable warnings -WarningAction SilentlyContinue | ConvertFrom-Json
        $expectedDirectories = @($ExpectedIds | ForEach-Object { "a-$_" })
        Assert-Condition (($result.ANCESTOR_DIRECTORIES -join '/') -eq ($expectedDirectories -join '/')) "$Name preserves root-to-parent ordering"
        Assert-Condition (($script:ancestorRequests -join '|') -eq ($ExpectedRequests -join '|')) "$Name follows the ancestor-ID contract"
        Assert-Condition ($script:ancestorResponses.Count -eq 0) "$Name consumes the expected batches"
        Assert-Condition ($result.FILE_NAME -eq $script:writtenExport -and $result.EXPORT_STATUS -eq 'Exported') "$Name writes the resolved export"
        Assert-Condition ((@($warnings).Count -gt 0) -eq [bool]$ExpectWarning) "$Name reports traversal failures explicitly"
    }

    Test-AncestorExport -Name 'Root page' -Responses @((New-AncestorBatch @())) -ExpectedIds @() -ExpectedRequests @('/wiki/api/v2/pages/99999/ancestors?limit=250')
    Test-AncestorExport -Name 'Short hierarchy' -Responses @((New-AncestorBatch @(1, 2))) -ExpectedIds @(1, 2) -ExpectedRequests @('/wiki/api/v2/pages/99999/ancestors?limit=250')
    Test-AncestorExport -Name 'Exact limit' -Responses @((New-AncestorBatch (1..250)), (New-AncestorBatch @())) -ExpectedIds (1..250) -ExpectedRequests @('/wiki/api/v2/pages/99999/ancestors?limit=250', '/wiki/api/v2/pages/1/ancestors?limit=250')
    Test-AncestorExport -Name 'Beyond limit' -Responses @((New-AncestorBatch (2..251)), (New-AncestorBatch @(1))) -ExpectedIds (1..251) -ExpectedRequests @('/wiki/api/v2/pages/99999/ancestors?limit=250', '/wiki/api/v2/pages/2/ancestors?limit=250')
    Test-AncestorExport -Name 'Multiple full batches' -Responses @((New-AncestorBatch (251..500)), (New-AncestorBatch (1..250)), (New-AncestorBatch @())) -ExpectedIds (1..500) -ExpectedRequests @('/wiki/api/v2/pages/99999/ancestors?limit=250', '/wiki/api/v2/pages/251/ancestors?limit=250', '/wiki/api/v2/pages/1/ancestors?limit=250')
    foreach ($contentType in @('folder', 'whiteboard', 'database', 'embed')) {
        $batch = New-AncestorBatch (2..251)
        $batch.results[0].type = $contentType
        Test-AncestorExport -Name "$contentType continuation" -Responses @($batch, (New-AncestorBatch @(1))) -ExpectedIds (1..251) -ExpectedRequests @('/wiki/api/v2/pages/99999/ancestors?limit=250', "/wiki/api/v2/$($contentType)s/2/ancestors?limit=250")
    }
    Test-AncestorExport -Name 'Continuation failure' -Responses @((New-AncestorBatch (2..251)), [InvalidOperationException]::new('Offline failure')) -ExpectedIds @(777) -ExpectedRequests @('/wiki/api/v2/pages/99999/ancestors?limit=250', '/wiki/api/v2/pages/2/ancestors?limit=250') -ExpectWarning
    Test-AncestorExport -Name 'Repeated ancestor' -Responses @((New-AncestorBatch (2..251)), (New-AncestorBatch @(2))) -ExpectedIds @(777) -ExpectedRequests @('/wiki/api/v2/pages/99999/ancestors?limit=250', '/wiki/api/v2/pages/2/ancestors?limit=250') -ExpectWarning
    Test-AncestorExport -Name 'Self cycle' -Responses @((New-AncestorBatch @(99999))) -ExpectedIds @(777) -ExpectedRequests @('/wiki/api/v2/pages/99999/ancestors?limit=250') -ExpectWarning

    & {
        $buildScript = Join-Path $repository 'build_and_push.ps1'
        $buildParameters = @{ ImageName = 'example/offline'; Version = 'test' }
        # Use an isolated script copy so these checks never read a real .env.
        $buildFixture = Join-Path $testRoot 'build fixture'
        New-Item -ItemType Directory -Path $buildFixture | Out-Null
        $isolatedBuildScript = Join-Path $buildFixture 'build_and_push.ps1'
        Copy-Item -LiteralPath $buildScript -Destination $isolatedBuildScript
        $envFile = Join-Path $buildFixture '.env'
        @'
AtlassianPowerKit_PROFILE_NAME=should-not-be-loaded
DOCKER_IMAGE_NAME=example/should-not-be-used
DOCKER_IMAGE_VERSION=should-not-be-used
DOCKER_PUSH=true
DOCKER_LATEST=true
DOCKER_TEST_RUN=true
DOCKER_MULTI_ARCH=true
'@ | Set-Content -LiteralPath $envFile
        $dockerState = @{
            Calls = [System.Collections.Generic.List[object]]::new()
            FailureCommand = ''
        }
        Set-Item Function:\docker -Value {
            $dockerState.Calls.Add([string[]]$args)
            $global:LASTEXITCODE = if ($args[0] -eq $dockerState.FailureCommand) { 23 } else { 0 }
        }.GetNewClosure()

        # Simulate old DOCKER_* values already inherited from the calling shell.
        $env:DOCKER_IMAGE_NAME = 'example/should-not-be-used'
        $env:DOCKER_IMAGE_VERSION = 'should-not-be-used'
        foreach ($name in @('DOCKER_PUSH', 'DOCKER_LATEST', 'DOCKER_TEST_RUN', 'DOCKER_MULTI_ARCH')) {
            Set-Item -Path "env:$name" -Value 'true'
        }
        & $isolatedBuildScript | Out-Null
        Assert-Condition ($dockerState.Calls.Count -eq 1 -and $dockerState.Calls[0][0] -eq 'build') 'Default to one local build regardless of .env and inherited DOCKER_* values'
        Assert-Condition ($dockerState.Calls[0][2] -match '^markz0r/atlassian-powerkit:\d{4}\.\d{2}\.\d{2}\.\d{4}$') 'Use the default image and timestamp without environment settings'
        Assert-Condition ($env:AtlassianPowerKit_PROFILE_NAME -eq 'offline') 'Do not import runtime credentials or change the host profile during builds'
        Assert-Condition (($dockerState.Calls[0] -join '|') -notmatch '--build-arg|--env|should-not-be') 'Do not forward runtime configuration to Docker build'

        Remove-Item -LiteralPath $envFile -Force
        $dockerState.Calls.Clear()
        & $isolatedBuildScript @buildParameters | Out-Null
        Assert-Condition (($dockerState.Calls[0] -join '|') -eq "build|--tag|example/offline:test|$buildFixture") 'Build with explicit parameters when no .env exists, preserving paths with spaces'

        $dockerState.Calls.Clear()
        Push-Location $testRoot
        try {
            & $buildScript @buildParameters -Latest | Out-Null
        } finally { Pop-Location }
        Assert-Condition ($dockerState.Calls.Count -eq 2) 'Build both versioned and latest tags'
        Assert-Condition ($dockerState.Calls[1][2] -eq 'example/offline:latest') 'Interpolate the latest tag correctly'
        Assert-Condition ($dockerState.Calls[0][-1] -eq $repository) 'Build from the script directory, not the caller directory'

        $dockerState.Calls.Clear()
        & $buildScript @buildParameters -SkipBuild -TestRun | Out-Null
        Assert-Condition ($dockerState.Calls.Count -eq 1 -and $dockerState.Calls[0][0] -eq 'run') 'Skip builds and pushes for smoke-only runs'
        Assert-Condition (($dockerState.Calls[0][2..4] -join '|') -eq '--entrypoint|pwsh|example/offline:test') 'Override the entrypoint without passing a second executable'
        Assert-Condition ($dockerState.Calls[0][-1] -match '/app' -and $dockerState.Calls[0][-1] -match 'Export-JiraProjectIssues') 'Smoke-check packaged modules at the application path'

        $dockerState.Calls.Clear()
        & $buildScript @buildParameters -MultiArch -Push -Latest | Out-Null
        Assert-Condition (($dockerState.Calls[0] -join '|') -eq 'buildx|ls') 'Check buildx before multi-platform builds'
        $multiArguments = $dockerState.Calls[1]
        Assert-Condition ($multiArguments -contains '--push' -and $multiArguments -notcontains '--load') 'Preserve multi-platform push selection'
        Assert-Condition ($multiArguments -contains 'example/offline:latest' -and $multiArguments[-1] -eq $repository) 'Pass tags and context as separate native arguments'
        Assert-Condition (($multiArguments -join '|') -notmatch '--build-arg|--env|should-not-be') 'Do not forward runtime configuration to buildx'

        $dockerState.Calls.Clear()
        & $buildScript @buildParameters -MultiArch | Out-Null
        Assert-Condition ($dockerState.Calls[1] -contains '--load' -and $dockerState.Calls[1] -notcontains '--push') 'Require an explicit switch to push multi-platform images'

        foreach ($failureCommand in @('build', 'push', 'run', 'buildx')) {
            $dockerState.Calls.Clear()
            $dockerState.FailureCommand = $failureCommand
            $parameters = @{ ImageName = 'example/offline'; Version = 'test'; Push = $true; TestRun = $true }
            if ($failureCommand -eq 'run') { $parameters.SkipBuild = $true }
            if ($failureCommand -eq 'buildx') { $parameters.MultiArch = $true }
            Assert-Throws { & $buildScript @parameters } "*Docker '$failureCommand' failed with exit code 23*"
            Assert-Condition ($dockerState.Calls[-1][0] -eq $failureCommand) "Stop immediately after $failureCommand fails"
        }
    }

    Write-Output "PASS: $script:assertionCount offline regression assertions."
} finally {
    foreach ($name in $environmentNames) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }
    $global:LASTEXITCODE = $savedLastExitCode
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
