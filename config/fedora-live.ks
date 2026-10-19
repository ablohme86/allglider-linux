# AllGlider Live Linux - Fedora 44 Kickstart Configuration
# Target: x86_64 Live ISO with Xfce4, NVIDIA + AMD/Intel out-of-the-box,
#         WinBridge, UMU, GE-Proton, AllGlider, Persistent USB & Installer.

lang en_US.UTF-8
keyboard us
timezone UTC
authselect select sssd with-silent-lastlog --force
selinux --permissive
firewall --enabled --service=mdns
 network --bootproto=dhcp --device=link --activate
rootpw --lock
user --name=liveuser --gecos="AllGlider Live User" --groups=wheel,video,render,audio,input --password=""

# Live image layout (squashfs root image size: 24 GiB uncompressed capacity)
zerombr
clearpart --all
part / --size=24576 --fstype=ext4

# Bootloader with NVIDIA DRM modeset & Nouveau blacklist (safe on AMD/Intel/QEMU too)
bootloader --location=none --append="rd.live.image quiet rhgb rd.driver.blacklist=nouveau modprobe.blacklist=nouveau nvidia-drm.modeset=1"

# Official Fedora 44 Repositories
repo --name=fedora --mirrorlist=https://mirrors.fedoraproject.org/mirrorlist?repo=fedora-44&arch=x86_64
repo --name=updates --mirrorlist=https://mirrors.fedoraproject.org/mirrorlist?repo=updates-released-f44&arch=x86_64

# RPM Fusion Free & Nonfree for Fedora 44 (Required for Out-of-the-Box NVIDIA Drivers)
repo --name=rpmfusion-free --mirrorlist=https://mirrors.rpmfusion.org/mirrorlist?repo=free-fedora-44&arch=x86_64
repo --name=rpmfusion-free-updates --mirrorlist=https://mirrors.rpmfusion.org/mirrorlist?repo=free-fedora-updates-released-44&arch=x86_64
repo --name=rpmfusion-nonfree --mirrorlist=https://mirrors.rpmfusion.org/mirrorlist?repo=nonfree-fedora-44&arch=x86_64
repo --name=rpmfusion-nonfree-updates --mirrorlist=https://mirrors.rpmfusion.org/mirrorlist?repo=nonfree-fedora-updates-released-44&arch=x86_64

# Services
services --enabled=NetworkManager,lightdm,bluetooth,udisks2,allglider-persistence,allglider-gpu-check --disabled=sshd

%packages
# Core & Xfce Desktop
@core
@xfce-desktop-environment
@hardware-support
@networkmanager-submodules

# Kernel & Live Boot
kernel
kernel-core
kernel-modules
kernel-modules-extra
kernel-devel
kernel-headers
dracut-live
livesys-scripts
grub2-efi-x64
grub2-efi-x64-cdboot
grub2-pc
grub2-pc-modules
grub2-tools
grub2-tools-extra
shim-x64
efibootmgr
syslinux

# Storage, Partitioning & Persistence
parted
gdisk
dosfstools
e2fsprogs
btrfs-progs
ntfs-3g
ntfsprogs
squashfs-tools
rsync
lsof
util-linux
cryptsetup
lvm2
udisks2

# Display Manager & Xfce Desktop Utilities
lightdm
lightdm-gtk
xfce4-terminal
xfce4-whiskermenu-plugin
xfce4-pulseaudio-plugin
xfce4-screenshooter
thunar
thunar-archive-plugin
file-roller
network-manager-applet
nm-connection-editor
blueman
pavucontrol
xdg-utils
xdg-user-dirs
xdg-user-dirs-gtk
shared-mime-info
zenity
libnotify

# PipeWire Audio
pipewire
pipewire-pulseaudio
pipewire-alsa
pipewire-jack-audio-connection-kit
wireplumber

# Networking & Firmware
NetworkManager
NetworkManager-wifi
NetworkManager-bluetooth
iwlwifi-dvm-firmware
iwlwifi-mvm-firmware
realtek-firmware
atheros-firmware
brcmfmac-firmware
mt7xxx-firmware
linux-firmware
curl
wget
ca-certificates
openssh-clients
git
jq
tar
xz
zstd
unzip

# AMD Radeon & Intel Graphics (64-bit + 32-bit for Proton/DXVK)
mesa-dri-drivers
mesa-dri-drivers.i686
mesa-vulkan-drivers
mesa-vulkan-drivers.i686
mesa-libGL
mesa-libGL.i686
mesa-libEGL
mesa-libEGL.i686
mesa-va-drivers
mesa-vdpau-drivers
vulkan-loader
vulkan-loader.i686
vulkan-tools
libva-utils
glx-utils
pciutils

