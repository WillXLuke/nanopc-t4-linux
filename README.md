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
version `7.3.0-8`, arm64) are attached to the release:
<https://github.com/WillXLuke/nanopc-t4-linux/releases/tag/v7.3.0-8>

## 1. Artifacts (`pkgs/`)

| File | Size | Purpose |
|---|---|---|
| `linux-image-7.3.0-nanopc-t4_7.3.0-8_arm64.deb` | 37 MB | kernel `Image.gz`, 1703 modules, DTBs, `System.map`, config |
| `linux-headers-7.3.0-nanopc-t4_7.3.0-8_arm64.deb` | 9.3 MB | pruned headers + cross-built host tools (`dkms`/out-of-tree modules) |
| `linux-image-7.3.0-nanopc-t4-dbg_7.3.0-8_arm64.deb` | 104 MB | `vmlinux` + per-module debug symbols (optional) |
| `linux-dtb-7.3.0-nanopc-t4_7.3.0-8_arm64.deb` | 115 KB | 50 RK3399 DTBs + `hd702e` overlay in `/boot/dtb/rockchip/` |
| `linux-libc-dev_7.3.0-8_arm64.deb` | 1.5 MB | UAPI headers (glibc/kernel headers; conflicts with distro `linux-libc-dev`) |
| `config-7.3.0-nanopc-t4` | 320 KB | the exact `.config` used |
| `linux-upstream_7.3.0-8_arm64.changes/.buildinfo` | 10 KB | dpkg-buildpackage metadata |
| `sha256sums.txt` | | checksums of all packages |

Kernel release string: **7.3.0-nanopc-t4** (`CONFIG_LOCALVERSION="-nanopc-t4"`),
Debian version `7.3.0-8`.

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
`NFT_CT`/`NFT_NAT`/`NFT_MASQ`/`NFT_REDIR`, the x_tables extensions tailscale needs
(`NFT_COMPAT`, `xt_mark`, `xt_connmark`+`NF_CONNTRACK_MARK`, `xt_conntrack`,
`xt_addrtype`, `xt_comment`, `xt_multiport`, `xt_TCPMSS`), and the classic
`IP_NF_*` iptables stack. Built in: `NVME_HWMON` (per-drive temperature sensors),
policy routing (`IP_MULTIPLE_TABLES`/`IPV6_MULTIPLE_TABLES`/`FIB_RULES`).

## 5. Installing on the board

```sh
sudo dpkg -i linux-image-7.3.0-nanopc-t4_7.3.0-8_arm64.deb \
             linux-dtb-7.3.0-nanopc-t4_7.3.0-8_arm64.deb \
             linux-headers-7.3.0-nanopc-t4_7.3.0-8_arm64.deb
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

**Tailscale netfilter/routing requirements.** Tailscale drives `iptables`
(here: `iptables-nft`, i.e. the nf_tables backend) or `nft` directly, and needs
policy routing for its fwmark rules. Everything below is enabled in this build:

| Tailscale uses | Kernel option | Module / built-in |
|---|---|---|
| `iptables-nft` → x_tables compat | `NFT_COMPAT` | `nft_compat.ko` |
| `-j MARK --set-mark v/mask`, `-m mark` | `NETFILTER_XT_MARK` (via `NETFILTER_XT_TARGET_MARK`) | `xt_mark.ko` (target rev 2 = value/mask, plus match) |
| `-j CONNMARK --restore-mark --nfmask .. --ctmask ..`, `-m connmark` | `NETFILTER_XT_CONNMARK` (selects `NF_CONNTRACK_MARK`) | `xt_connmark.ko` (target rev 2/3 + match) |
| `-m conntrack --ctstate` | `NETFILTER_XT_MATCH_CONNTRACK` | `xt_conntrack.ko` |
| `-m addrtype`, `-m comment`, `-m multiport`, `-j TCPMSS` | `NETFILTER_XT_MATCH_ADDRTYPE`/`_COMMENT`/`_MULTIPORT`, `NETFILTER_XT_TARGET_TCPMSS` | `xt_addrtype.ko`, `xt_comment.ko`, `xt_multiport.ko`, `xt_TCPMSS.ko` |
| `-j MASQUERADE`, `-t nat` | `NF_NAT` + `NFT_NAT`/`NFT_MASQ` (nft) and `IP_NF_NAT` + `NETFILTER_XT_TARGET_MASQUERADE` (legacy) | `nf_nat.ko`, `nft_nat.ko`, `nft_masq.ko`, `iptable_nat.ko`, `xt_MASQUERADE.ko` |
| nf_tables core incl. inet/ipv4/ipv6/netdev families, counters | `NF_TABLES` (+ bools `NF_TABLES_INET/IPV4/IPV6/NETDEV`) | `nf_tables.ko` |
| conntrack | `NF_CONNTRACK` | `nf_conntrack.ko` |
| `ip rule add fwmark ... table 52` | `IP_ADVANCED_ROUTER`, `IP_MULTIPLE_TABLES`, `IPV6_MULTIPLE_TABLES`, `FIB_RULES` | built in |
| `tailscale0` device | `TUN` | built in |
| raw sockets for `TS_ENABLE_RAW_DISCO` | `PACKET` | built in |

All of them autoload on demand through their `ipt_*`/`ip6t_*` module aliases;
if something is missing, load it explicitly:

```sh
sudo modprobe nft_compat xt_mark xt_connmark xt_conntrack xt_addrtype \
                xt_comment xt_multiport xt_TCPMSS nf_nat nf_conntrack nft_masq nft_nat
