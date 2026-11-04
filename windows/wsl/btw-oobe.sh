#!/bin/bash
# btw for WSL's first-launch setup. WSL runs this once, as root, the first
# time btw is opened: it creates the user btw runs as and sets up the package
# keys. Then WSL logs in as that user and btw opens.
set -u

echo
echo "  btw: first-time setup"
echo

# Each install makes its own package signing keys, so they aren't shared
# through the download.
echo "Setting up package keys (a few seconds)..."
pacman-key --init >/dev/null 2>&1
pacman-key --populate archlinux >/dev/null 2>&1

suggested=btw
while true; do
    read -r -p "Choose a user name [$suggested]: " name
    name=${name:-$suggested}
    name=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')
    if [[ ! $name =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        echo "Use lowercase letters, digits, - and _ (starting with a letter)."
        continue
    fi
    if useradd -m -u 1000 -G wheel -s /bin/bash "$name"; then
        break
    fi
    echo "That didn't work; try another name."
done

echo
echo "Choose a password for $name. Linux asks for it when you install software."
until passwd "$name"; do
    echo "Let's try that again."
done

echo
echo "All set. btw opens in a window in a moment."
echo "Next time, open btw from the Start menu."
exit 0
