BTW := app/.build/release/btw
CACHE := .cache

.PHONY: build smoke gui image boot-test factory dmg preview clean

# Builds the launcher and ad-hoc signs it with the virtualization entitlement;
# without the entitlement, Virtualization.framework refuses to start a VM.
build:
	swift build -c release --package-path app
	codesign --force --sign - --entitlements app/btw.entitlements $(BTW)

# Proof #1: boot a Linux kernel headless, console in this terminal (Ctrl-] quits).
smoke: build
	scripts/fetch-netboot.sh $(CACHE)/netboot
	$(BTW) run --name smoke --headless \
		--kernel $(CACHE)/netboot/Image \
		--initrd $(CACHE)/netboot/initrd.gz \
		--cmdline "console=hvc0"

# Proof #2: boot an installer ISO through EFI in a window (graphics, keyboard, mouse, NAT).
gui: build
	scripts/fetch-iso.sh $(CACHE)/iso
	$(BTW) run --name gui --iso $(CACHE)/iso/debian-arm64-netinst.iso

# The btw factory disk: pacstrap Arch Linux ARM in Docker -> out/btw-factory.img(.zst).
image:
	docker build --platform linux/arm64 -t btw-builder distro
	docker run --rm --privileged --platform linux/arm64 -v "$(CURDIR)":/work btw-builder /work/distro/build.sh

# Linux + QEMU: boot the image and check it logs in, grows its root and powers off.
boot-test:
	scripts/boot-test.py out/btw-factory.img 16

# Boot a VM cloned from the factory disk (first run clones; later runs reuse it).
factory: build
	$(BTW) run --name factory --from out/btw-factory.img --disk 32

# btw.app + btw-macos.dmg in dist/ (icon from assets/AppIcon.png if present).
dmg:
	scripts/package.sh

# Browser preview of the btw desktop (no VM needed).
preview:
	open desktop/index.html 2>/dev/null || xdg-open desktop/index.html

clean:
	rm -rf app/.build dist out
