#!/usr/bin/env python3
"""Tests the btw PC ISO in QEMU (x86-64, KVM when there is one).

  scripts/iso-test.py <btw-x86_64.iso> <screenshot dir>

1. Boots the ISO through BIOS and checks the live desktop comes up.
2. Boots it through UEFI with a blank disk, types "sudo btw-install" into
   the desktop's welcome terminal and answers its questions.
3. Checks what landed on the disk: GRUB for BIOS and UEFI, an fstab, a
   password for btw, and none of the live USB's leftovers.
4. Boots the installed disk, through UEFI and through BIOS.

Every step leaves a screenshot (PNG when ImageMagick is there, else PPM).
Needs qemu-system-x86_64, OVMF, e2fsprogs (debugfs) and mtools (mdir), and
no root: the disk is checked without mounting it.
"""
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time

ISO, SHOTS = sys.argv[1], sys.argv[2]
os.makedirs(SHOTS, exist_ok=True)
WORK = tempfile.mkdtemp(prefix="btw-iso-test.")
DISK = os.path.join(WORK, "disk.img")
PASSWORD = "btw-test-pw"
KVM = os.access("/dev/kvm", os.R_OK | os.W_OK)
# The desktop starts slower without KVM.
SLOW = 1 if KVM else 4


def ovmf():
    for code, vars_ in [("/usr/share/OVMF/OVMF_CODE_4M.fd", "/usr/share/OVMF/OVMF_VARS_4M.fd"),
                        ("/usr/share/edk2/x64/OVMF_CODE.4m.fd", "/usr/share/edk2/x64/OVMF_VARS.4m.fd"),
                        ("/usr/share/OVMF/OVMF_CODE.fd", "/usr/share/OVMF/OVMF_VARS.fd")]:
        if os.path.exists(code) and os.path.exists(vars_):
            mine = os.path.join(WORK, "vars.fd")
            if not os.path.exists(mine):
                shutil.copy(vars_, mine)
            return ["-drive", f"if=pflash,format=raw,readonly=on,file={code}",
                    "-drive", f"if=pflash,format=raw,file={mine}"]
    sys.exit("no OVMF firmware found (apt install ovmf)")


class VM:
    def __init__(self, name, uefi, cdrom=None, disk=None):
        self.name = name
        self.mon = os.path.join(WORK, f"{name}.mon")
        args = ["qemu-system-x86_64", "-m", "3072", "-smp", "2",
                "-vga", "virtio", "-display", "none",
                "-monitor", f"unix:{self.mon},server,nowait",
                "-nic", "user,model=virtio-net-pci",
                "-device", "qemu-xhci", "-device", "usb-tablet"]
        if KVM:
            args += ["-enable-kvm", "-cpu", "host"]
        if uefi:
            args += ovmf()
        if disk:
            args += ["-drive", f"file={disk},format=raw,if=virtio"]
        if cdrom:
            args += ["-cdrom", cdrom]
            if not uefi:
                args += ["-boot", "d"]
        self.log = open(os.path.join(SHOTS, f"{name}.qemu.log"), "w")
        self.proc = subprocess.Popen(args, stdout=self.log, stderr=subprocess.STDOUT)
        for _ in range(100):
            if os.path.exists(self.mon):
                break
            time.sleep(0.1)
        self.sock = socket.socket(socket.AF_UNIX)
        self.sock.connect(self.mon)
        self.sock.settimeout(5)
        self._read()
        self.n = 0

    def _read(self):
        data = b""
        try:
            while not data.endswith(b"(qemu) "):
                chunk = self.sock.recv(4096)
                if not chunk:
                    break
                data += chunk
        except socket.timeout:
            pass
        return data

    def hmp(self, cmd):
        self.sock.sendall(cmd.encode() + b"\n")
        return self._read()

    def shot(self, label):
        self.n += 1
        ppm = os.path.join(SHOTS, f"{self.name}-{self.n:02d}-{label}.ppm")
        self.hmp(f"screendump {ppm}")
        time.sleep(1)
        if shutil.which("convert") and os.path.exists(ppm):
            subprocess.run(["convert", ppm, ppm[:-4] + ".png"], check=False)
            os.remove(ppm)
        print(f"   screenshot: {label}", flush=True)

    KEYS = {" ": "spc", "\n": "ret", "-": "minus", "/": "slash", ".": "dot", "_": "shift-minus",
            ":": "shift-semicolon", "=": "equal"}

    def type(self, text):
        for ch in text:
            if ch in self.KEYS:
                key = self.KEYS[ch]
            elif ch.isupper():
                key = "shift-" + ch.lower()
            else:
                key = ch
            self.hmp(f"sendkey {key}")
            time.sleep(0.05)

    def wait(self, seconds):
        end = time.time() + seconds * SLOW
        while time.time() < end:
            if self.proc.poll() is not None:
                return False
            time.sleep(1)
        return True

    def stop(self):
        if self.proc.poll() is None:
            self.hmp("quit")
            try:
                self.proc.wait(20)
            except subprocess.TimeoutExpired:
                self.proc.kill()
        self.log.close()


failures = []


