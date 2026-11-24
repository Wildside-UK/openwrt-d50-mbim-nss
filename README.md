# Xunison Exigo Hub D50 5G: NSS offload with the modem on PCIe/MBIM

Full NSS offload on the Xunison (Zearts) Exigo Hub D50 5G, with the Quectel RM500Q-AE on the upstream PCIe/MBIM stack (`mhi_wwan_mbim` + `umbim`, netdev `wwan0`).

The image is kuncy7's IPQ5018 NSS release ([kuncy7/openwrt-nss-edma](https://github.com/kuncy7/openwrt-nss-edma), `ipq50xx-2026.11.23`) built from his published config and feed pins. Since 11.18 his tree includes the `umbim` fix from [openwrt/openwrt#25946](https://github.com/openwrt/openwrt/pull/25946) (without it an MBIM connection comes up with no DNS servers), so this repository no longer carries its own copy.

On top of that the image has two extras for a cellular link: [unRAVEL](#unravel-upload-shaping) for upload shaping (installed, switched off) and [conwatch](#conwatch), a watchdog that brings the connection back when it dies. Without those two, the package list is identical to kuncy7's own D50 image.

## Downloads

Each release has:

- `...-squashfs-sysupgrade.bin`: flash over a running OpenWrt.
- `...-squashfs-factory.img`: for U-Boot web recovery.
- `openwrt-imagebuilder-...Linux-x86_64.tar.zst` and `...Linux-aarch64.tar.zst`: Image Builders for adding your own packages and config. They don't include unRAVEL or conwatch.
- `kuncy7-ipq50xx-2026.11.23.pem`: the key kuncy7 signed this release's kmod feed with. It's already in the images; if you build your own with an Image Builder, put it in `files/etc/apk/keys/` or `apk add kmod-...` won't trust the feed.
- `image-packages.txt` and `sha256sums`.

Kernel modules for this build come from kuncy7's repository for the same release, which the image already lists.

## What works

- `nss-status`: offload active, Wi-Fi offload (wifili) on both radios, ECM accelerating the modem flows.
- A marked improvement in download speed, limited by the cell rather than the router (NSS core load ~3%).
- The firmware's deliveries to the host go to the second CPU core, leaving the first to the modem (kuncy7's `nss-irq-affinity`, no script needed).
- DNS from the network on `wwan` by default; with `peerdns 0` the servers stay out of `resolv.conf.auto` and show as inactive in `ifstatus wwan`.

## Setting up the modem

Modem in PCIe mode (`AT+QCFG="data_interface",1,0`, then a reboot). Interface `proto mbim`, device `/dev/wwan0mbim0`, and your APN.

## unRAVEL (upload shaping)

