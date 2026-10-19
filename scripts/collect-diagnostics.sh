#!/usr/bin/env bash
# ==============================================================================
# AllGlider Live Linux - Diagnostics Collector
# Collects GPU/driver info (NVIDIA/AMD/Intel), Vulkan status, persistence mount
# status, WinBridge/UMU/Proton configuration, and AllGlider status.
# ==============================================================================
set -euo pipefail

OUT_DIR="${1:-/tmp/allglider-diagnostics-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT_DIR"

echo "Collecting diagnostics into $OUT_DIR..."

uname -a > "$OUT_DIR/uname.txt"
cat /etc/os-release > "$OUT_DIR/os-release.txt" 2>/dev/null || true
cat /proc/cmdline > "$OUT_DIR/cmdline.txt" 2>/dev/null || true
lsblk -f > "$OUT_DIR/lsblk.txt" 2>/dev/null || true
df -h > "$OUT_DIR/df.txt" 2>/dev/null || true
lspci -nnk | grep -EA3 "VGA|3D|Display" > "$OUT_DIR/gpu-pci.txt" 2>/dev/null || true
lsmod | grep -E "nvidia|nouveau|amdgpu|radeon|i915|xe|virtio" > "$OUT_DIR/gpu-modules.txt" 2>/dev/null || true

if command -v vulkaninfo >/dev/null 2>&1; then
    vulkaninfo --summary > "$OUT_DIR/vulkan-summary.txt" 2>&1 || true
fi

if [ -f /run/allglider-gpu.json ]; then
    cp /run/allglider-gpu.json "$OUT_DIR/"
fi
if [ -f /run/allglider-persistence.json ]; then
    cp /run/allglider-persistence.json "$OUT_DIR/"
fi
if [ -f "$HOME/.config/winbridge/settings.json" ]; then
    cp "$HOME/.config/winbridge/settings.json" "$OUT_DIR/winbridge-settings.json"
fi

ARCHIVE="${OUT_DIR}.tar.gz"
tar -czf "$ARCHIVE" -C "$(dirname "$OUT_DIR")" "$(basename "$OUT_DIR")"
echo "Diagnostics bundle saved to: $ARCHIVE"
