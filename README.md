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

```powershell
# Text UI
AtlassianPowerKit
# Direct invocation (after .env configured)
AtlassianPowerKit -FunctionName "Get-JiraIssue" -FunctionParameters @{"Key"="TEST-1"}
```

```docker
# These examples assume `.env` contains `OSM_HOME=./osm_home`.
# Windows
mkdir .\osm_home
docker run --rm --env-file .env -v ${PWD}\osm_home:/mnt/osm -v "$Env:LOCALAPPDATA\Microsoft\PowerShell\secretmanagement\:/root/.secretmanagement/" -it markz0r/atlassian-powerkit:latest

# Linux
mkdir ./osm_home
docker run -it --rm --env-file .env -v ${PWD}/osm_home:/mnt/osm -v "$HOME/.local/share/powershell/secretmanagement/:/root/.secretmanagement/" markz0r/atlassian-powerkit:latest
```

### Building the Docker image

`build_and_push.ps1` also reads `.env`. Set `DOCKER_IMAGE_NAME` in `.env`; optional build flags include `DOCKER_IMAGE_VERSION`, `DOCKER_PUSH`, `DOCKER_LATEST`, `DOCKER_TEST_RUN`, and `DOCKER_MULTI_ARCH`.

## Documentation

- _[AtlassianPowerKit Wiki](../../wiki)_

## Dependencies

- PowerShell 7.0 or later (Core is supported on Windows, macOS, and Linux)
- Alternatively, you can use the Docker image to run the module:
  - `docker run --rm --env-file .env -v ${PWD}\osm_home:/mnt/osm -v "$Env:LOCALAPPDATA\Microsoft\PowerShell\secretmanagement\:/root/.secretmanagement/" -it markz0r/atlassian-powerkit:latest`
  - Ensure the mounted host path matches `OSM_HOME` in `.env`.

## Contributing

Contributions are welcome! If you find any issues or have suggestions for improvements, please open an issue or submit a pull request.

## License

See [LICENSE](LICENSE.md) file.

## Disclaimer

This module is provided as-is without any warranty or support. Use it at your own risk.
