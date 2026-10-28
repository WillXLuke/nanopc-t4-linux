#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Cross-build mainline Linux 7.3 for the FriendlyElec NanoPC-T4 (Rockchip
# RK3399) on an x86_64 Debian/Ubuntu host and package it as .deb files.
#
# Output (in $ROOT/pkgs):
#   linux-image-<release>_<debversion>_arm64.deb
#   linux-image-<release>-dbg_<debversion>_arm64.deb
#   linux-headers-<release>_<debversion>_arm64.deb
#   linux-libc-dev_<debversion>_arm64.deb
#
# Host requirements:
#   make gcc flex bison bc libssl-dev libelf-dev dpkg-dev rsync \
#   gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu device-tree-compiler
#   debhelper (bootstrapped into tools/dh if missing)
#
# Usage: scripts/build-kernel-deb.sh
#   VER=7.3 JOBS=16 DEB_VERSION=7.3.0-1 scripts/build-kernel-deb.sh

set -euo pipefail

VER=${VER:-7.3}
LOCALVERSION=${LOCALVERSION:--nanopc-t4}
DEB_VERSION=${DEB_VERSION:-${VER}.0-1}
JOBS=${JOBS:-$(nproc)}
ARCH=arm64
CROSS_COMPILE=aarch64-linux-gnu-

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=$ROOT/src/linux-$VER
BUILD=$ROOT/build
PKGS=$ROOT/pkgs
FRAGMENT=$ROOT/configs/nanopc-t4.fragment
URL=${URL:-https://cdn.kernel.org/pub/linux/kernel/v7.x}
MIRROR=${MIRROR:-https://mirrors.tuna.tsinghua.edu.cn/kernel/v7.x}

log() { printf '\n==> %s\n' "$*"; }

mkdir -p "$ROOT/src" "$ROOT/pkgs"

# ---------------------------------------------------------------------------
# 1. Source tarball
# ---------------------------------------------------------------------------
if [ ! -f "$ROOT/src/linux-$VER.tar.xz" ]; then
	log "downloading linux-$VER.tar.xz"
	curl -fL --retry 3 -o "$ROOT/src/linux-$VER.tar.xz" "$MIRROR/linux-$VER.tar.xz" ||
		curl -fL --retry 3 -o "$ROOT/src/linux-$VER.tar.xz" "$URL/linux-$VER.tar.xz"
fi

if [ ! -f "$ROOT/src/sha256sums.asc" ]; then
	curl -fsSL -o "$ROOT/src/sha256sums.asc" "$URL/sha256sums.asc" ||
		curl -fsSL -o "$ROOT/src/sha256sums.asc" "$MIRROR/sha256sums.asc"
fi

log "verifying tarball checksum"
( cd "$ROOT/src" && grep " linux-$VER.tar.xz\$" sha256sums.asc | sha256sum -c - )

if [ ! -d "$SRC" ]; then
	log "extracting"
	tar -C "$ROOT/src" -xf "$ROOT/src/linux-$VER.tar.xz"
fi

# ---------------------------------------------------------------------------
# 2. Configuration: arm64 defconfig + NanoPC-T4 fragment
# ---------------------------------------------------------------------------
if [ ! -f "$BUILD/.config" ]; then
	log "generating arm64 defconfig + board fragment"
	make -C "$SRC" ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE O="$BUILD" defconfig
	ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE \
		"$SRC/scripts/kconfig/merge_config.sh" -m -O "$BUILD" \
		"$BUILD/.config" "$FRAGMENT"
fi
make -C "$SRC" ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE O="$BUILD" olddefconfig
make -C "$SRC" ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE O="$BUILD" syncconfig

KERNELRELEASE=$(make -s -C "$SRC" ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE O="$BUILD" kernelrelease)
log "kernel release: $KERNELRELEASE"

# ---------------------------------------------------------------------------
# 2b. Board tuning patch: fan curve, 115200 console, 2.2/1.8 GHz overclock
# ---------------------------------------------------------------------------
BOARD_DTS=$SRC/arch/arm64/boot/dts/rockchip/rk3399-nanopc-t4.dts
if grep -q 'fan_70' "$BOARD_DTS"; then
	log "board tuning already applied"
else
	log "applying board tuning patch"
	patch -d "$SRC" -p1 < "$ROOT/patches/0001-nanopc-t4-fan-uart-overclock.patch"
fi

# ---------------------------------------------------------------------------
# 3. Build Image, modules and DTBs
# ---------------------------------------------------------------------------
log "building (-j$JOBS)"
make -C "$SRC" ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE O="$BUILD" -j"$JOBS" all

# ---------------------------------------------------------------------------
# 4. Private debhelper if the host does not have it
#    (dh_testdir/dh_prep/dh_gencontrol/... are used by the in-tree
#    debian/rules, so packaging needs debhelper even though it only
#    assembles the .debs)
# ---------------------------------------------------------------------------
DH_ENV=()
SKIP_DEPS_CHECK=0
if ! command -v dh_gencontrol >/dev/null 2>&1; then
	log "bootstrapping debhelper into tools/dh"
	mkdir -p "$ROOT/tools/dh"
	( cd "$ROOT/tools/dh" && apt-get download debhelper libdebhelper-perl >/dev/null )
	mkdir -p "$ROOT/tools/dh/root"
	for d in "$ROOT"/tools/dh/*.deb; do
		dpkg -x "$d" "$ROOT/tools/dh/root"
	done
	DH_ENV=(env "PATH=$ROOT/tools/dh/root/usr/bin:$PATH"
		    "PERL5LIB=$ROOT/tools/dh/root/usr/share/perl5")
	log "note: running dpkg-buildpackage with -d (build-deps are known to be satisfied)"
	SKIP_DEPS_CHECK=1
fi

# ---------------------------------------------------------------------------
# 4b. /boot/Image + /boot/uInitrd aliases (U-Boot / FriendlyElec boot scripts)
#     The image package ships a hook; scripts/package/builddeb has to install
#     it, which upstream does not do for us.
# ---------------------------------------------------------------------------
log "installing boot-alias hook into builddeb"
cp -f "$ROOT/boot/nanopc-t4-bootlinks" "$SRC/scripts/package/nanopc-t4-bootlinks"
python3 "$ROOT/scripts/patch-builddeb.py" "$SRC/scripts/package/builddeb"

# ---------------------------------------------------------------------------
# 5. debian/ directory + packaging (what `make bindeb-pkg` does internally)
# ---------------------------------------------------------------------------
log "generating debian/ metadata"
rm -rf "$BUILD/debian"
( cd "$BUILD" && \
  env srctree="$SRC" objtree="$BUILD" ARCH=$ARCH SRCARCH=$ARCH UTS_MACHINE=$ARCH \
	KERNELRELEASE="$KERNELRELEASE" KCONFIG_CONFIG=.config \
	KDEB_PKGVERSION="$DEB_VERSION" \
	DEBFULLNAME="${DEBFULLNAME:-NanoPC-T4 build}" \
	DEBEMAIL="${DEBEMAIL:-nanopc-t4@localhost}" \
	"$SRC/scripts/package/mkdebian" )

# Runtime deps for the image package.  kmod is needed for depmod; initramfs
# is optional because the SD/eMMC/NVMe drivers are built in.
sed -i '/^Description: Linux kernel, version/i Depends: kmod\nRecommends: initramfs-tools, u-boot-tools, linux-firmware' \
	"$BUILD/debian/control"

log "running dpkg-buildpackage"
DPKG_ARGS=(--build=binary --no-pre-clean --unsigned-changes -j1 "-a$ARCH")
[ "$SKIP_DEPS_CHECK" = 1 ] && DPKG_ARGS+=(-d)
if [ ${#DH_ENV[@]} -gt 0 ]; then
	( cd "$BUILD" && "${DH_ENV[@]}" dpkg-buildpackage "${DPKG_ARGS[@]}" )
else
	( cd "$BUILD" && dpkg-buildpackage "${DPKG_ARGS[@]}" )
fi

# ---------------------------------------------------------------------------
# 6. Standalone DTB package (/boot/dtb/rockchip, bootloader-friendly)
# ---------------------------------------------------------------------------
log "building DTB package"
KERNELRELEASE="$KERNELRELEASE" DEB_VERSION="$DEB_VERSION" "$ROOT/scripts/build-dtb-deb.sh"

# ---------------------------------------------------------------------------
# 7. Collect artifacts
# ---------------------------------------------------------------------------
log "collecting .deb files"
mv -f "$ROOT"/*.deb "$PKGS"/
mv -f "$ROOT"/*.changes "$ROOT"/*.buildinfo "$PKGS"/ 2>/dev/null || true
cp -f "$BUILD/.config" "$PKGS/config-$KERNELRELEASE"
( cd "$PKGS" && sha256sum ./*.deb > sha256sums.txt )
ls -lh "$PKGS"
