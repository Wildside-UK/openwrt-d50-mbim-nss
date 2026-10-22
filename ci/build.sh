#!/bin/bash
# Build the D50 NSS image and its Image Builder from pinned sources.
# Usage: ci/build.sh <work-dir>
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(dirname "$HERE")
WORK=$1

TREE=https://github.com/kuncy7/openwrt-nss-edma.git
TREE_REV=9caa35b4d718382ad882cb35c2372dbb569de901   # release ipq50xx-2026.10.21
DEVICE=xunison_exigo-hub-d50-5g

if [ ! -d "$WORK/.git" ]; then
	git clone --filter=blob:none "$TREE" "$WORK"
fi
cd "$WORK"
git checkout -q "$TREE_REV"

echo "== feeds (pinned, see ci/feeds.conf)"
cp "$HERE/feeds.conf" feeds.conf
./scripts/feeds update -a
./scripts/feeds install -a

echo "== tree patches"
for p in "$REPO"/patches/openwrt/*.patch "$REPO"/patches/umbim/*.patch; do
	echo "   $(basename "$p")"
	git apply "$p"
done

echo "== package feed list on the router (kuncy7's feed first, kmods match this kernel)"
mkdir -p files/etc/apk/repositories.d
cp "$HERE/distfeeds.list" files/etc/apk/repositories.d/distfeeds.list

echo "== config"
cp "$HERE/diffconfig" .config
make defconfig
for p in kmod-qca-nss-drv kmod-qca-nss-ecm umbim kmod-mhi-wwan-mbim; do
	grep -qE "^CONFIG_PACKAGE_$p=[ym]" .config || { echo "missing $p"; exit 1; }
done
grep -q '^CONFIG_IB=y' .config

echo "== download"
make download -j8

echo "== build ($DEVICE only)"
if ! make -j$(($(nproc) + 1)) TARGET_DEVICES="$DEVICE"; then
	make -j1 V=s TARGET_DEVICES="$DEVICE" 2>&1 | tail -300
	exit 1
fi
ls -la bin/targets/qualcommax/ipq50xx/
