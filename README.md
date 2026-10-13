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

For a local build using Bash on Linux, macOS, or WSL, run:

```bash
./build_local.sh --latest
# Use a custom local image name and tag:
./build_local.sh --image-name atlassian-powerkit --version dev
# Rebuild without cached layers and check for a newer base image:
./build_local.sh --latest --no-cache --pull
./build_local.sh --help
```

The Bash script defaults to `markz0r/atlassian-powerkit` with a timestamp tag; `--latest` adds the tag used in the runtime examples above. It builds from the script's directory, so it can also be invoked from another working directory. Docker and Bash are required. The image is [loaded into the current Docker daemon](https://docs.docker.com/reference/cli/docker/buildx/build/#load) and is not published. The script neither reads `.env` nor uses `DOCKER_*` variables for image names, tags, or publishing.

For PowerShell builds and explicit publishing:

`build_and_push.ps1` does not read or require `.env`. Build settings are explicit parameters: `-ImageName`, `-Version`, `-Push`, `-Latest`, `-TestRun`, and `-MultiArch`. The default image name is `markz0r/atlassian-powerkit`, and the default version is a timestamp. Existing `DOCKER_*` environment variables are ignored; publishing requires `-Push`.

```powershell
.\build_and_push.ps1 -TestRun
# Build and publish explicitly:
.\build_and_push.ps1 -ImageName 'markz0r/atlassian-powerkit' -Version 'your-new-tag' -Latest -Push
# Check an existing image without building or pushing:
.\build_and_push.ps1 -SkipBuild -TestRun -Version 'your-existing-tag'
```

`.env` is runtime configuration only: supply it with `docker run --env-file .env` as shown above ([Docker documentation](https://docs.docker.com/reference/cli/docker/container/run/#env)). The build context excludes `.env` files, profiles, and exports through `.dockerignore`. The smoke check imports every packaged module without requiring Atlassian credentials. Docker command failures stop the script instead of reporting a successful build.

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

Check the Bash build script with `bash tests/Test-BuildLocal.sh`. These checks use a fake Docker command and dummy `.env` files; they do not build or publish an image. Run `shellcheck build_local.sh tests/Test-BuildLocal.sh` for shell linting if ShellCheck is installed.

## License

See [LICENSE](LICENSE.md) file.

## Disclaimer

This module is provided as-is without any warranty or support. Use it at your own risk.
