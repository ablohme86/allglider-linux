#!/usr/bin/env bash
# ==============================================================================
# AllGlider Live Linux - Safe USB Flasher
# Writes AllGlider Live ISO to target USB flash drive with strict safety checks.
# ==============================================================================
set -euo pipefail

ISO_PATH="/home/alexander/Projects/allglider-linux/build/AllGlider-Live-F44-0.1.0-x86_64.iso"
TARGET="/dev/sda"

if [ ! -f "$ISO_PATH" ]; then
    echo "ERROR: ISO file not found: $ISO_PATH" >&2
    exit 1
fi

if [ ! -b "$TARGET" ]; then
    echo "ERROR: Target $TARGET is not a block device." >&2
    exit 1
fi

# Safety check: Verify that TARGET is indeed a USB device
TRAN=$(lsblk -no TRAN "$TARGET" 2>/dev/null | head -n 1)
if [ "$TRAN" != "usb" ]; then
    echo "SECURITY ABORT: $TARGET is not a USB device (TRAN=$TRAN). Refusing to proceed!" >&2
    exit 2
fi

# Safety check: Verify TARGET is NOT holding the current root filesystem
ROOT_DISK=$(lsblk -no PKNAME "$(findmnt -n -o SOURCE /)" 2>/dev/null | head -n 1)
if [ "/dev/$ROOT_DISK" = "$TARGET" ]; then
    echo "CRITICAL ABORT: Refusing to write over host system disk ($TARGET)!" >&2
    exit 2
fi

echo "=== Target Confirmed Safe: $TARGET ($TRAN, $(lsblk -no SIZE "$TARGET" | head -n 1)) ==="
echo "=== Unmounting any active partitions on $TARGET ==="
for part in "${TARGET}"*; do
    if [ -b "$part" ]; then
        umount "$part" 2>/dev/null || true
    fi
done

echo "=== Writing $ISO_PATH to $TARGET ==="
dd if="$ISO_PATH" of="$TARGET" bs=4M status=progress oflag=sync

echo "=== Flushing buffers ==="
sync
udevadm settle || true

echo "=== SUCCESS: AllGlider Live Linux successfully written to $TARGET! ==="
echo "You can now safely reboot and boot from the USB drive."
