#!/usr/bin/env bash
# ==============================================================================
# AllGlider Live Linux - Inner Fedora 44 Container ISO Builder
# Runs inside registry.fedoraproject.org/fedora:44 (rootless Podman).
# Builds the complete Fedora 44 Xfce + NVIDIA + WinBridge + AllGlider Live ISO
# without requiring host sudo or /dev/loop devices.
# ==============================================================================
set -euxo pipefail

WORKSPACE="/workspace"
STAGING="/var/tmp/allglider-staging"
source "$WORKSPACE/config/versions.lock"

DNF_CACHE="/workspace/cache/dnf-f44"
mkdir -p "$DNF_CACHE"

echo "=== [1/8] Configuring DNF Cache & Validating Kickstart ==="
cat >> /etc/dnf/dnf.conf << EOF
keepcache=True
cachedir=${DNF_CACHE}
max_parallel_downloads=10
EOF

# Install Kickstart validator, DNF5 plugins & ISO assembly tools in builder container
dnf -y install \
    dnf5-plugins \
    pykickstart \
    squashfs-tools \
    e2fsprogs \
    dosfstools \
    mtools \
    xorriso \
    syslinux \
    grub2-tools \
    grub2-tools-extra \
    grub2-pc-modules \
    grub2-efi-x64-cdboot \
    grub2-efi-x64-modules \
    shim-x64 \
    rsync \
    jq \
    git \
    curl \
    findutils \
    cpio

echo "Validating Kickstart syntax: config/fedora-live.ks"
ksvalidator "$WORKSPACE/config/fedora-live.ks"

echo "=== [2/8] Enabling RPM Fusion Free & Nonfree (Fedora ${FEDORA_RELEASE}) ==="
dnf -y install \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_RELEASE}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_RELEASE}.noarch.rpm"

echo "=== [3/8] Installing Fedora ${FEDORA_RELEASE} Xfce, NVIDIA, Mesa 32/64-bit & Gaming Packages ==="
# Read package list from packages-base.txt and packages-gaming.txt (excluding comments and empty lines)
mapfile -t BASE_PKGS < <(grep -vE '^\s*(#|$)' "$WORKSPACE/config/packages-base.txt")
mapfile -t GAME_PKGS < <(grep -vE '^\s*(#|$)' "$WORKSPACE/config/packages-gaming.txt")

dnf -y --setopt=install_weak_deps=False install --skip-unavailable \
    "${BASE_PKGS[@]}" \
    "${GAME_PKGS[@]}" \
    "${UMU_RPM_URL}"

# Remove heavy packages if pulled in by groups
dnf -y remove libreoffice\* thunderbird\* gimp\* pidgin\* transmission\* cheese\* || true

# Install OpenSSL 4.0 compatibility libraries for AllGlider
if [ -f /usr/lib64/libcrypto.so.4.0.3 ]; then
    ln -sf libcrypto.so.4.0.3 /usr/lib64/libcrypto.so.4
fi
if [ -f /usr/lib64/libssl.so.4.0.3 ]; then
    ln -sf libssl.so.4.0.3 /usr/lib64/libssl.so.4
fi
ldconfig

