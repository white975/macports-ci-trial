#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
if [[ $OSTYPE == darwin* ]]; then
    export PATH=/opt/local/bin:/opt/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin
fi

port=/opt/local/bin/port
ports=(docker docker-buildx-plugin docker-compose-plugin docker-sandboxes forgejo-runner forgejo-cli)
overlay=/Users/Shared/macports-ci-overlay
sources=/opt/local/etc/macports/sources.conf

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

setup() {
    [[ $(uname -s) == Darwin && $(uname -m) == arm64 && $(sw_vers -productVersion) == 15.* ]] || fail 'expected macOS 15 arm64'
    [[ ! -e $port && ! -e $overlay && ! -e $sources ]] || fail 'setup requires a clean test machine'
    local repo macports_pkg sha
    repo=$(cd "$(dirname "$0")/.." && pwd -P)
    tmp=$(mktemp -d)
    trap 'rm -rf -- "$tmp"' EXIT
    macports_pkg=MacPorts-2.12.7-15-Sequoia.pkg
    sha=87b2e87ed7adc4aca947b42eb7ff991614cc0edfccb486237f2bbc75f28aae63
    curl -fsSL --retry 2 -o "$tmp/$macports_pkg" "https://github.com/macports/macports-base/releases/download/v2.12.7/$macports_pkg"
    (cd "$tmp"; printf '%s  %s\n' "$sha" "$macports_pkg" | shasum -a 256 -c -)
    mkdir -p "$overlay"
    cp -R "$repo/devel" "$overlay/"
    chmod -R a+rX "$overlay"
    sudo mkdir -p "$(dirname "$sources")"
    printf 'file://%s [nosync]\nhttps://ftp.fau.de/macports/release/tarballs/ports.tar.gz [default]\n' "$overlay" | sudo tee "$sources" >/dev/null
    sudo installer -pkg "$tmp/$macports_pkg" -target /
    sudo "$port" -N sync
    "$port" version
    rm -rf -- "$tmp"
    trap - EXIT
}

lint() {
    local output name path
    output=$(cd "$overlay" && /opt/local/bin/portindex) || fail 'portindex failed'
    printf '%s\n' "$output"
    grep -Eq '^Ports failed:[[:space:]]+0[[:space:]]*$' <<<"$output" || fail 'index has failed recipes'
    for name in "${ports[@]}"; do
        path=$("$port" -q file "$name")
        [[ $path == "$overlay/devel/$name/Portfile" ]] || fail "$name resolved to $path"
        if ! output=$("$port" lint --nitpick "$name" 2>&1); then
            printf '%s\n' "$output" >&2
            fail "lint could not run for $name"
        fi
        printf '%s\n' "$output"
        grep -Fq '0 errors and 0 warnings found.' <<<"$output" || fail "lint reported findings for $name"
    done
    printf 'Indexed and linted %s overlay ports\n' "${#ports[@]}"
}

install_ports() {
    local name item deps
    local excluded=(and not \( docker or docker-buildx-plugin or docker-compose-plugin or docker-sandboxes or forgejo-runner or forgejo-cli \))
    for name in "${ports[@]}"; do
        [[ $("$port" -q file "$name") == "$overlay/devel/$name/Portfile" ]] || fail "wrong recipe for $name"
        # Let MacPorts use archives for dependencies, never for the overlay itself.
        deps=$("$port" -q echo "rdepof:$name" "${excluded[@]}")
        if [[ -n $deps ]]; then
            while IFS= read -r item; do
                [[ $item =~ ^[[:alnum:]][[:alnum:]_.+-]*$ ]] || fail "unexpected dependency name: $item"
                case $item in
                    docker|docker-buildx-plugin|docker-compose-plugin|docker-sandboxes|forgejo-runner|forgejo-cli)
                        fail "overlay port leaked into the dependency install: $item" ;;
                esac
            done <<<"$deps"
            sudo "$port" -N install --no-rev-upgrade "rdepof:$name" "${excluded[@]}"
        fi
        sudo "$port" -Ns install "$name"
        "$port" installed "$name"
    done
}

expect_version() {
    local name=$1 version output version_pattern
    shift
    version=$("$port" -q info --version "$name")
    [[ $version =~ ^[0-9]+(\.[0-9]+)+$ ]] || fail "could not determine expected version for $name"
    output=$("$@") || fail "command failed: $*"
    printf '%s: %s\n' "$name" "$output"
    version_pattern="(^|[[:space:]])v?${version//./\.}([[:space:],+]|$)"
    [[ $output =~ $version_pattern ]] || fail "expected $name version $version"
}

smoke() {
    config=$(mktemp -d)
    trap 'rm -rf -- "$config"' EXIT
    unset DOCKER_HOST DOCKER_CONTEXT
    expect_version docker /opt/local/bin/docker --version
    expect_version docker-buildx-plugin /opt/local/bin/docker --config "$config" buildx version
    expect_version docker-compose-plugin /opt/local/bin/docker --config "$config" compose version
    expect_version docker-sandboxes /opt/local/bin/sbx version
    expect_version forgejo-runner /opt/local/bin/forgejo-runner --version
    expect_version forgejo-cli /opt/local/bin/fj version
    rm -rf -- "$config"
    trap - EXIT
}

case ${1:-} in
    setup) setup ;;
    lint) lint ;;
    install) install_ports ;;
    smoke) smoke ;;
    *) fail 'usage: bash tests/macos.sh {setup|lint|install|smoke}' ;;
esac
