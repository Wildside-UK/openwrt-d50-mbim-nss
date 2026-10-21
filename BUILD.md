# Building

Tree: [kuncy7/openwrt-nss-edma](https://github.com/kuncy7/openwrt-nss-edma) at `900aedbd` (release `ipq50xx-2026.10.19`, OpenWrt main of 18 Oct 2026), feeds updated on 21 Oct 2026, profile `xunison_exigo-hub-d50-5g`.

Changes the tree needed on that date:

1. **The patch:** copy `patches/qca-nss-drv/0148-nss_rmnet_rx-unframe-accelerated-raw-ip-egress.patch` into `feeds/nss/qca-nss-drv/patches/`. It applies after the rest of the series. Pick the next free number if 0148 is taken by then.
2. **libffi:** OpenWrt moved `libffi` from the packages feed into core on 19 Oct (`openwrt/openwrt@9b835ec62`, `openwrt/packages@70ac3a844`). A core from 18 Oct with a later packages feed has it in neither, and `glib2` (pulled in by `mbim-utils`) fails to package with `missing dependencies: libffi.so.8`. Copy `package/libs/libffi/` from `9b835ec62` into the tree, or pin the packages feed to before `70ac3a844`.
3. **Only if you build an Image Builder (`CONFIG_IB=y`):** that compiles every board's DTB, and five ipq50xx boards reference `q6_wcss_pd*` labels the tree no longer defines (`cmcc_rax3000q`, `glinet_gl-x2000`, `linksys_mr2000`, `tplink_re700x`, `wallys_dr5018s`), so the image step fails. Comment out their `TARGET_DEVICES` lines in `target/linux/qualcommax/image/ipq50xx.mk`. A normal single-device build doesn't hit this.

For an Image Builder made this way, build the image from its own packages only, not the snapshot feeds: mixing in snapshot `procd`/`ucode` on top of an older base has broken Wi-Fi here before.

## Checking it worked

```
nss-status                                  # verdict: OFFLOAD ACTIVE, Wi-Fi: NSS offload active (wifili)
dmesg | grep 'raw-IP'                       # wwan0: raw-IP interface bound to rmnet_rx node N
cat /proc/sys/dev/nss/general/redirect      # 1
cat /sys/class/net/wwan0/statistics/rx_dropped   # stays put
grep rx_packets /sys/kernel/debug/qca-nss-drv/stats/rmnet_rx   # counts on the current node
```

Then a large download from a LAN client: without the patch it stops at about 41 KB.
