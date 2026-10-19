# AllGlider Live Linux

**AllGlider Live Linux** er en skreddersydd, minimalistisk og plug-and-play Linux-distribusjon basert på **Fedora 44 Xfce (x86_64)** med:
- **Innebygd GPU-støtte rett ut av boksen:** Ferdigkompilerte proprietære **NVIDIA-drivere** (RPM Fusion Nonfree `akmod-nvidia` + 32-bit/64-bit Vulkan/CUDA) samt full **AMD Radeon** og **Intel** Mesa/Vulkan-støtte (32-bit + 64-bit) i samme ISO.
- **WinBridge + UMU + GE-Proton ferdig installert:** Kjører Windows `.exe`-filer direkte fra skrivebordet uten at Steam trenger å være installert.
- **AllGlider ferdig installert:** Klar til bruk fra skrivebordet (`~/AllGlider/Launcher`) sammen med `og-inputbridge.exe`.
- **128 GB Persistent USB-arkitektur (`ALLGLIDER_DATA`):** Egen persistent datapartisjon som automatisk monteres ved oppstart, slik at Battle.net, World of Warcraft, WinBridge-prefixer, AllGlider-profiler og Wi-Fi-innstillinger lagres trygt uten risiko for korrupt Live-overlay.
- **First-Boot Battle.net Veiviser (`allglider-welcome`):** Sjekker skjermkort, lagringsplass og nettverk, og laster ned og starter offisiell Battle.net-installer via WinBridge.
- **Grafisk Disk-installer med USB-migrering (`allglider-installer`):** Lar deg installere hele systemet på en intern NVMe/SSD-disk og overfører alle innstillinger, profiler, WinBridge-prefixer og spill fra USB-en.

---

## Mappestruktur

```text
allglider-linux/
├── README.md
├── VERSION
├── config/
│   ├── fedora-live.ks           # Fedora 44 Kickstart med Xfce, NVIDIA akmods & Mesa
│   ├── packages-base.txt        # Oversikt over grunnpakker
│   ├── packages-gaming.txt      # Oversikt over GPU-, 32-bit-, Proton- og Qt6-pakker
│   └── versions.lock            # Låste versjoner for Fedora 44, WinBridge, UMU, GE-Proton og AllGlider
├── scripts/
│   ├── stage-assets.sh          # Henter og sjekksummerer WinBridge, AllGlider og GE-Proton til staging
│   ├── chroot-setup.sh          # Kjøres inne i Fedora 44-imaget under ISO-bygging
│   ├── build-iso.sh             # Bygger Live-ISO i ren Fedora 44 Podman-container (eller på host)
│   ├── prepare-usb.sh           # Oppretter 3-partisjons oppsett på 128 GB USB (EFI + LIVE + ALLGLIDER_DATA)
│   ├── allglider-persistence-mount.sh # Systemd-script som auto-monterer ALLGLIDER_DATA ved oppstart
│   ├── allglider-gpu-check.sh   # Detekterer NVIDIA/AMD/Intel ved boot og laster riktig modul
│   ├── verify-image.sh          # Validerer skript, Kickstart og ferdig ISO
│   └── collect-diagnostics.sh   # Samler inn GPU-, Vulkan-, WinBridge- og systemlogger
├── installer/
│   ├── first-boot-restore/
│   │   └── allglider-welcome.py # Førstegangsveiviser og Battle.net-nedlaster
│   ├── ui/
│   │   └── allglider-installer.py # Grafisk installer til intern disk (beskytter Live-USB)
│   └── migration/
│       └── migrate-data.sh      # Sikkerhetskopierer og migrerer brukerdata fra USB til intern disk
└── tests/
    ├── run-qemu.sh              # Starter ISO + persistent disk + virtuell NVMe i QEMU/KVM (UEFI)
    └── migration/
        └── test-migration.sh    # Automatisk enhetstest for migreringslogikken
```

---

## Kom i gang

### 1. Verifiser oppsett og kjør tester
```bash
./scripts/verify-image.sh
./tests/migration/test-migration.sh
```

### 2. Bygg Fedora 44 Live ISO (med NVIDIA, WinBridge, AllGlider og GE-Proton)
Bygger i en ren, isolert Fedora 44-container via `podman`:
```bash
./scripts/build-iso.sh
```
*(Tips: For å bygge en rask base-ISO uten å laste ned ~450 MB GE-Proton under første test, bruk `./scripts/build-iso.sh --skip-proton`.)*

### 3. Test ISO, Persistens og Installer i QEMU/KVM
```bash
./tests/run-qemu.sh
```

### 4. Skriv til 128 GB USB-minnepinne med persistent lagring
```bash
sudo ./scripts/prepare-usb.sh build/AllGlider-Live-F44-0.1.0-x86_64.iso /dev/sdX
```
# allglider-linux
