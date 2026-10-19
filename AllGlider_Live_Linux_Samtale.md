# AllGlider Live Linux – samtale og prosjektplan

**Dato:** 19. oktober 2026  
**Formål:** Samle samtalen om planleggingen av AllGlider Live Linux i én fil.

> Dokumentet er en samlet, lesbar gjengivelse av samtalen og prosjektbeslutningene. Markdown-formatering er brukt for lesbarhet; skjulte systemmeldinger og tekniske metadata er ikke inkludert.

---

## 1. Første spørsmål: Lage en minimalistisk Live Linux-distro

**Bruker:**  
Hvis jeg vil lage en minimalistisk live Linux distro med standard nettverksdrivere og full NVIDIA / RADEON skjermkort støtte med Xfce4 eller noe lett, hvordan går jeg frem da og hvordan debugger jeg det, setter det opp, pakker det ned og lager en ISO ut av det?

**Assistent – oppsummert svar:**  
Start med Fedora Xfce som base, bruk Kickstart til å definere systemet og `livemedia-creator` til å bygge en ISO. Del prosjektet i et grunnsystem, spill-/kompatibilitetsmiljø og AllGlider-integrasjon. Bygg og test i små trinn: først oppstart og desktop, deretter nettverk og grafikk, så WinBridge/Proton, persistens og til slutt installasjon. AMD kan bruke Mesa/amdgpu; NVIDIA krever en bevisst strategi for driver, lisensvilkår og Secure Boot. Test først i QEMU/KVM, deretter på fysisk maskinvare.

---

## 2. WinBridge og Proton

**Bruker:**  
Jeg vil ha https://github.com/ablohme86/winbridge med Proton ferdig installert for enkelt kjøring

**Assistent – oppsummert svar:**  
WinBridge og Proton skal være sentrale deler av distroens ferdigkonfigurerte miljø. WinBridge kan bruke UMU til å kjøre Windows-programmer gjennom Proton uten at Steam må være installert. Inkluder WinBridge/WinBridge Manager, UMU Launcher, én valgt og testet Proton-versjon, nødvendig Linux Runtime og relevante grafikkbiblioteker, inkludert 32-bit-biblioteker.

Versjonene bør låses og testes samlet. Proton og nødvendige runtime-filer må ligge lokalt hvis systemet skal fungere offline.

Referanser:
- https://github.com/ablohme86/winbridge
- https://github.com/ablohme86/winbridge/blob/master/INSTALL.md
- https://github.com/Open-Wine-Components/umu-launcher
- https://github.com/GloriousEggroll/proton-ge-custom

---

## 3. Persistent USB og grafisk installer

**Bruker:**  
Ja, vi må ha persistent lagring på USB disken, men også en light installer for å kunne velge å installere hele distroen på en disk om man vil og da også beholde instillingene man hadde på usb disken.

**Assistent – oppsummert svar:**  
Distroen skal ha persistent Live USB-lagring og en grafisk installer. Live-versjonen og den installerte versjonen bør bruke samme grunnsystem og samme AllGlider-oppsett.

Foreslått flyt:
1. Start fra USB i Live Mode.
2. Bruk Xfce, WinBridge, Proton og AllGlider direkte.
3. Lagre innstillinger og brukerdata persistent.
4. Start en grafisk installer og velg måldisk.
5. Installer systemet og overfør konfigurasjon, profiler, relevante Wine-prefixer og brukerdata.

Viktig designvalg: skill systemets skrivbare Live-lag fra brukerdataene. Migreringen skal ikke kopiere hele Live-overlayet ukritisk. Lag en eksplisitt liste over data som skal overføres, og kontroller eierskap, rettigheter og tilgjengelig plass.

---

## 4. Valgte rammer og konkret teknisk arkitektur

**Bruker:**  
For AllGlider Live Linux-distroen: USB-størrelse: 128 GB. Proton: alt forhåndsinstallert. Installer: grafisk installer med overføring av konfigurasjon fra USB. Lag en konkret teknisk arkitektur og byggeplan.

**Assistent – teknisk plan:**

### Mål

AllGlider Live Linux skal være en plug-and-play Linux-distro med persistent USB-lagring, WinBridge og Proton ferdig installert, samt grafisk installasjon på intern disk med overføring av brukerens oppsett.

### Teknologivalg

