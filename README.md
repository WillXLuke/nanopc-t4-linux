# Mainline Linux 7.3 for FriendlyElec NanoPC-T4 (RK3399)

Cross-built on x86_64 Ubuntu 26.04 (gcc 15.2.0, `aarch64-linux-gnu-`) and
packaged as Debian packages with the in-tree `scripts/package` machinery.

## Contents

| Path | What |
|---|---|
| `scripts/build-kernel-deb.sh` | full build: fetch 7.3, board patch, `make all`, `.deb` packaging |
| `scripts/build-dtb-deb.sh` | standalone `/boot/dtb/rockchip` package |
| `scripts/patch-builddeb.py` | installs the `/boot/Image` + `/boot/uInitrd` hooks into `scripts/package/builddeb` |
| `patches/0001-nanopc-t4-fan-uart-overclock.patch` | fan curve (48-70 C, min 38/255), 115200 console, 2.208/1.8 GHz OPPs |
| `configs/nanopc-t4.fragment` | `arm64 defconfig` delta: NVMe/PCIe/GMAC built in, distro extras as modules |
| `boot/nanopc-t4-bootlinks` | kernel hook that links `/boot/Image` and `/boot/uInitrd` |
| `boot/extlinux.conf.example` | U-Boot extlinux entry, `ttyS2` @ 115200 |
| `pkgs/sha256sums.txt`, `pkgs/config-7.3.0-nanopc-t4` | checksums and the exact kernel config |

Prebuilt packages (`linux-image`, `-dbg`, `-headers`, `linux-dtb`, `linux-libc-dev`,
version `7.3.0-5`, arm64) are attached to the release:
<https://github.com/WillXLuke/nanopc-t4-linux/releases/tag/v7.3.0-5>

## 1. Artifacts (`pkgs/`)

| File | Size | Purpose |
|---|---|---|
| `linux-image-7.3.0-nanopc-t4_7.3.0-5_arm64.deb` | 37 MB | kernel `Image.gz`, 1703 modules, DTBs, `System.map`, config |
| `linux-headers-7.3.0-nanopc-t4_7.3.0-5_arm64.deb` | 9.3 MB | pruned headers + cross-built host tools (`dkms`/out-of-tree modules) |
| `linux-image-7.3.0-nanopc-t4-dbg_7.3.0-5_arm64.deb` | 104 MB | `vmlinux` + per-module debug symbols (optional) |
| `linux-dtb-7.3.0-nanopc-t4_7.3.0-5_arm64.deb` | 115 KB | 50 RK3399 DTBs + `hd702e` overlay in `/boot/dtb/rockchip/` |
| `linux-libc-dev_7.3.0-5_arm64.deb` | 1.5 MB | UAPI headers (glibc/kernel headers; conflicts with distro `linux-libc-dev`) |
| `config-7.3.0-nanopc-t4` | 320 KB | the exact `.config` used |
| `linux-upstream_7.3.0-5_arm64.changes/.buildinfo` | 10 KB | dpkg-buildpackage metadata |
| `sha256sums.txt` | | checksums of all packages |

Kernel release string: **7.3.0-nanopc-t4** (`CONFIG_LOCALVERSION="-nanopc-t4"`),
Debian version `7.3.0-5`.

## 2. Build summary

* Source: `linux-7.3.tar.xz` from kernel.org, sha256
  `87363c24f10e06321eb362765521094e94471f6bff8bce2d6b3e40f39f004953`
  (release of 2026-10-18).
* Config: `arch/arm64/configs/defconfig` + `configs/nanopc-t4.fragment`.
* `make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- O=build -j16 all`
  ≈ 10 min on 16 vCPU; 3.6 GB of objects.
* Packaging: `scripts/package/mkdebian` + `scripts/package/builddeb`, driven
  by `dpkg-buildpackage --build=binary -aarm64` — i.e. exactly what
  `make bindeb-pkg` does. `-d` (skip build-dep check) and a private
  debhelper (`tools/dh/`) were used because this build host has no
  `debhelper` installed and a read-only `/`.
* Verified: package MD5 sums, `depmod -b` on the shipped module tree
  (1703 modules, no unresolved deps), `rk3399-nanopc-t4.dtb` present,
  `vmlinuz` is the 15 MB `Image.gz`.

## 3. What is in the image package

