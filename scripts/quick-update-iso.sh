#!/usr/bin/env bash
# ==============================================================================
# AllGlider Live Linux - Fast ISO Updater (~45 seconds)
# Updates scripts, installer, branding, Xfce4 configs, locale, and GRUB inside
# an existing built ISO without re-running full DNF package installation.
# ==============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/config/versions.lock"

chmod +x "$REPO_ROOT"/scripts/*.sh "$REPO_ROOT"/installer/first-boot-restore/*.py "$REPO_ROOT"/installer/ui/*.py "$REPO_ROOT"/installer/migration/*.sh
"$REPO_ROOT/scripts/stage-assets.sh"

podman run --rm \
    --security-opt label=disable \
    -v "$REPO_ROOT:/workspace" \
    -v "$REPO_ROOT/cache/dnf-f44:/var/cache/libdnf5" \
    -v "/var/tmp/allglider-staging:/var/tmp/allglider-staging" \
    -v "/usr/lib64/libcrypto.so.4.0.3:/usr/lib64/libcrypto.so.4.0.3:ro" \
    -v "/usr/lib64/libssl.so.4.0.3:/usr/lib64/libssl.so.4.0.3:ro" \
    "registry.fedoraproject.org/fedora:${FEDORA_RELEASE}" \
    bash -euxc '
        dnf -y install xorriso squashfs-tools grub2-tools grub2-tools-extra grub2-pc-modules grub2-efi-x64-modules dosfstools mtools gtk3 shared-mime-info cpio findutils >/dev/null

        ISO_PATH="/workspace/build/AllGlider-Live-F44-0.1.0-x86_64.iso"
        WORK="/var/tmp/quick_iso"
        ISO_ROOT="$WORK/iso_root"
        SQ_ROOT="$WORK/sq_root"
        rm -rf "$WORK"
        mkdir -p "$ISO_ROOT"

        osirrox -indev "$ISO_PATH" -extract / "$ISO_ROOT"
        chmod -R u+w "$ISO_ROOT"

        unsquashfs -no-xattrs -d "$SQ_ROOT" "$ISO_ROOT/LiveOS/squashfs.img"
        rm -f "$ISO_ROOT/LiveOS/squashfs.img"

        # Install Qt6 WebSockets & Multimedia dependencies into squashfs root
        dnf -y --installroot="$SQ_ROOT" --setopt=cachedir=/var/cache/libdnf5 install qt6-qtwebsockets qt6-qtmultimedia >/dev/null 2>&1 || true

        # Install OpenSSL 4.0 compatibility libraries for AllGlider
        cp -f /usr/lib64/libcrypto.so.4.0.3 "$SQ_ROOT/usr/lib64/libcrypto.so.4.0.3"
        cp -f /usr/lib64/libssl.so.4.0.3 "$SQ_ROOT/usr/lib64/libssl.so.4.0.3"
        ln -sf libcrypto.so.4.0.3 "$SQ_ROOT/usr/lib64/libcrypto.so.4"
        ln -sf libssl.so.4.0.3 "$SQ_ROOT/usr/lib64/libssl.so.4"
        chroot "$SQ_ROOT" ldconfig 2>/dev/null || true

        # Remove heavy non-gaming packages: CUDA compute libs and leftover build tools to shrink ISO
        rpm --root="$SQ_ROOT" -e --nodeps xorg-x11-drv-nvidia-cuda xorg-x11-drv-nvidia-cuda-libs xorg-x11-drv-nvidia-cuda-libs.i686 xorg-x11-drv-nvidia-kmodsrc 2>/dev/null || true
        rpm --root="$SQ_ROOT" -e --nodeps kernel-devel gcc gcc-c++ cmake cpp hplip 2>/dev/null || true
        rm -rf "$SQ_ROOT"/usr/share/doc/* "$SQ_ROOT"/usr/share/man/* "$SQ_ROOT"/var/cache/* 2>/dev/null || true

        # Copy updated staging into /opt/allglider inside squashfs root
        rm -rf "$SQ_ROOT/opt/allglider"
        mkdir -p "$SQ_ROOT/opt/allglider"
        cp -a /var/tmp/allglider-staging/* "$SQ_ROOT/opt/allglider/"

        # Ensure executable permissions on AllGlider binaries in /opt/allglider
        chmod +x "$SQ_ROOT"/opt/allglider/app/* 2>/dev/null || true

        # Install real AllGlider icons system-wide (hicolor theme + pixmaps)
        mkdir -p "$SQ_ROOT/usr/share/icons/hicolor" "$SQ_ROOT/usr/share/pixmaps"
        cp -a /var/tmp/allglider-staging/branding/icons/hicolor/* "$SQ_ROOT/usr/share/icons/hicolor/"
        cp -f /var/tmp/allglider-staging/branding/icons/*.png "$SQ_ROOT/usr/share/pixmaps/" 2>/dev/null || true
        cp -f /var/tmp/allglider-staging/branding/icons/*.svg "$SQ_ROOT/usr/share/pixmaps/" 2>/dev/null || true

        # Override every known start menu icon across all themes with official AllGlider logo
        for target_icon in fedora-logo-icon.png org.xfce.panel.applicationsmenu.png org.xfce.panel.whiskermenu.png xfce4-panel-menu.png xfce4-logo.png start-here.png; do
            find "$SQ_ROOT/usr/share/icons" -name "$target_icon" -exec cp -f /var/tmp/allglider-staging/branding/icons/allglider.png {} + 2>/dev/null || true
        done
        for target_svg in fedora-logo-icon.svg org.xfce.panel.applicationsmenu.svg org.xfce.panel.whiskermenu.svg xfce4-panel-menu.svg xfce4-logo.svg start-here.svg; do
            find "$SQ_ROOT/usr/share/icons" -name "$target_svg" -exec cp -f /var/tmp/allglider-staging/branding/icons/allglider.svg {} + 2>/dev/null || true
        done
        chroot "$SQ_ROOT" gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true

        # Configure Plymouth boot splash: OpenGlider watermark & AllGlider center logo
        mkdir -p "$SQ_ROOT/usr/share/plymouth/themes/spinner" "$SQ_ROOT/usr/share/plymouth/themes/bgrt" "$SQ_ROOT/usr/share/pixmaps"
        if [ -d /var/tmp/allglider-staging/branding/plymouth ]; then
            cp -f /var/tmp/allglider-staging/branding/plymouth/watermark.png "$SQ_ROOT/usr/share/plymouth/themes/spinner/watermark.png"
            cp -f /var/tmp/allglider-staging/branding/plymouth/watermark.png "$SQ_ROOT/usr/share/pixmaps/system-logo-white.png"
            cp -f /var/tmp/allglider-staging/branding/plymouth/watermark.png "$SQ_ROOT/usr/share/pixmaps/fedora-logo-sprite.png"
            cp -f /var/tmp/allglider-staging/branding/plymouth/bgrt-fallback.png "$SQ_ROOT/usr/share/plymouth/themes/spinner/bgrt-fallback.png"
            cp -f /var/tmp/allglider-staging/branding/plymouth/background.png "$SQ_ROOT/usr/share/plymouth/themes/spinner/background.png"

            for pfile in "$SQ_ROOT/usr/share/plymouth/themes/bgrt/bgrt.plymouth" "$SQ_ROOT/usr/share/plymouth/themes/spinner/spinner.plymouth"; do
                if [ -f "$pfile" ]; then
                    sed -i "s/^UseFirmwareBackground=.*/UseFirmwareBackground=false/" "$pfile"
                    sed -i "s/^WatermarkVerticalAlignment=.*/WatermarkVerticalAlignment=.95/" "$pfile"
                    sed -i "s/^VerticalAlignment=.*/VerticalAlignment=.7/" "$pfile"
                    grep -q "ScaleBackgroundImage" "$pfile" || sed -i "/\[two-step\]/a ScaleBackgroundImage=true" "$pfile"
                fi
            done
        fi

        # Install AllGlider desktop wallpapers across all system locations
        mkdir -p "$SQ_ROOT/usr/share/backgrounds/allglider" "$SQ_ROOT/usr/share/backgrounds/images" "$SQ_ROOT/usr/share/backgrounds/xfce"
        cp -a /var/tmp/allglider-staging/branding/wallpapers/* "$SQ_ROOT/usr/share/backgrounds/allglider/" 2>/dev/null || true
        CUSTOM_WP="$SQ_ROOT/usr/share/backgrounds/allglider/allglider-wallpaper.png"
        if [ -f "$CUSTOM_WP" ]; then
            ln -sf /usr/share/backgrounds/allglider/allglider-wallpaper.png "$SQ_ROOT/usr/share/backgrounds/images/default.png"
            ln -sf /usr/share/backgrounds/allglider/allglider-wallpaper.png "$SQ_ROOT/usr/share/backgrounds/default.png"
            ln -sf /usr/share/backgrounds/allglider/allglider-wallpaper.png "$SQ_ROOT/usr/share/backgrounds/xfce/xfce-shapes.svg" 2>/dev/null || true
        fi

        # Remove desktop icon emblems (padlocks & symlink arrows) system-wide
        /var/tmp/allglider-staging/scripts/remove-desktop-emblems.sh "$SQ_ROOT"

        # Set English locale & SELinux disabled
        echo "LANG=\"en_US.UTF-8\"" > "$SQ_ROOT/etc/locale.conf"
        if [ -f "$SQ_ROOT/etc/selinux/config" ]; then
            sed -i "s/^SELINUX=.*/SELINUX=disabled/" "$SQ_ROOT/etc/selinux/config"
        fi

        # LightDM display-setup-script for 1920x1080
        cat > "$SQ_ROOT/etc/lightdm/lightdm.conf.d/50-allglider-autologin.conf" << "EOF"
