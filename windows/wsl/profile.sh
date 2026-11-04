# btw for WSL: opening btw (from the Start menu, or its terminal tab) starts
# the btw desktop in a window. Keep the terminal window open while btw runs;
# WSL stops Linux once nothing started from Windows is running.
#
# To get a plain shell instead, create ~/.config/btw/no-autostart.
if [ -n "${WSL_DISTRO_NAME:-}" ] && [ -z "${BTW_STARTED:-}" ] && [ "$(id -u)" -ne 0 ] &&
    [ -t 0 ] && [ ! -e "$HOME/.config/btw/no-autostart" ] && command -v btw-wsl >/dev/null; then
    if pgrep -u "$(id -u)" -f btw-window.conf >/dev/null 2>&1; then
        echo "btw is already open."
    else
        echo "Starting btw. Keep this window open while you use it."
        echo "Alt+Shift+E closes btw. Ctrl+C here also stops it."
        btw-wsl
        echo
        echo "btw closed. Run btw-wsl to open it again, or close this window."
    fi
fi
