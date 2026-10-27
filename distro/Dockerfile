# Builder image: Arch Linux ARM (aarch64) with the tools to pacstrap a rootfs
# and assemble a disk image without loop devices. Native on Apple silicon;
# elsewhere it needs qemu-user binfmt for linux/arm64.
FROM --platform=linux/arm64 alpine:3.20 AS fetch
RUN apk add --no-cache curl libarchive-tools
ARG ALARM=https://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
RUN curl -fsSL -o /alarm.tar.gz "$ALARM" \
 && curl -fsSL -o /alarm.tar.gz.md5 "$ALARM.md5" \
 && echo "$(cut -d' ' -f1 /alarm.tar.gz.md5)  /alarm.tar.gz" | md5sum -c - \
 && mkdir /rootfs \
 && bsdtar -xpf /alarm.tar.gz -C /rootfs

FROM scratch
COPY --from=fetch /rootfs/ /
# CheckSpace can't see the container's mounts and makes pacman bail out.
RUN sed -i 's/^CheckSpace/#CheckSpace/' /etc/pacman.conf \
 && pacman-key --init \
 && pacman-key --populate archlinuxarm \
 && pacman -Syu --noconfirm arch-install-scripts dosfstools mtools e2fsprogs util-linux zstd \
 && pacman -Scc --noconfirm