def check(ok, what):
    print(f"== {what}: {'ok' if ok else 'FAILED'}", flush=True)
    if not ok:
        failures.append(what)


def debugfs(img, offset, cmd):
    """Runs a read-only debugfs command on the ext4 root inside the disk image."""
    part = os.path.join(WORK, "root.ext4")
    if not os.path.exists(part):
        start, size = offset
        subprocess.run(["dd", f"if={img}", f"of={part}", "bs=512", f"skip={start}", f"count={size}",
                        "status=none"], check=True)
    r = subprocess.run(["debugfs", "-R", cmd, part], capture_output=True, text=True)
    return r.stdout


def partitions(img):
    out = subprocess.run(["sfdisk", "-J", img], capture_output=True, text=True).stdout
    return json.loads(out)["partitiontable"]["partitions"] if out else []


print(f"KVM: {KVM}", flush=True)

# 1. The live desktop, through BIOS.
print("-- live, BIOS", flush=True)
vm = VM("live-bios", uefi=False, cdrom=ISO)
vm.wait(20); vm.shot("boot-menu")
vm.wait(70); vm.shot("desktop")
vm.stop()

# 2. Install, through UEFI.
print("-- install, UEFI", flush=True)
subprocess.run(["truncate", "-s", "12G", DISK], check=True)
vm = VM("install", uefi=True, cdrom=ISO, disk=DISK)
vm.wait(90); vm.shot("desktop")
vm.type("sudo btw-install\n"); vm.wait(8); vm.shot("disks")
vm.type("1\n"); vm.wait(3)
vm.type(PASSWORD + "\n"); vm.wait(1)
vm.type(PASSWORD + "\n"); vm.wait(2)
vm.type("Europe/Berlin\n"); vm.wait(2); vm.shot("confirm")
vm.type("erase\n")
# Copying: wait for "Restart now?", checking the screen now and then.
vm.wait(240); vm.shot("installing")
vm.wait(240); vm.shot("done")
vm.type("n\n"); vm.wait(3)
vm.stop()

# 3. What's on the disk.
print("-- the installed disk", flush=True)
parts = partitions(DISK)
check(len(parts) == 3, "three partitions (BIOS boot, EFI, root)")
if len(parts) == 3:
    root = (parts[2]["start"], parts[2]["size"])
    def has(path):
        out = debugfs(DISK, root, f"stat {path}")
        return "Inode:" in out
    def cat(path):
        return debugfs(DISK, root, f"cat {path}")
    check("UUID=" in cat("/etc/fstab"), "fstab mounts by UUID")
    check(re.search(r"^btw:\$", cat("/etc/shadow"), re.M) is not None, "btw has a password")
    check("Europe/Berlin" in debugfs(DISK, root, "stat /etc/localtime"), "time zone set")
    check(not has("/etc/sudoers.d/zz-btw-live"), "no live sudo-without-password")
    check(not has("/etc/systemd/system/getty@tty1.service.d/autologin.conf"), "no automatic login")
    check(not has("/usr/local/bin/btw-install"), "installer not left behind")
    check(has("/usr/local/bin/btw-session") and has("/usr/share/btw/shell/shell.qml"), "btw's files are there")
    check(not has("/etc/mkinitcpio.conf.d/archiso.conf"), "normal initramfs config")
    # pacman works: a server to download from, and signing keys made on first
    # start (never shipped: every PC's would be the same).
    check(re.search(r"^Server\s*=", cat("/etc/pacman.d/mirrorlist"), re.M) is not None, "pacman has a mirror")
    check(has("/etc/systemd/system/multi-user.target.wants/btw-pacman-init.service"), "pacman keys made on first start")
    check(not has("/etc/pacman.d/gnupg/trustdb.gpg"), "no pacman keys shipped")
    check(has("/usr/bin/git") and has("/usr/local/lib/btw/whole-os"), "Update btw can update everything")
    esp = parts[1]
    esp_img = os.path.join(WORK, "esp.img")
    subprocess.run(["dd", f"if={DISK}", f"of={esp_img}", "bs=512", f"skip={esp['start']}",
                    f"count={esp['size']}", "status=none"], check=True)
    listing = subprocess.run(["mdir", "-/", "-b", "-i", esp_img, "::"], capture_output=True, text=True).stdout
    check("BOOTX64.EFI" in listing.upper(), "UEFI loader on the EFI partition")
    check("grub.cfg" in listing, "GRUB menu")
    check("vmlinuz-linux" in listing and "initramfs-linux.img" in listing, "kernel and initramfs")

# 4. Boot the installed disk.
for mode, uefi in [("installed-uefi", True), ("installed-bios", False)]:
    print(f"-- {mode}", flush=True)
    vm = VM(mode, uefi=uefi, disk=DISK)
    vm.wait(45); vm.shot("login")
    vm.type("btw\n"); vm.wait(2); vm.type(PASSWORD + "\n")
    vm.wait(45); vm.shot("desktop")
    vm.stop()

shutil.rmtree(WORK, ignore_errors=True)
if failures:
    sys.exit("ISO test failed: " + ", ".join(failures))
print("ISO test passed (look at the screenshots too)")
