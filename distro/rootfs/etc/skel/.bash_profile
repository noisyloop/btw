# ~/.bash_profile
[[ -f ~/.bashrc ]] && . ~/.bashrc

# On the screen (tty1), start the desktop when a display is present.
# The serial console (hvc0) and SSH stay plain shells.
if [[ -z $WAYLAND_DISPLAY && $(tty) == /dev/tty1 ]]; then
    # On a PC booted through UEFI, the firmware's display (simpledrm, card0)
    # goes away when the real graphics driver takes over, so for a moment
    # there's none: wait for the drivers to settle, then for a display.
    udevadm settle -t 10 2>/dev/null
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        compgen -G '/dev/dri/card*' >/dev/null && break
        sleep 1
    done
    compgen -G '/dev/dri/card*' >/dev/null && btw-session
fi
