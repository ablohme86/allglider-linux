#!/usr/bin/env bash
# ==============================================================================
# AllGlider Live Linux - Host Disk Scanner for Existing Battle.net & WoW
# Detects Battle.net and World of Warcraft on internal Windows or Linux disks,
# mounts the host partition under /run/allglider/disks/, and generates trusted
# desktop shortcuts so users can start playing immediately without downloading.
# ==============================================================================
set -uo pipefail

RESULTS_FILE="/run/allglider-host-apps.json"
SCAN_BASE="/run/allglider/disks"
if ! mkdir -p "$SCAN_BASE" 2>/dev/null; then
    SCAN_BASE="/tmp/allglider/disks"
    RESULTS_FILE="/tmp/allglider-host-apps.json"
    mkdir -p "$SCAN_BASE" 2>/dev/null || true
fi

# Initialize empty state if not existing
echo '{"battlenet_found": false, "wow_found": false}' > "$RESULTS_FILE" 2>/dev/null || true
chmod 0644 "$RESULTS_FILE" 2>/dev/null || true

FOUND_BNET=""
FOUND_BNET_PART=""
FOUND_BNET_MNT=""
FOUND_WOW=""
FOUND_WOW_PART=""
FOUND_WOW_MNT=""
ENCRYPTED_DISKS=()

# Direct check for local host Battle.net & WoW (for testing and host environments)
HOST_BNET_DIR="/home/alexander/.local/share/winbridge/shared/pfx/drive_c/Program Files (x86)/Battle.net"
if [ -f "$HOST_BNET_DIR/Battle.net Launcher.exe" ]; then
    FOUND_BNET="$HOST_BNET_DIR/Battle.net Launcher.exe"
    FOUND_BNET_PART="host (/home/alexander)"
    FOUND_BNET_MNT="/home/alexander"
elif [ -f "$HOST_BNET_DIR/Battle.net.exe" ]; then
    FOUND_BNET="$HOST_BNET_DIR/Battle.net.exe"
    FOUND_BNET_PART="host (/home/alexander)"
    FOUND_BNET_MNT="/home/alexander"
fi

for HOST_WOW_PATH in \
    "/mnt/ekstra/Games/World of Warcraft/_forever_/Wow.exe" \
    "/mnt/ekstra/Games/World of Warcraft/_anniversary_/WowClassic.exe" \
    "/mnt/ekstra/Games/World of Warcraft/_classic_era_/WowClassic.exe" \
    "/mnt/ekstra/Games/World of Warcraft/_retail_/Wow.exe"; do
    if [ -f "$HOST_WOW_PATH" ]; then
        FOUND_WOW="$HOST_WOW_PATH"
        FOUND_WOW_PART="host (/mnt/ekstra)"
        FOUND_WOW_MNT="/mnt/ekstra"
        break
    fi
done

    # Query partitions safely using key-value pairs (handles empty labels and spaces correctly)
