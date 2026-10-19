#!/usr/bin/env python3
"""
AllGlider Live Linux - First-Boot Setup & Battle.net Installer Wizard
Verifies network, storage, GPU/Vulkan, and Proton readiness, displays any
post-install migration report, and downloads + launches Battle.net via WinBridge.
"""
import json
import shutil
import subprocess
import threading
import urllib.request
from pathlib import Path

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk

STATE_PATH = Path.home() / ".config" / "allglider" / "firstboot-state.json"
MIGRATION_REPORT = Path("/var/log/allglider-migration-report.json")
DOWNLOAD_DIR = Path.home() / "Downloads" / "BattleNet"
BATTLENET_EXE = DOWNLOAD_DIR / "Battle.net-Setup.exe"
BATTLENET_URL = "https://downloader.battle.net/download/getInstallerForGame?os=win&gameProgram=BATTLENET_APP"


def load_state() -> dict:
    if STATE_PATH.exists():
        try:
            return json.loads(STATE_PATH.read_text(encoding="utf-8"))
        except Exception:
            pass
    return {"completed": False, "battlenet_downloaded": False, "battlenet_launched": False}


def save_state(state: dict) -> None:
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    STATE_PATH.write_text(json.dumps(state, indent=2), encoding="utf-8")


class WelcomeWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title="AllGlider Live Linux – Setup & Battle.net")
        self.set_default_size(660, 480)
        self.set_border_width(16)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.state = load_state()

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        self.add(vbox)

        header = Gtk.Label()
        header.set_markup("<span size='x-large' weight='bold'>Welcome to AllGlider Live Linux</span>")
        header.set_xalign(0)
        vbox.pack_start(header, False, False, 0)

        subtitle = Gtk.Label(
            label="Fedora 44 Xfce • NVIDIA / AMD / Intel Ready • WinBridge + GE-Proton Pre-installed"
        )
        subtitle.set_xalign(0)
        vbox.pack_start(subtitle, False, False, 0)

        # System Readiness Frame
        status_frame = Gtk.Frame(label="System Status & Readiness")
        status_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        status_box.set_border_width(10)
        status_frame.add(status_box)
        vbox.pack_start(status_frame, False, False, 0)

        self.gpu_label = Gtk.Label(xalign=0)
        self.storage_label = Gtk.Label(xalign=0)
        self.proton_label = Gtk.Label(xalign=0)
        self.net_label = Gtk.Label(xalign=0)
        for lbl in (self.gpu_label, self.storage_label, self.proton_label, self.net_label):
            status_box.pack_start(lbl, False, False, 0)

        # Optional Migration Report Frame (shown on first boot after installing to internal disk)
        if MIGRATION_REPORT.exists():
            mig_frame = Gtk.Frame(label="USB Migration Summary")
            mig_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            mig_box.set_border_width(10)
            mig_frame.add(mig_box)
            try:
                rep = json.loads(MIGRATION_REPORT.read_text(encoding="utf-8"))
                transferred = ", ".join(rep.get("transferred", [])) or "None"
                skipped = ", ".join(rep.get("skipped", [])) or "None"
                mig_lbl = Gtk.Label(
                    label=f"Transferred from USB: {transferred}\nSkipped: {skipped}",
                    xalign=0,
                )
            except Exception:
                mig_lbl = Gtk.Label(label="System was successfully migrated from Live USB.", xalign=0)
            mig_box.pack_start(mig_lbl, False, False, 0)
            vbox.pack_start(mig_frame, False, False, 0)

        # Battle.net Setup Frame
        bnet_frame = Gtk.Frame(label="Battle.net & World of Warcraft Setup")
        bnet_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        bnet_box.set_border_width(10)
        bnet_frame.add(bnet_box)
        vbox.pack_start(bnet_frame, True, True, 0)

        self.discovered_bnet_exe = None
        self.discovered_wow_exe = None

        self.bnet_desc = Gtk.Label(
            label=(
                "1. Click 'Download & Launch Battle.net' to fetch the official Blizzard installer over HTTPS.\n"
                "2. WinBridge will automatically open the installer inside the shared GE-Proton environment.\n"
                "3. Sign in to Battle.net and install World of Warcraft to your preferred folder."
            ),
            xalign=0,
        )
        self.bnet_desc.set_line_wrap(True)
        bnet_box.pack_start(self.bnet_desc, False, False, 0)

        self.progress = Gtk.ProgressBar()
        self.progress.set_show_text(True)
        self.progress.set_text("Ready")
        bnet_box.pack_start(self.progress, False, False, 0)

        # Action Buttons
        btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        vbox.pack_end(btn_box, False, False, 0)

        self.refresh_btn = Gtk.Button(label="Refresh Status")
        self.refresh_btn.connect("clicked", lambda *_: self.refresh_checks())
        btn_box.pack_start(self.refresh_btn, False, False, 0)

        self.unlock_btn = Gtk.Button(label="Unlock Drive...")
        self.unlock_btn.connect("clicked", self.on_unlock_drive_clicked)
        self.unlock_btn.set_no_show_all(True)
        btn_box.pack_start(self.unlock_btn, False, False, 0)

        self.bnet_btn = Gtk.Button(label="Download & Launch Battle.net")
        self.bnet_btn.connect("clicked", self.on_install_battlenet)
        btn_box.pack_start(self.bnet_btn, False, False, 0)

        self.wow_btn = Gtk.Button(label="Start World of Warcraft")
        self.wow_btn.connect("clicked", self.on_launch_wow)
        self.wow_btn.set_no_show_all(True)
        btn_box.pack_start(self.wow_btn, False, False, 0)

        self.allglider_btn = Gtk.Button(label="Launch AllGlider")
        self.allglider_btn.connect("clicked", lambda *_: subprocess.Popen(["/usr/local/bin/allglider"]))
        btn_box.pack_start(self.allglider_btn, False, False, 0)

        self.close_btn = Gtk.Button(label="Finish (Don't show on startup)")
        self.close_btn.connect("clicked", self.on_complete)
        btn_box.pack_end(self.close_btn, False, False, 0)

        self.detected_encrypted_disks = []

        self.refresh_checks()

    def refresh_checks(self):
        # 1. GPU check
        gpu_text = "Unknown"
        gpu_file = Path("/run/allglider-gpu.json")
        if gpu_file.exists():
            try:
                info = json.loads(gpu_file.read_text(encoding="utf-8"))
                gpu_text = f"{info.get('vendor')} (driver: {info.get('driver')})"
            except Exception:
                pass
        self.gpu_label.set_text(f"• Graphics Card: {gpu_text}")

        # 2. Storage check
        usage = shutil.disk_usage(str(Path.home()))
        free_gib = usage.free / (1024 ** 3)
        persist_active = Path("/run/allglider-persistence.json").exists()
        mode_str = "Persistent USB (ALLGLIDER_DATA)" if persist_active else "Local Disk / Live RAM"
        warn = " [WARNING: Low disk space for WoW!]" if free_gib < 20 else ""
        self.storage_label.set_text(f"• Storage ({mode_str}): {free_gib:.1f} GiB free{warn}")

        # 3. Proton & WinBridge check
        wb_ok = shutil.which("winbridge") is not None
        umu_ok = shutil.which("umu-run") is not None
        proton_dirs = list(Path("/opt/allglider/proton").glob("*")) if Path("/opt/allglider/proton").exists() else []
        proton_name = proton_dirs[0].name if proton_dirs else "Default (UMU-Proton / GE-Proton)"
        self.proton_label.set_text(
            f"• WinBridge: {'OK' if wb_ok else 'Missing'} | UMU: {'OK' if umu_ok else 'Missing'} | Proton: {proton_name}"
        )

        # 4. Network check
        net_ok = False
        try:
            req = urllib.request.Request("https://fedoraproject.org", method="HEAD")
            with urllib.request.urlopen(req, timeout=3):
                net_ok = True
        except Exception:
            net_ok = False
        self.net_label.set_text(f"• Internet Connection: {'Connected' if net_ok else 'Offline'}")

        # 5. Check for existing host Battle.net / WoW & Encrypted drives
        host_apps_file = Path("/run/allglider-host-apps.json")
        if not host_apps_file.exists():
            host_apps_file = Path("/tmp/allglider-host-apps.json")
        if host_apps_file.exists():
            try:
                data = json.loads(host_apps_file.read_text(encoding="utf-8"))

                # Check for encrypted drives
                if data.get("encrypted_found") and data.get("encrypted_disks"):
                    self.detected_encrypted_disks = data.get("encrypted_disks")
                    disks_str = ", ".join(self.detected_encrypted_disks)
                    self.unlock_btn.show()
                    self.bnet_desc.set_text(
                        f"Encrypted Windows drive detected: {disks_str}\n"
                        "Click 'Unlock Drive...' below to enter your BitLocker password or recovery key,\n"
                        "or click 'Download & Launch Battle.net' to install Battle.net manually."
                    )
                    GLib.idle_add(self.prompt_unlock_encrypted, self.detected_encrypted_disks)
                else:
                    self.detected_encrypted_disks = []
                    self.unlock_btn.hide()

                if data.get("battlenet_found") and data.get("battlenet_exe"):
                    self.discovered_bnet_exe = data["battlenet_exe"]
                    part_info = f" on {data.get('battlenet_part')}" if data.get('battlenet_part') else ""
                    self.bnet_btn.set_label("Start Battle.net")
                    self.bnet_desc.set_text(
                        f"Battle.net was detected{part_info}!\n"
                        "Click 'Start Battle.net' to launch immediately via WinBridge without downloading."
                    )
                    self.progress.set_text(f"Battle.net ready{part_info}")
                if data.get("wow_found") and data.get("wow_exe"):
                    self.discovered_wow_exe = data["wow_exe"]
                    self.wow_btn.show()
            except Exception:
                pass

    def on_unlock_drive_clicked(self, _btn):
        if self.detected_encrypted_disks:
            self.show_unlock_password_dialog(self.detected_encrypted_disks[0])

    def prompt_unlock_encrypted(self, disks):
        flag_file = Path("/run/allglider-encrypted-prompt-shown")
        if flag_file.exists():
            return
        flag_file.touch(exist_ok=True)

        for disk in disks:
            dialog = Gtk.MessageDialog(
                transient_for=self,
                flags=Gtk.DialogFlags.MODAL | Gtk.DialogFlags.DESTROY_WITH_PARENT,
                message_type=Gtk.MessageType.QUESTION,
                buttons=Gtk.ButtonsType.YES_NO,
                text="Do you want to unlock the device?",
            )
            dialog.format_secondary_text(
                f"A BitLocker encrypted drive ({disk}) was detected on this computer.\n\n"
                "Unlocking it allows AllGlider to search for your existing Battle.net and "
                "World of Warcraft installations so you can start playing without re-downloading."
            )
            resp = dialog.run()
            dialog.destroy()

            if resp == Gtk.ResponseType.YES:
                self.show_unlock_password_dialog(disk)
            else:
                self.bnet_desc.set_text(
                    f"Could not search for Battle.net in your existing drive {disk} "
                    "because it's encrypted, manual download of Battle.Net and Warcraft is required"
                )

    def show_unlock_password_dialog(self, disk):
        pwd_dialog = Gtk.Dialog(
            title="Unlock BitLocker Drive",
            transient_for=self,
            flags=Gtk.DialogFlags.MODAL | Gtk.DialogFlags.DESTROY_WITH_PARENT,
        )
        pwd_dialog.add_buttons(
            "Cancel", Gtk.ResponseType.CANCEL,
            "Unlock", Gtk.ResponseType.OK,
        )
        pwd_dialog.set_default_response(Gtk.ResponseType.OK)
        pwd_dialog.set_default_size(440, 200)

        box = pwd_dialog.get_content_area()
        box.set_spacing(10)
        box.set_border_width(14)

        info_lbl = Gtk.Label(
            label=f"Enter the BitLocker password or 48-digit recovery key for:\n<b>{disk}</b>",
            use_markup=True,
            xalign=0,
        )
        box.pack_start(info_lbl, False, False, 0)

        entry = Gtk.Entry()
        entry.set_visibility(False)
        entry.set_activates_default(True)
        entry.set_placeholder_text("Password or Recovery Key")
        box.pack_start(entry, False, False, 0)

        show_chk = Gtk.CheckButton(label="Show password")
        show_chk.connect("toggled", lambda w: entry.set_visibility(w.get_active()))
        box.pack_start(show_chk, False, False, 0)

        status_lbl = Gtk.Label(xalign=0)
        status_lbl.set_line_wrap(True)
        box.pack_start(status_lbl, False, False, 0)

        pwd_dialog.show_all()

        while True:
            response = pwd_dialog.run()
            if response != Gtk.ResponseType.OK:
                pwd_dialog.destroy()
                self.bnet_desc.set_text(
                    f"Could not search for Battle.net in your existing drive {disk} "
                    "because it's encrypted, manual download of Battle.Net and Warcraft is required"
                )
                return

            password = entry.get_text().strip()
            if not password:
                status_lbl.set_markup("<span color='#d9534f'>Please enter a password or recovery key.</span>")
                continue

            status_lbl.set_markup("<span>Unlocking and mounting drive, please wait...</span>")
            while Gtk.events_pending():
                Gtk.main_iteration()

            unlock_bin = "/usr/local/sbin/allglider-unlock-bitlk"
            if not Path(unlock_bin).exists():
                unlock_bin = str(Path(__file__).resolve().parent.parent.parent / "scripts" / "allglider-unlock-bitlk.sh")

            cmd = ["sudo", unlock_bin, disk]
            try:
                proc = subprocess.run(
                    cmd,
                    input=password.encode("utf-8"),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=30,
                )
                if proc.returncode == 0:
                    pwd_dialog.destroy()
                    self.refresh_checks()

                    success_dialog = Gtk.MessageDialog(
                        transient_for=self,
                        flags=Gtk.DialogFlags.MODAL | Gtk.DialogFlags.DESTROY_WITH_PARENT,
                        message_type=Gtk.MessageType.INFO,
                        buttons=Gtk.ButtonsType.OK,
                        text="Drive Unlocked Successfully",
                    )
                    success_dialog.format_secondary_text(
                        f"Drive {disk} has been unlocked and mounted.\n\n"
                        "Desktop shortcuts for Battle.net and World of Warcraft have been created."
                    )
                    success_dialog.run()
                    success_dialog.destroy()
                    return
                else:
                    err_msg = proc.stderr.decode("utf-8", errors="replace").strip()
                    first_err_line = err_msg.splitlines()[-1] if err_msg else "Incorrect password or recovery key."
                    status_lbl.set_markup(
                        f"<span color='#d9534f'>Failed to unlock: {first_err_line}</span>"
                    )
            except subprocess.TimeoutExpired:
                status_lbl.set_markup("<span color='#d9534f'>Unlock timed out. Please try again.</span>")
            except Exception as ex:
                status_lbl.set_markup(f"<span color='#d9534f'>Error: {ex}</span>")

    def on_install_battlenet(self, _btn):
        if self.discovered_bnet_exe:
            self.progress.set_text("Launching host Battle.net via WinBridge...")
            subprocess.Popen(["winbridge", str(self.discovered_bnet_exe)])
            self.state["battlenet_launched"] = True
            save_state(self.state)
            return

        self.bnet_btn.set_sensitive(False)
        threading.Thread(target=self._download_and_run_bnet, daemon=True).start()

    def on_launch_wow(self, _btn):
        if self.discovered_wow_exe:
            self.progress.set_text("Launching World of Warcraft via WinBridge...")
            subprocess.Popen(["winbridge", str(self.discovered_wow_exe)])

    def _download_and_run_bnet(self):
        try:
            DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
            part_file = DOWNLOAD_DIR / "Battle.net-Setup.exe.part"

            if not (BATTLENET_EXE.exists() and BATTLENET_EXE.stat().st_size > 2_000_000):
                GLib.idle_add(self.progress.set_text, "Downloading Battle.net-Setup.exe from Blizzard...")
                req = urllib.request.Request(
                    BATTLENET_URL,
                    headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"},
                )
                with urllib.request.urlopen(req, timeout=30) as resp, open(part_file, "wb") as out:
                    total = int(resp.headers.get("Content-Length", "0") or "0")
                    downloaded = 0
                    while True:
                        chunk = resp.read(65536)
                        if not chunk:
                            break
                        out.write(chunk)
                        downloaded += len(chunk)
                        if total > 0:
                            GLib.idle_add(self.progress.set_fraction, min(1.0, downloaded / total))

                # Verify valid Windows PE executable ('MZ' magic header & > 2 MB)
                with open(part_file, "rb") as f:
                    magic = f.read(2)
                if magic != b"MZ" or part_file.stat().st_size < 2_000_000:
                    raise RuntimeError("Downloaded file is not a valid Windows executable (MZ header check failed).")

                part_file.replace(BATTLENET_EXE)

            self.state["battlenet_downloaded"] = True
            save_state(self.state)

            GLib.idle_add(self.progress.set_fraction, 1.0)
            GLib.idle_add(self.progress.set_text, "Launching Battle.net-Setup.exe via WinBridge...")
            subprocess.Popen(["winbridge", str(BATTLENET_EXE)])

            self.state["battlenet_launched"] = True
            save_state(self.state)
            GLib.idle_add(self.progress.set_text, "Battle.net launched in WinBridge!")
        except Exception as exc:
            GLib.idle_add(self.progress.set_text, f"Error: {exc}")
        finally:
            GLib.idle_add(self.bnet_btn.set_sensitive, True)

    def on_complete(self, _btn):
        self.state["completed"] = True
        save_state(self.state)
        autostart_file = Path.home() / ".config" / "autostart" / "allglider-welcome.desktop"
        if autostart_file.exists():
            autostart_file.unlink()
        Gtk.main_quit()


if __name__ == "__main__":
    win = WelcomeWindow()
    win.connect("destroy", Gtk.main_quit)
    win.show_all()
    Gtk.main()