[Seat:*]
autologin-user=liveuser
autologin-user-timeout=0
user-session=xfce
display-setup-script=/usr/local/bin/allglider-display-init
EOF

        # Install updated scripts, wizards, and branding into SQ_ROOT
        install -m 0755 /var/tmp/allglider-staging/installer/first-boot-restore/allglider-welcome.py "$SQ_ROOT/usr/local/bin/allglider-welcome"
        install -m 0755 /var/tmp/allglider-staging/installer/ui/allglider-installer.py "$SQ_ROOT/usr/local/bin/allglider-installer"
        install -m 0755 /var/tmp/allglider-staging/installer/migration/migrate-data.sh "$SQ_ROOT/usr/local/bin/allglider-migrate"
        install -m 0755 /var/tmp/allglider-staging/scripts/collect-diagnostics.sh "$SQ_ROOT/usr/local/bin/allglider-diagnostics"
        install -m 0755 /var/tmp/allglider-staging/scripts/remove-desktop-emblems.sh "$SQ_ROOT/usr/local/sbin/allglider-remove-emblems"
        install -m 0755 /var/tmp/allglider-staging/scripts/allglider-display-init.sh "$SQ_ROOT/usr/local/bin/allglider-display-init"
        install -m 0755 /var/tmp/allglider-staging/scripts/allglider-persistence-mount.sh "$SQ_ROOT/usr/local/sbin/allglider-persistence-mount"
        install -m 0755 /var/tmp/allglider-staging/scripts/allglider-gpu-check.sh "$SQ_ROOT/usr/local/sbin/allglider-gpu-check"
        install -m 0755 /var/tmp/allglider-staging/scripts/allglider-disk-scan.sh "$SQ_ROOT/usr/local/sbin/allglider-disk-scan"

        cat > "$SQ_ROOT/etc/systemd/system/allglider-disk-scan.service" << "EOF"
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
        mkdir -p "$SQ_ROOT/etc/systemd/system/multi-user.target.wants"
        ln -sf /etc/systemd/system/allglider-disk-scan.service "$SQ_ROOT/etc/systemd/system/multi-user.target.wants/allglider-disk-scan.service"

        # Update /usr/local/bin/allglider launcher script
        cat > "$SQ_ROOT/usr/local/bin/allglider" << "EOF"
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
        chmod 0755 "$SQ_ROOT/usr/local/bin/allglider"

        cat > "$SQ_ROOT/etc/xdg/autostart/allglider-display-init.desktop" << "EOF"
