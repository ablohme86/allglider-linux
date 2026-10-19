#!/usr/bin/env bash
# ==============================================================================
# AllGlider Live Linux - Desktop Icon Emblem Remover
# Completely removes the padlock (emblem-readonly) and arrow (emblem-symbolic-link)
# from all desktop shortcuts in Xfce / Thunar / Xfdesktop.
# ==============================================================================
set -euo pipefail

TARGET_ROOT="${1:-/}"

echo "=== Removing Desktop Icon Emblems (Padlocks & Link Arrows) in $TARGET_ROOT ==="
TMP_TRANS="/tmp/trans-1x1.png"
TMP_SVG="/tmp/trans-1x1.svg"

# Create 1x1 RGBA transparent PNG & SVG
base64 -d <<< "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=" > "$TMP_TRANS"
cat > "$TMP_SVG" << 'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"/>
EOF

# 1. Replace emblem icons across all themes in /usr/share/icons
for pattern in "*emblem-symbolic-link*" "*emblem-readonly*" "*emblem-locked*"; do
    find "$TARGET_ROOT/usr/share/icons" -name "$pattern.png" -exec cp -f "$TMP_TRANS" {} + 2>/dev/null || true
    find "$TARGET_ROOT/usr/share/icons" -name "$pattern.svg" -exec cp -f "$TMP_SVG" {} + 2>/dev/null || true
done

# 2. Update GTK icon caches
for theme_dir in "$TARGET_ROOT"/usr/share/icons/*; do
    if [ -d "$theme_dir" ] && [ -f "$theme_dir/index.theme" ]; then
        gtk-update-icon-cache -f "$theme_dir" 2>/dev/null || true
    fi
done

# 3. Ensure all desktop application launchers have 0666 permissions so liveuser is never marked readonly
chmod 0666 "$TARGET_ROOT"/usr/share/applications/allglider*.desktop 2>/dev/null || true
chmod 0666 "$TARGET_ROOT"/usr/share/applications/winbridge*.desktop 2>/dev/null || true
chmod 0666 "$TARGET_ROOT"/usr/share/applications/Battle.net*.desktop 2>/dev/null || true
chmod 0666 "$TARGET_ROOT"/usr/share/applications/World*.desktop 2>/dev/null || true
chmod 0666 "$TARGET_ROOT"/etc/skel/Desktop/*.desktop 2>/dev/null || true
chmod 0666 "$TARGET_ROOT"/home/liveuser/Desktop/*.desktop 2>/dev/null || true

# 4. Add GTK3 CSS rule to /etc/skel and /home/liveuser
mkdir -p "$TARGET_ROOT/etc/skel/.config/gtk-3.0" "$TARGET_ROOT/home/liveuser/.config/gtk-3.0"
cat > "$TARGET_ROOT/etc/skel/.config/gtk-3.0/gtk.css" << 'EOF'
/* Hide desktop icon emblems (padlocks & symlink arrows) */
.xfdesktop-icon-view .emblem,
XfdesktopIconView .emblem {
    opacity: 0;
    -gtk-icon-size: 0;
}
EOF
cp -f "$TARGET_ROOT/etc/skel/.config/gtk-3.0/gtk.css" "$TARGET_ROOT/home/liveuser/.config/gtk-3.0/gtk.css"

echo "=== Emblems Successfully Removed ==="
