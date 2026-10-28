# Xunison Exigo Hub D50 5G: NSS offload with the modem on PCIe/MBIM

Full NSS offload on the Xunison (Zearts) Exigo Hub D50 5G, with the Quectel RM500Q-AE on the upstream PCIe/MBIM stack (`mhi_wwan_mbim` + `umbim`, netdev `wwan0`).

The image is kuncy7's IPQ5018 NSS release ([kuncy7/openwrt-nss-edma](https://github.com/kuncy7/openwrt-nss-edma), `ipq50xx-2026.10.28`) built from his published config and feed pins, with one addition: the `umbim` fix from [openwrt/openwrt#25946](https://github.com/openwrt/openwrt/pull/25946). Without it an MBIM connection comes up with no DNS servers, so the internet works but nothing resolves. The package list is otherwise identical to kuncy7's own D50 image, and the build checks that.

Once #25946 is merged upstream, kuncy7's own D50 image will do the same job and this repo can be retired.

## Downloads

Each release has:

- `...-squashfs-sysupgrade.bin`: flash over a running OpenWrt.
- `...-squashfs-factory.img`: for U-Boot web recovery.
- `openwrt-imagebuilder-...Linux-x86_64.tar.zst` and `...Linux-aarch64.tar.zst`: Image Builders for adding your own packages and config.
- `image-packages.txt` and `sha256sums`.

Kernel modules for this build come from kuncy7's repository for the same release, which the image already lists.

## What works

- `nss-status`: offload active, Wi-Fi offload (wifili) on both radios, ECM accelerating the modem flows.
- Download 103-106 Mbit/s on Speedtest, limited by the cell rather than the router (NSS core load ~3%).
- The firmware's deliveries to the host go to the second CPU core, leaving the first to the modem (kuncy7's `nss-irq-affinity`, no script needed).
- DNS from the network on `wwan` by default; with `peerdns 0` the servers stay out of `resolv.conf.auto` and show as inactive in `ifstatus wwan`.

## Setting up the modem

Modem in PCIe mode (`AT+QCFG="data_interface",1,0`, then a reboot). Interface `proto mbim`, device `/dev/wwan0mbim0`, and your APN.

## Things to know

- **Leave Wi-Fi offload on** (`nss.general.wifi_offload=1`). The modem path only works with `redirect=1`, and turning Wi-Fi offload off while `redirect=1` is set crashed the 2.4 GHz radio firmware (`crash detected in q6wcss`) within a minute here.
- **Don't stop ECM to test without acceleration.** ECM sets `redirect` itself (`1` when it starts, `0` when it stops), and the modem path needs `redirect=1`, so `/etc/init.d/qca-nss-ecm stop` takes a raw-IP modem offline. To take acceleration out of the picture, stop ECM's front ends instead: `echo 1 > /sys/kernel/debug/ecm/front_end_ipv4_stop` and, if you use IPv6, `echo 1 > /sys/kernel/debug/ecm/front_end_ipv6_stop` (`echo 0` to both to undo).
- **Shaping:** kuncy7's NSS shaper (`sqm-scripts-nss`) only shapes traffic that crosses the Ethernet ports, and Wi-Fi clients' traffic never does, so on a typical D50 setup it shapes very little. Shape the upload with software cake on `wwan0` instead; accelerated uploads pass that queue.
- The "debugfs: 'rmnet_rx' already exists" warning after a re-connect is harmless.

## History

On 21 Oct 2026 this repo also carried a `qca-nss-drv` fix for raw-IP modems (accelerated LAN uploads left with a link-layer frame on, so every TCP download stopped after one window). It is now in kuncy7's tree as [kuncy7/nss-packages#5](https://github.com/kuncy7/nss-packages/pull/5), and moving the firmware's deliveries off the modem's CPU core is [kuncy7/openwrt-nss-edma#38](https://github.com/kuncy7/openwrt-nss-edma/pull/38).

## Credits

kuncy7 for the IPQ5018 NSS tree, Julius Bairaktaris for the generic raw-IP binding, and LS3434 and IceG for the D50 testing and modem work in the forum threads.

## Licence

The `umbim` patch is a change to OpenWrt and carries its licence (GPL-2.0). Everything else here is public domain.
