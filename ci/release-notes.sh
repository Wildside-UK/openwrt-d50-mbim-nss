#!/bin/bash
# Release notes for the build in this repo, for its GitHub release and the bump PR.
# Generated: the title, the header and base lines from the pins, links to kuncy7's
# releases since the last published build, the umbim line, the line about the old
# package repository going and the flashing line. Hand-kept: the bullets under
# "## Unreleased" in CHANGES.md. kuncy7's own bullets are never copied in, most of
# them are for other boards.
# Usage: ci/release-notes.sh [<the built image's lib/apk/db/installed>] > release-notes.md
# The first line is the release title, the rest is the body. GH_TOKEN is used if set.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(dirname "$HERE")
R=${GITHUB_REPOSITORY:-Wildside-UK/openwrt-d50-mbim-nss}
K=kuncy7/openwrt-nss-edma
DB=${1:-}

api() { curl -fsSL ${GH_TOKEN:+-H "Authorization: Bearer $GH_TOKEN"} "https://api.github.com/$1"; }
short() { echo "${1#ipq50xx-????.}"; }
rel() { echo "https://github.com/$K/releases/tag/$1"; }

TAG=$(grep -oE 'ipq50xx-[0-9]{4}\.[0-9]{2}\.[0-9]{2}' "$HERE/distfeeds.list" | head -1)
[ -n "$TAG" ] || { echo "no kuncy7 tag in ci/distfeeds.list" >&2; exit 1; }
# the last published build (RELEASE_NOTES_SINCE=d50-ipq50xx-... to compare with another)
LAST=${RELEASE_NOTES_SINCE:-$(api "repos/$R/releases/latest" | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')}
LAST=${LAST#d50-}

# kuncy7's releases after the last published build, up to this one
SINCE=$(api "repos/$K/releases?per_page=100" | python3 -I -c '
import json,sys
last,tag=sys.argv[1],sys.argv[2]
t=sorted(r["tag_name"] for r in json.load(sys.stdin)
         if r["tag_name"].startswith("ipq50xx-") and last < r["tag_name"] <= tag)
print(" ".join(t))' "$LAST" "$TAG")

KERNEL=
if [ -n "$DB" ] && [ -r "$DB" ]; then
	KERNEL=$(awk '/^P:kernel$/{f=1} f&&/^V:/{sub(/^V:/,""); print; exit}' "$DB" | sed 's/[~-].*//')
fi

UNRELEASED=$(awk '/^## /{f=($0=="## Unreleased"); next} f&&/^- /' "$REPO/CHANGES.md")

echo "D50 NSS + MBIM, kuncy7 $TAG"
echo
if [ -d "$REPO/patches/umbim" ]; then
	echo "kuncy7's \`$TAG\` for the Xunison Exigo Hub D50 5G, built from his published config and feed pins, with the \`umbim\` DNS fix from openwrt/openwrt#25946 carried here until his tree has it."
else
	echo "kuncy7's \`$TAG\` for the Xunison Exigo Hub D50 5G, built from his published config and feed pins."
fi
echo
echo "**Changes since the $(short "$LAST") build**"
if [ "$LAST" != "$TAG" ]; then
	links=
	for t in $SINCE; do links="${links:+$links, }[$(short "$t")]($(rel "$t"))"; done
	echo "- Base moves to kuncy7's $(short "$TAG") release${KERNEL:+ (kernel $KERNEL)}. His release notes: ${links:-[$(short "$TAG")]($(rel "$TAG"))}."
fi
[ -z "$UNRELEASED" ] || printf '%s\n' "$UNRELEASED"
if [ "$LAST" != "$TAG" ]; then
	code=$(curl -s -o /dev/null -w '%{http_code}' "https://kuncy7.github.io/openwrt-nss-edma/$LAST/std/packages.adb" || true)
	if [ "$code" = 404 ]; then
		case $(short "$LAST") in 11.*|08.*) a=an;; *) a=a;; esac
		echo "- The $(short "$LAST") package repository is gone (kuncy7 only keeps recent ones), so on $a $(short "$LAST") image \`apk add kmod-...\` no longer works. Moving to this one fixes that."
	fi
fi
[ "$LAST" != "$TAG" ] || [ -n "$UNRELEASED" ] || echo "- Rebuilt, nothing changed."
echo
echo "**Flashing:** \`sysupgrade -n\` the sysupgrade image over a running OpenWrt, or use the factory image with U-Boot web recovery. Then set up the modem as in the README. From 11.23 on, System > Image Update in LuCI can do it for you and keeps your settings."
