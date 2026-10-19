#!/usr/bin/env bash
# ==============================================================================
# AllGlider Live Linux - Chroot Setup Script (runs inside Fedora 44 image build)
# Configures WinBridge, UMU, GE-Proton, AllGlider, Persistence, and Installer.
# ==============================================================================
set -euxo pipefail

KVER="${1:-$(ls /lib/modules | sort -V | tail -n 1)}"
source /opt/allglider/config/versions.lock

echo "=== [1/7] Installing UMU Launcher (${UMU_VERSION}) ==="
if ! command -v umu-run >/dev/null 2>&1; then
    dnf -y install "${UMU_RPM_URL}" || true
fi

echo "=== [2/7] Building and Installing WinBridge (${WINBRIDGE_COMMIT}) ==="
if [ -d /opt/allglider/src/winbridge ]; then
    pushd /opt/allglider/src/winbridge
    make clean || true
    make -j"$(nproc)"
    make install
    popd
    rm -rf /opt/allglider/src/winbridge
fi

echo "=== [3/7] Configuring Skeleton User Profile (/etc/skel) ==="
mkdir -p /etc/skel/Desktop
mkdir -p /etc/skel/.config/winbridge
mkdir -p /etc/skel/.config/autostart
mkdir -p /etc/skel/.config/allglider
mkdir -p /etc/skel/.local/share/winbridge/shared
mkdir -p /etc/skel/.local/share/applications

# Configure WinBridge default Proton & shared prefix
cat > /etc/skel/.config/winbridge/settings.json << EOF
{
    "prefix": "/home/liveuser/.local/share/winbridge/shared",
    "proton": "/opt/allglider/proton/${PROTON_VERSION}"
}
EOF
chmod 0600 /etc/skel/.config/winbridge/settings.json

