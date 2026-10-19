#!/usr/bin/env bash
# ==============================================================================
# AllGlider Live Linux - Persistent Partition Auto-Mounter
# Mounts LABEL=ALLGLIDER_DATA in Live Mode and bind-mounts /home/liveuser
# and NetworkManager connections so all user data survives reboots cleanly.
# ==============================================================================
set -euo pipefail

# Only activate in Live environment (skip when running from installed internal disk)
if ! grep -q "rd.live.image" /proc/cmdline 2>/dev/null; then
    echo "allglider-persistence: System is installed on internal disk; skipping Live USB mount."
    exit 0
fi

# Wait up to 8 seconds for USB block devices to settle
for _ in {1..16}; do
    if blkid -L "ALLGLIDER_DATA" >/dev/null 2>&1; then
        break
    fi
    sleep 0.5
done

DATA_DEV=$(blkid -L "ALLGLIDER_DATA" || true)
if [ -z "$DATA_DEV" ]; then
    echo "allglider-persistence: No partition with LABEL=ALLGLIDER_DATA found. Running in non-persistent RAM mode."
    exit 0
fi

MOUNT_ROOT="/mnt/allglider-data"
mkdir -p "$MOUNT_ROOT"

if ! mountpoint -q "$MOUNT_ROOT"; then
    echo "allglider-persistence: Mounting $DATA_DEV at $MOUNT_ROOT..."
    mount -o rw,noatime "$DATA_DEV" "$MOUNT_ROOT"
fi

# 1. Persistent /home/liveuser
PERSIST_HOME="$MOUNT_ROOT/home/liveuser"
CURRENT_STAMP=$(stat -c %Y /usr/local/bin/allglider-welcome 2>/dev/null || echo "1")
STAMP_FILE="$PERSIST_HOME/.config/allglider/skel-stamp"

if [ ! -d "$PERSIST_HOME" ]; then
    echo "allglider-persistence: Initializing persistent /home/liveuser from /etc/skel..."
    mkdir -p "$PERSIST_HOME"
    cp -a /etc/skel/. "$PERSIST_HOME/"
    mkdir -p "$PERSIST_HOME/.config/allglider"
    echo "$CURRENT_STAMP" > "$STAMP_FILE"
    chown -R 1000:1000 "$PERSIST_HOME"
elif [ ! -f "$STAMP_FILE" ] || [ "$(cat "$STAMP_FILE" 2>/dev/null)" != "$CURRENT_STAMP" ]; then
    echo "allglider-persistence: Updating persistent /home/liveuser desktop & Xfce defaults from /etc/skel..."
    rm -f "$PERSIST_HOME/Desktop/allglider-installer.desktop"
    cp -af /etc/skel/Desktop/. "$PERSIST_HOME/Desktop/" 2>/dev/null || true
    cp -af /etc/skel/.config/xfce4/. "$PERSIST_HOME/.config/xfce4/" 2>/dev/null || true
    mkdir -p "$PERSIST_HOME/.config/allglider"
    echo "$CURRENT_STAMP" > "$STAMP_FILE"
    chown -R 1000:1000 "$PERSIST_HOME"
fi

if ! mountpoint -q /home/liveuser; then
    mkdir -p /home/liveuser
    mount --bind "$PERSIST_HOME" /home/liveuser
    chown 1000:1000 /home/liveuser
fi

# 2. Persistent NetworkManager Wi-Fi / VPN connections
PERSIST_NM="$MOUNT_ROOT/system/NetworkManager/system-connections"
mkdir -p "$PERSIST_NM"
chmod 0700 "$PERSIST_NM"
if [ -d /etc/NetworkManager/system-connections ] && ! mountpoint -q /etc/NetworkManager/system-connections; then
    cp -a /etc/NetworkManager/system-connections/. "$PERSIST_NM/" 2>/dev/null || true
    mount --bind "$PERSIST_NM" /etc/NetworkManager/system-connections
fi

# Record persistence metadata for GUI tools
cat > /run/allglider-persistence.json << EOF
{
    "active": true,
    "device": "$DATA_DEV",
    "mount_point": "$MOUNT_ROOT",
    "home_dir": "$PERSIST_HOME"
}
EOF

echo "allglider-persistence: Persistent storage active on $DATA_DEV."
