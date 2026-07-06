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
FLAG_MODS = 1 << 3

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


def build_modules(cmdline: bytes, mod_args: list[bytes],
                  payload_size: int = 64) -> bytes:
    """Multiboot struct + module descriptor array + arg strings + payloads.

    Layout (offsets from BASE):
      0x000  multiboot info struct
      0x080  module descriptors: len(mod_args) x 16 bytes
      0x0D0  arg strings, packed
      0x140  cmdline string
      0x180  module payloads, payload_size bytes each, distinct fill bytes
    """
    MODS_OFF, STRINGS_OFF, CMD_OFF, PAYLOAD_OFF = 0x080, 0x0D0, 0x140, 0x180
    count = len(mod_args)
    assert MODS_OFF + count * 16 <= STRINGS_OFF, "descriptors overflow strings"

    # arg strings packed sequentially; record their guest addresses
    str_addrs, off = [], STRINGS_OFF
    for arg in mod_args:
        str_addrs.append(BASE + off)
        off += len(arg) + 1
    assert off <= CMD_OFF, "arg strings overflow cmdline"

    # payloads: distinct fill byte per module so gdb dumps are recognizable
    descs, payloads = b"", b""
    for i, sa in enumerate(str_addrs):
        start = BASE + PAYLOAD_OFF + i * payload_size
        descs += struct.pack("<IIII", start, start + payload_size, sa, 0)
        payloads += bytes([0xAA + 0x11 * i]) * payload_size

    buf = bytearray(PAYLOAD_OFF)
    struct.pack_into(
        "<IIIIIII", buf, 0,
        FLAG_MEM | FLAG_BOOTDEV | FLAG_CMDLINE | FLAG_MODS,
        MEM_LOWER, MEM_UPPER, BOOT_DEVICE,
        BASE + CMD_OFF,        # cmdline     (+16)
        count,                 # mods_count  (+20)
        BASE + MODS_OFF,       # mods_addr   (+24)
    )
    for arg, addr in zip(mod_args, str_addrs):
        struct.pack_into(f"{len(arg) + 1}s", buf, addr - BASE, arg + b"\x00")
    struct.pack_into(f"{len(descs)}s", buf, MODS_OFF, descs)
    struct.pack_into(f"{len(cmdline) + 1}s", buf, CMD_OFF, cmdline + b"\x00")
    return bytes(buf) + payloads


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
        # bit 3 set, three fully-populated module descriptors with args,
        # payloads of distinct fill bytes (0xAA, 0xBB, 0xCC)
        "modules_3.bin": build_modules(
            b"/boot/eos.elf console=vga",
            [
                b"/boot/initrd.img root=/dev/hda1",
                b"/boot/font.psf",
                b"/boot/eos.cfg quiet",
            ],
        ),
    }

    for name, data in overlays.items():
        path = outdir / name
        path.write_bytes(data)
        print(f"{path}  ({len(data)} bytes)")

    print(f"\nload at 0x{BASE:08x}; cmdline ptr (when set) = 0x{BASE + CMDLINE_OFF:08x}")


if __name__ == "__main__":
    main()