# Pre-seed UMU runtime symlink if offline runtime was staged
if [ -d /opt/allglider/umu-runtime ]; then
    mkdir -p /etc/skel/.local/share/umu
    cp -a /opt/allglider/umu-runtime/* /etc/skel/.local/share/umu/ || true
fi

# Register .exe MIME associations for Thunar / Xfce
cat > /etc/skel/.config/mimeapps.list << 'EOF'
[Default Applications]
application/x-ms-dos-executable=winbridge.desktop
application/x-msdownload=winbridge.desktop
application/x-executable=winbridge.desktop
application/x-wine-extension-msp=winbridge.desktop

[Added Associations]
application/x-ms-dos-executable=winbridge.desktop;
application/x-msdownload=winbridge.desktop;
EOF

echo "=== [4/7] Installing AllGlider (${ALLGLIDER_VERSION}) ==="
if [ -d /opt/allglider/app ]; then
    # AllGlider requires a writable folder because Launcher copies allglider-gui to a random name
    cp -a /opt/allglider/app /etc/skel/AllGlider
    chmod +x /etc/skel/AllGlider/Launcher /etc/skel/AllGlider/og-inputbridge.exe || true

    # Create AllGlider wrapper script in /usr/local/bin
    cat > /usr/local/bin/allglider << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
APP_DIR="$HOME/AllGlider"
if [ ! -d "$APP_DIR" ] && [ -d /opt/allglider/app ]; then
    cp -a /opt/allglider/app "$APP_DIR"
fi
chmod +x "$APP_DIR"/Launcher "$APP_DIR"/allglider-gui 2>/dev/null || true
cd "$APP_DIR"
exec ./Launcher "$@"
EOF
    chmod 0755 /usr/local/bin/allglider

    # Application menu & Desktop entry for AllGlider
    cat > /usr/share/applications/allglider.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=AllGlider
GenericName=MMO Automation Engine
Comment=Start AllGlider
Exec=/usr/local/bin/allglider
Icon=allglider
Terminal=false
Categories=Game;Utility;
StartupNotify=true
EOF
    ln -sf /usr/share/applications/allglider.desktop /etc/skel/Desktop/allglider.desktop
fi

echo "=== [4b/7] Applying AllGlider Branding, Custom Wallpaper & Minimal Xfce4 Config ==="
if [ -d /opt/allglider/branding ]; then
    # 1. Install AllGlider icons system-wide (hicolor theme + pixmaps)
    mkdir -p /usr/share/icons/hicolor /usr/share/pixmaps
    if [ -d /opt/allglider/branding/icons/hicolor ]; then
        cp -a /opt/allglider/branding/icons/hicolor/* /usr/share/icons/hicolor/
    fi
    if [ -f /opt/allglider/branding/icons/allglider.png ]; then
        cp -f /opt/allglider/branding/icons/allglider.png /usr/share/pixmaps/allglider.png
    fi
    if [ -f /opt/allglider/branding/icons/allglider.svg ]; then
        cp -f /opt/allglider/branding/icons/allglider.svg /usr/share/pixmaps/allglider.svg
    fi
    gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true

    # 2. Install custom wallpapers and set as system-wide Fedora Xfce default for all monitor outputs
    mkdir -p /usr/share/backgrounds/allglider /usr/share/backgrounds/images
    cp -a /opt/allglider/branding/wallpapers/* /usr/share/backgrounds/allglider/
    CUSTOM_WP=$(ls /usr/share/backgrounds/allglider/allglider-wallpaper.* | head -n 1)
    if [ -n "$CUSTOM_WP" ]; then
        ln -sf "$CUSTOM_WP" /usr/share/backgrounds/images/default.png
        ln -sf "$CUSTOM_WP" /usr/share/backgrounds/images/default.svg
        ln -sf "$CUSTOM_WP" /usr/share/backgrounds/default.png
        if [ -f /etc/lightdm/lightdm-gtk-greeter.conf ]; then
            sed -i "s|^#*background=.*|background=$CUSTOM_WP|" /etc/lightdm/lightdm-gtk-greeter.conf
        fi
    fi

    # 3. Install minimal, dark-themed Xfce4 settings into both /etc/xdg/xfce4 and /etc/skel
    mkdir -p /etc/xdg/xfce4/xfconf/xfce-perchannel-xml /etc/xdg/xfce4/panel
    mkdir -p /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml /etc/skel/.config/xfce4/panel
    for xml_file in /opt/allglider/branding/xfce/*.xml; do
        if [ -f "$xml_file" ]; then
            cp -f "$xml_file" /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/
            cp -f "$xml_file" /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/
        fi
    done
    if [ -f /opt/allglider/branding/xfce/xfce4-panel.xml ]; then
        cp -f /opt/allglider/branding/xfce/xfce4-panel.xml /etc/xdg/xfce4/panel/default.xml
    fi
    cp -f /opt/allglider/branding/xfce/whiskermenu-*.rc /etc/skel/.config/xfce4/panel/ 2>/dev/null || true
    cp -f /opt/allglider/branding/xfce/whiskermenu-*.rc /etc/xdg/xfce4/panel/ 2>/dev/null || true

    # Override every known start menu icon across all themes with official AllGlider logo
    for target_icon in fedora-logo-icon.png org.xfce.panel.applicationsmenu.png org.xfce.panel.whiskermenu.png xfce4-panel-menu.png xfce4-logo.png start-here.png; do
        find /usr/share/icons -name "$target_icon" -exec cp -f /opt/allglider/branding/icons/allglider.png {} + 2>/dev/null || true
    done
    for target_svg in fedora-logo-icon.svg org.xfce.panel.applicationsmenu.svg org.xfce.panel.whiskermenu.svg xfce4-panel-menu.svg xfce4-logo.svg start-here.svg; do
        find /usr/share/icons -name "$target_svg" -exec cp -f /opt/allglider/branding/icons/allglider.svg {} + 2>/dev/null || true
    done

    # 4. Install Plymouth Boot Splash branding (OpenGlider watermark & AllGlider center)
    if [ -d /opt/allglider/branding/plymouth ]; then
        mkdir -p /usr/share/plymouth/themes/spinner /usr/share/plymouth/themes/bgrt /usr/share/pixmaps
        cp -f /opt/allglider/branding/plymouth/watermark.png /usr/share/plymouth/themes/spinner/watermark.png
        cp -f /opt/allglider/branding/plymouth/watermark.png /usr/share/pixmaps/system-logo-white.png
        cp -f /opt/allglider/branding/plymouth/watermark.png /usr/share/pixmaps/fedora-logo-sprite.png
        cp -f /opt/allglider/branding/plymouth/bgrt-fallback.png /usr/share/plymouth/themes/spinner/bgrt-fallback.png
        cp -f /opt/allglider/branding/plymouth/background.png /usr/share/plymouth/themes/spinner/background.png

        for pfile in /usr/share/plymouth/themes/bgrt/bgrt.plymouth /usr/share/plymouth/themes/spinner/spinner.plymouth; do
            if [ -f "$pfile" ]; then
                sed -i 's/^UseFirmwareBackground=.*/UseFirmwareBackground=false/' "$pfile"
                sed -i 's/^WatermarkVerticalAlignment=.*/WatermarkVerticalAlignment=.95/' "$pfile"
                sed -i 's/^VerticalAlignment=.*/VerticalAlignment=.7/' "$pfile"
                grep -q "ScaleBackgroundImage" "$pfile" || sed -i '/\[two-step\]/a ScaleBackgroundImage=true' "$pfile"
            fi
        done
    fi
