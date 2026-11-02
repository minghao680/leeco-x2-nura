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
    make-bootimg.py <kernel> <dtb> <out.img>   # dtb appended inside kernel blob
    make-bootimg.py --no-dtb <kernel> <out.img>  # kernel only, let lk2nd supply DTB

Use --no-dtb when booting from lk2nd: lk2nd embeds the x2 DTB and appends its
own copy, so a second DTB in the image can conflict with it.
"""

import struct
import sys

PAGE = 4096
KERNEL_ADDR = 0x80008000
RAMDISK_ADDR = 0x81000000
TAGS_ADDR = 0x80000100
BOARD = b""
CMDLINE = b"console=ttyMSM0,115200n8 earlycon panic=15"


def pad(data: bytes) -> bytes:
    rem = len(data) % PAGE
    return data + b"\0" * (PAGE - rem if rem else 0)


def main(kernel_path: str, dtb_path: str | None, out_path: str,
         kernel_addr: int = KERNEL_ADDR) -> int:
    with open(kernel_path, "rb") as f:
        kernel = f.read()

    # The Le Max 2 stock bootloader does NOT honour the header's dt_size field:
    # it rejects images with `dtb not found` unless the DTB is appended *inside*
    # the kernel segment. The stock boot.img does exactly that (dt_size=0 in the
    # header, 33 DTBs concatenated after the gzipped kernel), so we mirror that
    # layout here.
    #
    # With --no-dtb we skip the append entirely: lk2nd embeds the x2 DTB and
    # appends it itself, so sending a second copy risks a conflicting DTB.
    kernel_blob = kernel if dtb_path is None else kernel + open(dtb_path, "rb").read()
    dtb_len = len(kernel_blob) - len(kernel)

    header = struct.pack(
        "<8s10I16s512s32s1024s",
        b"ANDROID!",
        len(kernel_blob),       # kernel_size covers kernel + appended dtb
        kernel_addr,
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
        f.write(pad(kernel_blob))

    print(f"kernel      : {len(kernel)} bytes")
    print(f"dtb         : {dtb_len} bytes" + ("  (--no-dtb mode)" if dtb_len == 0 else ""))
    print(f"kernel blob : {len(kernel_blob)} bytes")
    print(f"kernel addr : {kernel_addr:#x}")
    print(f"image       : {out_path}")
    return 0


if __name__ == "__main__":
    args = sys.argv[1:]
    kernel_addr = KERNEL_ADDR
    if "--addr" in args:
        i = args.index("--addr")
        kernel_addr = int(args[i + 1], 0)
        del args[i:i + 2]
    if len(args) == 4 and args[0] == "--no-dtb":
        sys.exit(main(args[1], None, args[3], kernel_addr))
    if len(args) == 3:
        sys.exit(main(args[0], args[1], args[2], kernel_addr))
    print(__doc__)
    sys.exit(2)
