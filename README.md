# Xunison Exigo D50 5G: NSS offload with the modem on PCIe/MBIM

Full NSS offload on the Xunison (Zearts) Exigo D50 5G, with the Quectel RM500Q-AE on the upstream PCIe/MBIM stack (`mhi_wwan_mbim` + `umbim`, netdev `wwan0`) instead of the vendor `pcie_mhi` + `rmnet_nss` drivers.

It builds on kuncy7's IPQ5018 NSS work ([kuncy7/openwrt-nss-edma](https://github.com/kuncy7/openwrt-nss-edma), release `ipq50xx-2026.10.19`), which already carries the D50, the RM500Q-AE PCI ID and Julius Bairaktaris's generic raw-IP binding for `qca-nss-drv`. What this repo adds is one driver fix that makes that binding work for LAN traffic, plus a few small config files.

## What works

Tested on a D50 on 21 Oct 2026, LTE with three carriers aggregated, iPad on 5 GHz (160 MHz):

| | Before (software flow offload) | With NSS |
|---|---|---|
| Download | ~140 Mbit/s with CPU0 at ~61% | 116-160 Mbit/s with CPU0 at ~28%, NSS core ~7% |
| Peak seen on `wwan0` | | 203 Mbit/s |
| Upload latency under load | ~970 ms | 45-60 ms (with the optional cake script) |

- `nss-status`: OFFLOAD ACTIVE, Wi-Fi offload (wifili) on both radios, ECM accelerating modem flows (180+ at once during a speed test), kernel log clean.
- `wwan0: raw-IP interface bound to rmnet_rx node ...` at boot and again on every session re-connect.

## The bug the patch fixes

Without `0148`, the router itself works, but LAN clients behind the modem don't. Every TCP download stops after about 41 KB and HTTPS never completes. Pings and short requests go through, so it looks like it's working.

1. **Accelerated egress carries a link-layer frame.** For an accelerated flow from the LAN to the modem, the firmware hands the packet back to the transmit callback with the 14-byte frame the rmnet_rx node pair uses (zero MACs, IP ethertype) still on the front. `nss_rmnet_rx_bind_xmit()` queued it on the raw-IP `wwan0` as it was, so the modem dropped it. On a download those packets are the client's ACKs, so the server stops after one window, as soon as ECM accelerates the flow. A capture on `wwan0` shows it straight away: the accelerated packets start `0000 0000 0000 0000 0000 0000 0800 45..`.
2. **A failed hand-off drops the packet.** If the receive handler can't pass a packet to the firmware, it handed it to the stack still marked as an 802.3 frame, which no protocol handler takes. With `dev.nss.general.redirect=0` that is every received packet: `rx_dropped` on `wwan0` climbs with each one and the router goes offline. Note that `/etc/init.d/qca-nss-ecm stop` sets `redirect=0`, so on a raw-IP modem "does it work with ECM stopped?" makes things worse, not better. To take acceleration out of the picture while testing, use `echo 1 > /sys/kernel/debug/ecm/front_end_ipv4_stop` instead.

The patch strips the frame (and sets the protocol) in the transmit callback, and restores the original protocol when the hand-off fails.

## Using it

1. Build kuncy7's tree for the D50, with `patches/qca-nss-drv/0148-nss_rmnet_rx-unframe-accelerated-raw-ip-egress.patch` copied into `feeds/nss/qca-nss-drv/patches/`. See [BUILD.md](BUILD.md) for the other changes the tree needed on 21 Oct.
2. Modem in PCIe mode (`AT+QCFG="data_interface",1,0`, then a reboot), with `umbim`, `luci-proto-mbim` and the D50's MHI packages. Interface `proto mbim`, device `/dev/wwan0mbim0`.
3. Add the files under `files/` to the image (Image Builder `FILES=`), or copy them on and run them once:
   - `etc/uci-defaults/90-nss-no-flowtable`: software flow offloading off, or ECM never sees the flows.
   - `etc/uci-defaults/91-nss-led`: in this tree's device tree the internet LED is `green:wan-online`. A config carried over from a non-NSS build that drives `green:internet` leaves the LED dark.
   - `etc/hotplug.d/iface/95-wwan-cake` (optional): cake on `wwan0` upload. Set `RATE` to about 80-85% of your measured upload speed. Needs `tc-full` and `kmod-sched-cake`.

## Things to know

- **Leave Wi-Fi offload on** (`nss.general.wifi_offload=1`). With it off, the modem path needs `redirect=1` anyway, and `redirect=1` with Wi-Fi on the host path crashed the 2.4 GHz firmware (`crash detected in q6wcss`) within a minute here.
- **ECM sets `redirect` itself:** `1` when it starts, `0` when it stops. The modem path needs it on.
- The "debugfs: 'rmnet_rx' already exists" warning after a re-connect is harmless: the old node pair is torn down and a new one created when `umbim` brings `wwan0` down and up.

## Credits

kuncy7 for the IPQ5018 NSS tree, Julius Bairaktaris for the generic raw-IP binding this fixes, and LS3434 and IceG for the D50 testing and modem work in the forum threads.

## Licence

The patch is a change to qca-nss-drv and carries its licence (ISC). The config files are public domain: use them however you like.
