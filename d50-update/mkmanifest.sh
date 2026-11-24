#!/bin/bash
# Write and sign latest.json for an image, for System > Image Update on the router.
# Usage: mkmanifest.sh <sysupgrade.bin> <build> <seq> <secret-key> <out-dir> [image-url] [base] [notes] [packages]
#   build      the image's name, the same string the image carries as BUILD= in /etc/d50-build
#   seq        build time in unix seconds (SEQ= in /etc/d50-build)
#   image-url  where the router downloads the image; default: the file name, next to latest.json
#   packages   file name or URL of the image's package list (one name per line), optional
# Signs with signify-openbsd or usign, whichever is installed (same key format).
set -euo pipefail
[ $# -ge 5 ] || { sed -n '3,8p' "$0"; exit 2; }
IMG=$1 BUILD=$2 SEQ=$3 KEY=$4 OUT=$5 URL=${6:-$(basename "$1")} BASE=${7:-} NOTES=${8:-} PKGS=${9:-}
mkdir -p "$OUT"
jq -n --arg build "$BUILD" --argjson seq "$SEQ" --arg image "$URL" \
	--arg sha256 "$(sha256sum "$IMG" | cut -d' ' -f1)" --argjson size "$(stat -c %s "$IMG")" \
	--arg base "$BASE" --arg notes "$NOTES" --arg packages "$PKGS" \
	'{build: $build, seq: $seq, image: $image, sha256: $sha256, size: $size}
	 + (if $base != "" then {base: $base} else {} end)
	 + (if $notes != "" then {notes: $notes} else {} end)
	 + (if $packages != "" then {packages: $packages} else {} end)' > "$OUT/latest.json"
if command -v signify-openbsd >/dev/null; then
	signify-openbsd -S -s "$KEY" -m "$OUT/latest.json" -x "$OUT/latest.json.sig"
else
	usign -S -s "$KEY" -m "$OUT/latest.json" -x "$OUT/latest.json.sig"
fi
echo "$OUT/latest.json: $BUILD"
