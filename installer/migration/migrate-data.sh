#!/usr/bin/env bash
# ==============================================================================
# AllGlider Live Linux - Safe User & Application Data Migration Script
# Transfers explicit user configurations, AllGlider profiles, WinBridge prefixes,
# and optional game data from Live USB to an installed target root filesystem.
# Never copies raw Live overlay or machine-specific driver caches.
# ==============================================================================
set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <target-root-mount> [--include-logs] [--source-home <dir>]"
    exit 1
fi

TARGET_ROOT="$1"
shift
INCLUDE_LOGS="false"
SRC_HOME="/home/liveuser"

while [ $# -gt 0 ]; do
    case "$1" in
        --include-logs)
            INCLUDE_LOGS="true"
            shift
            ;;
        --source-home)
            SRC_HOME="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

DST_HOME="$TARGET_ROOT/home/liveuser"
mkdir -p "$DST_HOME"

# 1. Create a versioned backup of key configurations on the USB stick if persistent storage is mounted
if [ -d /mnt/allglider-data ]; then
    BACKUP_DIR="/mnt/allglider-data/backups"
    mkdir -p "$BACKUP_DIR"
    STAMP=$(date +%Y%m%d-%H%M%S)
    BACKUP_FILE="$BACKUP_DIR/pre-migration-config-${STAMP}.tar.zst"
    echo "Creating versioned configuration backup at $BACKUP_FILE..."
    tar --zstd -cf "$BACKUP_FILE" -C "$SRC_HOME" \
        --ignore-failed-read \
        AllGlider \
        .config/winbridge \
        .config/allglider \
        .local/share/applications 2>/dev/null || true
fi

# 2. Check available space on target filesystem vs source data size
SRC_KB=$(du -sk "$SRC_HOME" 2>/dev/null | awk '{print $1}' || echo 0)
DST_FREE_KB=$(df -Pk "$DST_HOME" | awk 'NR==2 {print $4}')
if [ "$SRC_KB" -gt "$DST_FREE_KB" ]; then
    echo "ERROR: Insufficient space on target disk ($DST_FREE_KB KiB free, need $SRC_KB KiB)." >&2
    exit 2
fi

TRANSFERRED=()
SKIPPED=("~/.cache" "Live-USB boot data" "Wine Temp/Cache directories")

copy_item() {
    local rel_path="$1"
    local label="$2"
    if [ -e "$SRC_HOME/$rel_path" ]; then
        echo "Migrating $label ($rel_path)..."
        mkdir -p "$(dirname "$DST_HOME/$rel_path")"
        rsync -aHA \
            --exclude='*.lock' \
            --exclude='pfx.lock' \
            --exclude='drive_c/users/*/Temp/*' \
            --exclude='drive_c/windows/temp/*' \
            "$SRC_HOME/$rel_path" "$(dirname "$DST_HOME/$rel_path")/"
        TRANSFERRED+=("$label")
    else
        SKIPPED+=("$label (not present)")
    fi
}

# Explicit allowlist of migratable items
copy_item "AllGlider" "AllGlider profiles & settings"
copy_item ".config/winbridge" "WinBridge settings"
copy_item ".config/allglider" "AllGlider system configuration"
copy_item ".config/mimeapps.list" "File associations (.exe)"
copy_item ".config/xfce4" "Xfce desktop settings"
copy_item ".local/share/winbridge/shared" "WinBridge shared Windows prefix & Battle.net/WoW"
copy_item ".local/share/umu" "UMU runtime data"
copy_item ".local/share/applications" "Application shortcuts"
copy_item ".local/share/icons" "Extracted application icons"
copy_item "Desktop" "Desktop shortcuts"
copy_item "Games" "Games folder (~/Games)"
copy_item "Downloads/BattleNet" "Downloaded Battle.net installer"

if [ "$INCLUDE_LOGS" = "true" ]; then
    copy_item ".local/share/allglider/logs" "AllGlider logs"
else
    SKIPPED+=("Logs (excluded by user)")
fi

# Remove installer shortcut from installed system desktop
rm -f "$DST_HOME/Desktop/allglider-installer.desktop"

# Migrate persistent Wi-Fi / NetworkManager connections if present
if [ -d /etc/NetworkManager/system-connections ]; then
    mkdir -p "$TARGET_ROOT/etc/NetworkManager/system-connections"
    cp -a /etc/NetworkManager/system-connections/. "$TARGET_ROOT/etc/NetworkManager/system-connections/" 2>/dev/null || true
    chmod 0700 "$TARGET_ROOT/etc/NetworkManager/system-connections"
    TRANSFERRED+=("NetworkManager Wi-Fi profiles")
fi

# Fix ownership & permissions on target home directory
chown -R 1000:1000 "$DST_HOME"
if [ -f "$DST_HOME/.config/winbridge/settings.json" ]; then
    chmod 0600 "$DST_HOME/.config/winbridge/settings.json"
fi

# Write migration report for First-Boot verification on internal disk
mkdir -p "$TARGET_ROOT/var/log"
TRANSFERRED_JSON=$(printf '%s\n' "${TRANSFERRED[@]}" | jq -R . | jq -s .)
SKIPPED_JSON=$(printf '%s\n' "${SKIPPED[@]}" | jq -R . | jq -s .)

cat > "$TARGET_ROOT/var/log/allglider-migration-report.json" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "status": "success",
    "transferred": $TRANSFERRED_JSON,
    "skipped": $SKIPPED_JSON
}
EOF

echo "Migration complete!"
