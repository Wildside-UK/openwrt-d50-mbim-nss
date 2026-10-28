# Building

`ci/build.sh` builds the image and its Image Builder from pinned sources, and GitHub Actions runs it on every push to `ci` (`.github/workflows/build.yml`), once on x86_64 and once on arm64.

- **Tree:** kuncy7/openwrt-nss-edma at `70e98fd027` (release `ipq50xx-2026.10.28`).
- **Config and feeds:** kuncy7's published `diffconfig-std.txt` and `feeds-std.buildinfo` for that release (`ci/diffconfig`, `ci/feeds.conf`), plus the Image Builder and the optional packages it needs.
- **Patches:**
  - `patches/umbim/0001`: openwrt/openwrt#25946, the network's DNS servers registered as peer DNS.
  - `patches/openwrt/0001`: the NSS packages (and kuncy7's sqm/iperf3 set) in the D50's `DEVICE_PACKAGES`, so the Image Builder's default image matches the build's own. It also comments out five boards whose device trees reference labels the tree no longer defines, which an Image Builder build would otherwise trip over.
  - `patches/openwrt/0002`: `base-files` takes `distfeeds.list` from `files/`, so images made with the Image Builder also point `apk` at kuncy7's feed, whose kernel modules match this kernel.

To build locally: `ci/build.sh <work-dir>` on a normal OpenWrt build host.

## Checks

`ci/verify.sh` fails the build unless:

- the image's package list equals `ci/expected-packages.txt` (kuncy7's 10.28 D50 image),
- the kernel is kuncy7's 10.28 kernel,
- `qca-nss-drv` carries the raw-IP egress fix,
- `mbim.sh` registers the peer DNS,
- the package feeds point at kuncy7's repository,
- and the Image Builder reproduces the image (same packages, same files, same kernel).

## Checking a flashed router

```
nss-status                                       # offload active, Wi-Fi: NSS offload active (wifili)
dmesg | grep 'raw-IP'                            # wwan0: raw-IP interface bound to rmnet_rx node N
cat /proc/sys/dev/nss/general/redirect           # 1
cat /sys/class/net/wwan0/statistics/rx_dropped   # stays put
ifstatus wwan | jsonfilter -e '@["dns-server"]'  # the network's DNS servers
```