| Område | Foreslått løsning |
|---|---|
| Linux-base | Fedora Xfce Spin, x86-64 |
| Image-bygging | Kickstart + `livemedia-creator` |
| Windows-programmer | WinBridge |
| Proton uten Steam | UMU + låst Proton-versjon + kompatibel runtime |
| Grafikk | Mesa for AMD/Intel; separat NVIDIA-strategi |
| Persistens | Live-skrivbart lag pluss applikasjonsdatakatalog |
| Installer | Eksisterende Fedora-installasjonsmotor med AllGlider-migrering |
| Testing | QEMU/KVM, automatiserte tester og fysiske maskiner |

### USB-layout

En markedsført 128 GB USB-enhet gir omtrent 119 GiB før filsystem- og partisjonsoverhead. Endelig fordeling fastsettes når image, Proton og runtime er målt.

- Liten EFI-/oppstartspartisjon.
- Live-system med Fedora, Xfce, WinBridge, UMU, Proton og biblioteker. Foreløpig budsjettering: omtrent 15–30 GiB, avhengig av endelig image.
- Resten til persistent data: innstillinger, profiler, prefixer, Battle.net og eventuelt spilldata.

Skill mellom systempersistens og applikasjonspersistens. Applikasjonsdata må kunne sikkerhetskopieres og migreres uavhengig av Live-overlayet. Vurder en separat datapartisjon for store filer.

### WinBridge, UMU og Proton

- Bygg og installer WinBridge på en repeterbar måte.
- Inkluder UMU, én kjent Proton-versjon og nødvendig runtime.
- Lås Fedora-, WinBridge-, UMU-, Proton- og runtime-versjoner i `config/versions.lock`.
- Test et lokalt testprogram offline.
- Ikke bruk «latest» ukritisk i produksjonsbygg.
- Kontroller lisenser og distribusjonsvilkår.

### Installer og migrering

1. Start installasjonsveiviseren fra Xfce.
2. Velg språk, måldisk og alternativer.
3. Vis diskmodell og størrelse, og krev eksplisitt bekreftelse før destruktive operasjoner.
4. Lag en versjonert sikkerhetskopi av migrerbare data på USB-en.
5. Installer systemet og oppstartsfilene på måldisken.
6. Gjenopprett og valider brukerdata.
7. Kontroller eierskap, rettigheter, ledig plass og Proton/runtime.
8. Ved første oppstart fra intern disk, vis hva som ble overført eller hoppet over.

Data som bør overføres:
- WinBridge-innstillinger.
- WinBridge sitt delte Windows-miljø.
- UMU/Proton-data når versjonen og runtime samsvarer.
- Relevante Wine-prefixer.
- AllGlider-profiler og innstillinger.
- Logger etter brukerens valg.

Ikke kopier midlertidig cache, USB-spesifikke boot-data eller maskinspesifikk driverkonfigurasjon. Opprett slike deler på nytt på målsystemet.

### Foreslått repository

```text
allglider-live/
├── README.md
├── VERSION
├── config/
│   ├── fedora-live.ks
│   ├── packages-base.txt
│   ├── packages-gaming.txt
│   └── versions.lock
├── branding/
│   ├── wallpapers/
│   ├── icons/
│   └── xfce/
├── packages/
│   ├── allglider/
│   └── winbridge/
├── scripts/
│   ├── build-iso.sh
│   ├── prepare-usb.sh
│   ├── verify-image.sh
│   └── collect-diagnostics.sh
├── installer/
│   ├── ui/
│   ├── migration/
│   └── first-boot-restore/
└── tests/
    ├── boot/
    ├── persistence/
    ├── proton/
    └── migration/
```

Hold genererte ISO-er, spillfiler, Proton-arkiver og brukerdata utenfor Git.

### Byggeprosess

1. Opprett et rent, kontrollert Fedora-byggemiljø.
2. Lag og valider Kickstart-filen.
3. Bygg en liten base-ISO.
4. Test ISO-en i QEMU/KVM: oppstart, desktop, nettverk og avslutning/omstart.
5. Legg til WinBridge, UMU og Proton.
6. Test Proton offline.
7. Legg til persistens og test på fysisk USB.
8. Implementer installer og migrering.
9. Kjør release-sjekklisten.

Illustrativ bygging – må verifiseres mot valgt Fedora-versjon:

```bash
sudo dnf install lorax-lmc-novirt livecd-tools pykickstart mock

livemedia-creator \\
  --ks config/fedora-live.ks \\
  --no-virt \\
  --make-iso \\
  --resultdir ./build
```

### Testplan

