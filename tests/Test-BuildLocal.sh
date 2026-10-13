#!/usr/bin/env bash
set -euo pipefail

repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null && pwd -P)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
fixture="$test_root/repository with spaces"
mkdir -p "$fixture" "$test_root/bin" "$test_root/caller"
cp "$repository/build_local.sh" "$fixture/build_local.sh"
cp "$repository/.dockerignore" "$fixture/.dockerignore"
printf 'FROM scratch\n' > "$fixture/Dockerfile"

export APK_DOCKER_LOG="$test_root/docker-arguments"
export APK_DOCKER_FAILURE=0
cat > "$test_root/bin/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\0' "$@" >> "$APK_DOCKER_LOG"
exit "$APK_DOCKER_FAILURE"
EOF
chmod +x "$test_root/bin/docker"
export PATH="$test_root/bin:$PATH"
export DOCKER_IMAGE_NAME=example/ignored
export DOCKER_IMAGE_VERSION=ignored
export DOCKER_PUSH=true
export DOCKER_LATEST=true

# Sourcing either runtime file would fail the build and create this marker.
printf 'touch "%s"\nexit 89\n' "$test_root/env-was-sourced" > "$fixture/.env"
cp "$fixture/.env" "$test_root/caller/.env"
cd "$test_root/caller"

assertions=0
assert() {
    if ! "$@"; then
        printf 'FAIL: %s\n' "$*" >&2
        exit 1
    fi
    assertions=$((assertions + 1))
}

read_arguments() {
    docker_args=()
    while IFS= read -r -d '' arg; do
        docker_args+=("$arg")
    done < "$APK_DOCKER_LOG"
}

is_timestamp_tag() {
    [[ $1 =~ ^markz0r/atlassian-powerkit:[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]{4}$ ]]
}

bash "$fixture/build_local.sh" > "$test_root/output"
read_arguments
assert test "${#docker_args[@]}" -eq 5
assert test "${docker_args[0]}" = build
assert test "${docker_args[1]}" = --load
assert test "${docker_args[2]}" = --tag
assert is_timestamp_tag "${docker_args[3]}"
assert test "${docker_args[4]}" = "$fixture"
assert test ! -e "$test_root/env-was-sourced"

rm "$fixture/.env" "$test_root/caller/.env"
: > "$APK_DOCKER_LOG"
bash "$fixture/build_local.sh" --image-name example/local --version dev --latest --no-cache --pull > "$test_root/output"
read_arguments
assert test "${#docker_args[@]}" -eq 9
assert test "${docker_args[2]}" = --no-cache
assert test "${docker_args[3]}" = --pull
assert test "${docker_args[4]}" = --tag
assert test "${docker_args[5]}" = example/local:dev
assert test "${docker_args[6]}" = --tag
assert test "${docker_args[7]}" = example/local:latest
assert test "${docker_args[8]}" = "$fixture"

expect_failure() {
    local expected_status=$1
    shift
    local status=0
    : > "$APK_DOCKER_LOG"
    bash "$fixture/build_local.sh" "$@" > "$test_root/output" 2>&1 || status=$?
    assert test "$status" -eq "$expected_status"
    assert test ! -s "$APK_DOCKER_LOG"
}
expect_failure 2 --push
expect_failure 2 --version
expect_failure 2 --version ''
expect_failure 2 --image-name --latest

mv "$fixture/.dockerignore" "$fixture/ignore.saved"
expect_failure 1
mv "$fixture/ignore.saved" "$fixture/.dockerignore"

: > "$APK_DOCKER_LOG"
APK_DOCKER_FAILURE=23 bash "$fixture/build_local.sh" > "$test_root/output" 2>&1 && status=0 || status=$?
assert test "$status" -eq 23
assert test -s "$APK_DOCKER_LOG"
if grep -q 'Local image ready:' "$test_root/output"; then
    printf 'FAIL: failed build reported success\n' >&2
    exit 1
fi
assertions=$((assertions + 1))

: > "$APK_DOCKER_LOG"
bash "$fixture/build_local.sh" --help > "$test_root/output"
assert test ! -s "$APK_DOCKER_LOG"
printf 'PASS: %s local-build assertions.\n' "$assertions"
