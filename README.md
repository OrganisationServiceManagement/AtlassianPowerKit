# AtlassianPowerKit

- Various functions in PowerShell to interact with Atlassian Cloud APIs
- Supports multiple profiles for different Atlassian Cloud accounts
- Docker image available for cross-platform support (Windows, macOS, Linux):
  - [markz0r/atlassian-powerkit](https://hub.docker.com/r/markz0r/atlassian-powerkit)

## Usage

```powershell
git clone https://github.com/OrganisationServiceManagement/AtlassianPowerKit.git
cd .\AtlassianPowerKit
Copy-Item .\env_example .\.env
# Edit .env and fill in the required values.
Import-Module ".\AtlassianPowerKit.psd1"
AtlassianPowerKit
```

## Configuration

AtlassianPowerKit reads configuration from `.env` in the repository root. Copy `env_example` to `.env`, then set the required values:

```dotenv
AtlassianPowerKit_PROFILE_NAME=default
AtlassianPowerKit_ENDPOINT=example.atlassian.net
AtlassianPowerKit_UserName=user@example.com
AtlassianPowerKit_APIKey=your_atlassian_api_token
```

`.env` is ignored by Git. The module fails fast if any required profile values are missing instead of prompting interactively.
Nested modules resolve their dependencies relative to their own files, independently of the working directory or `OSM_INSTALL`.

```powershell
# Text UI
AtlassianPowerKit
# Direct invocation (after .env configured)
AtlassianPowerKit -FunctionName "Get-JiraIssue" -FunctionParameters @{"Key"="TEST-1"}
```

The container starts PowerShell, imports the toolkit from `/app`, and runs `AtlassianPowerKit`. Export data belongs in `/mnt/osm`, separate from the application files. Override the host's `OSM_HOME` when passing `.env` to Docker:

```powershell
# Windows
New-Item -ItemType Directory -Path .\osm_home -Force
docker run --rm --env-file .env -e OSM_HOME=/mnt/osm -v "${PWD}\osm_home:/mnt/osm" -it markz0r/atlassian-powerkit:latest
```

```bash
# Linux/macOS
mkdir ./osm_home
docker run --rm --env-file .env -e OSM_HOME=/mnt/osm -v "${PWD}/osm_home:/mnt/osm" -it markz0r/atlassian-powerkit:latest
```

### Building the Docker image

`build_and_push.ps1` also reads `.env`. Set `DOCKER_IMAGE_NAME` in `.env`; optional build flags include `DOCKER_IMAGE_VERSION`, `DOCKER_PUSH`, `DOCKER_LATEST`, `DOCKER_TEST_RUN`, and `DOCKER_MULTI_ARCH`.

```powershell
.\build_and_push.ps1 -TestRun
# Check an existing image without building or pushing:
.\build_and_push.ps1 -SkipBuild -TestRun -Version 'your-existing-tag'
```

The build context includes application modules, not local `.env` files, profiles, or exports. The smoke check imports every packaged module without requiring Atlassian credentials. Docker command failures stop the script instead of reporting a successful build.

Confluence space-list snapshots include a local timestamp in each filename. Page exports traverse all ancestor batches in root-to-parent order, including folder and other supported content ancestors, to preserve the complete hierarchy.

## Documentation

- _[AtlassianPowerKit Wiki](../../wiki)_

## Dependencies

- PowerShell 7.3 or later (Core is supported on Windows, macOS, and Linux)
- Alternatively, you can use the Docker image to run the module:
  - Use the Docker commands above to mount export data without hiding the application files.

## Contributing

Contributions are welcome! If you find any issues or have suggestions for improvements, please open an issue or submit a pull request.

Run the offline regression checks with `pwsh -NoProfile -File .\tests\Test-Regression.ps1`. They do not use a real Atlassian account or invoke Docker.

## License

See [LICENSE](LICENSE.md) file.

## Disclaimer

This module is provided as-is without any warranty or support. Use it at your own risk.
