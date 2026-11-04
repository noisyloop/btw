# The desktop's welcome terminal asks for a password on a new VM. Elsewhere
# (the serial console, a headless boot), say how.
if [ -e /var/lib/btw/choose-password ] && [ "$(tty)" != /dev/tty1 ]; then
    echo "btw has no password yet. Choose one: sudo /usr/local/lib/btw/set-password"
fi
