# Builder image: Arch Linux ARM (aarch64) with the tools to pacstrap a rootfs
# and assemble a disk image without loop devices. Build it for linux/arm64:
# native on Apple silicon and arm64 runners, elsewhere via qemu-user binfmt.
FROM alpine:3.20 AS fetch
RUN apk add --no-cache curl gnupg libarchive-tools
# os.archlinuxarm.org redirects to a mirror and has no valid TLS certificate,
# so the tarball comes over plain HTTP and is checked against the signature
# from Arch Linux ARM's build key, pinned by its full fingerprint.
ARG ALARM=http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
ARG ALARM_SIGNER=68B3537F39A313B3E574D06777193F152BDBE6A6
RUN curl -fsSL -o /alarm.tar.gz "$ALARM" \
 && curl -fsSL -o /alarm.tar.gz.sig "$ALARM.sig" \
 && curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&options=mr&search=0x$ALARM_SIGNER" | gpg --batch --import \
 && gpg --batch --status-fd 1 --verify /alarm.tar.gz.sig /alarm.tar.gz | grep -q "^\[GNUPG:\] VALIDSIG .*$ALARM_SIGNER" \
 && mkdir /rootfs \
 && bsdtar -xpf /alarm.tar.gz -C /rootfs

FROM scratch
COPY --from=fetch /rootfs/ /
# CheckSpace can't see the container's mounts and makes pacman bail out, and
# pacman's download sandbox (Landlock + the alpm user) isn't permitted inside a
# container build. Packages are still verified against their signatures.
RUN sed -i -e 's/^CheckSpace/#CheckSpace/' -e '/^\[options\]/a DisableSandbox' /etc/pacman.conf \
 && pacman-key --init \
 && pacman-key --populate archlinuxarm \
 && pacman -Syu --noconfirm arch-install-scripts dosfstools mtools e2fsprogs util-linux zstd \
 && pacman -Scc --noconfirm