```
/boot/vmlinuz-7.3.0-nanopc-t4            gzip-compressed arm64 Image
/boot/System.map-7.3.0-nanopc-t4
/boot/config-7.3.0-nanopc-t4
/lib/modules/7.3.0-nanopc-t4/            1703 modules + modules.dep
/usr/lib/linux-image-7.3.0-nanopc-t4/    arm64 DTBs, rockchip/
                                         rk3399-nanopc-t4.dtb
                                         rk3399-nanopc-t4-hd702e.dtb (panel overlay)
/etc/kernel/postinst.d/zz-nanopc-t4-bootlinks     /boot/Image link (see §6)
/etc/kernel/postrm.d/zz-nanopc-t4-bootlinks
/etc/initramfs/post-update.d/zz-nanopc-t4-uinitrd /boot/uInitrd regeneration
```

`Depends: kmod` (for `depmod`), `Recommends: initramfs-tools, u-boot-tools, linux-firmware`.
Maintainer scripts are the upstream hook shims: `postinst`/`postrm`/`preinst`/
`prerm` run `run-parts` over `/etc/kernel/*.d` and `/usr/share/kernel/*.d`, so
`update-initramfs` and `u-boot-update`/`flash-kernel` integrate automatically
when installed.

## 4. Board configuration

Built in (`=y`) so the board boots without an initramfs (SD, eMMC, NVMe, NFS):

* `MMC_DW_ROCKCHIP`, `MMC_SDHCI_OF_ARASAN`, `USB_XHCI_HCD`, `USB_DWC3`,
  `USB_STORAGE`, `PINCTRL_ROCKCHIP`, `REGULATOR_RK808`, `PWM_ROCKCHIP`,
  `ROCKCHIP_IOMMU`, `ROCKCHIP_IODOMAIN`, ext4
* added by the fragment: `PCIE_ROCKCHIP_HOST`, `PHY_ROCKCHIP_PCIE`,
  `NVME_CORE`/`BLK_DEV_NVME`, `STMMAC_ETH`/`STMMAC_PLATFORM`/`DWMAC_ROCKCHIP`
  (GMAC), `REALTEK_PHY`

Modules (`=m`): `DRM_ROCKCHIP` (+ `dw-hdmi`, `dw-mipi-dsi`), `DRM_PANFROST`,
`VIDEO_HANTRO` (VPU), `SND_SOC_ES8316` (codec), `BRCMFMAC` + `BT_HCIUART`/`BT_BCM`
(AP6356S), `TYPEC_FUSB302` + `PHY_ROCKCHIP_TYPEC`, `RTC_DRV_RK808`,
`SENSORS_PWM_FAN` (fan), `IR_GPIO_CIR`, `ZRAM`, `F2FS_FS`, `XFS_FS`,
`NTFS3_FS`, `EXFAT_FS`, `DM_CRYPT`, `DM_VERITY`, `ROCKCHIP_THERMAL`,
`NF_TABLES` (with inet/ipv4/ipv6/netdev families built in), `NF_NAT`/`NF_CONNTRACK`,
`NFT_CT`/`NFT_NAT`/`NFT_MASQ`/`NFT_REDIR`/`NFT_COUNTER`, and the classic
`IP_NF_*` iptables stack. Built in: `NVME_HWMON` (per-drive temperature sensors).

## 5. Installing on the board

```sh
sudo dpkg -i linux-image-7.3.0-nanopc-t4_7.3.0-5_arm64.deb \
             linux-dtb-7.3.0-nanopc-t4_7.3.0-5_arm64.deb \
             linux-headers-7.3.0-nanopc-t4_7.3.0-5_arm64.deb
sudo apt-get -f install      # only if initramfs-tools/kmod are missing
```

The DTB package is architecture-clean data only (no maintainer scripts) and
installs:

```
/boot/dtb/rockchip/rk3399-nanopc-t4.dtb
/boot/dtb/rockchip/rk3399-nanopc-t4-hd702e.dtbo   (HD702E panel overlay)
/boot/dtb/rockchip/rk3399-nanopi-m4*.dtb ...      (all rk3399 boards)
```

Do **not** install `linux-libc-dev_...arm64.deb` on a running distro unless you
really want to replace the system UAPI headers (it is built for the sake of a
complete upstream package set).

## 6. Booting with U-Boot / extlinux

Install `linux-dtb-...` and add an entry (see `boot/extlinux.conf.example`):

