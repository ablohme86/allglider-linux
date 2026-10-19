#!/usr/bin/env bash
# ==============================================================================
# AllGlider Live Linux - Hardware GPU Detection & NVIDIA/AMD/Intel Auto-Config
# Inspects PCI Vendor IDs: [10de] NVIDIA, [1002] AMD, [8086] Intel, else Virtual.
# ==============================================================================
set -euo pipefail

GPU_INFO=$(lspci -nn | grep -iE "VGA compatible controller|3D controller|Display controller" || true)
VENDOR="Unknown"
DRIVER="unknown"

if echo "$GPU_INFO" | grep -qi "\[10de:"; then
    VENDOR="NVIDIA"
    modprobe -r nouveau 2>/dev/null || true
    if modprobe nvidia-drm modeset=1 2>/dev/null; then
        DRIVER="nvidia"
    else
        DRIVER="nouveau-or-fallback"
    fi
elif echo "$GPU_INFO" | grep -qi "\[1002:"; then
    VENDOR="AMD Radeon"
    modprobe amdgpu 2>/dev/null || true
    DRIVER="amdgpu (Mesa)"
elif echo "$GPU_INFO" | grep -qi "\[8086:"; then
    VENDOR="Intel"
    modprobe i915 2>/dev/null || modprobe xe 2>/dev/null || true
    DRIVER="intel (Mesa)"
else
    VENDOR="Virtual GPU (QEMU/KVM)"
    DRIVER="virtio/qxl (Mesa)"
fi

cat > /run/allglider-gpu.json << EOF
{
    "vendor": "$VENDOR",
    "driver": "$DRIVER",
    "pci_devices": $(echo "$GPU_INFO" | jq -R -s -c 'split("\n") | map(select(length > 0))')
}
EOF

echo "allglider-gpu-check: Detected $VENDOR using driver $DRIVER"
