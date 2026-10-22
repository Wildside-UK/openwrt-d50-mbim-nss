#!/bin/bash
# Check a build against what was tested on a D50, and that its Image Builder
# reproduces the image. Usage: ci/verify.sh <work-dir> <scratch-dir>
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(cd "$1" && pwd)
T=$2
B=$WORK/bin/targets/qualcommax/ipq50xx
U=$WORK/staging_dir/host/bin/unsquashfs4
OD=$(ls "$WORK"/staging_dir/toolchain-*/bin/aarch64-openwrt-linux-musl-objdump)
DEVICE=xunison_exigo-hub-d50-5g
KERNEL_HASH=b323c2a49a8ac532b429d3f653870279   # kuncy7's ipq50xx-2026.10.21 kernel
fail=0
bad() { echo "FAIL: $*"; fail=1; }

# unpack a sysupgrade image's root filesystem into $2/rootfs
unpack() {
	rm -rf "$2"; mkdir -p "$2"
	tar -xf "$1" -C "$2"
	# non-root: device nodes can't be created, which is the only error expected
	"$U" -q -d "$2/rootfs" "$2"/sysupgrade-*/root >/dev/null 2>&1 || true
	[ -s "$2/rootfs/lib/apk/db/installed" ] || { echo "FAIL: could not unpack $1"; exit 1; }
	grep '^P:' "$2/rootfs/lib/apk/db/installed" | sed 's/^P://' | sort > "$2/packages.txt"
}

unpack "$B"/*"$DEVICE"*sysupgrade.bin "$T/image"
R=$T/image/rootfs

echo "== packages ($(wc -l < "$T/image/packages.txt"))"
diff "$HERE/expected-packages.txt" "$T/image/packages.txt" || bad "package list differs from the tested image"

echo "== kernel"
v=$(awk '/^P:kernel$/{f=1} f&&/^V:/{print; exit}' "$R/lib/apk/db/installed")
echo "   $v"
case "$v" in *"$KERNEL_HASH"*) ;; *) bad "kernel hash is not $KERNEL_HASH" ;; esac

echo "== qca-nss-drv raw-IP egress fix"
n=$("$OD" -d --disassemble=nss_rmnet_rx_bind_xmit "$R/lib/modules/"*/qca-nss-drv.ko | grep -cE '^\s+[0-9a-f]+:')
echo "   nss_rmnet_rx_bind_xmit: $n instructions (12 without the fix)"
[ "$n" -gt 40 ] || bad "qca-nss-drv lacks the raw-IP egress fix"

echo "== umbim peer DNS"
grep -q proto_add_dns_server "$R/lib/netifd/proto/mbim.sh" || bad "mbim.sh does not register peer DNS"

echo "== package feeds on the router"
head -1 "$R/etc/apk/repositories.d/distfeeds.list"
grep -q '^https://kuncy7.github.io/' "$R/etc/apk/repositories.d/distfeeds.list" || bad "distfeeds.list lacks kuncy7's feed"

echo "== Image Builder reproduces the image"
mkdir -p "$T/ib"
tar --zstd -xf "$B"/openwrt-imagebuilder-*.tar.zst -C "$T/ib"
make -C "$T"/ib/openwrt-imagebuilder-* image PROFILE="$DEVICE" > "$T/ib.log" 2>&1 || { tail -40 "$T/ib.log"; bad "Image Builder failed"; }
unpack "$T"/ib/openwrt-imagebuilder-*/bin/targets/qualcommax/ipq50xx/*"$DEVICE"*sysupgrade.bin "$T/ibimage"
diff "$T/image/packages.txt" "$T/ibimage/packages.txt" || bad "Image Builder package set differs"
diff <(cd "$R" && find . | sort) <(cd "$T/ibimage/rootfs" && find . | sort) || bad "Image Builder file list differs"
cmp "$T"/image/sysupgrade-*/kernel "$T"/ibimage/sysupgrade-*/kernel || bad "Image Builder kernel differs"

[ "$fail" = 0 ] && echo "ALL CHECKS PASSED" || { echo "CHECKS FAILED"; exit 1; }
