# The desktop's welcome terminal asks for a password on a new btw. Without
# the desktop (the serial console, a headless boot, or a screen the desktop
# couldn't start on), say how.
if [ -e /var/lib/btw/choose-password ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    echo "btw has no password yet. Choose one: sudo /usr/local/lib/btw/set-password"
fi
