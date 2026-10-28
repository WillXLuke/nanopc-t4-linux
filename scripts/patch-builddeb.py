#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Install the NanoPC-T4 boot-alias hooks into scripts/package/builddeb.

The linux-image package has to ship
  /etc/kernel/{postinst,postrm}.d/zz-nanopc-t4-bootlinks
  /etc/initramfs/post-update.d/zz-nanopc-t4-uinitrd
so that /boot/Image and /boot/uInitrd point at the kernel just installed.
Upstream builddeb has no hook for adding extra payload, so patch the install
step.  Idempotent: re-running is a no-op.

Usage: patch-builddeb.py path/to/scripts/package/builddeb
"""

import sys

MARKER = "nanopc-t4-bootlinks"

ANCHOR = (
    '\tcp "$(${MAKE} -s -f ${srctree}/Makefile image_name)" '
    '"${pdir}/${installed_image_path}"\n'
)

BLOCK = ANCHOR + (
    "\n"
    "\t# NanoPC-T4: U-Boot style /boot/Image and /boot/uInitrd aliases\n"
    "\tfor hook in postinst postrm; do\n"
    '\t\tinstall -d "${pdir}/etc/kernel/${hook}.d"\n'
    '\t\tinstall -m 0755 "${srctree}/scripts/package/nanopc-t4-bootlinks" \\\n'
    '\t\t\t"${pdir}/etc/kernel/${hook}.d/zz-nanopc-t4-bootlinks"\n'
    "\tdone\n"
    '\tinstall -d "${pdir}/etc/initramfs/post-update.d"\n'
    '\tinstall -m 0755 "${srctree}/scripts/package/nanopc-t4-bootlinks" \\\n'
    '\t\t"${pdir}/etc/initramfs/post-update.d/zz-nanopc-t4-uinitrd"\n'
)


def main(path: str) -> int:
    src = open(path, encoding="utf-8").read()
    if MARKER in src:
        print(f"{path}: already patched")
        return 0
    if ANCHOR not in src:
        print(f"{path}: anchor not found (unexpected builddeb layout)", file=sys.stderr)
        return 1
    open(path, "w", encoding="utf-8").write(src.replace(ANCHOR, BLOCK, 1))
    print(f"{path}: patched")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        raise SystemExit(2)
    raise SystemExit(main(sys.argv[1]))
