#!/bin/bash
# Run by zz-btw-apply.hook inside the ISO's root, after every package is
# installed: btw's files go over the packages' (their configs replace sway's,
# nftables', ...), then the btw user is made, and the stage is removed.
set -euo pipefail
stage=/var/lib/btw-iso/stage
cp -a "$stage/." /
rm -rf /var/lib/btw-iso
# The btw user (etc/sysusers.d/btw.conf) and its home, from /etc/skel.
systemd-sysusers
install -d -m 0700 -o btw -g btw /home/btw
cp -dRT --update=none --preserve=mode,timestamps,links /etc/skel /home/btw
chown -R btw:btw /home/btw
# No password, and none that everyone knows: the account is locked, sudo asks
# for a password, and the welcome terminal has you choose one first
# (usr/local/lib/btw/set-password, as on the Mac VM).
usermod -p '!' btw
install -d -m 755 /var/lib/btw
echo btw >/var/lib/btw/choose-password
