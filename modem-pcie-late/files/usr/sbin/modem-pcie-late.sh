#!/bin/sh
# Bring the D50's modem back onto PCIe when it misses the link at boot.
#
# The kernel waits about 1 s for the modem's PCIe link at boot and does not
# look again. After a U-Boot web-recovery install the modem sometimes misses
# it, and the link then never trains by itself, even though the modem is up on
# USB (tested 16 Nov 2026). A modem restart over its USB AT port (AT+CFUN=1,1,
# Quectel's soft reset, no power cut) brings the link up within about 2 s.
# Nothing is bound to the modem over PCIe in that state, so the restart is safe.
#
# On a miss: wait 3 s for the link anyway, then restart the modem over USB, wait
# for the root port's Data Link Layer Link Active bit and rescan the bus. The
# modem sits straight on the root port (no switch), so a rescan enumerates it as
# it would have at boot.
#
# Does nothing when the modem enumerated at boot. Runs before logd, so it logs
# to the kernel log and keeps a record of every miss in /etc/modem-pcie-late.log,
# which survives a reboot. Usage: modem-pcie-late.sh [link_timeout_s]

RC=/sys/devices/platform/soc@0/80000000.pcie
TIMEOUT=${1:-40}
AT_IF=02	# the modem's USB AT interface (ttyUSB2 normally)
REC=/etc/modem-pcie-late.log

up() { cut -d' ' -f1 /proc/uptime; }
ms() { ucode -e "sleep($1)"; }	# busybox sleep has no fractions
usb_modem() { grep -qx 2c7c /sys/bus/usb/devices/*/idVendor 2>/dev/null && echo yes || echo no; }
log() {
	echo "<5>modem-pcie-late: $*" > /dev/kmsg
	echo "$(date '+%F %T') up $(up)s: $*" >> "$REC"
	echo "modem-pcie-late: $*" >&2
}

RP=$(ls -d "$RC"/pci*/*:00:00.0 2>/dev/null | head -1)
[ -n "$RP" ] || { log "no root port under $RC"; exit 0; }
ls -d "$RP"/*:01:00.0 >/dev/null 2>&1 && { echo "<6>modem-pcie-late: modem on PCIe at boot, nothing to do" > /dev/kmsg; exit 0; }

rd() { hexdump -s "$1" -n 1 -e '1/1 "%u"' "$RP/config"; }

# PCI Express capability (ID 0x10); Link Status is at +0x12, DLLLA is bit 13
CAP=0 p=$(rd 52)
while [ "${p:-0}" -ne 0 ]; do
	[ "$(rd "$p")" -eq 16 ] && { CAP=$p; break; }
	p=$(rd $((p + 1)))
done
[ "$CAP" -ne 0 ] || { log "no PCIe capability on $RP"; exit 0; }
link() { [ $(( $(rd $((CAP + 0x13))) & 0x20 )) -ne 0 ]; }

# wait_link <seconds>: returns 0 as soon as the link is up
wait_link() {
	local end
	end=$(awk -v t="$(up)" -v d="$1" 'BEGIN { print t + d }')
	while ! link; do
		awk -v n="$(up)" -v e="$end" 'BEGIN { exit !(n >= e) }' && return 1
		ms 100
	done
	return 0
}

# the modem's AT tty: the ttyUSB of USB interface $AT_IF on a Quectel (2c7c) device
at_tty() {
	local t
	for t in /sys/bus/usb/devices/*:1.*/ttyUSB*; do
		[ -e "$t" ] || continue
		[ "$(cat "${t%/*}/bInterfaceNumber" 2>/dev/null)" = "$AT_IF" ] || continue
		[ "$(cat "${t%/*}/../idVendor" 2>/dev/null)" = 2c7c ] || continue
		echo "${t##*/}"
		return
	done
}

[ -f "$REC" ] && [ "$(wc -l < "$REC")" -gt 400 ] && { tail -n 200 "$REC" > "$REC.new"; mv "$REC.new" "$REC"; }
echo "--- boot $(cat /proc/sys/kernel/random/boot_id), kernel PCIe lines:" >> "$REC"
dmesg | grep -E "80000000\.pcie|0001:" >> "$REC"
log "modem not on PCIe at boot (uptime $(up)s, link bit now: $(link && echo up || echo down), modem on USB: $(usb_modem))"

if ! wait_link 3; then
	TTY=
	for i in $(seq 30); do	# USB comes up a few seconds into boot
		TTY=$(at_tty)
		[ -n "$TTY" ] && break
		sleep 1
	done
	if [ -z "$TTY" ]; then
		log "no link and no modem AT port on USB; leaving it to a reboot"
		exit 0
	fi
	log "no link: restarting the modem with AT+CFUN=1,1 on /dev/$TTY"
	sms_tool -d "/dev/$TTY" at 'AT+CFUN=1,1' > /dev/null 2>&1 &
	AT=$!
	if ! wait_link "$TIMEOUT"; then
		kill "$AT" 2>/dev/null
		log "no link ${TIMEOUT}s after the modem restart (modem on USB: $(usb_modem)); leaving it to a reboot"
		exit 0
	fi
	kill "$AT" 2>/dev/null
fi
T1=$(up)
ms 100	# 100 ms after link up before config requests (PCIe CEM)
echo 1 > /sys/bus/pci/rescan
for i in $(seq 50); do ls -d "$RP"/*:01:00.0 >/dev/null 2>&1 && break; ms 100; done
if ls -d "$RP"/*:01:00.0 >/dev/null 2>&1; then
	log "link up at ${T1}s, modem enumerated by rescan at $(up)s ($(cat "$RP"/*:01:00.0/vendor):$(cat "$RP"/*:01:00.0/device))"
else
	log "link up at ${T1}s but rescan found no device"
fi
exit 0
