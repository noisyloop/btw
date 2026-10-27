BTW := app/.build/release/btw
CACHE := .cache

.PHONY: build smoke gui dmg clean

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

# btw.app + btw.dmg in dist/ (icon from assets/AppIcon.png if present).
dmg:
	scripts/package.sh

clean:
	rm -rf app/.build dist
