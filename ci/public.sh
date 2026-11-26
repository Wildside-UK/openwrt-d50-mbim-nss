#!/bin/bash
# Make the published image: the Image Builder from this build, plus unRAVEL
# (installed, not running), conwatch, modem-pcie-late, System > Image Update
# (d50-update/), LuCI, and adblock-lean (on, set up on the first uplink by
# public/files/etc/hotplug.d/iface/96-adblock-lean) with luci-app-adblock-lean. The plain image and both Image
# Builders stay as built. Usage: ci/public.sh <work-dir> <scratch-dir> <out-dir>
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(dirname "$HERE")
WORK=$(cd "$1" && pwd)
T=$(mkdir -p "$2" && cd "$2" && pwd)
OUT=$(mkdir -p "$3" && cd "$3" && pwd)
B=$WORK/bin/targets/qualcommax/ipq50xx
U=$WORK/staging_dir/host/bin/unsquashfs4
DEVICE=xunison_exigo-hub-d50-5g
UNRAVEL_URL=https://github.com/Wildside-UK/unravel-cellular/releases/download/v0.5.0-rc1-cellular.5/unravel-cellular-0.5.0_rc1_p5-r1.apk
UNRAVEL_SHA256=34ca16c0af7a378d0c6f484476d56d60dd5e5c9652976eaab82c685f564350bf
# adblock-lean is not an OpenWrt package: its files at the release tag, version stamped the
# way its installer does it, plus the md5 registry its installer writes.
ABL_VER=0.8.1
ABL_URL=https://raw.githubusercontent.com/lynxthecat/adblock-lean/v$ABL_VER
ABL_FILES="adblock-lean:76f932cdf29d568b32949acb828b8b46e23d72dd516ac5d65c2a789e8e932960
usr/lib/adblock-lean/abl-lib.sh:24087cbb9bc6f433db4461e31d837f48cae97f0a4033db870db38b9a68f2aff7
usr/lib/adblock-lean/abl-process.sh:59f609cd83c26b1c0532b132163fbe759dc919cac0c293f3e4c24fe644e68649"
LUCI_ABL_APK=luci-app-adblock-lean-0.1.0-r1.apk
LUCI_ABL_URL=https://raw.githubusercontent.com/Wildside-UK/luci-app-adblock-lean/4aa149c8babe08fe5f9453b9e8881785c4b1d5a2/apk/$LUCI_ABL_APK
LUCI_ABL_SHA256=92bf0b9c2591d9f57926ebec309c0028477709d5e174d61c202dc118d58092cc
EXTRA_PKGS="unravel-cellular sms-tool kmod-usb-serial-option luci luci-app-adblock-lean gawk sed coreutils-sort"
fail=0
bad() { echo "FAIL: $*"; fail=1; }

echo "== unRAVEL package"
mkdir -p "$T/pub"
wget -q -O "$T/pub/unravel-cellular.apk" "$UNRAVEL_URL"
echo "$UNRAVEL_SHA256  $T/pub/unravel-cellular.apk" | sha256sum -c -

echo "== adblock-lean $ABL_VER and luci-app-adblock-lean"
mkdir -p "$T/pub/abl"
echo "$ABL_FILES" | while IFS=: read -r f sum; do
	wget -q -O "$T/pub/abl/${f##*/}" "$ABL_URL/$f"
	echo "$sum  $T/pub/abl/${f##*/}" | sha256sum -c -
done
wget -q -O "$T/pub/$LUCI_ABL_APK" "$LUCI_ABL_URL"
echo "$LUCI_ABL_SHA256  $T/pub/$LUCI_ABL_APK" | sha256sum -c -

