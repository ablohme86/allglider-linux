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

apply_wallpaper() {
    local wp="/usr/share/backgrounds/allglider/allglider-wallpaper.png"
    [ -f "$wp" ] || return 0
    command -v xfconf-query >/dev/null 2>&1 || return 0

    # 1. Update all currently connected monitor outputs from xrandr
    for out in $CONNECTED_OUTPUTS; do
        for p in \
            "/backdrop/screen0/monitor${out}/workspace0/last-image" \
            "/backdrop/screen0/monitor${out}/workspace0/image-path" \
            "/backdrop/screen0/monitor${out}/last-image" \
            "/backdrop/screen0/monitor${out}/image-path"; do
            xfconf-query -c xfce4-desktop -p "$p" -s "$wp" --create -t string 2>/dev/null || true
        done
        xfconf-query -c xfce4-desktop -p "/backdrop/screen0/monitor${out}/workspace0/image-style" -s 5 --create -t int 2>/dev/null || true
        xfconf-query -c xfce4-desktop -p "/backdrop/screen0/monitor${out}/image-style" -s 5 --create -t int 2>/dev/null || true
    done

    # 2. Update all monitor backdrops currently registered in xfconf
    for prop in $(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep -E 'image-path|last-image'); do
        xfconf-query -c xfce4-desktop -p "$prop" -s "$wp" 2>/dev/null || true
    done
    for prop in $(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep -E 'image-style'); do
        xfconf-query -c xfce4-desktop -p "$prop" -s 5 2>/dev/null || true
    done
}

show_encryption_popup() {
    local apps_file="/run/allglider-host-apps.json"
    local flag_file="/run/allglider-encrypted-popup-shown"
    [ -f "$apps_file" ] || return 0
    [ -f "$flag_file" ] && return 0

    local is_enc
    is_enc=$(jq -r '.encrypted_found // false' "$apps_file" 2>/dev/null || echo "false")
    if [ "$is_enc" = "true" ]; then
        local disks
        disks=$(jq -r '.encrypted_disks | join(", ")' "$apps_file" 2>/dev/null || echo "")
        [ -n "$disks" ] || return 0
        local msg="Could not search for Battle.net in your existing drive ${disks} because it's encrypted, manual download of Battle.Net and Warcraft is required"

        # Wait a few seconds so desktop and allglider-welcome have started
        sleep 4
        [ -f "$flag_file" ] && return 0
        if pgrep -f "allglider-welcome" >/dev/null 2>&1; then
            return 0
        fi

        touch "$flag_file" 2>/dev/null || true
        if command -v zenity >/dev/null 2>&1; then
            zenity --warning --title="Encrypted Drive Detected" --text="$msg" 2>/dev/null || true
        elif command -v notify-send >/dev/null 2>&1; then
            notify-send -u critical "Encrypted Drive Detected" "$msg" 2>/dev/null || true
        fi
    fi
}

if [ "$(id -u)" -eq 0 ]; then
    if [ -x /usr/local/sbin/allglider-disk-scan ]; then
        /usr/local/sbin/allglider-disk-scan 2>/dev/null || true
    fi
fi

if [ "$(id -u)" -ne 0 ]; then
    trust_desktop_launchers
    apply_wallpaper
    (
        sleep 2
        trust_desktop_launchers
        apply_wallpaper
        command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
        command -v xfdesktop >/dev/null 2>&1 && xfdesktop --reload 2>/dev/null || true
        show_encryption_popup
    ) >/dev/null 2>&1 &
fi



