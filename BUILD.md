# Building

`ci/build.sh` builds the image and its Image Builder from pinned sources, and GitHub Actions runs it on every push to `ci` (`.github/workflows/build.yml`), once on x86_64 and once on arm64.

- **Tree:** kuncy7/openwrt-nss-edma at `ade890c346` (release `ipq50xx-2026.11.24`).
- **Config and feeds:** kuncy7's published `diffconfig-std.txt` and `feeds-std.buildinfo` for that release (`ci/diffconfig`, `ci/feeds.conf`), plus the Image Builder and the optional packages it needs.
- **Patches:**
  - `patches/openwrt/0001`: the NSS packages (and kuncy7's sqm/iperf3 set) in the D50's `DEVICE_PACKAGES`, so the Image Builder's default image matches the build's own. It also comments out five boards (cmcc_rax3000q, glinet_gl-x2000, linksys_mr2000, tplink_re700x, wallys_dr5018s) whose device trees reference labels the tree no longer defines, which an Image Builder build would otherwise trip over. Still the case in 11.11.
  - `patches/openwrt/0002`: `base-files` takes `distfeeds.list` from `files/`, so images made with the Image Builder also point `apk` at kuncy7's feed, whose kernel modules match this kernel.

- **Published image:** `ci/public.sh` runs the Image Builder from the same build once more with the extras in the README: the unRAVEL-cellular package (fetched from its GitHub release, sha256 checked) installed but not enabled, with the config in `public/files/etc/config/unravel`; conwatch, enabled; modem-pcie-late (`modem-pcie-late/`, with `sms-tool` and the USB serial driver); System > Image Update (`d50-update/`); LuCI; and adblock-lean (its pinned upstream files, sha256 checked) with luci-app-adblock-lean from its signed apk repository. `ci/public-extra-packages.txt` lists the packages it adds. Only that image is published. The plain image is built and checked but not shipped, and both Image Builders stay as built (without any of these).

To build locally: `ci/build.sh <work-dir>` on a normal OpenWrt build host.

## Checks

`ci/verify.sh` fails the build unless:

- the image's package list equals `ci/expected-packages.txt` (kuncy7's 11.24 D50 image),
- the kernel is kuncy7's 11.24 kernel,
- `qca-nss-drv` carries the raw-IP egress fix,
- `mbim.sh` registers the peer DNS,
- the package feeds point at kuncy7's repository,
- and the Image Builder reproduces the image (same packages, same files, same kernel).

`ci/public.sh` then fails the build unless the published image has the plain image's packages plus `ci/public-extra-packages.txt`, the same kernel, unRAVEL installed but not enabled with our config, conwatch present and live, modem-pcie-late, the Image Update page with its signing key, LuCI, adblock-lean with its first-setup marker and luci-app-adblock-lean, the peer DNS fix and kuncy7's feed.

## Releasing

Each build's files include `release-notes.md` from `ci/release-notes.sh`: the title on the first line, then the notes. The header, the base line with links to kuncy7's releases since the last published build, the umbim line, the old package repository line and the flashing line are generated; the rest is the Unreleased bullets in `CHANGES.md`, so add one there with each change. The same notes go in the bump PR. Releases are named `d50-<kuncy7 tag>`, and `latest.json` in the build's files already points at that name.

When a release is published, rename Unreleased in `CHANGES.md` to its tag, put the generated lines from its notes under it, and start a new empty Unreleased.

## Checking a flashed router

```
nss-status                                       # offload active, Wi-Fi: NSS offload active (wifili)
dmesg | grep 'raw-IP'                            # wwan0: raw-IP interface bound to rmnet_rx node N
cat /proc/sys/dev/nss/general/redirect           # 1
cat /sys/class/net/wwan0/statistics/rx_dropped   # stays put
ifstatus wwan | jsonfilter -e '@["dns-server"]'  # the network's DNS servers
pgrep -f conwatch.sh; logread -e conwatch        # running, "started: dry_run=0 ..."
/etc/init.d/unravel enabled || echo off          # off until you enable it
```
