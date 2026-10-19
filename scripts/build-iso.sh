#!/usr/bin/env bash
# ==============================================================================
# AllGlider Live Linux - Fedora 44 Live ISO Builder
# Builds AllGlider Live Linux ISO inside a clean rootless Fedora 44 container
# (or on host via livemedia-creator with --host).
# ==============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/config/versions.lock"

BUILD_DIR="$REPO_ROOT/build"
MODE="container"
SKIP_PROTON="false"

while [ $# -gt 0 ]; do
    case "$1" in
        --host)
            MODE="host"
            shift
            ;;
        --container)
            MODE="container"
            shift
            ;;
        --skip-proton)
            SKIP_PROTON="true"
            shift
            ;;
        *)
            echo "Unknown argument: $1" >&2
            echo "Usage: $0 [--container|--host] [--skip-proton]" >&2
            exit 1
            ;;
    esac
done

chmod +x "$REPO_ROOT/scripts/build-iso-container-inner.sh"

# 1. Stage offline assets (WinBridge, AllGlider, Branding, and optionally GE-Proton)
STAGE_ARGS=()
if [ "$SKIP_PROTON" = "true" ]; then
    STAGE_ARGS+=("--skip-proton")
fi
"$REPO_ROOT/scripts/stage-assets.sh" "${STAGE_ARGS[@]}"

mkdir -p "$BUILD_DIR" "$REPO_ROOT/cache/dnf-f44"
ISO_NAME="AllGlider-Live-F${FEDORA_RELEASE}-${ALLGLIDER_DISTRO_VERSION}-x86_64.iso"

if [ "$MODE" = "container" ]; then
    echo "=== Building Fedora ${FEDORA_RELEASE} Live ISO inside rootless Fedora ${FEDORA_RELEASE} container ==="
    podman run --rm \
        --security-opt label=disable \
        -v "$REPO_ROOT:/workspace" \
        -v "$REPO_ROOT/cache/dnf-f44:/var/cache/libdnf5" \
        -v "/var/tmp/allglider-staging:/var/tmp/allglider-staging" \
        -v "/usr/lib64/libcrypto.so.4.0.3:/usr/lib64/libcrypto.so.4.0.3:ro" \
        -v "/usr/lib64/libssl.so.4.0.3:/usr/lib64/libssl.so.4.0.3:ro" \
        "registry.fedoraproject.org/fedora:${FEDORA_RELEASE}" \
        /workspace/scripts/build-iso-container-inner.sh
else
    echo "=== Building Fedora ${FEDORA_RELEASE} Live ISO directly on host ==="
    ksvalidator "$REPO_ROOT/config/fedora-live.ks"
    sudo rm -rf "$BUILD_DIR/lmc-result"
    sudo livemedia-creator \
        --ks "$REPO_ROOT/config/fedora-live.ks" \
        --no-virt \
        --resultdir "$BUILD_DIR/lmc-result" \
        --project "AllGlider-Live-Linux" \
        --make-iso \
        --volid "ALLGLIDER_LIVE" \
        --iso-only \
        --iso-name "${ISO_NAME}" \
        --releasever "${FEDORA_RELEASE}" \
        --nomacboot
    sudo chown -R "$(id -u):$(id -g)" "$BUILD_DIR"
    if [ -f "$BUILD_DIR/lmc-result/${ISO_NAME}" ]; then
        mv -f "$BUILD_DIR/lmc-result/${ISO_NAME}" "$BUILD_DIR/${ISO_NAME}"
        (cd "$BUILD_DIR" && sha256sum "${ISO_NAME}" > "${ISO_NAME}.sha256")
    fi
fi

echo "=== ISO Build Finished: $BUILD_DIR/${ISO_NAME} ==="
