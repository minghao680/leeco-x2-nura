#!/usr/bin/env python3
"""Build a minimal Android boot image (header v0) around a raw kernel.

Needed because `fastboot boot` on this device wants an ANDROID! header; a bare
Image.gz+dtb concatenation is not loadable.

The offset values are the ones the Le Max 2 bootloader uses, read back from the
device's own boot partition:
    kernel_addr  = 0x80008000
    ramdisk_addr = 0x81000000
    tags_addr    = 0x80000100
    page_size    = 4096

Usage:
    make-bootimg.py <kernel> <dtb> <out.img>
"""

import struct
import sys

PAGE = 4096
KERNEL_ADDR = 0x80008000
RAMDISK_ADDR = 0x81000000
TAGS_ADDR = 0x80000100
BOARD = b""
CMDLINE = b"console=ttyMSM0,115200n8 earlycon"


def pad(data: bytes) -> bytes:
    rem = len(data) % PAGE
    return data + b"\0" * (PAGE - rem if rem else 0)


def main(kernel_path: str, dtb_path: str, out_path: str) -> int:
    with open(kernel_path, "rb") as f:
        kernel = f.read()
    with open(dtb_path, "rb") as f:
        dtb = f.read()

    # The Le Max 2 bootloader does NOT honour the header's dt_size field: it
    # rejects images with `dtb not found` unless the DTB is appended *inside*
    # the kernel segment. The stock boot.img does exactly that (dt_size=0 in
    # the header, 33 DTBs concatenated after the gzipped kernel), so we mirror
    # that layout here.
    kernel_with_dtb = kernel + dtb

    header = struct.pack(
        "<8s10I16s512s32s1024s",
        b"ANDROID!",
        len(kernel_with_dtb),   # kernel_size covers kernel + appended dtb
        KERNEL_ADDR,
        0,                      # no ramdisk
        RAMDISK_ADDR,
        0,                      # no second stage
        0,
        TAGS_ADDR,
        PAGE,
        0,                      # dt_size = 0, dtb lives inside the kernel blob
        0,                      # unused
        BOARD,
        CMDLINE,
        b"",                    # id
        b"",                    # extra cmdline
    )

    with open(out_path, "wb") as f:
        f.write(pad(header))
        f.write(pad(kernel_with_dtb))

    print(f"kernel      : {len(kernel)} bytes")
    print(f"dtb         : {len(dtb)} bytes")
    print(f"kernel+dtb  : {len(kernel_with_dtb)} bytes")
    print(f"image       : {out_path}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 4:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(*sys.argv[1:]))
