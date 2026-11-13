#!/usr/bin/env python3
"""Make patches/openwrt/0001 from a kuncy7 tree's ipq50xx.mk.
Usage: ci/gen-0001.py <tree-dir>   (writes the patch to stdout, leaves the tree clean)
Comments out the boards whose device trees reference labels the tree no longer
defines, and adds the NSS packages to the D50's DEVICE_PACKAGES. Exits 1 if
the D50 block isn't where it should be."""
import subprocess, sys
tree = sys.argv[1]
mk = "target/linux/qualcommax/image/ipq50xx.mk"
BROKEN = ["cmcc_rax3000q", "glinet_gl-x2000", "linksys_mr2000", "tplink_re700x", "wallys_dr5018s"]
EXTRA = """ \\
		kmod-qca-nss-ecm kmod-qca-nss-drv-igs kmod-qca-nss-drv-netlink \\
		kmod-qca-nss-drv-pppoe kmod-qca-nss-drv-qdisc kmod-qca-nss-drv-vlan-mgr \\
		kmod-qca8337-nss kmod-qca-dsa-nss kmod-rtl8367s-nss kmod-ifb \\
		nssinfo nss-tools-dwmac ethtool ip-full tc-full dumpimage \\
		sqm-scripts sqm-scripts-nss kmod-sched-cake iperf3"""
path = f"{tree}/{mk}"
s = open(path).read()
for d in BROKEN:
    s = s.replace(f"\nTARGET_DEVICES += {d}\n", f"\n# TARGET_DEVICES += {d}\n")
start = s.find("define Device/xunison_exigo-hub-d50-5g\n")
end = s.find("endef", start)
block = s[start:end]
if start < 0 or end < 0 or not block.rstrip().endswith("umbim"):
    sys.exit("D50 DEVICE_PACKAGES no longer ends with umbim: update ci/gen-0001.py by hand")
s = s[:start] + block.rstrip() + EXTRA + "\n" + s[end:]
open(path, "w").write(s)
try:
    sys.stdout.write(subprocess.run(["git", "-C", tree, "diff", "--", mk], check=True, capture_output=True, text=True).stdout)
finally:
    subprocess.run(["git", "-C", tree, "checkout", "--", mk], check=True)
