#!/usr/bin/env bash
# ==============================================================================
# AllGlider Live Linux - Release Artifacts Preparer
# Splits the ISO into <= 1900MB chunks for GitHub Releases (which has a 2GB limit)
# and creates join-iso.bat and join-iso.sh helper scripts.
# ==============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build"

ISO_FILE=$(ls "$BUILD_DIR"/*.iso 2>/dev/null | head -n 1 || true)
if [ -z "$ISO_FILE" ] || [ ! -f "$ISO_FILE" ]; then
    echo "ERROR: No ISO file found in $BUILD_DIR" >&2
    exit 1
fi

ISO_BASENAME="$(basename "$ISO_FILE")"
echo "=== Preparing Release Artifacts for $ISO_BASENAME ==="

# 1. Compute SHA256 of the complete ISO
echo "Computing SHA256 of $ISO_BASENAME..."
(cd "$BUILD_DIR" && sha256sum "$ISO_BASENAME" > "${ISO_BASENAME}.sha256")
cat "$BUILD_DIR/${ISO_BASENAME}.sha256"

# 2. Split ISO into <= 1900MB chunks
echo "Splitting ISO into 1900MB parts (.001, .002, ...)..."
split -d -a 3 --numeric-suffixes=1 -b 1900M "$ISO_FILE" "$BUILD_DIR/${ISO_BASENAME}."

# 3. Create Windows batch join script
JOIN_CMD="copy /b"
FIRST=1
for part in $(ls "$BUILD_DIR/${ISO_BASENAME}".0*); do
    BN="$(basename "$part")"
    if [ $FIRST -eq 1 ]; then
        JOIN_CMD="$JOIN_CMD \"$BN\""
        FIRST=0
    else
        JOIN_CMD="$JOIN_CMD + \"$BN\""
    fi
done
JOIN_CMD="$JOIN_CMD \"${ISO_BASENAME}\""

cat > "$BUILD_DIR/join-iso.bat" << EOF
@echo off
setlocal
title AllGlider Live ISO Reassembler
echo ========================================================
echo  AllGlider Live Linux - ISO Reassembler
echo ========================================================
echo.
echo Merging ISO chunks into ${ISO_BASENAME}...
$JOIN_CMD
if not exist "${ISO_BASENAME}" (
    echo.
    echo ERROR: Failed to merge ISO chunks!
    pause
    exit /b 1
)
echo.
echo Calculating SHA-256 checksum...
certutil -hashfile "${ISO_BASENAME}" SHA256
echo.
echo Success! ${ISO_BASENAME} is ready to flash with Rufus or BalenaEtcher.
echo ========================================================
pause
EOF
sed -i 's/$/\r/' "$BUILD_DIR/join-iso.bat"

# 4. Create Linux/macOS join script
cat > "$BUILD_DIR/join-iso.sh" << EOF
#!/usr/bin/env bash
set -euo pipefail
echo "=== AllGlider Live Linux - ISO Reassembler ==="
echo "Merging ISO chunks into ${ISO_BASENAME}..."
cat "${ISO_BASENAME}".0* > "${ISO_BASENAME}"
echo "Verifying SHA-256 checksum..."
sha256sum -c "${ISO_BASENAME}.sha256"
echo "=== Success! ${ISO_BASENAME} is ready to flash with Rufus or BalenaEtcher ==="
EOF
chmod +x "$BUILD_DIR/join-iso.sh"

# 5. Remove original oversized ISO so it doesn't get uploaded to GitHub Releases
rm -f "$ISO_FILE"

echo "=== Release Artifacts Ready in $BUILD_DIR: ==="
ls -lh "$BUILD_DIR"