while read -r line; do
    KNAME="" FSTYPE="" LABEL="" MOUNTPOINT="" TYPE=""
    eval "$line"
    [ -n "$KNAME" ] || continue
    [ "$TYPE" = "part" ] || [ "$TYPE" = "disk" ] || [ "$TYPE" = "crypt" ] || continue
    DEV_PATH="/dev/$KNAME"

    # If this is a raw partition that is already unlocked in /dev/mapper, skip the raw partition
    DEV_BASE=$(basename "$DEV_PATH")
    if [ -e "/dev/mapper/bitlk_${DEV_BASE}" ]; then
        continue
    fi

    # Ignore CD/ISO, swap, and Live media
    case "$FSTYPE" in
        iso9660|swap|squashfs) continue ;;
    esac
    case "$LABEL" in
        ALLGLIDER_LIVE|AG_USB_EFI) continue ;;
    esac
    case "$DEV_PATH" in
        /dev/loop*|/dev/zram*) continue ;;
    esac

    # Check if partition is encrypted (BitLocker / LUKS)
    IS_ENCRYPTED=0
    case "$FSTYPE" in
        BitLocker|bitlocker|crypto_BitLocker|crypto_LUKS|bitlk)
            IS_ENCRYPTED=1
            ;;
    esac

    if [ "$IS_ENCRYPTED" -eq 0 ]; then
        BLK_TYPE=$(blkid -s TYPE -o value "$DEV_PATH" 2>/dev/null || true)
        case "$BLK_TYPE" in
            BitLocker|bitlocker|crypto_BitLocker|crypto_LUKS|bitlk)
                IS_ENCRYPTED=1
                ;;
        esac
    fi

    if [ "$IS_ENCRYPTED" -eq 0 ]; then
        SIG=$(dd if="$DEV_PATH" bs=1 skip=3 count=8 2>/dev/null || true)
        if [ "$SIG" = "-FVE-FS-" ]; then
            IS_ENCRYPTED=1
        fi
    fi

    if [ "$IS_ENCRYPTED" -eq 0 ] && command -v cryptsetup >/dev/null 2>&1; then
        if cryptsetup bitlkDump "$DEV_PATH" >/dev/null 2>&1 || cryptsetup isLuks "$DEV_PATH" >/dev/null 2>&1; then
            IS_ENCRYPTED=1
        fi
    fi

    if [ "$IS_ENCRYPTED" -eq 1 ]; then
        echo "AllGlider Disk Scan: Encrypted drive detected: $DEV_PATH"
        ENCRYPTED_DISKS+=("$DEV_PATH")
        continue
    fi

    PART_NAME=$(basename "$DEV_PATH")
    MNT_DIR=""
    WE_MOUNTED=0

    if [ -n "$MOUNTPOINT" ] && [ -d "$MOUNTPOINT" ]; then
        MNT_DIR="$MOUNTPOINT"
    else
        MNT_DIR="$SCAN_BASE/$PART_NAME"
        mkdir -p "$MNT_DIR"
        # Try mounting read-only (standard, ntfs3, and ntfs-3g with ro)
        if mount -o ro "$DEV_PATH" "$MNT_DIR" 2>/dev/null || \
           mount -t ntfs-3g -o ro "$DEV_PATH" "$MNT_DIR" 2>/dev/null || \
           mount -t ntfs3 -o ro "$DEV_PATH" "$MNT_DIR" 2>/dev/null; then
            WE_MOUNTED=1
        else
            rmdir "$MNT_DIR" 2>/dev/null || true
            # Double check if mount failure was due to BitLocker
            if command -v cryptsetup >/dev/null 2>&1 && cryptsetup bitlkDump "$DEV_PATH" >/dev/null 2>&1; then
                echo "AllGlider Disk Scan: BitLocker encrypted drive confirmed on mount failure: $DEV_PATH"
                ENCRYPTED_DISKS+=("$DEV_PATH")
            fi
            continue
        fi
    fi

    # Scan for Battle.net Launcher
    BNET_CANDIDATES=(
        "Program Files (x86)/Battle.net/Battle.net Launcher.exe"
        "Program Files (x86)/Battle.net/Battle.net.exe"
        "Program Files/Battle.net/Battle.net Launcher.exe"
        "Program Files/Battle.net/Battle.net.exe"
        "Battle.net/Battle.net Launcher.exe"
        "Battle.net/Battle.net.exe"
        "Games/Battle.net/Battle.net Launcher.exe"
        "Games/Battle.net/Battle.net.exe"
        "Spill/Battle.net/Battle.net Launcher.exe"
        "Spill/Battle.net/Battle.net.exe"
        "home/alexander/.local/share/winbridge/shared/pfx/drive_c/Program Files (x86)/Battle.net/Battle.net Launcher.exe"
        "home/alexander/.local/share/winbridge/shared/pfx/drive_c/Program Files (x86)/Battle.net/Battle.net.exe"
        "alexander/.local/share/winbridge/shared/pfx/drive_c/Program Files (x86)/Battle.net/Battle.net Launcher.exe"
        "alexander/.local/share/winbridge/shared/pfx/drive_c/Program Files (x86)/Battle.net/Battle.net.exe"
        ".local/share/winbridge/shared/pfx/drive_c/Program Files (x86)/Battle.net/Battle.net Launcher.exe"
        ".local/share/winbridge/shared/pfx/drive_c/Program Files (x86)/Battle.net/Battle.net.exe"
    )

    PART_HAS_APP=0

    if [ -z "$FOUND_BNET" ]; then
        for REL in "${BNET_CANDIDATES[@]}"; do
            FULL_PATH="$MNT_DIR/$REL"
            if [ -f "$FULL_PATH" ]; then
                FOUND_BNET="$FULL_PATH"
                FOUND_BNET_PART="$DEV_PATH"
                FOUND_BNET_MNT="$MNT_DIR"
                PART_HAS_APP=1
                break
            fi
        done

        # If not found at common paths, try a search up to 6 levels deep for Launcher or Battle.net.exe
        if [ -z "$FOUND_BNET" ]; then
            QUICK_FIND=$(find "$MNT_DIR" -maxdepth 6 -type f \( -iname "Battle.net Launcher.exe" -o -iname "Battle.net.exe" \) 2>/dev/null | head -n 1)
            if [ -n "$QUICK_FIND" ] && [ -f "$QUICK_FIND" ]; then
                FOUND_BNET="$QUICK_FIND"
                FOUND_BNET_PART="$DEV_PATH"
                FOUND_BNET_MNT="$MNT_DIR"
                PART_HAS_APP=1
            fi
        fi
    fi

    # Scan for World of Warcraft
    if [ -z "$FOUND_WOW" ]; then
        WOW_CANDIDATES=(
            "Program Files (x86)/World of Warcraft/_retail_/Wow.exe"
            "Program Files (x86)/World of Warcraft/_classic_/WowClassic.exe"
            "Program Files (x86)/World of Warcraft/_classic_era_/WowClassic.exe"
            "Program Files (x86)/World of Warcraft/Wow.exe"
            "World of Warcraft/_retail_/Wow.exe"
            "World of Warcraft/_classic_/WowClassic.exe"
            "World of Warcraft/_classic_era_/WowClassic.exe"
            "World of Warcraft/Wow.exe"
            "Games/World of Warcraft/_retail_/Wow.exe"
            "Games/World of Warcraft/_classic_/WowClassic.exe"
            "Games/World of Warcraft/_classic_era_/WowClassic.exe"
            "Games/World of Warcraft/_anniversary_/WowClassic.exe"
            "Games/World of Warcraft/_forever_/Wow.exe"
            "Spill/World of Warcraft/_retail_/Wow.exe"
            "Spill/World of Warcraft/_classic_/WowClassic.exe"
            "Spill/World of Warcraft/_classic_era_/WowClassic.exe"
            "Spill/World of Warcraft/_anniversary_/WowClassic.exe"
            "Spill/World of Warcraft/_forever_/Wow.exe"
        )
        for REL in "${WOW_CANDIDATES[@]}"; do
            FULL_PATH="$MNT_DIR/$REL"
            if [ -f "$FULL_PATH" ]; then
                FOUND_WOW="$FULL_PATH"
                FOUND_WOW_PART="$DEV_PATH"
                FOUND_WOW_MNT="$MNT_DIR"
                PART_HAS_APP=1
                break
            fi
        done

        if [ -z "$FOUND_WOW" ]; then
            QUICK_WOW=$(find "$MNT_DIR" -maxdepth 6 -type f \( -iname "Wow.exe" -o -iname "WowClassic.exe" \) 2>/dev/null | head -n 1)
            if [ -n "$QUICK_WOW" ] && [ -f "$QUICK_WOW" ]; then
                FOUND_WOW="$QUICK_WOW"
                FOUND_WOW_PART="$DEV_PATH"
                FOUND_WOW_MNT="$MNT_DIR"
                PART_HAS_APP=1
            fi
        fi
    fi

    # If this partition had nothing interesting and we mounted it temporarily, unmount it
    if [ "$PART_HAS_APP" -eq 0 ] && [ "$WE_MOUNTED" -eq 1 ]; then
        umount "$MNT_DIR" 2>/dev/null || true
        rmdir "$MNT_DIR" 2>/dev/null || true
    fi

