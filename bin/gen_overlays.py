#!/usr/bin/env python3
"""Generate multiboot info overlays for gdb/QEMU memory overlay testing.

Each overlay is a raw image of a multiboot v1 info struct (plus satellite
cmdline string) intended to be loaded at BASE, e.g.:

    (gdb) restore overlays/cmdline_populated.bin binary 0x90000
    (gdb) set $ebx = 0x90000

or baked in at launch:

    qemu-system-i386 ... -device loader,file=overlays/cmdline_populated.bin,addr=0x90000
"""

import struct
from pathlib import Path

BASE = 0x90000          # guest load address all pointers assume
CMDLINE_OFF = 0x80      # string placed just past the struct

FLAG_MEM = 1 << 0
FLAG_BOOTDEV = 1 << 1
FLAG_CMDLINE = 1 << 2

MEM_LOWER = 639
MEM_UPPER = 129920
BOOT_DEVICE = 0x8000FFFF   # drive 0x80, partition 0, no nesting


def build(flags: int, cmdline: bytes | None) -> bytes:
    buf = bytearray(CMDLINE_OFF)
    cmdline_ptr = (BASE + CMDLINE_OFF) if cmdline is not None else 0
    struct.pack_into(
        "<IIIII", buf, 0,
        flags, MEM_LOWER, MEM_UPPER, BOOT_DEVICE, cmdline_ptr,
    )
    if cmdline is not None:
        buf += cmdline + b"\x00"
    return bytes(buf)


def main() -> None:
    outdir = Path.cwd() / "build/overlays"
    #outdir = Path(__file__).resolve().parent / "build/overlays"
    outdir.mkdir(exist_ok=True,parents=True)

    overlays = {
        # realistic GRUB-style cmdline: kernel path then arguments
        "cmdline_populated.bin": build(
            FLAG_MEM | FLAG_BOOTDEV | FLAG_CMDLINE,
            b"/boot/eos.elf console=vga loglevel=7",
        ),
        # bit 2 clear: cmdline field is garbage and must not be read
        "cmdline_flag_clear.bin": build(
            FLAG_MEM | FLAG_BOOTDEV,
            None,
        ),
        # bit 2 set, pointer valid, string is empty: first byte is NUL
        "cmdline_empty.bin": build(
            FLAG_MEM | FLAG_BOOTDEV | FLAG_CMDLINE,
            b"",
        ),
    }

    for name, data in overlays.items():
        path = outdir / name
        path.write_bytes(data)
        print(f"{path}  ({len(data)} bytes)")

    print(f"\nload at 0x{BASE:08x}; cmdline ptr (when set) = 0x{BASE + CMDLINE_OFF:08x}")


if __name__ == "__main__":
    main()
