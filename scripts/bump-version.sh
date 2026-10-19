#!/usr/bin/env bash
# ==============================================================================
# AllGlider Live Linux - Distro Version Bumper
# Increments the patch version (e.g. 0.1.0 -> 0.1.1) in VERSION & config/versions.lock.
# Accepts optional custom version argument: ./scripts/bump-version.sh [version]
# ==============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$REPO_ROOT/VERSION"
LOCK_FILE="$REPO_ROOT/config/versions.lock"

if [ ! -f "$VERSION_FILE" ]; then
    echo "0.1.0" > "$VERSION_FILE"
fi

CURRENT_VER="$(tr -d '[:space:]' < "$VERSION_FILE")"

if [ $# -gt 0 ] && [ -n "${1:-}" ] && [ "$1" != "--patch" ]; then
    NEW_VER="${1#v}"
else
    IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VER"
    PATCH=$(( ${PATCH:-0} + 1 ))
    NEW_VER="${MAJOR}.${MINOR}.${PATCH}"
fi

echo "$NEW_VER" > "$VERSION_FILE"
if [ -f "$LOCK_FILE" ]; then
    sed -i "s/^ALLGLIDER_DISTRO_VERSION=.*/ALLGLIDER_DISTRO_VERSION=\"${NEW_VER}\"/" "$LOCK_FILE"
fi

echo "Version bumped: ${CURRENT_VER} -> ${NEW_VER}"
