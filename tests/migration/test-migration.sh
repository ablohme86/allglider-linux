#!/usr/bin/env bash
# ==============================================================================
# AllGlider Live Linux - Automated Migration Unit Test
# Verifies that installer/migration/migrate-data.sh transfers allowlisted user
# data (AllGlider, WinBridge, Proton prefix) and excludes temporary cache/locks.
# ==============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR=$(mktemp -d /tmp/allglider-mig-test.XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

SRC_HOME="$TMP_DIR/src_home"
TARGET_ROOT="$TMP_DIR/target_root"

mkdir -p \
    "$SRC_HOME/AllGlider/data" \
    "$SRC_HOME/.config/winbridge" \
    "$SRC_HOME/.local/share/winbridge/shared/pfx/drive_c/users/steamuser/Temp" \
    "$SRC_HOME/.cache/mesa_shader_cache"

echo "test-profile" > "$SRC_HOME/AllGlider/data/profile.json"
echo '{"proton": "/opt/allglider/proton/GE-Proton11-10"}' > "$SRC_HOME/.config/winbridge/settings.json"
echo "lock" > "$SRC_HOME/.local/share/winbridge/shared/pfx.lock"
echo "temp-junk" > "$SRC_HOME/.local/share/winbridge/shared/pfx/drive_c/users/steamuser/Temp/junk.tmp"
echo "shader" > "$SRC_HOME/.cache/mesa_shader_cache/blob"

# Run migration script (without root chown failure if run as normal user)
bash -c '
    chown() { true; }
    export -f chown
    "$0" "$1" --source-home "$2"
' "$REPO_ROOT/installer/migration/migrate-data.sh" "$TARGET_ROOT" "$SRC_HOME"

# Assertions
test -f "$TARGET_ROOT/home/liveuser/AllGlider/data/profile.json"
test -f "$TARGET_ROOT/home/liveuser/.config/winbridge/settings.json"
test ! -f "$TARGET_ROOT/home/liveuser/.local/share/winbridge/shared/pfx.lock"
test ! -f "$TARGET_ROOT/home/liveuser/.local/share/winbridge/shared/pfx/drive_c/users/steamuser/Temp/junk.tmp"
test ! -d "$TARGET_ROOT/home/liveuser/.cache"
test -f "$TARGET_ROOT/var/log/allglider-migration-report.json"

echo "PASS: Migration allowlist, cache/lock exclusion, and report generation verified!"