```
label linux-7.3.0-nanopc-t4
  kernel /boot/vmlinuz-7.3.0-nanopc-t4
  fdt /boot/dtb/rockchip/rk3399-nanopc-t4.dtb
  append root=PARTUUID=<rootfs-partuuid> rootwait rw console=ttyS2,115200n8
```

(Without the DTB package the same file lives in
`/usr/lib/linux-image-7.3.0-nanopc-t4/rockchip/`; copy it to `/boot/dtb/`.)

* Serial console on the NanoPC-T4 is `ttyS2` at **115200** 8N1 (this build
  overrides the upstream `stdout-path` default of 1.5 Mbaud, see §11).
* `vmlinuz-*` is `Image.gz`. Mainline U-Boot's `booti` decompresses it; a
  bootloader without gzip support needs the raw `Image`
  (`build/arch/arm64/boot/Image`) instead.
* U-Boot must be built for `nanopc-t4` (mainline `nanopc-t4-rk3399_defconfig`
  or FriendlyElec's U-Boot) and load `/boot/extlinux/extlinux.conf`.

### Fixed names for boot.scr (FriendlyElec / Armbian style)

The image package ships hooks that relink the fixed names every time it is
installed, upgraded or removed:

```
/boot/Image   -> vmlinuz-7.3.0-nanopc-t4
/boot/uInitrd -> uInitrd-7.3.0-nanopc-t4      (mkimage wrapped initrd)
```

* `/etc/kernel/postinst.d/zz-nanopc-t4-bootlinks` runs after initramfs-tools
  (the `zz-` prefix), so `initrd.img-<release>` already exists;
  `/etc/kernel/postrm.d/...` only removes links pointing at the removed release.
* `uInitrd-<release>` is built with `mkimage -A arm64 -O linux -T ramdisk
  -C none` (`-C none`: U-Boot passes the blob through and the kernel
  autodetects gzip/zstd/xz/lz4). Without `u-boot-tools` the hook falls back to
  linking the plain `initrd.img-<release>`.
* On a vfat `/boot` (no symlinks) the hook copies the files instead.
* `/etc/initramfs/post-update.d/zz-nanopc-t4-uinitrd` regenerates `uInitrd`
  whenever the initramfs is rebuilt.
* `/boot/Image` is `Image.gz`. U-Boot's `booti` decompresses it only when
  `kernel_comp_addr_r` / `kernel_comp_size` are set; otherwise boot the raw
  `Image` (extlinux path above) or `zcat /boot/Image > /boot/Image.raw`.

## 7. Firmware (Wi-Fi/BT)

The kernel ships no firmware. For the on-board AP6356S you need
`brcmfmac4356-sdio.bin` plus the board NVRAM `brcmfmac4356-sdio.txt` in
`/lib/firmware/brcm/` (`firmware-brcm80211` on Debian, `linux-firmware` on
Ubuntu provide the `.bin`; the `.txt` NVRAM comes from FriendlyElec's BSP).
Bluetooth uses `BT_HCIUART_BCM` with the matching `.hcd` file.

## 8. Caveats

* Cross-compiled here, **not boot-tested** (no NanoPC-T4 attached to this
  machine). Package-level checks passed; runtime behaviour (HDMI/DP, USB-C,
  Wi-Fi) still needs verification on hardware.
* Kernel and modules are unsigned (`CONFIG_MODULE_SIG` off).
* Debug info is `CONFIG_DEBUG_INFO_REDUCED`, hence the 104 MB `-dbg` package.
* No initramfs is built here; `initramfs-tools` on the target does that from
  the `postinst` hook.

## 9. Tailscale and NVMe temperatures

**Tailscale (nftables).** The netfilter stack is modular, so userspace has to be
able to load it (udev does this automatically):

```sh
sudo modprobe nf_tables nf_nat nf_conntrack nft_ct nft_masq nft_nat nft_counter
sudo tailscale up            # or restart the daemon
sudo nft list tables         # ts_* tables appear once tailscale is up
sudo nft list table inet ts_state     # sanity check
```

`nf_tables` must be loadable *and* have the `inet` family compiled in
(`CONFIG_NF_TABLES_INET=y` — a bool, part of `nf_tables.ko`); without it
`nft add table inet ...` fails with "Operation not supported". For legacy
iptables (`iptables-legacy`, `iptables -t nat ...`) the `IP_NF_*` and
`xtables-legacy` modules are included too; `iptables-nft` needs only the first
line above.

**`-j MARK --set-mark 0x40000/0xff0000` fails?** iptables-nft translates the
MARK target through `nft_compat`, so both `nft_compat.ko` and `xt_mark.ko`
(match + target, target revision 2 carries the `value/mask` form) must exist:

```sh
sudo modprobe nft_compat xt_mark
sudo iptables -t filter -A ts-forward -i tailscale0 -j MARK --set-mark 0x40000/0xff0000
```

The symptom of a missing module is `Warning: Extension MARK revision 0 not
supported, missing kernel module?` followed by `MARK: bad value for option
"--set-mark", or out of range` — revision 0 has no mask support, hence the
rejection.

**NVMe temperature.** `CONFIG_NVME_HWMON=y` exposes each namespace controller as
a hwmon device:

```sh
grep . /sys/class/hwmon/hwmon*/name          # one "nvme" per drive
cat /sys/class/hwmon/hwmon*/temp1_input      # millidegrees C
sensors                                       # lm-sensors >= 3.6: nvme-pci-0100
```

`temp1_input` is the composite sensor; drives with multiple sensors add
`temp2_input`/`temp3_input`. If `sensors` shows nothing, check that
`/sys/class/hwmon/hwmonX/name` exists — a missing `nvme` entry means the
running DTB/kernel predates this build.

## 10. Reproducing

```sh
scripts/build-kernel-deb.sh          # VER=7.3 JOBS=16 DEB_VERSION=7.3.0-1
```

The script was validated end-to-end on this host: it reproduces the packages
in `pkgs/` (full log in `logs/script-run.log`).

`scripts/build-dtb-deb.sh` builds the standalone `/boot/dtb/rockchip` package
from the already-built DTBs (`SOC_PREFIX=rk3399` by default) and is called by
the main script.

Needs ~6 GB disk (`src/` 1.8 GB + `build/` 3.6 GB) and the cross toolchain
(`gcc-aarch64-linux-gnu`, `device-tree-compiler`, `libssl-dev`, `libelf-dev`,
`bc`, `flex`, `bison`, `dpkg-dev`). On a host that already has `debhelper`
installed, plain
`make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- bindeb-pkg` works as usual.

## 11. Board tuning in this build

Applied by `patches/0001-nanopc-t4-fan-uart-overclock.patch` to
`arch/arm64/boot/dts/rockchip/rk3399-nanopc-t4.dts` (no kernel code changes):

**Fan curve.** PWM must be at least 38/255 for the fan to spin, so the cooling
levels are `0 38 60 81 103 125 147 168 190 212 233 255` (state 0 = off) and
`cpu_thermal` gets 11 active trips, one fan state each:

| Trip | 48 | 50 | 52 | 54 | 56 | 58 | 60 | 64 | 66 | 68 | 70 °C |
|---|---|---|---|---|---|---|---|---|---|---|---|
| PWM | 38 | 60 | 81 | 103 | 125 | 147 | 168 | 190 | 212 | 233 | 255 |
| RPM (approx.) | ~1200 | | | | | | | | | | ~5000 |

Hysteresis is 1 °C; the SoC passive trips (70/75 °C) and 95 °C critical trip
are unchanged, so the fan saturates at 70 °C just before CPU throttling starts.

**Console baud.** `chosen/stdout-path = "serial2:115200n8"` (upstream: 1.5 Mbaud).
U-Boot still talks at its own baud rate; set `CONFIG_BAUDRATE=115200` there (or
keep `console=ttyS2,1500000n8` on the kernel command line) if you want one
setting for both.

**Overclock.** Little cores up to 1.8 GHz (`vdd_cpu_l`, 1.25 V), big cores up to
2.208 GHz (`vdd_cpu_b`, 1.275 V), after
[QiuSimons/R4S-OpenWrt 991-rockchip-rk3399-overclock](https://github.com/QiuSimons/R4S-OpenWrt/blob/master/PATCH/new/main/991-rockchip-rk3399-overclock-to-2.2-1.8-GHz-for-NanoPi4.patch).
The RK3399 PLL tables already carry 1.8/2.016/2.208 GHz and both regulators can
supply the voltages, so the OPPs are simply appended to `cluster0_opp` /
`cluster1_opp`. This is out of spec — expect more heat, higher current, and
possible instability on marginal SoCs; the fan curve above is tuned for it.
To revert, drop the patch (or its `&cluster0_opp`/`&cluster1_opp` blocks).
