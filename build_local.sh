#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: ./build_local.sh [options]

Build and load an image into the current Docker daemon.
Runtime .env files are never read. This script does not publish images.

Options:
  --image-name NAME  Image repository (default: markz0r/atlassian-powerkit)
  --version TAG      Image tag (default: yyyy.MM.dd.HHmm timestamp)
  --latest           Also tag the image as latest
  --no-cache         Build without cached layers
  --pull             Check for an updated base image
  -h, --help         Show this help
EOF
}

image_name='markz0r/atlassian-powerkit'
version=''
tag_latest=false
docker_arguments=(build --load)

while (( $# > 0 )); do
    case "$1" in
        --image-name|--version)
            if (( $# < 2 )) || [[ -z "$2" || "$2" == -* ]]; then
                printf 'Error: %s requires a value.\n' "$1" >&2
                exit 2
            fi
            if [[ "$1" == --image-name ]]; then
                image_name=$2
            else
                version=$2
            fi
            shift 2
            ;;
        --latest)
            tag_latest=true
            shift
            ;;
        --no-cache|--pull)
            docker_arguments+=("$1")
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Error: unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd -P)
for required_file in Dockerfile .dockerignore; do
    if [[ ! -f "$script_dir/$required_file" ]]; then
        printf 'Error: required build file missing: %s\n' "$script_dir/$required_file" >&2
        exit 1
    fi
done

if ! command -v docker >/dev/null 2>&1; then
    printf 'Error: Docker CLI is required.\n' >&2
    exit 1
fi

version=${version:-$(date +%Y.%m.%d.%H%M)}
tags=("$image_name:$version")
if [[ "$tag_latest" == true && "$version" != latest ]]; then
    tags+=("$image_name:latest")
fi

# Use argument arrays and the repository context; never source runtime .env files.
for tag in "${tags[@]}"; do
    docker_arguments+=(--tag "$tag")
done
docker_arguments+=("$script_dir")

printf 'Building local image: %s\n' "${tags[0]}"
docker "${docker_arguments[@]}"
printf 'Local image ready: %s\n' "${tags[@]}"
