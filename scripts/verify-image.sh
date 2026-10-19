#!/usr/bin/env bash
# ==============================================================================
# AllGlider Live Linux - Image & Configuration Verifier
# Validates Kickstart syntax, shell/python scripts, and built ISO structure.
# ==============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/config/versions.lock"

echo "=== [1/4] Checking shell script syntax (bash -n) ==="
for sh_file in "$REPO_ROOT"/scripts/*.sh "$REPO_ROOT"/installer/migration/*.sh; do
    bash -n "$sh_file"
    echo "  OK: $(basename "$sh_file")"
done

echo "=== [2/4] Checking Python syntax (py_compile) ==="
python3 -m py_compile \
    "$REPO_ROOT/scripts/fetch-latest-allglider.py" \
    "$REPO_ROOT/installer/first-boot-restore/allglider-welcome.py" \
    "$REPO_ROOT/installer/ui/allglider-installer.py"
echo "  OK: Python scripts compiled cleanly"

echo "=== [3/4] Checking Kickstart file ==="
if command -v ksvalidator >/dev/null 2>&1; then
    ksvalidator "$REPO_ROOT/config/fedora-live.ks"
    echo "  OK: config/fedora-live.ks validated with ksvalidator"
else
    echo "  INFO: ksvalidator not installed on host (will be validated in Fedora ${FEDORA_RELEASE} build container)"
fi

echo "=== [4/4] Checking built ISO artifact (if present) ==="
ISO_PATH="${1:-$REPO_ROOT/build/AllGlider-Live-F${FEDORA_RELEASE}-${ALLGLIDER_DISTRO_VERSION}-x86_64.iso}"
if [ -f "$ISO_PATH" ]; then
    SIZE_MB=$(du -m "$ISO_PATH" | awk '{print $1}')
    echo "  Found ISO: $ISO_PATH (${SIZE_MB} MiB)"
    if [ -f "${ISO_PATH}.sha256" ]; then
        (cd "$(dirname "$ISO_PATH")" && sha256sum -c "$(basename "${ISO_PATH}.sha256")")
    fi
else
    echo "  INFO: ISO not built yet ($ISO_PATH). Run ./scripts/build-iso.sh to build."
fi

echo "=== Verification Passed ==="
