#!/bin/bash
# Make the published image: the Image Builder from this build, plus unRAVEL
# (installed, not running) and conwatch. The plain image and both Image
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
fail=0
bad() { echo "FAIL: $*"; fail=1; }

echo "== unRAVEL package"
mkdir -p "$T/pub"
wget -q -O "$T/pub/unravel-cellular.apk" "$UNRAVEL_URL"
echo "$UNRAVEL_SHA256  $T/pub/unravel-cellular.apk" | sha256sum -c -

echo "== Image Builder"
tar --zstd -xf "$B"/openwrt-imagebuilder-*.tar.zst -C "$T/pub"
IB=$(echo "$T"/pub/openwrt-imagebuilder-*)
cp "$T/pub/unravel-cellular.apk" "$IB/packages/unravel-cellular-0.5.0_rc1_p5-r1.apk"
make -C "$IB" image PROFILE="$DEVICE" PACKAGES="unravel-cellular" \
	FILES="$REPO/public/files" DISABLED_SERVICES="unravel" BIN_DIR="$T/pub/bin" > "$T/pub/ib.log" 2>&1 \
	|| { tail -60 "$T/pub/ib.log"; exit 1; }

echo "== checks"
rm -rf "$T/pub/x"; mkdir -p "$T/pub/x"
tar -xf "$T"/pub/bin/*"$DEVICE"*sysupgrade.bin -C "$T/pub/x"
"$U" -q -d "$T/pub/x/rootfs" "$T"/pub/x/sysupgrade-*/root >/dev/null 2>&1 || true
R=$T/pub/x/rootfs
[ -s "$R/lib/apk/db/installed" ] || { echo "FAIL: could not unpack the image"; exit 1; }
grep '^P:' "$R/lib/apk/db/installed" | sed 's/^P://' | LC_ALL=C sort > "$T/pub/packages.txt"
diff <( (cat "$HERE/expected-packages.txt"; echo unravel-cellular) | LC_ALL=C sort) "$T/pub/packages.txt" \
	|| bad "package list is not the plain image's plus unravel-cellular"
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
grep -q proto_add_dns_server "$R/lib/netifd/proto/mbim.sh" || bad "mbim.sh does not register peer DNS"
grep -q '^https://kuncy7.github.io/' "$R/etc/apk/repositories.d/distfeeds.list" || bad "distfeeds.list lacks kuncy7's feed"

mkdir -p "$OUT"
cp "$T"/pub/bin/*"$DEVICE"*sysupgrade.bin "$T"/pub/bin/*"$DEVICE"*factory.img "$OUT/"
cp "$T/pub/packages.txt" "$OUT/image-packages.txt"
[ "$fail" = 0 ] && echo "PUBLIC IMAGE CHECKS PASSED" || { echo "PUBLIC IMAGE CHECKS FAILED"; exit 1; }
