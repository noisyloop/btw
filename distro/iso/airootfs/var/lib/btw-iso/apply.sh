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
