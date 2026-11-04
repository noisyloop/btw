#!/usr/bin/env bash
# Checks a built btw.wsl without Windows: run as root inside a container made
# from it (docker import). It sets up a user the way the first-launch setup
# does, then opens btw with btw-wsl inside a headless Sway that stands in for
# WSLg's display, and checks that btw comes up and closes cleanly.
set -euo pipefail
fail() { echo "FAIL: $*" >&2; exit 1; }

for f in /usr/local/bin/btw-session /usr/local/bin/btw-wsl /usr/lib/wsl/btw-oobe.sh \
         /usr/lib/wsl/btw.ico /etc/wsl-distribution.conf /etc/wsl.conf /etc/profile.d/btw-wsl.sh \
         /usr/share/btw/shell/shell.qml /usr/share/btw/config/sway/config; do
    [ -e "$f" ] || fail "missing $f"
done
pacman -Q sway quickshell foot waybar >/dev/null || fail "packages missing"
bash -n /usr/lib/wsl/btw-oobe.sh || fail "first-launch setup has a syntax error"
echo "files and packages: ok"

# What the first-launch setup does, minus the questions.
useradd -m -u 1000 -G wheel -s /bin/bash tester
uid=1000
rt=/run/user/$uid
wslg=/mnt/wslg/runtime-dir
mkdir -p "$rt" "$wslg"
chown tester "$rt" "$wslg"
chmod 700 "$rt" "$wslg"

# WSLg's display: a headless Sway whose socket is in /mnt/wslg/runtime-dir.
printf 'output HEADLESS-1 resolution 1280x800\n' >/home/tester/outer.conf
runuser -u tester -- env XDG_RUNTIME_DIR="$wslg" WLR_BACKENDS=headless WLR_RENDERER=pixman \
    WLR_LIBINPUT_NO_DEVICES=1 setsid sway -c /home/tester/outer.conf >/home/tester/outer.log 2>&1 &
for _ in $(seq 50); do
    sock=$(ls "$wslg" | grep -E '^wayland-[0-9]+$' | head -n1 || true)
    [ -n "$sock" ] && break
    sleep 0.1
done
[ -n "$sock" ] || { cat /home/tester/outer.log; fail "the stand-in display didn't start"; }

# Open btw the way the Start menu shortcut does.
runuser -u tester -- env XDG_RUNTIME_DIR="$rt" WAYLAND_DISPLAY="$sock" HOME=/home/tester \
    setsid btw-wsl </dev/null >/home/tester/btw-wsl.log 2>&1 &
sleep 8
log=/home/tester/.local/state/sway.log
pgrep -u tester -f btw-window.conf >/dev/null || { cat /home/tester/btw-wsl.log "$log" 2>/dev/null; fail "btw didn't come up"; }
pgrep -u tester -x swaybg >/dev/null || fail "no wallpaper (swaybg)"
pgrep -u tester -x foot >/dev/null || fail "no terminal (foot)"
echo "btw opened in its window: ok"

# Close it (Alt+Shift+E does swaymsg exit).
inner=$(ls "$rt"/sway-ipc.*.sock 2>/dev/null | head -n1)
[ -n "$inner" ] || inner=$(ls "$wslg"/sway-ipc.*.sock | while read -r s; do
    runuser -u tester -- env SWAYSOCK="$s" swaymsg -t get_outputs 2>/dev/null | grep -q '"WL-1"' && echo "$s"; done | head -n1)
runuser -u tester -- env SWAYSOCK="$inner" swaymsg exit >/dev/null 2>&1 || true
for _ in $(seq 30); do grep -q "sway exited with status 0" "$log" && break; sleep 0.2; done
grep -q "sway exited with status 0" "$log" || { cat "$log"; fail "btw didn't close cleanly"; }
echo "btw closed cleanly: ok"