echo "== Image Builder"
tar --zstd -xf "$B"/openwrt-imagebuilder-*.tar.zst -C "$T/pub"
IB=$(echo "$T"/pub/openwrt-imagebuilder-*)
cp "$T/pub/unravel-cellular.apk" "$IB/packages/unravel-cellular-0.5.0_rc1_p5-r1.apk"
cp "$T/pub/$LUCI_ABL_APK" "$IB/packages/"
# public/files plus the build's own files/ (feed list and kuncy7's feed key)
rm -rf "$T/pub/files"; mkdir -p "$T/pub/files"
cp -a "$WORK/files/." "$T/pub/files/"
cp -a "$REPO/public/files/." "$T/pub/files/"
# adblock-lean, laid out as its installer leaves it
F=$T/pub/files
install -D -m 755 "$T/pub/abl/adblock-lean" "$F/etc/init.d/adblock-lean"
sed -i "/^\s*ABL_VERSION\s*=/{s/.*/ABL_VERSION=\"$ABL_VER\"/;}; /^\s*ABL_UPD_CHANNEL\s*=/{s/.*/ABL_UPD_CHANNEL=\"release\"/;}" "$F/etc/init.d/adblock-lean"
install -D -m 644 "$T/pub/abl/abl-lib.sh" "$F/usr/lib/adblock-lean/abl-lib.sh"
install -D -m 644 "$T/pub/abl/abl-process.sh" "$F/usr/lib/adblock-lean/abl-process.sh"
(cd "$F" && md5sum etc/init.d/adblock-lean usr/lib/adblock-lean/abl-lib.sh usr/lib/adblock-lean/abl-process.sh) \
	| sed 's|  |  /|' > "$F/etc/adblock-lean/abl-reg.md5"
cp -a "$REPO/modem-pcie-late/files/." "$T/pub/files/"
# System > Image Update: the page, and /etc/d50-build naming this image the way its
# latest.json will (release tag + commit, commit time), written to $T for the signing step
cp -a "$REPO/d50-update/files/." "$T/pub/files/"
KTAG=$(grep -oE 'ipq50xx-[0-9]{4}\.[0-9]{2}\.[0-9]{2}' "$HERE/distfeeds.list" | head -1)
[ -n "$KTAG" ] || { echo "FAIL: no kuncy7 tag in ci/distfeeds.list"; exit 1; }
printf 'BUILD=d50-%s+%s\nSEQ=%s\n' "$KTAG" "$(git -C "$REPO" rev-parse --short=7 HEAD)" "$(git -C "$REPO" log -1 --format=%ct)" \
	> "$T/pub/files/etc/d50-build"
cp "$T/pub/files/etc/d50-build" "$T/d50-build"
make -C "$IB" image PROFILE="$DEVICE" PACKAGES="$EXTRA_PKGS" \
	FILES="$T/pub/files" DISABLED_SERVICES="unravel" BIN_DIR="$T/pub/bin" > "$T/pub/ib.log" 2>&1 \
	|| { tail -60 "$T/pub/ib.log"; exit 1; }

echo "== checks"
rm -rf "$T/pub/x"; mkdir -p "$T/pub/x"
tar -xf "$T"/pub/bin/*"$DEVICE"*sysupgrade.bin -C "$T/pub/x"
"$U" -q -d "$T/pub/x/rootfs" "$T"/pub/x/sysupgrade-*/root >/dev/null 2>&1 || true
R=$T/pub/x/rootfs
[ -s "$R/lib/apk/db/installed" ] || { echo "FAIL: could not unpack the image"; exit 1; }
grep '^P:' "$R/lib/apk/db/installed" | sed 's/^P://' | LC_ALL=C sort > "$T/pub/packages.txt"
# extras: unravel-cellular, sms-tool + the USB serial driver for modem-pcie-late, LuCI,
# luci-app-adblock-lean and the tools adblock-lean recommends; ci/public-extra-packages.txt
# lists them with their dependencies
diff <(cat "$HERE/expected-packages.txt" "$HERE/public-extra-packages.txt" | LC_ALL=C sort -u) "$T/pub/packages.txt" \
	|| bad "package list is not the plain image's plus ci/public-extra-packages.txt"
# ci/verify.sh unpacked the plain image into $T/image
cmp "$T"/pub/x/sysupgrade-*/kernel "$T"/image/sysupgrade-*/kernel || bad "kernel differs from the plain image"
ls "$R"/etc/rc.d/ | grep -q "^S.*unravel" && bad "unravel is enabled"
[ -x "$R/usr/sbin/unravel" ] || bad "no /usr/sbin/unravel"
grep -q "option upload_base_kbits '100000'" "$R/etc/config/unravel" || bad "unravel config is not ours"
grep -q history_key_file "$R/etc/config/unravel" && bad "unravel config has history_key_file"
for f in usr/sbin/conwatch.sh etc/init.d/conwatch etc/uci-defaults/99-conwatch; do
	[ -x "$R/$f" ] || bad "$f missing or not executable"
