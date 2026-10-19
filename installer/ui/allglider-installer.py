#!/usr/bin/env python3
"""
AllGlider Live Linux - Graphical Disk Installer with USB Migration
Installs the Fedora 44 Live system onto a selected internal disk and migrates
AllGlider profiles, WinBridge shared environment, Proton data, and settings.
"""
import json
import subprocess
import threading
from pathlib import Path

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk


def get_boot_usb_disks() -> set:
    """Identify physical parent disk(s) backing the Live USB or ALLGLIDER_DATA so they are never offered as targets."""
    protected = set()
    try:
        out = subprocess.check_output(
            ["lsblk", "-J", "-o", "NAME,PKNAME,LABEL,MOUNTPOINTS"],
            text=True,
        )
        data = json.loads(out)

        def scan(nodes, parent_disk=None):
            for node in nodes:
                disk_name = parent_disk or node.get("name")
                label = (node.get("label") or "").upper()
                mounts = node.get("mountpoints") or []
                if (
                    label in ("ALLGLIDER_DATA", "ALLGLIDER_LIVE", "ALLGLIDER_EFI", "AG_USB_EFI")
                    or any(m and ("/run/initramfs/live" in m or "/mnt/allglider-data" in m or m == "/") for m in mounts)
                ):
                    if disk_name:
                        protected.add(disk_name)
                for child in node.get("children", []):
                    scan([child], disk_name)

        scan(data.get("blockdevices", []))
    except Exception:
        pass
    return protected


def list_candidate_disks() -> list:
    protected = get_boot_usb_disks()
    candidates = []
    try:
        out = subprocess.check_output(
            ["lsblk", "-J", "-b", "-d", "-o", "NAME,SIZE,MODEL,TRAN,TYPE,RO"],
            text=True,
        )
        data = json.loads(out)
        for dev in data.get("blockdevices", []):
            name = dev.get("name", "")
            if dev.get("type") != "disk" or int(dev.get("ro") or 0) == 1:
                continue
            if name.startswith(("loop", "ram", "zram", "sr")):
                continue
            if name in protected:
                continue
            size_gib = int(dev.get("size") or 0) / (1024 ** 3)
            if size_gib < 20:
                continue
            model = (dev.get("model") or "Virtual / Internal Disk").strip()
            tran = (dev.get("tran") or "internal").upper()
            candidates.append(
                {
                    "path": f"/dev/{name}",
                    "name": name,
                    "size_gib": size_gib,
                    "model": model,
                    "tran": tran,
                }
            )
    except Exception:
        pass
    return candidates


class InstallerWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title="Install AllGlider Live Linux to Internal Disk")
        self.set_default_size(680, 500)
        self.set_border_width(16)
        self.set_position(Gtk.WindowPosition.CENTER)

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        self.add(vbox)

        title = Gtk.Label()
        title.set_markup("<span size='x-large' weight='bold'>Install AllGlider Linux to Disk</span>")
        title.set_xalign(0)
        vbox.pack_start(title, False, False, 0)

        desc = Gtk.Label(
            label=(
                "This wizard installs AllGlider Linux (Fedora 44 Xfce with NVIDIA/AMD/Intel drivers, "
                "WinBridge, and GE-Proton) onto a target internal disk and migrates your setup from the USB drive."
            ),
            xalign=0,
        )
        desc.set_line_wrap(True)
        vbox.pack_start(desc, False, False, 0)

        # Target Disk Selection
        disk_frame = Gtk.Frame(label="1. Select Target Disk (Live USB is automatically protected)")
        disk_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        disk_box.set_border_width(10)
        disk_frame.add(disk_box)
        vbox.pack_start(disk_frame, False, False, 0)

        self.disk_combo = Gtk.ComboBoxText()
        disk_box.pack_start(self.disk_combo, False, False, 0)

        # Migration Options
        mig_frame = Gtk.Frame(label="2. Select Data to Migrate from USB")
        mig_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        mig_box.set_border_width(10)
        mig_frame.add(mig_box)
        vbox.pack_start(mig_frame, False, False, 0)

        self.migrate_chk = Gtk.CheckButton(
            label="Migrate AllGlider profiles, WinBridge settings, shared Windows prefix, and Battle.net/WoW"
        )
        self.migrate_chk.set_active(True)
        mig_box.pack_start(self.migrate_chk, False, False, 0)

        self.logs_chk = Gtk.CheckButton(label="Include application logs from USB")
        self.logs_chk.set_active(False)
        mig_box.pack_start(self.logs_chk, False, False, 0)

        # Explicit Confirmation
        self.confirm_chk = Gtk.CheckButton(
            label="I confirm that all existing partitions and data on the selected target disk will be erased."
        )
        vbox.pack_start(self.confirm_chk, False, False, 0)

        self.progress = Gtk.ProgressBar()
        self.progress.set_show_text(True)
        self.progress.set_text("Ready to install")
        vbox.pack_start(self.progress, False, False, 0)

        # Buttons
        btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        vbox.pack_end(btn_box, False, False, 0)

        refresh_btn = Gtk.Button(label="Refresh Disks")
        refresh_btn.connect("clicked", lambda *_: self.populate_disks())
        btn_box.pack_start(refresh_btn, False, False, 0)

        self.install_btn = Gtk.Button(label="Start Installation")
        self.install_btn.connect("clicked", self.on_install_clicked)
        btn_box.pack_end(self.install_btn, False, False, 0)

        self.disks = []
        self.populate_disks()

    def populate_disks(self):
        self.disk_combo.remove_all()
        self.disks = list_candidate_disks()
        for d in self.disks:
            label = f"{d['path']} — {d['model']} ({d['size_gib']:.1f} GiB, {d['tran']})"
            self.disk_combo.append_text(label)
        if self.disks:
            self.disk_combo.set_active(0)

    def on_install_clicked(self, _btn):
        idx = self.disk_combo.get_active()
        if idx < 0 or idx >= len(self.disks):
            self.progress.set_text("Error: No valid target disk selected.")
            return
        if not self.confirm_chk.get_active():
            self.progress.set_text("Please check the confirmation box before starting installation.")
            return

        target_disk = self.disks[idx]
        dialog = Gtk.MessageDialog(
            transient_for=self,
            flags=0,
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.OK_CANCEL,
            text=f"Confirm formatting {target_disk['path']} ({target_disk['model']})",
        )
        dialog.format_secondary_text(
            f"Size: {target_disk['size_gib']:.1f} GiB\nAll existing data on {target_disk['path']} will be permanently erased."
        )
        resp = dialog.run()
        dialog.destroy()
        if resp != Gtk.ResponseType.OK:
            return

        self.install_btn.set_sensitive(False)
        threading.Thread(
            target=self._run_install,
            args=(target_disk["path"], self.migrate_chk.get_active(), self.logs_chk.get_active()),
            daemon=True,
        ).start()

    def _update(self, fraction: float, text: str):
        GLib.idle_add(self.progress.set_fraction, fraction)
        GLib.idle_add(self.progress.set_text, text)

    def _run_install(self, disk_path: str, do_migrate: bool, include_logs: bool):
        try:
            self._update(0.05, f"Partitioning {disk_path} (GPT: EFI + Root)...")
            subprocess.run(["wipefs", "-a", disk_path], check=True)
            subprocess.run(["parted", "-s", disk_path, "mklabel", "gpt"], check=True)
            subprocess.run(["parted", "-s", disk_path, "mkpart", "ESP", "fat32", "1MiB", "513MiB"], check=True)
            subprocess.run(["parted", "-s", disk_path, "set", "1", "esp", "on"], check=True)
            subprocess.run(["parted", "-s", disk_path, "mkpart", "ALLGLIDER_ROOT", "ext4", "513MiB", "100%"], check=True)
            subprocess.run(["udevadm", "settle"], check=True)

            sep = "p" if disk_path[-1].isdigit() else ""
            efi_part = f"{disk_path}{sep}1"
            root_part = f"{disk_path}{sep}2"

            self._update(0.15, "Formatting filesystems...")
            subprocess.run(["mkfs.vfat", "-F", "32", "-n", "AG_EFI", efi_part], check=True)
            subprocess.run(["mkfs.ext4", "-F", "-L", "ALLGLIDER_ROOT", root_part], check=True)

            target_mnt = Path("/mnt/allglider-target")
            target_mnt.mkdir(parents=True, exist_ok=True)
            subprocess.run(["mount", root_part, str(target_mnt)], check=True)
            (target_mnt / "boot" / "efi").mkdir(parents=True, exist_ok=True)
            subprocess.run(["mount", efi_part, str(target_mnt / "boot" / "efi")], check=True)

            self._update(0.30, "Copying base system (Fedora 44, NVIDIA, WinBridge, Proton)...")
            src_root = "/run/rootfsbase" if Path("/run/rootfsbase/usr").exists() else "/"
            subprocess.run(
                [
                    "rsync",
                    "-aHA",
                    "--exclude=/dev/*",
                    "--exclude=/proc/*",
                    "--exclude=/sys/*",
                    "--exclude=/tmp/*",
                    "--exclude=/run/*",
                    "--exclude=/mnt/*",
                    "--exclude=/media/*",
                    "--exclude=/lost+found",
                    "--exclude=/home/liveuser/*",
                    f"{src_root}/",
                    f"{target_mnt}/",
                ],
                check=True,
            )

            self._update(0.65, "Configuring /etc/fstab and bootloader (GRUB2)...")
            efi_uuid = subprocess.check_output(["blkid", "-s", "UUID", "-o", "value", efi_part], text=True).strip()
            root_uuid = subprocess.check_output(["blkid", "-s", "UUID", "-o", "value", root_part], text=True).strip()

            fstab_content = (
                f"UUID={root_uuid}  /          ext4  defaults,noatime  1 1\n"
                f"UUID={efi_uuid}   /boot/efi  vfat  umask=0077,shortname=winnt  0 2\n"
            )
            (target_mnt / "etc" / "fstab").write_text(fstab_content, encoding="utf-8")

            grub_default = (
                'GRUB_TIMEOUT=3\n'
                'GRUB_DISTRIBUTOR="AllGlider Linux"\n'
                'GRUB_DEFAULT=saved\n'
                'GRUB_CMDLINE_LINUX="selinux=0 enforcing=0 quiet rhgb rd.driver.blacklist=nouveau modprobe.blacklist=nouveau nvidia-drm.modeset=1"\n'
                'GRUB_ENABLE_BLSCFG=true\n'
            )
            (target_mnt / "etc" / "default" / "grub").write_text(grub_default, encoding="utf-8")

            for bind_dir in ("dev", "proc", "sys", "run"):
                (target_mnt / bind_dir).mkdir(parents=True, exist_ok=True)
                subprocess.run(["mount", "--bind", f"/{bind_dir}", str(target_mnt / bind_dir)], check=True)

            subprocess.run(["chroot", str(target_mnt), "grub2-mkconfig", "-o", "/boot/grub2/grub.cfg"], check=True)

            if do_migrate:
                self._update(0.80, "Migrating AllGlider setup, WinBridge prefix, and user data from USB...")
                cmd = ["/usr/local/bin/allglider-migrate", str(target_mnt)]
                if include_logs:
                    cmd.append("--include-logs")
                subprocess.run(cmd, check=True)
            else:
                subprocess.run(["cp", "-a", "/etc/skel/.", str(target_mnt / "home" / "liveuser/")], check=True)
                subprocess.run(["chown", "-R", "1000:1000", str(target_mnt / "home" / "liveuser")], check=True)

            self._update(0.95, "Syncing disks and unmounting...")
            subprocess.run(["sync"], check=True)
            for bind_dir in ("run", "sys", "proc", "dev", "boot/efi"):
                subprocess.run(["umount", "-l", str(target_mnt / bind_dir)], check=False)
            subprocess.run(["umount", "-l", str(target_mnt)], check=False)

            self._update(1.0, "Installation and migration complete! You can now reboot and remove the USB drive.")
        except Exception as exc:
            self._update(0.0, f"Installation error: {exc}")
        finally:
            GLib.idle_add(self.install_btn.set_sensitive, True)


if __name__ == "__main__":
    win = InstallerWindow()
    win.connect("destroy", Gtk.main_quit)
    win.show_all()
    Gtk.main()
