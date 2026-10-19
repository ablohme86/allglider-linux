#!/usr/bin/env bash
# ==============================================================================
# AllGlider Live Linux - QEMU/KVM Test Runner
# Boots the built Live ISO with UEFI (OVMF), a persistent ALLGLIDER_DATA disk,
# and a simulated 40 GiB internal NVMe disk to test persistence & installation.
# ==============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/config/versions.lock"

VM_DIR="$REPO_ROOT/tests/.vm"
mkdir -p "$VM_DIR"

ISO_PATH="${1:-$REPO_ROOT/build/AllGlider-Live-F${FEDORA_RELEASE}-${ALLGLIDER_DISTRO_VERSION}-x86_64.iso}"
if [ ! -f "$ISO_PATH" ]; then
    echo "ERROR: ISO not found at $ISO_PATH" >&2
    echo "Build it first with: ./scripts/build-iso.sh" >&2
    exit 1
fi

# 1. Create a persistent ALLGLIDER_DATA virtual partition image (8 GiB) if not present
PERSIST_IMG="$VM_DIR/allglider-data.raw"
if [ ! -f "$PERSIST_IMG" ]; then
    echo "Creating 8 GiB persistent ALLGLIDER_DATA test volume..."
    truncate -s 8G "$PERSIST_IMG"
    mkfs.ext4 -F -L "ALLGLIDER_DATA" "$PERSIST_IMG"
fi

# 2. Create a simulated 40 GiB internal target disk (qcow2) to test the Graphical Installer
INTERNAL_DISK="$VM_DIR/internal-nvme.qcow2"
if [ ! -f "$INTERNAL_DISK" ]; then
    echo "Creating 40 GiB virtual internal disk for installer testing..."
    qemu-img create -f qcow2 "$INTERNAL_DISK" 40G
fi

# 3. Prepare writable OVMF UEFI NVRAM vars
OVMF_CODE="/usr/share/edk2/ovmf/OVMF_CODE.fd"
OVMF_VARS_SRC="/usr/share/edk2/ovmf/OVMF_VARS.fd"
OVMF_VARS="$VM_DIR/OVMF_VARS.fd"
if [ ! -f "$OVMF_VARS" ] && [ -f "$OVMF_VARS_SRC" ]; then
    cp "$OVMF_VARS_SRC" "$OVMF_VARS"
fi

echo "=== Starting QEMU/KVM UEFI Test VM ==="
exec qemu-system-x86_64 \
    -enable-kvm \
    -machine q35,accel=kvm \
    -cpu host \
    -smp 4 \
    -m 4096 \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,file="$OVMF_VARS" \
    -cdrom "$ISO_PATH" \
    -drive file="$PERSIST_IMG",format=raw,if=virtio \
    -drive file="$INTERNAL_DISK",format=qcow2,if=none,id=nvme0 \
    -device nvme,drive=nvme0,serial=AG-NVME-TEST01 \
    -device virtio-vga-gl \
    -display gtk,gl=on \
    -netdev user,id=net0 \
    -device virtio-net-pci,netdev=net0 \
    -usb -device usb-tablet