sudo systemctl restart tailscaled
sudo iptables -t mangle -S PREROUTING | head        # connmark rules present
sudo ip rule | head                                # fwmark rules / table 52
```

Two failure signatures this build fixes:

- `Extension MARK revision 0 not supported, missing kernel module?` then
  `MARK: bad value for option "--set-mark"` — MARK target rev 2 (the
  `value/mask` form) lives in `xt_mark.ko`, reached through `nft_compat`.
- `Extension connmark revision 0 not supported` then
  `unknown option "--nfmask"` — `--nfmask`/`--ctmask` exist only in CONNMARK
  target rev 2/3, which lives in `xt_connmark.ko`; `NF_CONNTRACK_MARK` must be
  enabled for the ctmark storage itself.

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

**Fan curve.** PWM must be at least 38/255 for this fan to spin, so the cooling
levels are `0 38 62 86 110 134 159 183 207 231 255` (state 0 = off) and
`cpu_thermal` gets 10 active trips, one fan state each:

| Trip (°C) | 60 | 62 | 64 | 66 | 68 | 70 | 72 | 74 | 76 | 78 |
|---|---|---|---|---|---|---|---|---|---|---|
| PWM (of 255) | 38 | 62 | 86 | 110 | 134 | 159 | 183 | 207 | 231 | 255 |
| approx. RPM | ~1200 | | | | | | | | | ~5000 |

Hysteresis is 1 °C. The fan therefore stays silent below 60 °C, starts at the
lowest duty the fan can actually run at, and reaches 100 % at 78 °C.

**Thermal trips (CPU).** The RK3399 defaults (`cpu_alert0` 70 °C, `cpu_alert1`
75 °C, `cpu_crit` 95 °C) are raised:

| Trip | default | this build |
|---|---|---|
| `cpu_alert0` (big cores throttled) | 70 °C | **84 °C** |
| `cpu_alert1` (all cores throttled) | 75 °C | **90 °C** |
| `cpu_crit` (shutdown) | 95 °C | **96 °C** |

Together this lets the big cluster hold 2.208 GHz up to 84 °C instead of being
capped to 2.016 GHz at 70 °C, while the fan is already at full speed from 78 °C.
It is outside Rockchip's recommended envelope (SoC `tshut` default is 95 °C):
the board runs hotter and the 96 °C critical trip leaves only 6 °C headroom
above the 90 °C throttling point. Watch `thermal_zone0/temp`.

**Fan tachometer.** The fan's tach wire (GPIO2_A6) is wired to the `pwm-fan`
node, so the driver counts pulses and reports RPM:

```dts
interrupts = <RK_PA6 IRQ_TYPE_EDGE_FALLING>;   /* GPIO2_A6 */
pulses-per-revolution = <2>;
```

```sh
cat /sys/class/hwmon/hwmon*/fan1_input     # RPM, updates once a second
sensors | grep -i fan                      # pwmfan-isa-0000: fan1: ... RPM
```

RPM is sampled over a one-second window, so it reads 0 while the fan is stopped
and lags one step behind sudden PWM changes. `pulses-per-revolution = 2` is
correct for the usual 2-pulse fans; raise it if the reading is exactly double
the real speed.

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