[unRAVEL](https://github.com/Lochnair/unravel) by Lochnair changes the cake rate on `wwan0` as the cell's capacity moves, preventing uploads from filling the modem's buffers and increasing latency. The package is [unRAVEL-cellular](https://github.com/Wildside-UK/unravel-cellular) `0.5.0-rc1-cellular.5`, which is upstream unRAVEL plus one change (a separate learned-rate history per cell, off unless you set it up). The low-load cut cap, idle recovery and keeping what it's learned across a restart are all upstream.

It ships installed but not running because it needs one number from you. Set `upload_base_kbits` in `/etc/config/unravel` to the best upload speed your connection gets (it's 100000 to start with, which is likely too high for most cells), then:

```
/etc/init.d/unravel enable && /etc/init.d/unravel start
```

It only shapes the upload. Download is left alone (NSS should be left to manage downloads). `logread -e unravel` shows what it's doing.

## conwatch

conwatch watches the data path, not the modem. Every 30 s it checks that `wwan` is up and that 9.9.9.9, 149.112.112.11 or 1.1.1.1 answers a ping. After 4 failed checks in a row it runs `ifup wwan`, waits 2 minutes, tries once more, and if the connection still isn't back it reboots the router. At most 3 reboots, 30 minutes apart, then it just keeps trying `ifup`. The count resets after 6 hours of working connection. It does nothing in the first 5 minutes after boot, or while there's no interface called `wwan` (so a router whose modem isn't set up yet is left alone; if your setup has another name, set `IFACE` in `/etc/conwatch.conf`). It never touches the modem's AT port.

It's on by default in this image. `logread -e conwatch` shows what it's done. Settings are in `/etc/conwatch.conf`.

- Pause it (until the next reboot): `touch /tmp/conwatch.pause`
- Turn it off: `/etc/init.d/conwatch stop; /etc/init.d/conwatch disable`
- Watch without acting: `DRY_RUN=1` in `/etc/conwatch.conf`, then `/etc/init.d/conwatch restart`

## Image Update

System > Image Update in LuCI checks this repo for a newer release and flashes it when you press Update. It reads `latest.json` from the latest release, checks it's signed by the key in the image (`/etc/d50-update/keys/`), downloads the sysupgrade image, checks its size and sha256 and runs `sysupgrade -T` on it before it flashes. Settings are kept, the same as the stock Flash Firmware page.

Packages you've installed yourself aren't in the new image and will be removed. The page lists them before you update, their settings are kept so you can reinstall them after.

It only checks when you open the page, it never updates on its own. `logread -e d50-update` shows what it's done.

To use it with your own builds, change `manifest_url` in `/etc/config/d50-update` and put your public key in `/etc/d50-update/keys/` (usign or signify, named by its fingerprint). `d50-update/mkmanifest.sh` makes and signs the `latest.json`.

It's in the images from the release after `d50-ipq50xx-2026.11.11` on. Older images need flashing by hand once to get it.

## Things to know

- **Leave Wi-Fi offload on** (`nss.general.wifi_offload=1`). The modem path only works with `redirect=1`, and turning Wi-Fi offload off while `redirect=1` will crash the 2.4 GHz radio firmware (`crash detected in q6wcss`) within a minute or two.
- **Don't stop ECM to test without acceleration.** ECM sets `redirect` itself (`1` when it starts, `0` when it stops), the modem path needs `redirect=1`, and `/etc/init.d/qca-nss-ecm stop` takes a raw-IP modem offline. To take acceleration out of the picture, stop ECM's front ends instead: `echo 1 > /sys/kernel/debug/ecm/front_end_ipv4_stop` and, if you use IPv6, `echo 1 > /sys/kernel/debug/ecm/front_end_ipv6_stop` (`echo 0` to both to undo).
- **Upload shaping:** the NSS shaper only covers the Ethernet ports, not the modem, hence why the upload is shaped by unRAVEL with cake on `wwan0`. This works with NSS offload on.
- The "debugfs: 'rmnet_rx' already exists" warning after a re-connect is harmless.
- **One program at a time on the modem's AT port.** This image doesn't share out the modem's AT ports (`/dev/wwan0at0`, `/dev/ttyUSB2`, `/dev/ttyUSB3`). If you add things that talk to the modem, like the IceG modem apps, SMS tools or your own scripts using `sms_tool`, it's up to the user to make sure they don't use the same port at the same time. Two at once can leave the port not answering. On my device this has taken the data connection down until a reboot. modem-pcie-late only uses it once, early in boot, before anything else runs.

  On my own router I fixed it with a wrapper. `sms_tool` and `comgt` are replaced by a script that takes a lock for each port, so only one AT command runs on a port at a time and the rest queue (giving up after 60 s). Every command also gets a time limit, so one that hangs is killed and frees the port instead of holding it forever. The real ports are moved to `/dev/modem/` and the usual names become placeholders that can't be opened, so nothing reaches the modem except through the wrapper. I also moved everything onto the USB AT port (`/dev/ttyUSB2`), as `/dev/wwan0at0` stayed stuck until a reboot when two programs overlapped on it.

## History

On 21 Oct 2026 this repo also carried a `qca-nss-drv` fix for raw-IP modems (accelerated LAN uploads left with a link-layer frame on, so every TCP download stopped after one window). It is now in kuncy7's tree as [kuncy7/nss-packages#5](https://github.com/kuncy7/nss-packages/pull/5), and moving the firmware's deliveries off the modem's CPU core is [kuncy7/openwrt-nss-edma#38](https://github.com/kuncy7/openwrt-nss-edma/pull/38).

## Credits

kuncy7 for the IPQ5018 NSS tree, Julius Bairaktaris for the generic raw-IP binding, Lochnair for unRAVEL, and LS3434 and IceG for the D50 testing and modem work in the forum threads.

## Licence

The OpenWrt patches carry OpenWrt's licence (GPL-2.0). unRAVEL is MPL-2.0. Everything else here is public domain.
