#!/usr/bin/env bash
# ==============================================================================
# AllGlider Live Linux - Display & Resolution Initializer
# Ensures 1920x1080 resolution on Virtual Machine displays (QEMU / virt-manager)
# and native preferred resolution on physical NVIDIA / AMD / Intel monitors.
# ==============================================================================
set -uo pipefail

# Start spice-vdagent if available (enables dynamic window resizing in virt-manager)
if command -v spice-vdagent >/dev/null 2>&1; then
    spice-vdagent 2>/dev/null || true
fi

if ! command -v xrandr >/dev/null 2>&1; then
    exit 0
fi

# Inspect connected outputs
CONNECTED_OUTPUTS=$(xrandr --query | awk '/ connected/ {print $1}')
for OUT in $CONNECTED_OUTPUTS; do
    if [[ "$OUT" =~ ^(Virtual|qxl|VGA|bochs) ]]; then
        # Virtual display in QEMU / virt-manager defaults to 800x600 or 1024x768;
        # set 1920x1080 (or 1600x900 fallback) automatically.
        xrandr --output "$OUT" --mode 1920x1080 2>/dev/null \
            || xrandr --output "$OUT" --mode 1600x900 2>/dev/null \
            || xrandr --output "$OUT" --mode 1440x900 2>/dev/null \
            || xrandr --output "$OUT" --mode 1366x768 2>/dev/null \
            || xrandr --output "$OUT" --auto 2>/dev/null || true
    else
        # Physical display (DP, HDMI, eDP): use monitor's native preferred mode
        xrandr --output "$OUT" --auto 2>/dev/null || true
    fi
done

# Trust and mark executable all Desktop launchers in Xfce
trust_desktop_launchers() {
    local ddir="${HOME:-/home/liveuser}/Desktop"
    [ -d "$ddir" ] || return 0

    python3 -c '
import glob, os, ctypes
try:
    gio = ctypes.CDLL("libgio-2.0.so.0")
    gio.g_file_new_for_path.argtypes = [ctypes.c_char_p]
    gio.g_file_new_for_path.restype = ctypes.c_void_p
except Exception:
    gio = None

try:
    xfutil = ctypes.CDLL("libxfce4util.so.7")
    xfutil.xfce_g_file_set_trusted.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p]
    xfutil.xfce_g_file_set_trusted.restype = ctypes.c_int
except Exception:
    xfutil = None

desktop_dir = os.path.expanduser("~/Desktop")
for path in glob.glob(os.path.join(desktop_dir, "*.desktop")):
    try:
        os.chmod(path, 0o755)
        if gio and xfutil:
            gf = gio.g_file_new_for_path(path.encode("utf-8"))
            xfutil.xfce_g_file_set_trusted(gf, 1, None, None)
    except Exception:
        pass
' 2>/dev/null || true

    for f in "$ddir"/*.desktop; do
        [ -f "$f" ] || continue
        chmod +x "$f" 2>/dev/null || true
        if command -v gio >/dev/null 2>&1; then
            csum=$(sha256sum "$f" 2>/dev/null | awk '{print $1}')
            [ -n "$csum" ] && gio set -t string "$f" metadata::xfce-exe-checksum "$csum" 2>/dev/null || true
            gio set -t string "$f" metadata::trusted true 2>/dev/null || true
        fi
    done
}

if [ "$(id -u)" -eq 0 ]; then
    if [ -x /usr/local/sbin/allglider-disk-scan ]; then
        /usr/local/sbin/allglider-disk-scan 2>/dev/null || true
    fi
fi

if [ "$(id -u)" -ne 0 ]; then
    trust_desktop_launchers
    (
        sleep 2
        trust_desktop_launchers
        command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
        command -v xfdesktop >/dev/null 2>&1 && xfdesktop --reload 2>/dev/null || true
    ) >/dev/null 2>&1 &
fi

