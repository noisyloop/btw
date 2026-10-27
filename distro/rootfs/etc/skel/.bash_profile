# ~/.bash_profile
[[ -f ~/.bashrc ]] && . ~/.bashrc

# On the VM's screen (tty1), start the desktop when a display is present.
# The serial console (hvc0) and SSH stay plain shells.
if [[ -z $WAYLAND_DISPLAY && $(tty) == /dev/tty1 && -e /dev/dri/card0 ]]; then
    btw-session
fi