done
grep -q '^DRY_RUN=0' "$R/etc/conwatch.conf" || bad "conwatch is not live"
for f in usr/sbin/modem-pcie-late.sh etc/init.d/modem-pcie-late etc/uci-defaults/98-modem-pcie-late; do
	[ -x "$R/$f" ] || bad "$f missing or not executable"
done
# openwrt/openwrt#26762's modem_pcie_recover does the same job: never ship both
[ -z "$(find "$R/etc" -name '*modem_pcie_recover*' | head -1)" ] || bad "modem_pcie_recover (PR 26762) is in the tree too"
[ -x "$R/usr/libexec/rpcd/d50-update" ] && [ -f "$R/www/luci-static/resources/view/system/d50-update.js" ] \
	|| bad "Image Update page missing"
cmp "$R/etc/d50-build" "$T/d50-build" || bad "/etc/d50-build differs"
grep -q "releases/latest/download/latest.json" "$R/etc/config/d50-update" || bad "d50-update config is not the public one"
ls "$R"/etc/d50-update/keys/* >/dev/null 2>&1 || bad "no Image Update signing key"
# LuCI and adblock-lean
[ -x "$R/etc/init.d/uhttpd" ] && [ -f "$R/www/luci-static/resources/luci.js" ] || bad "LuCI missing"
[ -x "$R/etc/init.d/adblock-lean" ] || bad "adblock-lean missing or not executable"
grep -q "^ABL_VERSION=\"$ABL_VER\"\$" "$R/etc/init.d/adblock-lean" && grep -q '^ABL_UPD_CHANNEL="release"$' "$R/etc/init.d/adblock-lean" \
	|| bad "adblock-lean version not stamped"
(cd "$R" && sed 's|  /|  |' etc/adblock-lean/abl-reg.md5 | md5sum -c --quiet -) || bad "adblock-lean md5 registry does not match its files"
[ -f "$R/etc/adblock-lean/.first-setup" ] && [ ! -e "$R/etc/adblock-lean/config" ] || bad "adblock-lean first-setup marker missing or a config is baked in"
[ -x "$R/etc/hotplug.d/iface/96-adblock-lean" ] || bad "96-adblock-lean missing or not executable"
grep -qx '/etc/adblock-lean/' "$R/lib/upgrade/keep.d/adblock-lean" || bad "adblock-lean config not kept over sysupgrade"
[ -x "$R/usr/libexec/rpcd/luci.adblock-lean" ] && [ -f "$R/www/luci-static/resources/view/adblock-lean/overview.js" ] \
	|| bad "luci-app-adblock-lean missing"
[ -f "$R/etc/apk/keys/wildside-uk.pem" ] && [ -f "$R/etc/apk/keys/wildside-uk-backup.pem" ] \
	&& grep -q 'luci-app-adblock-lean/refs/heads/main/apk/packages.adb' "$R/etc/apk/repositories.d/customfeeds.list" \
	|| bad "luci-app-adblock-lean repository or keys missing"
grep -q proto_add_dns_server "$R/lib/netifd/proto/mbim.sh" || bad "mbim.sh does not register peer DNS"
grep -q '^https://kuncy7.github.io/' "$R/etc/apk/repositories.d/distfeeds.list" || bad "distfeeds.list lacks kuncy7's feed"
cmp "$R"/etc/apk/keys/kuncy7-ipq50xx-*.pem "$WORK"/files/etc/apk/keys/kuncy7-ipq50xx-*.pem || bad "kuncy7 feed key missing or differs"
out=$("$WORK/staging_dir/host/bin/apk" --keys-dir "$R/etc/apk/keys" adbdump "$T/kuncy7-std.adb" 2>&1 | grep '^# sig' | sed 's/\(# sig v.. h.. [0-9a-f]\{32\}\)[0-9a-f.]*/\1/' || true)
echo "kuncy7 feed with the published image's keys: $out"
echo "$out" | grep -q ': OK$' || bad "kuncy7's feed is not trusted by the published image's keys"

mkdir -p "$OUT"
cp "$T"/pub/bin/*"$DEVICE"*sysupgrade.bin "$T"/pub/bin/*"$DEVICE"*factory.img "$OUT/"
cp "$T/pub/packages.txt" "$OUT/image-packages.txt"
[ "$fail" = 0 ] && echo "PUBLIC IMAGE CHECKS PASSED" || { echo "PUBLIC IMAGE CHECKS FAILED"; exit 1; }
