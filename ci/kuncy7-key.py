#!/usr/bin/env python3
"""Fetch the key kuncy7 signed a release's std package feed with.

kuncy7 signs each release's kmod feed with a new key, and the only place that
key is published is inside the release's own images (std group:
/etc/apk/keys/public-key.pem). Without it apk calls the feed UNTRUSTED and
ignores it, so `apk add kmod-...` finds nothing.

This reads the release tag from the feed list, takes the key IDs the feed is
signed with from its packages.adb, then opens std-group sysupgrade images from
that release until one carries a key with a matching ID, and writes it out.
No match = exit 1, so a build cannot ship without the key.

apk's key ID is the first 16 bytes of sha512 of the raw EC public point.

Usage: ci/kuncy7-key.py <distfeeds.list> <out-dir> <scratch-dir>
Writes <out-dir>/kuncy7-ipq50xx-<date>.pem
"""
import hashlib, os, zlib, re, shutil, subprocess, sys, tarfile, urllib.request

REPO = 'https://github.com/kuncy7/openwrt-nss-edma'
TRIES = 5

def die(msg):
    print(f'kuncy7-key: {msg}', file=sys.stderr)
    sys.exit(1)

def get(url, path=None):
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url, timeout=120) as r:
                data = r.read()
            break
        except Exception:
            if attempt == 2:
                raise
    if path:
        open(path, 'wb').write(data)
    return data

def sig_ids(adb):
    """Key IDs of the SIG blocks in an apk v3 .adb file."""
    if adb[:4] == b'ADBd':                   # whole file deflated (raw stream)
        adb = zlib.decompressobj(-15).decompress(adb[4:])
    elif adb[:4] == b'ADBc' and adb[4] == 1:  # ADBc + alg 1 (deflate) + level
        adb = zlib.decompressobj(-15).decompress(adb[6:])
    if adb[:4] != b'ADB.':
        die('packages.adb is not an ADB file')
    ids, off = [], 8
    while off + 4 <= len(adb):
        hdr = int.from_bytes(adb[off:off + 4], 'little')
        btype, size = hdr >> 30, hdr & 0x3fffffff
        if size < 4:
            break
        if btype == 1:                       # ADB_BLOCK_SIG: ver, hash_alg, id[16], sig
            ids.append(adb[off + 6:off + 22].hex())
        off += (size + 7) & ~7
    return ids

def key_id(pem_path):
    der = subprocess.run(['openssl', 'pkey', '-pubin', '-in', pem_path, '-outform', 'DER'],
                         check=True, capture_output=True).stdout
    return hashlib.sha512(der[-65:]).hexdigest()[:32]

def main():
    if len(sys.argv) != 4:
        die('usage: kuncy7-key.py <distfeeds.list> <out-dir> <scratch-dir>')
    feeds, out, tmp = sys.argv[1:]
    m = re.search(r'^(https://kuncy7\.github\.io/openwrt-nss-edma/(ipq50xx-(\d{4}\.\d\d\.\d\d))/std/)packages\.adb$',
                  open(feeds).read(), re.M)
    if not m:
        die(f'no kuncy7 std feed in {feeds}')
    base, tag, date = m.groups()
    os.makedirs(out, exist_ok=True)
    os.makedirs(tmp, exist_ok=True)

    want = sig_ids(get(base + 'packages.adb'))
    if not want:
        die(f'{tag} std feed has no signature')
    print(f'{tag} std feed signed by key id(s): {" ".join(want)}')

    info = get(f'{REPO}/releases/download/{tag}/config-std.buildinfo').decode()
    devices = re.findall(r'^CONFIG_TARGET_DEVICE_qualcommax_ipq50xx_DEVICE_(\S+)=y$', info, re.M)
    if not devices:
        die(f'{tag}: no std devices in config-std.buildinfo')

    for dev in devices[:TRIES]:
        img = os.path.join(tmp, 'k.bin')
        try:
            get(f'{REPO}/releases/download/{tag}/openwrt-qualcommax-ipq50xx-{dev}-squashfs-sysupgrade.bin', img)
        except Exception as e:
            print(f'  {dev}: no image ({e})')
            continue
        x = os.path.join(tmp, 'x')
        shutil.rmtree(x, ignore_errors=True)
        os.makedirs(x)
        with tarfile.open(img) as t:
            root = [n for n in t.getnames() if n.endswith('/root')]
            if not root:
                print(f'  {dev}: not a sysupgrade tar')
                continue
            t.extract(root[0], x, filter='data')
        r = subprocess.run(['unsquashfs', '-q', '-n', '-d', os.path.join(x, 'fs'), os.path.join(x, root[0]),
                            'etc/apk/keys/public-key.pem'], capture_output=True)
        pem = os.path.join(x, 'fs/etc/apk/keys/public-key.pem')
        if not os.path.isfile(pem):
            print(f'  {dev}: no etc/apk/keys/public-key.pem ({r.stderr.decode().strip()[:200]})')
            continue
        kid = key_id(pem)
        print(f'  {dev}: public-key.pem id {kid}')
        if kid in want:
            dest = os.path.join(out, f'kuncy7-ipq50xx-{date}.pem')
            shutil.copyfile(pem, dest)
            os.chmod(dest, 0o644)
            print(f'key for {tag} -> {dest}')
            return
    die(f'{tag}: no std image key matches the feed signature {" ".join(want)}')

main()