# NVIDIA Out-of-the-Box Proprietary Drivers (64-bit + 32-bit)
akmods
akmod-nvidia
xorg-x11-drv-nvidia
xorg-x11-drv-nvidia-libs
xorg-x11-drv-nvidia-libs.i686
xorg-x11-drv-nvidia-cuda
xorg-x11-drv-nvidia-cuda-libs
xorg-x11-drv-nvidia-cuda-libs.i686
xorg-x11-drv-nvidia-power
nvidia-settings
nvidia-vaapi-driver

# WinBridge & AllGlider Dependencies
qt6-qtbase
qt6-qtbase-gui
qt6-qtbase-devel
qt6-qtsvg
qt6-qtwebsockets
qt6-qtmultimedia
python3
python3-gobject
python3-dbus
python3-requests
gtk3
gcc-c++
make
cmake

# Wine / Proton / UMU 32-bit & 64-bit Libraries
gamemode
gamemode.i686
libFAudio
libFAudio.i686
alsa-lib
alsa-lib.i686
pulseaudio-libs
pulseaudio-libs.i686
pipewire-libs
pipewire-libs.i686
freetype
freetype.i686
fontconfig
fontconfig.i686
gnutls
gnutls.i686
libpng
libpng.i686
libSM
libSM.i686
libX11
libX11.i686
libXext
libXext.i686
libXcursor
libXcursor.i686
libXi
libXi.i686
libXinerama
libXinerama.i686
libXrandr
libXrandr.i686
libXrender
libXrender.i686
libXxf86vm
libXxf86vm.i686
libXcomposite
libXcomposite.i686
libgcrypt
libgcrypt.i686
libgpg-error
libgpg-error.i686
libv4l
libv4l.i686
libxml2
libxml2.i686
libxslt
libxslt.i686
ocl-icd
ocl-icd.i686
openal-soft
openal-soft.i686
SDL2
SDL2.i686
sqlite-libs
sqlite-libs.i686
systemd-libs
systemd-libs.i686
zlib-ng-compat
zlib-ng-compat.i686
glibc
glibc.i686
libstdc++
libstdc++.i686
icoutils
cabextract

# Exclude heavy unnecessary packages
-libreoffice*
-thunderbird*
-gimp*
-pidgin*
-transmission*
-cheese*
%end

# ==============================================================================
# Stage 1: Copy offline assets from host staging area into target rootfs
# ==============================================================================
%post --nochroot --erroronfail
set -euxo pipefail

STAGING_DIR="/var/tmp/allglider-staging"
if [ -d "$STAGING_DIR" ]; then
    mkdir -p "$INSTALL_ROOT/opt/allglider"
    cp -a "$STAGING_DIR"/* "$INSTALL_ROOT/opt/allglider/"
fi
%end

# ==============================================================================
# Stage 2: Chroot configuration (NVIDIA pre-build, WinBridge, Proton, AllGlider)
# ==============================================================================
%post --erroronfail
set -euxo pipefail

# 1. Passwordless sudo for liveuser
cat > /etc/sudoers.d/allglider-liveuser << 'EOF'
liveuser ALL=(ALL) NOPASSWD: ALL
Defaults:liveuser !requiretty
EOF
chmod 0440 /etc/sudoers.d/allglider-liveuser

# 2. Configure LightDM autologin into Xfce4 for liveuser
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/50-allglider-autologin.conf << 'EOF'
[Seat:*]
autologin-user=liveuser
autologin-user-timeout=0
user-session=xfce
EOF

# Configure livesys session to xfce
if [ -f /etc/sysconfig/livesys ]; then
    sed -i 's/^livesys_session=.*/livesys_session="xfce"/' /etc/sysconfig/livesys
else
    echo 'livesys_session="xfce"' > /etc/sysconfig/livesys
fi

# 3. Blacklist nouveau & configure NVIDIA DRM modeset (coexists safely with AMD/Intel/QEMU)
cat > /etc/modprobe.d/allglider-nvidia.conf << 'EOF'
blacklist nouveau
options nouveau modeset=0
options nvidia-drm modeset=1 fbdev=1
EOF

# Ensure Xorg uses OutputClass matching so non-NVIDIA GPUs (AMD/Intel/QEMU) fall back to Mesa/modesetting automatically
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

# 4. Pre-compile NVIDIA kernel module (akmods) for the installed Fedora 44 kernel
KVER=$(ls /lib/modules | sort -V | tail -n 1)
echo "Building NVIDIA kernel module for Fedora 44 kernel: $KVER"
akmods --force --kernels "$KVER" || true
depmod -a "$KVER"

# 5. Install UMU Launcher, GE-Proton, WinBridge, and AllGlider from /opt/allglider
if [ -x /opt/allglider/scripts/chroot-setup.sh ]; then
    /opt/allglider/scripts/chroot-setup.sh "$KVER"
fi

# 6. Rebuild initramfs with live boot + GPU support
dracut --force --N --add "dmsquash-live pollcdrom" --kver "$KVER" "/boot/initramfs-${KVER}.img"

# Fix home directory ownership for liveuser
chown -R liveuser:liveuser /home/liveuser || true
%end