- Live USB starter med UEFI.
- Nettverk fungerer.
- AMD/Intel-grafikk og NVIDIA-strategi testes.
- Innstillinger overlever omstart.
- Proton kjører et lokalt testprogram uten nett.
- Førstegangsveiviser tåler avbrudd.
- Installer fungerer på virtuell disk.
- Migrering overfører relevante data.
- Installert system fungerer etter at USB-en kobles fra.
- Installer beskytter mot feil diskvalg.

### Milepæler

- M1: Fedora Xfce base-image.
- M2: WinBridge og Proton offline.
- M3: Persistent USB.
- M4: Førstegangsveiviser.
- M5: Grafisk installer.
- M6: Migrering.
- M7: Release og dokumentasjon.

Foreslått første arbeidsøkt: 20. oktober 2026. Opprett repository, velg og lås Fedora-release, lag minimal Kickstart, bygg første base-ISO og test i QEMU/KVM.

---

## 5. Battle.net lastes ned ved første oppstart

**Bruker:**  
Ja, Battle.net installasjonsfiler blir hentet ned fra nettet ved første oppstart

**Assistent – oppsummert svar:**  
Battle.net-installasjonsprogrammet skal ikke ligge i ISO-en. I stedet skal distroens First Boot Setup-veiviser:

1. Kontrollere nettverk, lagringsplass og at UMU/Proton fungerer.
2. Hente Battle.net-installasjonsprogrammet fra en kontrollert, offisiell Blizzard-kilde over HTTPS.
3. Kontrollere at nedlastingen er komplett og integriteten der en pålitelig kontroll finnes.
4. Starte installasjonen gjennom WinBridge og den forhåndsinstallerte Proton-versjonen.
5. Lagre status persistent, slik at prosessen kan gjenopptas etter avbrudd.
6. La brukeren logge inn og installere WoW selv via Battle.net.
7. La brukeren velge lagringssted og varsle ved lite plass.

Battle.net og WoW bør være separate trinn. Ikke hardkod en uverifisert URL, og ikke inkluder spillfiler i ISO-en uten avklart redistribusjonsrett.

---

## 6. Planen skal dokumenteres, og arbeidet starter i morgen

**Bruker:**  
Ja

**Assistent:**  
Supert! Vi kan følge opp AllGlider Live Linux fra den første Fedora Xfce-ISO-en til persistent USB, WinBridge/Proton og den grafiske installasjonen med migrering. Det ble foreslått å minne brukeren på prosjektet i morgen, om én uke eller ukentlig.

**Bruker:**  
Skriv hele planen i en dokument for meg, så starter vi i morgen.

**Assistent:**  
Det første forsøket på å generere dokumentet feilet på grunn av en verktøybegrensning, så ingen fil ble opprettet i det forsøket.

**Bruker:**  
Skriv hele samtalen her i en fil

---

## 7. Endelig beslutningslogg

- **Produkt:** AllGlider Live Linux.
- **Base:** Fedora Xfce, x86-64; velg og lås en konkret Fedora-release før bygging.
- **USB:** 128 GB med persistent lagring.
- **WinBridge:** Forhåndsinstallert.
- **Proton:** UMU og en valgt Proton-versjon forhåndsinstallert, med nødvendig runtime og offline-test.
- **Battle.net:** Installasjonsprogram lastes ned ved første oppstart fra offisiell kilde.
- **World of Warcraft:** Brukeren installerer spillet selv via Battle.net.
- **Installer:** Grafisk installer med sikker diskvalgprosess og migrering fra USB.
- **Persistens:** Skill systemets Live-overlay fra applikasjonsdata som kan sikkerhetskopieres og migreres.
- **Første arbeidsøkt:** 20. oktober 2026: repository, Fedora-versjon, Kickstart og første base-ISO.

## 8. Referanser

- WinBridge: https://github.com/ablohme86/winbridge
- WinBridge installasjon: https://github.com/ablohme86/winbridge/blob/master/INSTALL.md
- Fedora Live Image / livemedia-creator: https://fedoraproject.org/wiki/Livemedia-creator-_How_to_create_and_use_a_Live_CD
- Fedora Spins: https://fedoraproject.org/spins/
- UMU Launcher: https://github.com/Open-Wine-Components/umu-launcher
- GE-Proton: https://github.com/GloriousEggroll/proton-ge-custom

---

*Arbeidsdokument. Kommandoer, pakkestøtte, installasjonsmotor, lisensvilkår og driverstrategi må verifiseres mot valgt Fedora-release før publisering.*
