#!/usr/bin/env bash
# Boots Debian's arm64 netboot kernel headless with the btw launcher and waits
# for the kernel banner on the serial console. Needs a Mac that can run VMs
# (`btw check`); hosted CI runners usually can't.
#   scripts/smoke-mac.sh <path/to/btw>
set -euo pipefail

btw="$1"
root="$(cd "$(dirname "$0")/.." && pwd)"
netboot="$root/.cache/netboot"
log="$(mktemp)"

"$root/scripts/fetch-netboot.sh" "$netboot"
"$btw" run --name ci-smoke --headless --memory 2 \
  --kernel "$netboot/Image" --initrd "$netboot/initrd.gz" --cmdline "console=hvc0" \
  </dev/null >"$log" 2>&1 &
pid=$!

ok=""
for _ in $(seq 120); do
  if grep -q "Linux version" "$log"; then ok=1; break; fi
  kill -0 "$pid" 2>/dev/null || break
  sleep 1
done
kill -TERM "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true
cat "$log"
rm -rf "$HOME/Library/Application Support/btw/VMs/ci-smoke"
[[ -n "$ok" ]] || { echo "no kernel banner on the console" >&2; exit 1; }
echo "smoke test passed: the kernel booted"
