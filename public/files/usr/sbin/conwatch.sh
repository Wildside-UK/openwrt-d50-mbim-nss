#!/bin/sh
# Connection watchdog for the D50 (worker for /etc/init.d/conwatch).
#
# Watches the data path, not the modem: wwan must be up AND pings by IP must
# get out. After a dwell it tries `ifup wwan` (twice), then a router reboot.
# Reboots are rate-limited with state kept in flash, and never a loop.
#
# It never touches the AT port, never runs mbimcli, uqmi, AT+CFUN or
# /etc/init.d/network restart. Settings live in /etc/conwatch.conf.
#
# Pause by hand: touch /tmp/conwatch.pause (cleared by a reboot).
# Stop for good: /etc/init.d/conwatch stop; /etc/init.d/conwatch disable

TAG=conwatch
CONF=/etc/conwatch.conf
STATE=/etc/conwatch.state

# Defaults; /etc/conwatch.conf overrides them.
DRY_RUN=1                # 1 = log what it would do, act on nothing
IFACE=wwan
TARGETS="9.9.9.9 149.112.112.11 1.1.1.1"
INTERVAL=30              # seconds between checks while healthy
FAILS_BEFORE_ACT=4       # consecutive failed checks before acting (~2 min)
GRACE=300                # no action before this uptime (s), lets the modem settle after boot
IFUP_TRIES=2             # ifup attempts before a reboot
IFUP_WAIT=120            # seconds to wait for recovery after each ifup
REBOOT_GAP=1800          # min uptime before rebooting again after its own reboot
REBOOT_MAX=3             # watchdog reboots in a row, then ifup only
HEALTHY_RESET=21600      # continuous healthy seconds that reset the count (6 h)
IFUP_RETRY=600           # once reboots are spent, ifup this often (s)

[ -r "$CONF" ] && . "$CONF"

log() { logger -t "$TAG" "$*"; }
uptime_s() { cut -d. -f1 /proc/uptime; }

# Healthy = netifd says up AND any target answers (two tries each).
healthy() {
	ifstatus "$IFACE" 2>/dev/null | grep -q '"up": true' || return 1
	for t in $TARGETS; do
		ping -c2 -W3 "$t" >/dev/null 2>&1 && return 0
	done
	return 1
}

# Manual pause or a sysupgrade in progress: never act.
paused() {
	[ -e /tmp/conwatch.pause ] || [ -e /tmp/sysupgrade.lock ] || [ -e /tmp/sysupgrade.tgz ]
}

# ---- reboot state (flash; written only on reboot and on reset) ----
COUNT=0
AFTER_WD=0
load_state() {
	[ -r "$STATE" ] && . "$STATE"
	COUNT=${COUNT:-0}
	# LAST_WD_BOOT=1 means the boot before this one was ours.
	if [ "${LAST_WD_BOOT:-0}" = 1 ]; then
		AFTER_WD=1
		save_state "$COUNT" 0
	fi
}
save_state() {
	printf 'COUNT=%s\nLAST_WD_BOOT=%s\n' "$1" "$2" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
	sync
}

# Uptime is the only clock that can be trusted here: the D50 has no RTC and
# boots on a stale time, so the gap rule uses uptime, not dates.
reboot_allowed() {
	if [ "$COUNT" -ge "$REBOOT_MAX" ]; then
		WHY="$COUNT watchdog reboots in a row with no ${HEALTHY_RESET}s healthy spell"
		return 1
	fi
	if [ "$AFTER_WD" = 1 ] && [ "$(uptime_s)" -lt "$REBOOT_GAP" ]; then
		WHY="last boot was a watchdog reboot, uptime $(uptime_s)s < ${REBOOT_GAP}s"
		return 1
	fi
	return 0
}

do_ifup() {
	if [ "$DRY_RUN" = 1 ]; then log "DRY RUN: would ifup $IFACE ($1)"; return; fi
	log "ifup $IFACE ($1)"
	ifup "$IFACE"
}

# Wait up to $1 s for the path to come back. 0 = recovered.
wait_recover() {
	end=$(( $(uptime_s) + $1 ))
	while [ "$(uptime_s)" -lt "$end" ]; do
		sleep 15
		healthy && return 0
	done
	return 1
}

do_reboot() {
	n=$((COUNT + 1))
	if [ "$DRY_RUN" = 1 ]; then
		log "DRY RUN: would reboot the router (watchdog reboot $n of $REBOOT_MAX)"
		return
	fi
	log "rebooting the router: data path dead after $IFUP_TRIES ifup (watchdog reboot $n of $REBOOT_MAX)"
	save_state "$n" 1
	sleep 3   # let the log line get out (remote syslog, if set up)
	reboot
	sleep 120
}

# The ladder. Called after FAILS_BEFORE_ACT failed checks.
recover() {
	t0=$(uptime_s)
	i=1
	while [ "$i" -le "$IFUP_TRIES" ]; do
		paused && { log "paused mid-ladder, standing down"; return; }
		do_ifup "attempt $i of $IFUP_TRIES"
		if wait_recover "$IFUP_WAIT"; then
			if [ "$DRY_RUN" = 1 ]; then
				log "DRY RUN: recovered on its own during wait $i, $(( $(uptime_s) - t0 ))s into the ladder"
			else
				log "recovered after ifup $i, $(( $(uptime_s) - t0 ))s into the ladder"
			fi
			return
		fi
		i=$((i + 1))
	done
	if reboot_allowed; then
		do_reboot
		[ "$DRY_RUN" = 1 ] || return
		# Dry run: carry on as if we were still waiting.
		wait_recover "$IFUP_RETRY" && log "DRY RUN: recovered on its own, $(( $(uptime_s) - t0 ))s after the first failure"
		return
	fi
	log "reboot suppressed: $WHY; ifup every ${IFUP_RETRY}s until it recovers"
	while ! healthy; do
		paused && return
		sleep "$IFUP_RETRY"
		healthy && break
		do_ifup "retry, reboots spent"
	done
	log "recovered, $(( $(uptime_s) - t0 ))s after the ladder started"
}

main() {
	load_state
	log "started: dry_run=$DRY_RUN fails=$FAILS_BEFORE_ACT x ${INTERVAL}s, ifup ${IFUP_TRIES}x${IFUP_WAIT}s, grace ${GRACE}s, reboots max $REBOOT_MAX gap ${REBOOT_GAP}s, count $COUNT, after_wd $AFTER_WD"
	fails=0
	healthy_since=
	while :; do
		up=$(uptime_s)
		if healthy; then
			[ "$fails" -ge 2 ] && log "path back after $fails failed checks"
			fails=0
			[ -n "$healthy_since" ] || healthy_since=$up
			if [ "$COUNT" -gt 0 ] && [ $((up - healthy_since)) -ge "$HEALTHY_RESET" ]; then
				log "healthy for ${HEALTHY_RESET}s, reboot count $COUNT -> 0"
				COUNT=0; AFTER_WD=0; save_state 0 0
			fi
		else
			healthy_since=
			fails=$((fails + 1))
			[ "$fails" = 1 ] && log "check failed (wwan down or no reply from $TARGETS)"
			if [ "$fails" -ge "$FAILS_BEFORE_ACT" ]; then
				if [ "$up" -lt "$GRACE" ] || paused; then
					:
				else
					log "data path dead for $fails checks, starting recovery"
					recover
					fails=0
					continue
				fi
			fi
		fi
		sleep "$INTERVAL"
	done
}

main