echo "=== [4/8] Staging AllGlider, WinBridge, Proton & Branding into /opt/allglider ==="
mkdir -p /opt/allglider
cp -a "$STAGING"/* /opt/allglider/

# Create liveuser account & passwordless sudo
if ! id liveuser >/dev/null 2>&1; then
    useradd -m -u 1000 -G wheel,video,render,audio,input -c "AllGlider Live User" liveuser
    passwd -d liveuser || true
fi

cat > /etc/sudoers.d/allglider-liveuser << 'EOF'
liveuser ALL=(ALL) NOPASSWD: ALL
Defaults:liveuser !requiretty
EOF
chmod 0440 /etc/sudoers.d/allglider-liveuser

# Disable SELinux enforcing so SquashFS (-no-xattrs) and Wine/Proton never hit unlabeled_t denials
if [ -f /etc/selinux/config ]; then
    sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
fi

# Set system language to English (en_US.UTF-8)
echo 'LANG="en_US.UTF-8"' > /etc/locale.conf

# Configure LightDM autologin into Xfce4 + 1920x1080 display setup
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/50-allglider-autologin.conf << 'EOF'
[Seat:*]
autologin-user=liveuser
autologin-user-timeout=0
user-session=xfce
display-setup-script=/usr/local/bin/allglider-display-init
EOF

echo 'livesys_session="xfce"' > /etc/sysconfig/livesys

# Configure NVIDIA & Nouveau blacklist + Xorg OutputClass so NVIDIA/AMD/Intel/QEMU all work out of the box
cat > /etc/modprobe.d/allglider-nvidia.conf << 'EOF'
blacklist nouveau
options nouveau modeset=0
options nvidia-drm modeset=1 fbdev=1
EOF

mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/10-allglider-gpu.conf << 'EOF'
Section "OutputClass"
    Identifier "nvidia"
    MatchDriver "nvidia-drm"
    Driver "nvidia"
    Option "AllowEmptyInitialConfiguration"
    Option "PrimaryGPU" "yes"
    ModulePath "/usr/lib64/nvidia/xorg"
    ModulePath "/usr/lib64/xorg/modules"
EndSection
EOF

echo "=== [5/8] Pre-compiling NVIDIA Kernel Module (akmods) for Fedora ${FEDORA_RELEASE} Kernel ==="
KVER=$(ls /lib/modules | sort -V | tail -n 1)
echo "Target Fedora ${FEDORA_RELEASE} Kernel: ${KVER}"
akmods --force --kernels "$KVER" || echo "WARN: akmods returned non-zero, continuing..."
depmod -a "$KVER"

echo "=== [6/8] Running chroot-setup.sh (WinBridge, AllGlider, Branding, Services) ==="
/opt/allglider/scripts/chroot-setup.sh "$KVER"

# Enable essential services and set graphical.target as default
systemctl enable NetworkManager.service lightdm.service bluetooth.service udisks2.service || true
systemctl set-default graphical.target || true
ln -sf /usr/lib/systemd/system/lightdm.service /etc/systemd/system/display-manager.service

echo "=== [7/8] Generating Live Initramfs (dracut dmsquash-live) ==="
dracut --force --no-hostonly \
    --add "dmsquash-live pollcdrom" \
    --add-drivers "overlay" \
    --kver "$KVER" \
    "/boot/initramfs-${KVER}.img"

echo "=== [8/8] Packing SquashFS Live Image & Building Hybrid UEFI/BIOS ISO ==="
ISO_WORK="/var/tmp/iso-work"
ISO_ROOT="$ISO_WORK/iso_root"
rm -rf "$ISO_WORK"
mkdir -p "$ISO_ROOT"/{LiveOS,images/pxeboot,EFI/BOOT,boot/grub2/i386-pc}

# Ensure standard mountpoints exist with proper permissions
mkdir -p /{dev,proc,sys,run,tmp,mnt,media,var/tmp}
chmod 1777 /tmp /var/tmp

# Copy kernel and initramfs before packing SquashFS
cp "/boot/vmlinuz-${KVER}" "$ISO_ROOT/images/pxeboot/vmlinuz"
cp "/boot/initramfs-${KVER}.img" "$ISO_ROOT/images/pxeboot/initrd.img"

# Build SquashFS directly from / (supported natively by dracut dmsquash-live with rd.live.overlay.overlayfs=1)
mksquashfs / "$ISO_ROOT/LiveOS/squashfs.img" \
    -comp zstd -Xcompression-level 6 \
    -no-xattrs -noappend \
    -wildcards \
    -e \
    "proc/*" \
    "sys/*" \
    "dev/*" \
    "run/*" \
    "tmp/*" \
    "mnt/*" \
    "media/*" \
    "var/tmp/*" \
    "var/cache/libdnf5/*" \
    "var/cache/dnf/*" \
    "workspace" \
    "workspace/*"

# Create GRUB configuration for both UEFI and BIOS
cat > "$ISO_ROOT/boot/grub2/grub.cfg" << 'EOF'
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

# Prepare UEFI Boot Image (efiboot.img)
grub2-mkstandalone \
    -d /usr/lib/grub/x86_64-efi \
    -O x86_64-efi \
    --modules="part_gpt part_msdos fat iso9660 ext2 normal boot linux configfile loopback chain efifwsetup efi_gop efi_uga ls search search_label search_fs_uuid search_fs_file gfxterm all_video loadenv" \
    -o "$ISO_ROOT/EFI/BOOT/BOOTX64.EFI" \
    "boot/grub2/grub.cfg=$ISO_ROOT/boot/grub2/grub.cfg"

dd if=/dev/zero of="$ISO_ROOT/images/efiboot.img" bs=1M count=16
mkfs.vfat "$ISO_ROOT/images/efiboot.img"
mmd -i "$ISO_ROOT/images/efiboot.img" ::/EFI ::/EFI/BOOT
mcopy -i "$ISO_ROOT/images/efiboot.img" "$ISO_ROOT/EFI/BOOT/BOOTX64.EFI" ::/EFI/BOOT/BOOTX64.EFI
mcopy -i "$ISO_ROOT/images/efiboot.img" "$ISO_ROOT/EFI/BOOT/grub.cfg" ::/EFI/BOOT/grub.cfg

# Prepare BIOS El Torito Boot Image
cp -r /usr/lib/grub/i386-pc/* "$ISO_ROOT/boot/grub2/i386-pc/"
grub2-mkimage \
    -d /usr/lib/grub/i386-pc \
    -O i386-pc-eltorito \
    -o "$ISO_ROOT/boot/grub2/i386-pc/eltorito.img" \
    -p /boot/grub2 \
    iso9660 biosdisk part_msdos part_gpt normal boot linux configfile search search_label

ISO_NAME="AllGlider-Live-F${FEDORA_RELEASE}-${ALLGLIDER_DISTRO_VERSION}-x86_64.iso"
mkdir -p "$WORKSPACE/build"

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
    -output "$WORKSPACE/build/${ISO_NAME}" \
    "$ISO_ROOT"

(cd "$WORKSPACE/build" && sha256sum "${ISO_NAME}" > "${ISO_NAME}.sha256")
echo "=== SUCCESS: Built $WORKSPACE/build/${ISO_NAME} ==="
