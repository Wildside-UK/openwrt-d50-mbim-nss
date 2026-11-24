# modem-pcie-late

A boot script that brings the D50's modem back onto PCIe when it misses the link at boot.

## The problem

After a U-Boot web-recovery install the first boot often doesn't see the modem (`80000000.pcie: Device not found`, no `0001:01:00.0`). It misses aound 70% of the time on web-recovery installs. A reboot fixes it, and normal reboots and cold power-ons are fine.

The kernel only waits about 1 s for the modem link at probe and doesn't look again. On a miss the modem is up on USB but the PCIe link never trains by itself, a late rescan on its own doesn't help. Restarting the modem over its USB AT port (`AT+CFUN=1,1`, Quectel's soft reset, no power cut) brings the link up within 2 s and a rescan then finds it. More detail in the [forum thread](https://forum.openwrt.org/t/adding-support-for-xunison-exigo-d50-5g-zearts-d50-5g-ipq5018/247016/584).

## What it does

It runs early in boot (`S11`, before `modem-at` and `network`), so everything after it sees the modem as on a normal boot.

- Modem on PCIe at boot: does nothing.
- Modem missing: waits 3 s for the link anyway, then sends `AT+CFUN=1,1` on the modem's USB AT port (USB interface 02 on a 2c7c device, normally `/dev/ttyUSB2`), waits up to 40 s for the root port's link active bit, then `echo 1 > /sys/bus/pci/rescan`.
- If there's no AT port on USB, or the link still doesn't come up, it leaves it to a reboot.

On my unit it recovered at 33.6 s into boot with no reboot:

```
modem-pcie-late: modem not on PCIe at boot (uptime 22.95s, link bit now: down, modem on USB: yes)
modem-pcie-late: no link: restarting the modem with AT+CFUN=1,1 on /dev/ttyUSB2
modem-pcie-late: link up at 33.36s, modem enumerated by rescan at 33.58s (0x17cb:0x0306)
```

It logs to the kernel log (`dmesg | grep modem-pcie-late`) as it runs before logd, keeping a record of every miss in `/etc/modem-pcie-late.log`, surviving a reboot.

## Using it

The miss only happens on the first boot of a fresh web-recovery install, so the script has to be **baked into the image you install**. Copying it onto a running router won't help since you'll already be running on the firmware and needing a reboot.

It's in the images from this repo from `d50-ipq50xx-2026.11.23` on. For your own Image Builder build, add the two files under `files/`:

```
files/usr/sbin/modem-pcie-late.sh
files/etc/init.d/modem-pcie-late
```

both executable, and enable it with a `files/etc/uci-defaults/` script running `/etc/init.d/modem-pcie-late enable`. It needs `sms-tool` and `ucode` in the image.

It only applies to D50 units with its RM500Q-AE on PCIe (`data_interface 1,0`). If you are using USB you do not need this.

## Upstream

A cut-down version of this is in [openwrt/openwrt#26762](https://github.com/openwrt/openwrt/pull/26762). It does the same AT restart and rescan but writes to the tty directly so it doesn't need `sms_tool`, and leaves the modem alone if it's set to USB data mode. If that gets merged, this script won't be needed on upstream images.
