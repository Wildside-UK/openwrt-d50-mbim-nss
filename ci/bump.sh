#!/bin/bash
# Move every pin to a kuncy7 release. Every value comes from the release
# itself; nothing is typed in by hand.
# Usage: ci/bump.sh <tag> <scratch-dir>      (needs gh, git, python3, unsquashfs)
# Exit 0 = pins moved (or already there), 3 = can't be done safely (reason on
# stderr, for an issue), anything else = a plain error.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(dirname "$HERE")
TAG=$1
T=$(mkdir -p "$2" && cd "$2" && pwd)
K=${KUNCY7_REPO:-kuncy7/openwrt-nss-edma}
DEVICE=xunison_exigo-hub-d50-5g
stop() { echo "BUMP STOPPED: $*" >&2; exit 3; }

OLD=$(grep -oE 'ipq50xx-[0-9]{4}\.[0-9]{2}\.[0-9]{2}' "$HERE/distfeeds.list" | head -1)
echo "== $OLD -> $TAG"
[ "$OLD" != "$TAG" ] || { echo "already on $TAG"; exit 0; }

echo "== tree revision from the release notes"
if [ -z "${BUMP_RELEASE_BODY:-}" ]; then
	BODY=$(gh release view "$TAG" -R "$K" --json body -q .body 2>/dev/null) || stop "release $TAG not found in $K"
else
	BODY=$BUMP_RELEASE_BODY
fi
SHORTS=$(printf '%s\n' "$BODY" | grep -oiE 'built from `[0-9a-f]{7,40}`' | grep -oE '[0-9a-f]{7,40}' | sort -u || true)
[ "$(printf '%s' "$SHORTS" | grep -c .)" = 1 ] || stop "release $TAG: no single 'built from \`<sha>\`' line in the notes (found: ${SHORTS:-none})"
REV=$(gh api "repos/$K/commits/$SHORTS" --jq .sha 2>/dev/null) || stop "release $TAG: $SHORTS does not resolve to one commit in $K"
echo "   $SHORTS -> $REV"

echo "== release files"
rm -rf "$T/rel"; mkdir -p "$T/rel"
gh release download "$TAG" -R "$K" -D "$T/rel" -p diffconfig-std.txt -p feeds-std.buildinfo -p "*$DEVICE*sysupgrade.bin" \
	|| stop "release $TAG: diffconfig-std.txt, feeds-std.buildinfo or the D50 sysupgrade image is missing"
for f in diffconfig-std.txt feeds-std.buildinfo; do [ -s "$T/rel/$f" ] || stop "release $TAG: $f is empty"; done

echo "== config and feeds"
OURS=$(sed -n '/^# --- added for the D50/,$p' "$HERE/diffconfig")
[ -n "$OURS" ] || stop "ci/diffconfig has no '# --- added for the D50' block"
{ cat "$T/rel/diffconfig-std.txt"; printf '%s\n' "$OURS"; } > "$HERE/diffconfig"
cp "$T/rel/feeds-std.buildinfo" "$HERE/feeds.conf"

echo "== kernel and package list from kuncy7's own D50 image"
rm -rf "$T/img"; mkdir -p "$T/img"
tar -xf "$T"/rel/*"$DEVICE"*sysupgrade.bin -C "$T/img"
unsquashfs -q -d "$T/img/rootfs" "$T"/img/sysupgrade-*/root >/dev/null 2>&1 || true
DB=$T/img/rootfs/lib/apk/db/installed
[ -s "$DB" ] || stop "release $TAG: could not unpack the D50 image"
KV=$(awk '/^P:kernel$/{f=1} f&&/^V:/{print; exit}' "$DB")
KH=$(printf '%s' "$KV" | grep -oE '~[0-9a-f]{32}-' | tr -d '~-')
[ -n "$KH" ] || stop "release $TAG: no kernel hash in '$KV'"
grep '^P:' "$DB" | sed 's/^P://' | LC_ALL=C sort > "$HERE/expected-packages.txt"
echo "   $KV, $(wc -l < "$HERE/expected-packages.txt") packages"

echo "== pins"
sed -i "s|^TREE_REV=.*|TREE_REV=$REV   # release $TAG|" "$HERE/build.sh"
sed -i "s|^KERNEL_HASH=.*|KERNEL_HASH=$KH   # kuncy7's $TAG kernel|" "$HERE/verify.sh"
sed -i "s|$OLD|$TAG|g" "$HERE/distfeeds.list"
grep -q "/$TAG/std/" "$HERE/distfeeds.list" || stop "ci/distfeeds.list did not take $TAG"

echo "== tree and patches"
if [ ! -d "$T/tree/.git" ]; then git clone -q --filter=blob:none "https://github.com/$K.git" "$T/tree"; fi
git -C "$T/tree" fetch -q origin "$REV"
git -C "$T/tree" checkout -q -f "$REV"
python3 "$HERE/gen-0001.py" "$T/tree" > "$T/0001.patch" || stop "patches/openwrt/0001 can't be made for $TAG (see the message above)"
[ -s "$T/0001.patch" ] || stop "patches/openwrt/0001 came out empty for $TAG"
cp "$T/0001.patch" "$REPO/patches/openwrt/0001-ipq50xx-d50-nss-device-packages.patch"
UMBIM_DROPPED=
if grep -q proto_add_dns_server "$T/tree/package/network/utils/umbim/files/lib/netifd/proto/mbim.sh" 2>/dev/null; then
	echo "   $TAG's mbim.sh already registers peer DNS (openwrt/openwrt#25946): dropping patches/umbim"
	git -C "$REPO" rm -q -r patches/umbim
	UMBIM_DROPPED=1
fi
for p in "$REPO"/patches/openwrt/*.patch "$REPO"/patches/umbim/*.patch; do
	[ -e "$p" ] || continue
	git -C "$T/tree" apply --check "$p" 2>"$T/apply.err" || stop "$(basename "$p") no longer applies to $TAG: $(head -3 "$T/apply.err" | tr '\n' ' ')"
	git -C "$T/tree" apply "$p"
done
git -C "$T/tree" checkout -q -f "$REV"; git -C "$T/tree" clean -fdq

echo "== text (pin swaps only)"
sed -i "s|$OLD|$TAG|g" "$REPO/README.md" "$REPO/BUILD.md"
OLDREV=$(grep -oE 'kuncy7/openwrt-nss-edma at `[0-9a-f]{10}`' "$REPO/BUILD.md" | grep -oE '[0-9a-f]{10}' || true)
[ -z "$OLDREV" ] || sed -i "s|at \`$OLDREV\`|at \`${REV:0:10}\`|" "$REPO/BUILD.md"
O=${OLD#ipq50xx-????.}; N=${TAG#ipq50xx-????.}
sed -i -E "s/kuncy7's $O (D50 image|kernel)/kuncy7's $N \1/g" "$REPO/BUILD.md"

{
	echo "TAG=$TAG"; echo "OLD=$OLD"; echo "REV=$REV"; echo "KERNEL=$KV"
	echo "UMBIM_DROPPED=$UMBIM_DROPPED"
	echo "PACKAGES_DIFF<<EOF"; git -C "$REPO" diff -U0 -- ci/expected-packages.txt | grep '^[-+][^-+]' || echo "(none)"; echo "EOF"
	echo "TEXT_LEFT<<EOF"; grep -nE "\b${O//./\\.}\b" "$REPO/README.md" "$REPO/BUILD.md" || echo "(none)"; echo "EOF"
} > "$T/summary.txt"
echo "== done"; cat "$T/summary.txt"
