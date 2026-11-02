#!/bin/bash
# boot-test.sh — full lk2nd boot + ramoops readback loop for the x2.
#
# Prereqs: device reachable via adb (boots bootloader from there) or already
# in a fastboot mode. Kernel Image.gz + dtb assembled into a boot.img first
# (scripts/make-bootimg.py). The kernel must have CONFIG_PSTORE_RAM=y.
#
# Flow (no user interaction needed unless the device hard-hangs):
#   adb reboot bootloader
#   fastboot boot lk2nd.img
#   fastboot boot boot.img          <- kernel runs; panic=15 auto-reboots
#   (crash lands back at stock LK fastboot)
#   fastboot boot lk2nd.img         <- re-enter lk2nd
#   fastboot oem ramoops console    <- stage the kernel console log
#   fastboot get_staged console.log <- fetch it
#
# Usage: boot-test.sh <boot.img> [lk2nd.img]

set -u
BOOT="${1:?usage: boot-test.sh <boot.img> [lk2nd.img]}"
LK2ND="${2:-out/lk2nd/lk2nd-x2-11/build-lk2nd-msm8996/lk2nd.img}"
SER=33470699

wait_fastboot() { # <seconds>
	for _ in $(seq 1 "${1:-40}"); do
		fastboot devices 2>/dev/null | grep -q "$SER" && return 0
		sleep 1
	done
	return 1
}

echo "== [1/6] reboot to bootloader =="
if adb devices | grep -q "$SER"; then
	adb -s "$SER" reboot bootloader
fi
wait_fastboot 60 || { echo "no fastboot device"; exit 1; }
fastboot getvar product 2>&1 | head -1

echo "== [2/6] boot lk2nd =="
fastboot boot "$LK2ND" >/dev/null 2>&1
sleep 5
wait_fastboot 30 || { echo "lk2nd did not come up"; exit 1; }
fastboot getvar product 2>&1 | head -1

echo "== [3/6] boot kernel (panic=15 auto-reboots on panic) =="
fastboot boot "$BOOT" 2>&1 | grep -E "OKAY|FAILED"
echo "   waiting up to 60s for crash-reboot..."
for i in $(seq 1 30); do
	sleep 2
	fastboot devices 2>/dev/null | grep -q "$SER" && { echo "   back at t=$((i*2))s"; break; }
done
fastboot getvar product 2>&1 | head -1

echo "== [4/6] re-enter lk2nd =="
fastboot boot "$LK2ND" >/dev/null 2>&1
sleep 5
wait_fastboot 30 || { echo "lk2nd did not come up"; exit 1; }

echo "== [5/6] fetch ramoops console =="
OUT="console-$(date +%Y%m%d-%H%M%S).log"
fastboot oem ramoops console 2>&1 | head -2
fastboot get_staged "$OUT" 2>&1 | tail -1
ls -la "$OUT" 2>/dev/null || { echo "no staged log; try 'oem ramoops regions'"; exit 1; }

echo "== [6/6] done =="
echo "kernel console log: $OUT"
echo "first lines:"
head -5 "$OUT"