fi

echo "=== [5/7] Installing First-Boot Setup, Display Initializer & Graphical Disk Installer ==="
install -m 0755 /opt/allglider/installer/first-boot-restore/allglider-welcome.py /usr/local/bin/allglider-welcome
install -m 0755 /opt/allglider/installer/ui/allglider-installer.py /usr/local/bin/allglider-installer
install -m 0755 /opt/allglider/installer/migration/migrate-data.sh /usr/local/bin/allglider-migrate
install -m 0755 /opt/allglider/scripts/collect-diagnostics.sh /usr/local/bin/allglider-diagnostics
install -m 0755 /opt/allglider/scripts/allglider-display-init.sh /usr/local/bin/allglider-display-init

cat > /etc/xdg/autostart/allglider-display-init.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=AllGlider Display Resolution Initializer
Exec=/usr/local/bin/allglider-display-init
Terminal=false
NoDisplay=true
X-GNOME-Autostart-Phase=Initialization
EOF

# Desktop entry for First-Boot / Battle.net Setup
cat > /usr/share/applications/allglider-welcome.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=AllGlider & Battle.net Setup
GenericName=First Boot Wizard
Comment=Set up Battle.net, Proton, and verify graphics drivers
Exec=/usr/local/bin/allglider-welcome
Icon=system-software-install
Terminal=false
Categories=System;Game;
EOF
cp /usr/share/applications/allglider-welcome.desktop /etc/skel/.config/autostart/allglider-welcome.desktop
ln -sf /usr/share/applications/allglider-welcome.desktop /etc/skel/Desktop/allglider-welcome.desktop

# Desktop entry for Graphical Disk Installer
cat > /usr/share/applications/allglider-installer.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Install AllGlider Linux to Disk
GenericName=System Installer
Comment=Install AllGlider Linux onto an internal disk and migrate your USB setup
Exec=pkexec /usr/local/bin/allglider-installer
Icon=drive-harddisk
Terminal=false
Categories=System;
EOF
chmod 0755 /usr/share/applications/allglider-installer.desktop
ln -sf /usr/share/applications/allglider-installer.desktop /etc/skel/Desktop/allglider-installer.desktop

# Copy WinBridge Manager desktop shortcut to Desktop if installed
if [ -f /usr/local/share/applications/winbridge-manager.desktop ]; then
    cp -f /usr/local/share/applications/winbridge-manager.desktop /usr/share/applications/
    chmod 0755 /usr/share/applications/winbridge-manager.desktop
    ln -sf /usr/share/applications/winbridge-manager.desktop /etc/skel/Desktop/winbridge-manager.desktop
fi

echo "=== [6/7] Installing Persistent USB Auto-Mount, GPU Detection & Disk Scan Services ==="
install -m 0755 /opt/allglider/scripts/allglider-persistence-mount.sh /usr/local/sbin/allglider-persistence-mount
install -m 0755 /opt/allglider/scripts/allglider-gpu-check.sh /usr/local/sbin/allglider-gpu-check
install -m 0755 /opt/allglider/scripts/allglider-disk-scan.sh /usr/local/sbin/allglider-disk-scan

cat > /etc/systemd/system/allglider-disk-scan.service << 'EOF'
[Unit]
Description=AllGlider Host Disk Scanner for Battle.net & WoW
After=local-fs.target systemd-udevd.service
Before=lightdm.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/allglider-disk-scan

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/allglider-persistence.service << 'EOF'
[Unit]
Description=AllGlider Persistent USB Data Partition Auto-Mounter (ALLGLIDER_DATA)
DefaultDependencies=no
After=local-fs-pre.target systemd-udevd.service
Before=local-fs.target lightdm.service NetworkManager.service
Conflicts=shutdown.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/allglider-persistence-mount

[Install]
WantedBy=local-fs.target
EOF

cat > /etc/systemd/system/allglider-gpu-check.service << 'EOF'
[Unit]
Description=AllGlider GPU & Vulkan Readiness Check (NVIDIA / AMD / Intel)
After=systemd-modules-load.service
Before=lightdm.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/allglider-gpu-check

[Install]
WantedBy=multi-user.target
EOF

systemctl enable allglider-persistence.service allglider-gpu-check.service allglider-disk-scan.service

echo "=== [7/7] Populating /home/liveuser from /etc/skel ==="
mkdir -p /home/liveuser
cp -a /etc/skel/. /home/liveuser/
chown -h -R liveuser:liveuser /home/liveuser

update-mime-database /usr/local/share/mime || true
update-mime-database /usr/share/mime || true
echo "=== Chroot Setup Complete ==="
