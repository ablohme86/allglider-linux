#!/usr/bin/env bash
# ==============================================================================
# AllGlider Live Linux - 128 GB Persistent USB Creator
# Creates the 3-partition layout on a target USB device (or loop disk image):
#   1. ESP (512 MiB, FAT32, label: AG_USB_EFI)
#   2. Live System (20 GiB, ext4, label: ALLGLIDER_LIVE)
#   3. Persistent User/App Data (Remaining ~100 GiB, ext4, label: ALLGLIDER_DATA)
# ==============================================================================
set -euo pipefail

if [ $# -lt 2 ]; then
    echo "Usage: sudo $0 <path-to-iso> <target-usb-device-or-image-file>"
    echo "Example (physical 128GB USB): sudo $0 build/AllGlider-Live-F44-0.1.0-x86_64.iso /dev/sdX"
    exit 1
fi

ISO_PATH="$1"
TARGET_DEV="$2"

if [ ! -f "$ISO_PATH" ]; then
    echo "ERROR: ISO file not found: $ISO_PATH" >&2
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Please run this script with sudo." >&2
    exit 1
fi

LOOP_DEV=""
cleanup() {
    set +e
    umount -l /mnt/ag-iso /mnt/ag-efi /mnt/ag-live 2>/dev/null || true
    if [ -n "$LOOP_DEV" ]; then
        losetup -d "$LOOP_DEV" 2>/dev/null || true
    fi
}
trap cleanup EXIT

if [ -f "$TARGET_DEV" ]; then
    echo "Attaching disk image file $TARGET_DEV as loop device..."
    LOOP_DEV=$(losetup --find --show -P "$TARGET_DEV")
    DISK="$LOOP_DEV"
elif [ -b "$TARGET_DEV" ]; then
    DISK="$TARGET_DEV"
    # Safety check: refuse to overwrite the host root disk
    ROOT_DISK=$(lsblk -no PKNAME "$(findmnt -n -o SOURCE /)" | head -n 1)
    if [ "/dev/$ROOT_DISK" = "$DISK" ]; then
        echo "CRITICAL: Refusing to format host system disk ($DISK)!" >&2
        exit 2
    fi
else
    echo "ERROR: Target $TARGET_DEV is neither a block device nor an image file." >&2
    exit 1
fi

# Dynamically size ALLGLIDER_LIVE based on actual ISO size + 1.5 GiB headroom (min 5 GiB)
ISO_MIB=$(du -m "$ISO_PATH" | awk '{print $1}')
LIVE_SIZE_MIB=$(( ISO_MIB + 1536 ))
if [ "$LIVE_SIZE_MIB" -lt 5120 ]; then
    LIVE_SIZE_MIB=5120
fi
LIVE_END_MIB=$(( 513 + LIVE_SIZE_MIB ))

DISK_BYTES=$(blockdev --getsize64 "$DISK")
DISK_MIB=$(( DISK_BYTES / 1048576 ))
MIN_REQUIRED_MIB=$(( LIVE_END_MIB + 1024 ))

if [ "$DISK_MIB" -lt "$MIN_REQUIRED_MIB" ]; then
    echo "ERROR: USB device is too small (${DISK_MIB} MiB). Minimum required is ${MIN_REQUIRED_MIB} MiB (~8 GB)." >&2
    exit 3
fi

DATA_MIB=$(( DISK_MIB - LIVE_END_MIB ))
echo "=== Partitioning $DISK (${DISK_MIB} MiB total: 512MiB EFI + ${LIVE_SIZE_MIB}MiB LiveOS + ${DATA_MIB}MiB ALLGLIDER_DATA) ==="
wipefs -a "$DISK"
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart ALLGLIDER_LIVE ext4 513MiB "${LIVE_END_MIB}MiB"
parted -s "$DISK" mkpart ALLGLIDER_DATA ext4 "${LIVE_END_MIB}MiB" 100%
partprobe "$DISK" || true
udevadm settle

SEP=""
if [[ "$DISK" =~ [0-9]$ ]]; then
    SEP="p"
fi
P_EFI="${DISK}${SEP}1"
P_LIVE="${DISK}${SEP}2"
P_DATA="${DISK}${SEP}3"

echo "=== Formatting partitions ==="
mkfs.vfat -F 32 -n "AG_USB_EFI" "$P_EFI"
mkfs.ext4 -F -L "ALLGLIDER_LIVE" "$P_LIVE"
mkfs.ext4 -F -L "ALLGLIDER_DATA" "$P_DATA"

mkdir -p /mnt/ag-iso /mnt/ag-efi /mnt/ag-live
mount -o loop,ro "$ISO_PATH" /mnt/ag-iso
mount "$P_EFI" /mnt/ag-efi
mount "$P_LIVE" /mnt/ag-live

echo "=== Copying EFI boot files and LiveOS image ==="
cp -a /mnt/ag-iso/EFI /mnt/ag-efi/
cp -a /mnt/ag-iso/LiveOS /mnt/ag-live/
cp -a /mnt/ag-iso/images /mnt/ag-live/ 2>/dev/null || true
if [ -d /mnt/ag-iso/boot ]; then
    cp -a /mnt/ag-iso/boot /mnt/ag-live/
    cp -a /mnt/ag-iso/boot /mnt/ag-efi/ 2>/dev/null || true
fi

sync
echo "=== Persistent USB successfully created on $TARGET_DEV ==="
echo "  - EFI Partition:        $P_EFI (AG_USB_EFI)"
echo "  - Live OS Partition:    $P_LIVE (ALLGLIDER_LIVE)"
echo "  - Persistent Data:      $P_DATA (ALLGLIDER_DATA)"