[Desktop Entry]
Type=Application
Name=AllGlider Display Resolution Initializer
Exec=/usr/local/bin/allglider-display-init
Terminal=false
NoDisplay=true
X-GNOME-Autostart-Phase=Initialization
EOF

        # Ensure all 4 .desktop applications are registered system-wide
        mkdir -p "$SQ_ROOT/usr/share/applications" "$SQ_ROOT/etc/skel/Desktop" "$SQ_ROOT/home/liveuser/Desktop"

        cat > "$SQ_ROOT/usr/share/applications/allglider.desktop" << "EOF"
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

        cat > "$SQ_ROOT/usr/share/applications/allglider-welcome.desktop" << "EOF"
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

        cat > "$SQ_ROOT/usr/share/applications/allglider-installer.desktop" << "EOF"
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

        # Ensure all .desktop files in /usr/share/applications are root-owned and executable
        if [ -f "$SQ_ROOT/usr/local/share/applications/winbridge-manager.desktop" ]; then
            cp -f "$SQ_ROOT/usr/local/share/applications/winbridge-manager.desktop" "$SQ_ROOT/usr/share/applications/"
        fi
        chmod 0755 "$SQ_ROOT"/usr/share/applications/*.desktop
        chmod 0666 "$SQ_ROOT"/usr/share/applications/allglider*.desktop "$SQ_ROOT"/usr/share/applications/winbridge*.desktop 2>/dev/null || true

        # Populate Desktop icons as standalone regular files owned by liveuser (never symlinks)
        rm -rf "$SQ_ROOT/etc/skel/Desktop"/* "$SQ_ROOT/home/liveuser/Desktop"/*
        cp -f "$SQ_ROOT/usr/share/applications/allglider.desktop" "$SQ_ROOT/etc/skel/Desktop/"
        cp -f "$SQ_ROOT/usr/share/applications/allglider-welcome.desktop" "$SQ_ROOT/etc/skel/Desktop/"
        cp -f "$SQ_ROOT/usr/share/applications/allglider-installer.desktop" "$SQ_ROOT/etc/skel/Desktop/"
        if [ -f "$SQ_ROOT/usr/share/applications/winbridge-manager.desktop" ]; then
            cp -f "$SQ_ROOT/usr/share/applications/winbridge-manager.desktop" "$SQ_ROOT/etc/skel/Desktop/"
        fi
        chmod 0755 "$SQ_ROOT/etc/skel/Desktop"/*.desktop

        # Pre-seed ~/AllGlider in liveuser home
        rm -rf "$SQ_ROOT/home/liveuser/AllGlider"
        mkdir -p "$SQ_ROOT/home/liveuser/AllGlider"
        cp -a "$SQ_ROOT/opt/allglider/app/." "$SQ_ROOT/home/liveuser/AllGlider/"
        chmod +x "$SQ_ROOT/home/liveuser/AllGlider"/Launcher "$SQ_ROOT/home/liveuser/AllGlider"/allglider-gui 2>/dev/null || true

        # Apply Xfce4 dark theme & single panel layout to both /etc/xdg/xfce4 and /etc/skel
        mkdir -p "$SQ_ROOT/etc/xdg/xfce4/xfconf/xfce-perchannel-xml" "$SQ_ROOT/etc/xdg/xfce4/panel"
        mkdir -p "$SQ_ROOT/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml" "$SQ_ROOT/etc/skel/.config/xfce4/panel"
        for xml_file in /var/tmp/allglider-staging/branding/xfce/*.xml; do
            cp -f "$xml_file" "$SQ_ROOT/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/"
            cp -f "$xml_file" "$SQ_ROOT/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/"
        done
        cp -f /var/tmp/allglider-staging/branding/xfce/xfce4-panel.xml "$SQ_ROOT/etc/xdg/xfce4/panel/default.xml"
        cp -f /var/tmp/allglider-staging/branding/xfce/whiskermenu-*.rc "$SQ_ROOT/etc/skel/.config/xfce4/panel/" 2>/dev/null || true
        cp -f /var/tmp/allglider-staging/branding/xfce/whiskermenu-*.rc "$SQ_ROOT/etc/xdg/xfce4/panel/" 2>/dev/null || true

        # Sync /etc/skel to /home/liveuser
        cp -a "$SQ_ROOT/etc/skel/Desktop/." "$SQ_ROOT/home/liveuser/Desktop/"
        cp -a "$SQ_ROOT/etc/skel/.config/xfce4/." "$SQ_ROOT/home/liveuser/.config/xfce4/"
        cp -f /var/tmp/allglider-staging/branding/xfce/whiskermenu-*.rc "$SQ_ROOT/home/liveuser/.config/xfce4/panel/" 2>/dev/null || true

        # Fix ownership to liveuser:liveuser (1000:1000)
        chown -R 1000:1000 "$SQ_ROOT/home/liveuser"

        for d in "$SQ_ROOT/etc/skel/Desktop" "$SQ_ROOT/home/liveuser/Desktop"; do
            chmod 0755 "$d"/*.desktop 2>/dev/null || true
            for f in "$d"/*.desktop; do
                if [ -f "$f" ]; then
                    csum=$(sha256sum "$f" 2>/dev/null | cut -d" " -f1)
                    gio set -t string "$f" metadata::xfce-exe-checksum "$csum" 2>/dev/null || true
                    gio set -t string "$f" metadata::trusted true 2>/dev/null || true
                fi
            done
        done

        # Re-apply emblem removal and GTK3 CSS to ensure skel and liveuser are pristine
        /var/tmp/allglider-staging/scripts/remove-desktop-emblems.sh "$SQ_ROOT"
        chown -R 1000:1000 "$SQ_ROOT/home/liveuser"

        # Inject custom Plymouth splash directly into early boot initrd.img
        echo "=== Injecting custom Plymouth splash into initrd.img ==="
        INITRD_INJECT="$WORK/initrd_inject"
        rm -rf "$INITRD_INJECT"
        mkdir -p "$INITRD_INJECT/usr/share/plymouth/themes/spinner" "$INITRD_INJECT/usr/share/plymouth/themes/bgrt" "$INITRD_INJECT/usr/share/pixmaps"
        cp -f "$SQ_ROOT/usr/share/plymouth/themes/spinner/"*.png "$INITRD_INJECT/usr/share/plymouth/themes/spinner/" 2>/dev/null || true
        cp -f "$SQ_ROOT/usr/share/plymouth/themes/spinner/spinner.plymouth" "$INITRD_INJECT/usr/share/plymouth/themes/spinner/" 2>/dev/null || true
        cp -f "$SQ_ROOT/usr/share/plymouth/themes/bgrt/bgrt.plymouth" "$INITRD_INJECT/usr/share/plymouth/themes/bgrt/" 2>/dev/null || true
        cp -f "$SQ_ROOT/usr/share/pixmaps/system-logo-white.png" "$INITRD_INJECT/usr/share/pixmaps/" 2>/dev/null || true
        (cd "$INITRD_INJECT" && find . | cpio -o -H newc) >> "$ISO_ROOT/images/pxeboot/initrd.img"
        rm -rf "$INITRD_INJECT"

        # Repack SquashFS
        mksquashfs "$SQ_ROOT" "$ISO_ROOT/LiveOS/squashfs.img" -comp zstd -Xcompression-level 6 -no-xattrs -noappend
        rm -rf "$SQ_ROOT"

        # Update GRUB config with English menuentries & video=1920x1080
        cat > "$ISO_ROOT/boot/grub2/grub.cfg" << "EOF"
set default="0"
set timeout=5
insmod all_video
insmod gfxterm
insmod iso9660
insmod fat
insmod ext2
insmod part_gpt
insmod part_msdos
insmod search_label
insmod search_fs_file
terminal_output gfxterm

search --no-floppy --set=root --label ALLGLIDER_LIVE

menuentry "Start AllGlider Live Linux (Fedora 44 Xfce - NVIDIA / AMD / Intel)" {
    search --no-floppy --set=root --label ALLGLIDER_LIVE
    linux /images/pxeboot/vmlinuz root=live:CDLABEL=ALLGLIDER_LIVE rd.live.image rd.live.overlay.overlayfs=1 selinux=0 enforcing=0 systemd.unit=graphical.target video=1920x1080 rw quiet rhgb rd.driver.blacklist=nouveau modprobe.blacklist=nouveau nvidia-drm.modeset=1
    initrd /images/pxeboot/initrd.img
}

menuentry "Start AllGlider Live Linux (Troubleshooting / Verbose Mode)" {
    search --no-floppy --set=root --label ALLGLIDER_LIVE
    linux /images/pxeboot/vmlinuz root=live:CDLABEL=ALLGLIDER_LIVE rd.live.image rd.live.overlay.overlayfs=1 selinux=0 enforcing=0 systemd.unit=graphical.target video=1920x1080 rw rd.driver.blacklist=nouveau modprobe.blacklist=nouveau nvidia-drm.modeset=1
    initrd /images/pxeboot/initrd.img
}

menuentry "Start AllGlider Live Linux (Safe Graphics / Nomodeset)" {
    search --no-floppy --set=root --label ALLGLIDER_LIVE
    linux /images/pxeboot/vmlinuz root=live:CDLABEL=ALLGLIDER_LIVE rd.live.image rd.live.overlay.overlayfs=1 selinux=0 enforcing=0 systemd.unit=graphical.target rw nomodeset
    initrd /images/pxeboot/initrd.img
}
EOF
        cp "$ISO_ROOT/boot/grub2/grub.cfg" "$ISO_ROOT/EFI/BOOT/grub.cfg"

        grub2-mkstandalone \
            -d /usr/lib/grub/x86_64-efi \
            -O x86_64-efi \
            --modules="part_gpt part_msdos fat iso9660 ext2 normal boot linux configfile loopback chain efifwsetup efi_gop efi_uga ls search search_label search_fs_uuid search_fs_file gfxterm all_video loadenv" \
            -o "$ISO_ROOT/EFI/BOOT/BOOTX64.EFI" \
            "boot/grub2/grub.cfg=$ISO_ROOT/boot/grub2/grub.cfg"

        rm -f "$ISO_ROOT/images/efiboot.img"
        dd if=/dev/zero of="$ISO_ROOT/images/efiboot.img" bs=1M count=16
        mkfs.vfat "$ISO_ROOT/images/efiboot.img"
        mmd -i "$ISO_ROOT/images/efiboot.img" ::/EFI ::/EFI/BOOT
        mcopy -i "$ISO_ROOT/images/efiboot.img" "$ISO_ROOT/EFI/BOOT/BOOTX64.EFI" ::/EFI/BOOT/BOOTX64.EFI
        mcopy -i "$ISO_ROOT/images/efiboot.img" "$ISO_ROOT/EFI/BOOT/grub.cfg" ::/EFI/BOOT/grub.cfg

        grub2-mkimage \
            -d /usr/lib/grub/i386-pc \
            -O i386-pc-eltorito \
            -o "$ISO_ROOT/boot/grub2/i386-pc/eltorito.img" \
            -p /boot/grub2 \
            iso9660 biosdisk part_msdos part_gpt normal boot linux configfile search search_label

        xorriso -as mkisofs \
            -iso-level 3 \
            -full-iso9660-filenames \
            -volid "ALLGLIDER_LIVE" \
            -eltorito-boot boot/grub2/i386-pc/eltorito.img \
            -no-emul-boot \
            -boot-load-size 4 \
            -boot-info-table \
            --grub2-boot-info \
            --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
            -eltorito-alt-boot \
            -e images/efiboot.img \
            -no-emul-boot \
            -append_partition 2 0xef "$ISO_ROOT/images/efiboot.img" \
            -output "${ISO_PATH}.new" \
            "$ISO_ROOT"

        mv -f "${ISO_PATH}.new" "$ISO_PATH"
        (cd /workspace/build && sha256sum "$(basename "$ISO_PATH")" > "$(basename "$ISO_PATH").sha256")
    '
echo "=== Fast ISO Update Complete ==="
