#!/usr/bin/env python3
"""Boots the btw factory disk in QEMU (aarch64, UEFI) and checks that it:
  1. boots through systemd-boot and logs in automatically on the console (hvc0),
  2. grows its root filesystem to fill a larger disk,
  3. resolves DNS names and has the desktop installed,
  4. powers off cleanly when asked.

  scripts/boot-test.py out/btw-factory.img [disk GiB, default 16]

Needs qemu-system-aarch64 and the qemu-efi-aarch64 firmware. Uses KVM when
/dev/kvm is usable, otherwise TCG (slow, but CI runners have no nested virt).
"""
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time

FIRMWARE = ["/usr/share/qemu-efi-aarch64/QEMU_EFI.fd", "/usr/share/AAVMF/AAVMF_CODE.fd"]


def main():
    image = sys.argv[1]
    disk_gib = int(sys.argv[2]) if len(sys.argv) > 2 else 16
    work = tempfile.mkdtemp(prefix="btw-boot-")
    disk = os.path.join(work, "disk.img")
    sock = os.path.join(work, "console.sock")

    # Same as the launcher: a copy of the factory disk, grown sparsely.
    subprocess.run(["cp", "--sparse=always", image, disk], check=True)
    os.truncate(disk, disk_gib << 30)

    firmware = next((p for p in FIRMWARE if os.path.exists(p)), None)
    if firmware is None:
        sys.exit("no aarch64 UEFI firmware found (install qemu-efi-aarch64)")
    if os.access("/dev/kvm", os.R_OK | os.W_OK):
        accel, timeout = ["-accel", "kvm", "-cpu", "host"], 300
    else:
        accel, timeout = ["-accel", "tcg", "-cpu", "max"], 1500
    print(f"booting with {accel[1]}, timeout {timeout}s", flush=True)

    qemu = subprocess.Popen([
        "qemu-system-aarch64", "-M", "virt", *accel, "-smp", "2", "-m", "2048",
        "-bios", firmware, "-display", "none", "-serial", "null",
        "-drive", f"file={disk},if=virtio,format=raw",
        "-nic", "user,model=virtio-net-pci",
        # A virtio console shows up as hvc0, like Virtualization.framework's.
        "-device", "virtio-serial-pci",
        "-chardev", f"socket,id=con,path={sock},server=on,wait=off",
        "-device", "virtconsole,chardev=con",
    ])
    try:
        console = connect(sock, qemu)
        expect(console, qemu, rb"btw@btw", timeout)
        print("\n== logged in automatically", flush=True)

        console.sendall(b"echo ROOT-BYTES=$(findmnt -bno SIZE /)\n")
        size = int(expect(console, qemu, rb"ROOT-BYTES=(\d+)", 120).group(1))
        want = (disk_gib - 1) << 30
        print(f"\n== root filesystem: {size / 2**30:.1f} GiB on a {disk_gib} GiB disk", flush=True)
        if size < want:
            fail(f"root did not grow to fill the disk ({size} < {want} bytes)")

        # DNS broke in the first images; check a lookup works (QEMU provides DNS).
        console.sendall(b"echo DNS-$(getent hosts archlinux.org >/dev/null && echo ok || echo fail)\n")
        dns = expect(console, qemu, rb"DNS-(ok|fail)", 60).group(1)
        print(f"\n== DNS: {dns.decode()}", flush=True)
        if dns != b"ok":
            console.sendall(b"ls -l /etc/resolv.conf; systemctl --no-pager status systemd-resolved | head -20\n")
            drain(console, 8)
            fail("DNS lookups don't work in the VM")

        console.sendall(b"echo DESKTOP-$(pacman -Q sway waybar foot fuzzel >/dev/null && echo ok || echo missing)\n")
        desktop = expect(console, qemu, rb"DESKTOP-(ok|missing)", 60).group(1)
        print(f"\n== desktop packages: {desktop.decode()}", flush=True)
        if desktop != b"ok":
            fail("the desktop packages are missing")

        console.sendall(b"echo btw | sudo -S systemctl poweroff\n")
        try:
            qemu.wait(timeout=180)
        except subprocess.TimeoutExpired:
            fail("the VM did not power off")
        print("\n== powered off cleanly", flush=True)
    finally:
        if qemu.poll() is None:
            qemu.kill()
        shutil.rmtree(work, ignore_errors=True)


def connect(path, qemu):
    for _ in range(100):
        if qemu.poll() is not None:
            fail("qemu exited before the console came up")
        try:
            s = socket.socket(socket.AF_UNIX)
            s.connect(path)
            return s
        except OSError:
            time.sleep(0.2)
    fail("could not connect to the VM console")


def expect(console, qemu, pattern, timeout):
    buffer = b""
    deadline = time.time() + timeout
    while time.time() < deadline:
        if qemu.poll() is not None:
            fail(f"qemu exited (status {qemu.returncode}) while waiting for {pattern!r}")
        console.settimeout(min(5, max(0.1, deadline - time.time())))
        try:
            chunk = console.recv(4096)
        except socket.timeout:
            continue
        if not chunk:
            fail("the VM console closed")
        sys.stdout.write(chunk.decode(errors="replace"))
        sys.stdout.flush()
        buffer += chunk
        match = re.search(pattern, buffer)
        if match:
            return match
    fail(f"timed out after {timeout}s waiting for {pattern!r}")


def drain(console, seconds):
    """Prints whatever the console sends for a few seconds (diagnostics)."""
    deadline = time.time() + seconds
    while time.time() < deadline:
        console.settimeout(max(0.1, deadline - time.time()))
        try:
            chunk = console.recv(4096)
        except socket.timeout:
            continue
        if not chunk:
            return
        sys.stdout.write(chunk.decode(errors="replace"))
        sys.stdout.flush()


def fail(message):
    print(f"\nboot test failed: {message}", file=sys.stderr, flush=True)
    sys.exit(1)


if __name__ == "__main__":
    main()
