#!/usr/bin/env bash
# ==============================================================================
# AllGlider Live Linux - Offline Asset Stager
# Prepares WinBridge, AllGlider, GE-Proton, UMU Runtime, and installer scripts
# in /var/tmp/allglider-staging before Kickstart ISO creation.
# ==============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/config/versions.lock"

CACHE_DIR="$REPO_ROOT/cache"
STAGING_DIR="/var/tmp/allglider-staging"
SKIP_PROTON="false"

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-proton)
            SKIP_PROTON="true"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

mkdir -p "$CACHE_DIR"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"/{config,scripts,installer,branding,src,app,proton,umu-runtime}

echo "=== [1/4] Staging project scripts, configs, branding, and installer ==="
if [ -f "$REPO_ROOT/scripts/generate-plymouth-assets.py" ]; then
    python3 "$REPO_ROOT/scripts/generate-plymouth-assets.py"
fi
if [ -f "$REPO_ROOT/branding/wallpapers/generate-wallpaper.py" ]; then
    python3 "$REPO_ROOT/branding/wallpapers/generate-wallpaper.py"
fi
cp -a "$REPO_ROOT/config/." "$STAGING_DIR/config/"
cp -a "$REPO_ROOT/scripts/." "$STAGING_DIR/scripts/"
cp -a "$REPO_ROOT/installer/." "$STAGING_DIR/installer/"
cp -a "$REPO_ROOT/branding/." "$STAGING_DIR/branding/"

echo "=== [2/4] Staging WinBridge (${WINBRIDGE_COMMIT}) ==="
if [ ! -d "$CACHE_DIR/winbridge/.git" ]; then
    git clone "$WINBRIDGE_REPO" "$CACHE_DIR/winbridge"
fi
git -C "$CACHE_DIR/winbridge" fetch --all --tags
git -C "$CACHE_DIR/winbridge" checkout --force "$WINBRIDGE_COMMIT"
cp -a "$CACHE_DIR/winbridge" "$STAGING_DIR/src/winbridge"

echo "=== [3/4] Staging AllGlider (${ALLGLIDER_VERSION}) ==="
LOCAL_AG_TARBALL="/home/alexander/Projects/openglider/dist/${ALLGLIDER_TARBALL}"
if [ -f "$LOCAL_AG_TARBALL" ] && [ ! -f "$CACHE_DIR/${ALLGLIDER_TARBALL}" ]; then
    cp "$LOCAL_AG_TARBALL" "$CACHE_DIR/${ALLGLIDER_TARBALL}"
fi

if [ -f "$CACHE_DIR/${ALLGLIDER_TARBALL}" ]; then
    echo "${ALLGLIDER_SHA256}  $CACHE_DIR/${ALLGLIDER_TARBALL}" | sha256sum -c -
    tar -xzf "$CACHE_DIR/${ALLGLIDER_TARBALL}" --strip-components=1 -C "$STAGING_DIR/app"
else
    echo "WARNING: ${ALLGLIDER_TARBALL} not found in cache or ../openglider/dist/."
fi

echo "=== [4/4] Staging Offline GE-Proton (${PROTON_VERSION}) ==="
if [ "$SKIP_PROTON" = "true" ]; then
    echo "Skipping GE-Proton download (--skip-proton enabled for fast base build)."
else
    PROTON_ARCHIVE="$CACHE_DIR/$(basename "$PROTON_URL")"
    PROTON_SHA_FILE="$CACHE_DIR/$(basename "$PROTON_SHA512_URL")"

    if [ ! -f "$PROTON_ARCHIVE" ]; then
        echo "Downloading $(basename "$PROTON_URL")..."
        curl -fL --retry 3 -o "$PROTON_ARCHIVE.part" "$PROTON_URL"
        mv "$PROTON_ARCHIVE.part" "$PROTON_ARCHIVE"
    fi
    if [ ! -f "$PROTON_SHA_FILE" ]; then
        curl -fL --retry 3 -o "$PROTON_SHA_FILE" "$PROTON_SHA512_URL"
    fi

    echo "Verifying $(basename "$PROTON_URL") SHA512 checksum..."
    (cd "$CACHE_DIR" && sha512sum -c "$PROTON_SHA_FILE")

    echo "Extracting $(basename "$PROTON_URL") into staging directory..."
    tar -xzf "$PROTON_ARCHIVE" -C "$STAGING_DIR/proton"

    if [ -d "$STAGING_DIR/proton/${PROTON_VERSION}-x86_64" ] && [ ! -d "$STAGING_DIR/proton/${PROTON_VERSION}" ]; then
        ln -sf "${PROTON_VERSION}-x86_64" "$STAGING_DIR/proton/${PROTON_VERSION}"
    fi
fi

echo "=== Staging Complete at $STAGING_DIR ==="
