# SPDX-License-Identifier: GPL-2.0+
# Linux's virtio sound driver (sound/virtio, unchanged from v7.3), built out of
# tree. Arch Linux ARM's linux-aarch64 leaves CONFIG_SND_VIRTIO off, and it's
# the only sound device a Mac's Virtualization.framework gives a VM.
#
#   make KERNELDIR=/usr/lib/modules/<version>/build
#
# DKMS (dkms.conf) runs this for every installed kernel.

obj-m += virtio_snd.o

virtio_snd-y := \
	virtio_card.o \
	virtio_chmap.o \
	virtio_ctl_msg.o \
	virtio_jack.o \
	virtio_kctl.o \
	virtio_pcm.o \
	virtio_pcm_msg.o \
	virtio_pcm_ops.o

KERNELDIR ?= /usr/lib/modules/$(shell uname -r)/build

all:
	$(MAKE) -C $(KERNELDIR) M=$(CURDIR) modules

clean:
	$(MAKE) -C $(KERNELDIR) M=$(CURDIR) clean
