# AllGlider Live Linux

**AllGlider Live Linux** is a tailored, lightweight, plug-and-play live Linux distribution based on **Fedora 44 Xfce (x86_64)** designed for gaming and MMO automation:

- **Out-of-the-Box Multi-GPU Support:** Pre-compiled proprietary **NVIDIA drivers** (RPM Fusion Nonfree `akmod-nvidia` with 32-bit & 64-bit Vulkan/CUDA) alongside full **AMD Radeon** and **Intel** Mesa/Vulkan support (32-bit + 64-bit) in a single unified ISO image.
- **Pre-installed WinBridge + UMU + GE-Proton:** Runs Windows `.exe` game binaries directly from the desktop without needing Steam or manual Wine configuration.
- **Pre-installed AllGlider:** Ready to launch immediately from the desktop (`~/AllGlider/Launcher`) together with `og-inputbridge.exe`.
- **Automatic Host Disk Scanner (`allglider-disk-scan`):** Detects existing Battle.net and World of Warcraft installations on internal Windows (NTFS) or Linux partitions at boot time, automatically placing ready-to-run desktop shortcuts without requiring re-downloading or re-installing.
- **128 GB Persistent USB Architecture (`ALLGLIDER_DATA`):** Dedicated persistent data partition automatically mounted at boot so that Battle.net, World of Warcraft, WinBridge prefixes, AllGlider profiles, and Wi-Fi credentials remain safe without risk of live overlay corruption.
- **First-Boot Battle.net Setup Wizard (`allglider-welcome`):** Checks GPU acceleration, disk space, and network connectivity, automatically adapting depending on whether local game files were detected.
- **Graphical System Installer with USB Migration (`allglider-installer`):** Easily install the operating system onto an internal NVMe/SSD drive, with 1-click migration of all settings, profiles, prefixes, and game installations from your USB drive.
- **Custom Polished Branding:** Custom OpenGlider boot splash powered by Plymouth, clean desktop icon presentation (no lock/link badges), official AllGlider Whisker start menu icon, and seamless gradient desktop wallpapers.

---

## Directory Structure

```text
allglider-linux/
├── README.md
├── VERSION
├── config/
│   ├── fedora-live.ks                  # Fedora 44 Kickstart recipe (Xfce, NVIDIA akmods & Mesa)
│   ├── packages-base.txt               # Base system package list
│   ├── packages-gaming.txt             # GPU drivers, 32-bit libs, Proton & Qt6 package list
│   └── versions.lock                   # Locked versions for Fedora 44, WinBridge, UMU, GE-Proton & AllGlider
├── branding/
│   ├── icons/                          # AllGlider application and panel icons
│   ├── plymouth/                       # OpenGlider boot splash theme assets
│   ├── wallpapers/                     # High-resolution desktop wallpapers
│   └── xfce/                           # Xfce4 panel and Whisker Menu configurations
├── scripts/
│   ├── stage-assets.sh                 # Downloads, verifies, and stages WinBridge, AllGlider & GE-Proton
│   ├── build-iso.sh                    # Builds the full Live ISO inside a clean Fedora 44 container
│   ├── build-iso-container-inner.sh    # Inner container script for livemedia-creator
│   ├── quick-update-iso.sh             # Fast ISO repacker (~45s) for iterative branding & script updates
│   ├── chroot-setup.sh                 # System configuration hook executed inside the chroot
│   ├── allglider-disk-scan.sh          # Systemd service detecting host Battle.net & WoW installations
│   ├── allglider-persistence-mount.sh  # Auto-mounts the persistent ALLGLIDER_DATA partition at boot
│   ├── allglider-gpu-check.sh          # GPU detection and driver verification script
│   ├── allglider-display-init.sh       # Display resolution initializer (1080p fallback)
│   ├── remove-desktop-emblems.sh       # Removes desktop icon padlock and link emblems
│   ├── prepare-usb.sh                  # Partitions a 128 GB USB with EFI, LIVE, and persistent DATA
│   ├── flash-usb.sh                    # Direct ISO flasher to USB target
│   ├── verify-image.sh                 # Validates project scripts, Kickstart, and output ISO
│   └── collect-diagnostics.sh          # Collects GPU, Vulkan, WinBridge, and system log diagnostics
├── installer/
│   ├── first-boot-restore/
│   │   └── allglider-welcome.py        # First-boot setup wizard and Battle.net launcher/downloader
│   ├── ui/
│   │   └── allglider-installer.py      # Graphical disk installer to internal storage
│   └── migration/
│       └── migrate-data.sh             # Backs up and migrates user data from USB to internal disk
└── tests/
    ├── run-qemu.sh                     # Runs ISO + persistent disk + virtual NVMe in QEMU/KVM (UEFI)
    └── migration/
        └── test-migration.sh           # Automated unit test suite for user data migration logic
```

---

## Getting Started

### 1. Verify Setup and Run Tests
Validate the Kickstart configuration, scripts, and data migration logic:
```bash
./scripts/verify-image.sh
./tests/migration/test-migration.sh
```

### 2. Build the Live ISO
Build the complete Fedora 44 Live ISO with NVIDIA drivers, WinBridge, AllGlider, and GE-Proton in an isolated container via Podman:
```bash
./scripts/build-iso.sh
```
*(Tip: To build a fast base ISO without downloading GE-Proton during initial iteration, use `./scripts/build-iso.sh --skip-proton`.)*

For quick updates (~45 seconds) to scripts, branding, wallpapers, or desktop configs without full package reinstallation:
```bash
./scripts/quick-update-iso.sh
```

### 3. Test in QEMU/KVM
Test boot, persistence mounting, and installer workflow in a virtual machine:
```bash
./tests/run-qemu.sh
```

### 4. Create a Bootable Persistent USB Drive
Format a 128 GB USB flash drive with persistent storage:
```bash
sudo ./scripts/prepare-usb.sh build/AllGlider-Live-F44-0.1.0-x86_64.iso /dev/sdX
```
Or flash directly to a test USB drive:
```bash
sudo ./scripts/flash-usb.sh /dev/sdX
```
