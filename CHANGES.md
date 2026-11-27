# Changes

What changed in each published build. With each change, add a bullet under Unreleased. `ci/release-notes.sh` puts them in the next release's notes, after the generated base line. When that release is published, rename Unreleased to its tag and start a new empty Unreleased above it.

## Unreleased

- New: LuCI, the web interface. Browse to the router's address.
- New: adblock-lean 0.8.1 ad blocking, on. It sets itself up the first time the router gets a connection: Hagezi Pro plus Threat Intelligence Feeds medium, updated daily at 05:00. Services > Adblock-lean in LuCI (luci-app-adblock-lean) shows what's blocked and edits the lists. Your adblock-lean settings are kept over a sysupgrade. See the README.
- Fixed: System > Image Update showed empty lines where the "up to date" and package lines should be.

## d50-ipq50xx-2026.11.23

kuncy7's `ipq50xx-2026.11.23` for the Xunison Exigo Hub D50 5G, built from his published config and feed pins. The `umbim` DNS fix (openwrt/openwrt#25946) is in his tree now, so it's no longer carried here.

- Base moves to kuncy7's 11.23 release (OpenWrt main of 18 Nov, kernel 6.18.60). From OpenWrt: a fix to the IPQ5018's MDIO clocks and resets, upstream Wi-Fi driver fixes, and mac80211 and hostapd fixes.
- From kuncy7's release: the NSS firmware version and memory profile are now chosen when the router starts instead of being fixed in the build. Both 12.5-210 and 12.2-156 are in the image, the D50 boots 12.5-210 by default.
- New: System > Image Update in LuCI. It checks this repo for a newer release and flashes it when you press Update, keeping your settings. This release has to be flashed by hand, later ones can be done from that page. See the README.
- New: modem-pcie-late. After a U-Boot web-recovery install the modem often misses PCIe on the first boot, this brings it back without a reboot. It adds `sms-tool` and the USB serial driver to the image. See modem-pcie-late/README.md.
- The 11.11 package repository is gone (kuncy7 keeps the newest 3 releases), so on an 11.11 image `apk add kmod-...` no longer works. Moving to this one fixes that.

## d50-ipq50xx-2026.11.11

kuncy7's `ipq50xx-2026.11.11` for the Xunison Exigo Hub D50 5G, built from his published config and feed pins, with the `umbim` DNS fix from openwrt/openwrt#25946. That fix was merged into OpenWrt on 12 Nov, the day after kuncy7's release, so it's still carried here until his tree has it.

- Base moves to kuncy7's 11.11 release (OpenWrt main of 5 Nov, kernel 6.18.60, NSS firmware 12.5-210).
- From kuncy7's release: the Wi-Fi transmit rate no longer drops to 6 Mbit/s for idle clients in `iw` and LuCI, and a LAN port that linked up just as the NSS firmware took over the Ethernet controller can no longer leave every LAN port dead until a reboot.
- New: unRAVEL upload shaping (unRAVEL-cellular 0.5.0-rc1-cellular.5), installed but switched off. Set `upload_base_kbits` in `/etc/config/unravel` to your best upload speed, then `/etc/init.d/unravel enable && /etc/init.d/unravel start`. See the README.
- New: conwatch, on. If the connection dies it runs `ifup wwan` twice, then reboots the router, at most 3 times in a row and 30 minutes apart. Pause it with `touch /tmp/conwatch.pause`, turn it off with `/etc/init.d/conwatch disable`. See the README.
- The 10.28 package repository is gone (kuncy7 keeps the newest 3 releases), so on a 10.28 image `apk add kmod-...` no longer works. Moving to this one fixes that.
