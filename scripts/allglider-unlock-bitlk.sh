#!/usr/bin/env bash
# ==============================================================================
# AllGlider Live Linux - BitLocker Drive Unlocker & Scanner
# Unlocks a BitLocker partition via cryptsetup with user password or recovery key,
# mounts it read-only under /run/allglider/disks/, and scans for Battle.net & WoW.
# ==============================================================================
set -euo pipefail

DEV="${1:-}"
if [ -z "$DEV" ] || [ ! -b "$DEV" ]; then
    echo "ERROR: Valid block device required (e.g. /dev/nvme0n1p3 or /dev/sda2)" >&2
    exit 1
fi

DEV_BASE=$(basename "$DEV")
MAP_NAME="bitlk_${DEV_BASE}"
SCAN_BASE="/run/allglider/disks"
if ! mkdir -p "$SCAN_BASE" 2>/dev/null; then
    SCAN_BASE="/tmp/allglider/disks"
    mkdir -p "$SCAN_BASE" 2>/dev/null || true
fi
MNT_DIR="$SCAN_BASE/${DEV_BASE}"

# Read password / recovery key from standard input
PASSWORD=$(cat)
if [ -z "$PASSWORD" ]; then
    echo "ERROR: Password or recovery key cannot be empty." >&2
    exit 1
fi

echo "=== Attempting to unlock $DEV (mapping as $MAP_NAME) ==="

# Clean up any stale mapping/mount
if [ -e "/dev/mapper/$MAP_NAME" ]; then
    umount "$MNT_DIR" 2>/dev/null || true
    cryptsetup close "$MAP_NAME" 2>/dev/null || true
fi

# Attempt cryptsetup open with --type bitlk
# Accepts passphrases and 48-digit recovery keys via stdin with --key-file -
if ! echo -n "$PASSWORD" | cryptsetup open --type bitlk "$DEV" "$MAP_NAME" --key-file - 2>&1; then
    echo "ERROR: Failed to unlock $DEV with the provided password or recovery key." >&2
    exit 2
fi

MAP_DEV="/dev/mapper/$MAP_NAME"
mkdir -p "$MNT_DIR"

# Wait up to 3 seconds for udev device node to appear
for i in {1..15}; do
    [ -e "$MAP_DEV" ] && break
    sleep 0.2
done

if [ ! -e "$MAP_DEV" ]; then
    echo "ERROR: Mapped device $MAP_DEV did not appear." >&2
    cryptsetup close "$MAP_NAME" 2>/dev/null || true
    exit 3
fi

# Mount read-only so host Windows filesystem is never modified
MOUNT_OK=0
if mount -t ntfs-3g -o ro "$MAP_DEV" "$MNT_DIR" 2>/dev/null || \
   mount -t ntfs3 -o ro "$MAP_DEV" "$MNT_DIR" 2>/dev/null || \
   mount -o ro "$MAP_DEV" "$MNT_DIR" 2>/dev/null; then
    MOUNT_OK=1
fi

if [ "$MOUNT_OK" -eq 0 ]; then
    echo "ERROR: Failed to mount decrypted device $MAP_DEV." >&2
    cryptsetup close "$MAP_NAME" 2>/dev/null || true
    rmdir "$MNT_DIR" 2>/dev/null || true
    exit 4
fi

echo "SUCCESS: $DEV unlocked and mounted read-only at $MNT_DIR"

# Re-run disk scan so Battle.net and WoW on the unlocked drive are discovered and desktop entries created
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -x /usr/local/sbin/allglider-disk-scan ]; then
    /usr/local/sbin/allglider-disk-scan || true
elif [ -x "$SCRIPT_DIR/allglider-disk-scan.sh" ]; then
    "$SCRIPT_DIR/allglider-disk-scan.sh" || true
fi

echo "=== BitLocker unlock and game scan complete for $DEV ==="
