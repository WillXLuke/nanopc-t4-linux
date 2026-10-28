#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Package the already-built Rockchip device trees into a standalone .deb
# (bootloader-friendly layout: /boot/dtb/rockchip/*.dtb, *.dtbo).
#
# Requires a completed kernel build in $ROOT/build.
#
# Usage: scripts/build-dtb-deb.sh
#   KERNELRELEASE=7.3.0-nanopc-t4 DEB_VERSION=7.3.0-2 SOC_PREFIX=rk3399 \
#     scripts/build-dtb-deb.sh

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
KERNELRELEASE=${KERNELRELEASE:-7.3.0-nanopc-t4}
DEB_VERSION=${DEB_VERSION:-7.3.0-2}
SOC_PREFIX=${SOC_PREFIX:-rk3399}
DTS_DIR=$ROOT/build/arch/arm64/boot/dts/rockchip
STAGE=$ROOT/build/dtb-deb
PKGS=$ROOT/pkgs
PKG=linux-dtb-$KERNELRELEASE

log() { printf '\n==> %s\n' "$*"; }

[ -d "$DTS_DIR" ] || { echo "no DTBs in $DTS_DIR (build the kernel first)" >&2; exit 1; }
mkdir -p "$PKGS"

log "staging $SOC_PREFIX DTBs"
rm -rf "$STAGE"
mkdir -p "$STAGE/boot/dtb/rockchip" "$STAGE/DEBIAN"
shopt -s nullglob
for f in "$DTS_DIR"/$SOC_PREFIX*.dtb "$DTS_DIR"/$SOC_PREFIX*.dtbo; do
	cp -a "$f" "$STAGE/boot/dtb/rockchip/"
done
shopt -u nullglob
n=$(find "$STAGE/boot/dtb/rockchip" -type f | wc -l)
[ "$n" -gt 0 ] || { echo "no $SOC_PREFIX DTBs staged" >&2; exit 1; }

cat > "$STAGE/DEBIAN/control" <<EOF
Package: $PKG
Source: linux-upstream
Version: $DEB_VERSION
Architecture: arm64
Maintainer: NanoPC-T4 build <nanopc-t4@localhost>
Installed-Size: $(du -sk "$STAGE" | cut -f1)
Section: kernel
Priority: optional
Homepage: https://www.kernel.org/
Description: Device tree blobs for Linux $KERNELRELEASE (Rockchip $SOC_PREFIX)
 Mainline Linux $KERNELRELEASE device trees for Rockchip $SOC_PREFIX SoCs
 (NanoPC-T4, NanoPi M4/M4B/Neo4/R4S, Rock Pi 4, ...), installed under
 /boot/dtb/rockchip for direct use by U-Boot extlinux (fdt ...) or
 flash-kernel.
EOF

( cd "$STAGE" && find . -type f ! -path './DEBIAN/*' -printf '%P\n' | sort |
	xargs -r md5sum > DEBIAN/md5sums )

out=$PKGS/${PKG}_${DEB_VERSION}_arm64.deb
log "building $out"
rm -f "$out"
dpkg-deb --root-owner-group -Zxz -b "$STAGE" "$out" >/dev/null
dpkg-deb -I "$out" | sed -n '/Package/,/Description/p'
dpkg-deb -c "$out" | grep -E 'rk3399-nanopc-t4(\.dtb|-hd702e\.dtbo)' || true
ls -lh "$out"