done < <(lsblk -P -o KNAME,FSTYPE,LABEL,MOUNTPOINT,TYPE 2>/dev/null)

# Prepare JSON results
BNET_BOOL="false"
WOW_BOOL="false"
ENCRYPTED_BOOL="false"
[ -n "$FOUND_BNET" ] && BNET_BOOL="true"
[ -n "$FOUND_WOW" ] && WOW_BOOL="true"
[ ${#ENCRYPTED_DISKS[@]} -gt 0 ] && ENCRYPTED_BOOL="true"

# Format encrypted disks as JSON array
ENCRYPTED_JSON="[]"
if [ ${#ENCRYPTED_DISKS[@]} -gt 0 ]; then
    ENCRYPTED_JSON=$(printf '%s\n' "${ENCRYPTED_DISKS[@]}" | jq -R . | jq -s -c . 2>/dev/null || echo "[\"${ENCRYPTED_DISKS[0]}\"]")
fi

cat > "$RESULTS_FILE" << EOF
{
  "battlenet_found": $BNET_BOOL,
  "battlenet_exe": "$FOUND_BNET",
  "battlenet_part": "$FOUND_BNET_PART",
  "battlenet_mnt": "$FOUND_BNET_MNT",
  "wow_found": $WOW_BOOL,
  "wow_exe": "$FOUND_WOW",
  "wow_part": "$FOUND_WOW_PART",
  "wow_mnt": "$FOUND_WOW_MNT",
  "encrypted_found": $ENCRYPTED_BOOL,
  "encrypted_disks": $ENCRYPTED_JSON
}
EOF
chmod 0644 "$RESULTS_FILE" 2>/dev/null || true

# Function to trust a desktop file in Xfce
trust_desktop_file() {
    local target="$1"
    [ -f "$target" ] || return 0
    chmod 0755 "$target" 2>/dev/null || true
    if command -v gio >/dev/null 2>&1; then
        csum=$(sha256sum "$target" 2>/dev/null | awk '{print $1}')
        [ -n "$csum" ] && gio set -t string "$target" metadata::xfce-exe-checksum "$csum" 2>/dev/null || true
        gio set -t string "$target" metadata::trusted true 2>/dev/null || true
    fi
}

# Create desktop entries for liveuser and skel
create_shortcuts() {
    local ddir="$1"
    mkdir -p "$ddir" /usr/share/applications

    if [ -n "$FOUND_BNET" ]; then
        cat > "/usr/share/applications/Battle.net.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Battle.net
GenericName=Battle.net (Host Disk)
Comment=Launch Battle.net from host drive via WinBridge
Exec=/usr/local/bin/winbridge "$FOUND_BNET"
Icon=allglider-battlenet
Terminal=false
Categories=Game;
StartupNotify=true
EOF
        chmod 0666 "/usr/share/applications/Battle.net.desktop"
        cp -f "/usr/share/applications/Battle.net.desktop" "$ddir/Battle.net.desktop"
        trust_desktop_file "$ddir/Battle.net.desktop"
    fi

    if [ -n "$FOUND_WOW" ]; then
        cat > "/usr/share/applications/World of Warcraft.desktop" << EOF
[Desktop Entry]
Type=Application
Name=World of Warcraft
GenericName=World of Warcraft (Host Disk)
Comment=Launch World of Warcraft from host drive via WinBridge
Exec=/usr/local/bin/winbridge "$FOUND_WOW"
Icon=allglider
Terminal=false
Categories=Game;
StartupNotify=true
EOF
        chmod 0666 "/usr/share/applications/World of Warcraft.desktop"
        cp -f "/usr/share/applications/World of Warcraft.desktop" "$ddir/World of Warcraft.desktop"
        trust_desktop_file "$ddir/World of Warcraft.desktop"
    fi

    for dfile in "$ddir"/*.desktop; do
        [ -f "$dfile" ] && trust_desktop_file "$dfile"
    done
}

create_shortcuts "/etc/skel/Desktop"
if [ -d "/home/liveuser/Desktop" ]; then
    create_shortcuts "/home/liveuser/Desktop"
    chown -R 1000:1000 "/home/liveuser/Desktop" 2>/dev/null || true
fi

python3 -c '
import glob, os, ctypes
try:
    gio = ctypes.CDLL("libgio-2.0.so.0")
    gio.g_file_new_for_path.argtypes = [ctypes.c_char_p]
    gio.g_file_new_for_path.restype = ctypes.c_void_p
    xfutil = ctypes.CDLL("libxfce4util.so.7")
    xfutil.xfce_g_file_set_trusted.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p]
    xfutil.xfce_g_file_set_trusted.restype = ctypes.c_int
    for p in glob.glob("/home/liveuser/Desktop/*.desktop"):
        gf = gio.g_file_new_for_path(p.encode("utf-8"))
        xfutil.xfce_g_file_set_trusted(gf, 1, None, None)
except Exception:
    pass
' 2>/dev/null || true

echo "=== AllGlider Disk Scan: Battle.net=$BNET_BOOL, WoW=$WOW_BOOL ==="
