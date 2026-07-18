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
FLAG_AOUT = 1 << 4
FLAG_ELF = 1 << 5
FLAG_MMAP = 1 << 6
FLAG_DRIVES = 1 << 7
FLAG_CONFIG = 1 << 8
FLAG_LOADER_NAME = 1 << 9

MEM_LOWER = 639
MEM_UPPER = 129920
# drive 0x80, all three partition levels populated (disklabel-style
# nesting: DOS partition 1 -> sub-partition 2 -> sub-sub 3), no 0xFF
# sentinels anywhere
BOOT_DEVICE = 0x80010203

# ELF section header fields (flag bit 5), values from a live eos boot:
# 7 headers, 40 bytes each, table at 0x00010138, string table index 6
ELF_NUM = 7
ELF_ENTSIZE = 40
ELF_ADDR = 0x00010138
ELF_SHNDX = 6

# a.out symbols (flag bit 4) — mutually exclusive with bit 5: both
# describe the same union bytes at struct offsets 28..40, so a.out gets
# its own overlay and never rides along with the ELF fields.
# (name, value, n_type); 0x05 = N_TEXT | N_EXT (global text symbol)
AOUT_SYMBOLS = [
    (b"_start", 0x00100090, 0x05),
    (b"kmain", 0x00100200, 0x05),
    (b"prn_byte", 0x00100450, 0x05),
]

# memory map (flag bit 6): 6 QEMU-style e820 entries x 24 bytes = 144
# bytes total, matching the live boot's "Memory map length: 144 bytes".
# (base, length, type); type 1 = available RAM, 2 = reserved.
MMAP_ENTRIES = [
    (0x0000000000000000, 0x000000000009FC00, 1),   # low RAM, 639 KB
    (0x000000000009FC00, 0x0000000000000400, 2),   # EBDA
    (0x00000000000F0000, 0x0000000000010000, 2),   # BIOS ROM shadow
    (0x0000000000100000, 0x0000000007EE0000, 1),   # main RAM, 129920 KB
    (0x0000000007FE0000, 0x0000000000020000, 2),   # top-of-RAM reserved
    (0x00000000FFFC0000, 0x0000000000040000, 2),   # flash/ROM at 4 GB
]

# A period-correct 1994 machine's drive fleet, in BIOS enumeration
# order. drive_mode 0 = CHS, 1 = LBA (it's 1994: CHS everywhere).
# The ports lists deliberately differ in length so the drive entries
# differ in SIZE (18/16/16 bytes) — a walker that hardcodes any stride
# desyncs at the second entry; only honoring each entry's own
# self-inclusive size field walks this fleet correctly.
DRIVES_1994 = [
    # 3.5" 1.44 MB floppy (drive A:), AT FDC ports incl. DOR/MSR/FIFO
    dict(number=0x00, mode=0, cylinders=80, heads=2, sectors=18,
         ports=(0x3F2, 0x3F4, 0x3F5)),
    # primary-master IDE HDD at the classic 1024/16/63 BIOS ceiling
    # (~504 MiB), primary IDE command + control blocks
    dict(number=0x80, mode=0, cylinders=1024, heads=16, sectors=63,
         ports=(0x1F0, 0x3F6)),
    # secondary-master IDE HDD, a ~340 MB WD-Caviar-class disk,
    # secondary IDE command + control blocks
    dict(number=0x81, mode=0, cylinders=1010, heads=12, sectors=55,
         ports=(0x170, 0x376)),
]

# Bootloader name (flag bit 9): same pointer-to-cstring species as
# cmdline. Deliberately NOT a plausible GRUB string, so a wrong-pointer
# bug can't masquerade as a correct read.
LOADER_NAME = b"eos-fixture-loader 9.9"

# ROM config table (flag bit 8): format is the BIOS INT 15h/AH=C0h
# Get Configuration table, which Multiboot points at but does not
# define. eos therefore never walks it -- the fixture exists so the
# gate and (at most) a pointer print can be exercised. Length word is
# SELF-EXCLUSIVE (counts the bytes after itself): third convention in
# the report after mmap (self-exclusive) and drives (self-inclusive).
# Body bytes are period-flavored tracer dye: model 0xFC (AT-class),
# submodel 0x01, BIOS rev 0x00, feature bytes 0x74 0x40, then two
# 0xC7 filler bytes so a hex dump has a recognizable signature.
CONFIG_TABLE = struct.pack("<H", 7) + bytes(
    [0xFC, 0x01, 0x00, 0x74, 0x40, 0xC7, 0xC7]
)


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


def pack_drive(number: int, mode: int, cylinders: int, heads: int,
               sectors: int, ports: tuple[int, ...]) -> bytes:
    """One multiboot drive structure.

    Layout: size(4) number(1) mode(1) cylinders(2) heads(1) sectors(1),
    then zero-terminated array of 2-byte I/O ports. size counts the
    whole structure, terminator included.
    """
    ports_blob = b"".join(struct.pack("<H", p) for p in (*ports, 0))
    size = 10 + len(ports_blob)
    return struct.pack(
        "<IBBHBB", size, number, mode, cylinders, heads, sectors
    ) + ports_blob


def build_drives(drive_list: list[dict]) -> bytes:
    """Multiboot struct with only bit 7 (+mem/bootdev) set; the drive
    structures packed back-to-back, drives_length spanning them all."""
    DRIVES_OFF = 0x80
    drives = b"".join(pack_drive(**d) for d in drive_list)
    buf = bytearray(DRIVES_OFF)
    struct.pack_into(
        "<IIII", buf, 0,
        FLAG_MEM | FLAG_BOOTDEV | FLAG_DRIVES,
        MEM_LOWER, MEM_UPPER, BOOT_DEVICE,
    )
    struct.pack_into("<II", buf, 52, len(drives), BASE + DRIVES_OFF)
    return bytes(buf) + drives


def pack_mmap(entries: list[tuple[int, int, int]]) -> bytes:
    """Multiboot mmap buffer: each entry is size(4) base(8) length(8)
    type(4). size does NOT count itself; the walker hops
    entry += size + 4. All entries here are the standard 24-byte shape
    (size field = 20).
    """
    blob = b""
    for base, length, mtype in entries:
        blob += struct.pack("<IQQI", 20, base, length, mtype)
    return blob


def pack_aout_syms(symbols: list[tuple[bytes, int, int]]) -> tuple[bytes, int, int]:
    """a.out symbol satellite per the multiboot spec: tabsize dword,
    nlist array (12 bytes each: n_strx n_type n_other n_desc n_value),
    strsize dword, then the string blob. n_strx offsets count from the
    strsize dword itself (classic a.out), so the first string is at 4;
    strsize likewise includes its own 4 bytes.

    Returns (blob, tabsize, strsize) so the header fields can mirror
    the sizes embedded in the satellite.
    """
    strings, strx = b"", []
    for name, _value, _ntype in symbols:
        strx.append(4 + len(strings))
        strings += name + b"\x00"
    strsize = 4 + len(strings)

    nlists = b""
    for (name, value, ntype), sx in zip(symbols, strx):
        nlists += struct.pack("<IBBHI", sx, ntype, 0, 0, value)
    tabsize = len(nlists)

    blob = (struct.pack("<I", tabsize) + nlists
            + struct.pack("<I", strsize) + strings)
    return blob, tabsize, strsize


def build_aout(symbols: list[tuple[bytes, int, int]]) -> bytes:
    """Multiboot struct with bit 4 (+mem/bootdev) set: a.out symbol
    fields at offsets 28..40, satellite table just past the struct."""
    AOUT_OFF = 0x80
    blob, tabsize, strsize = pack_aout_syms(symbols)
    buf = bytearray(AOUT_OFF)
    struct.pack_into(
        "<IIII", buf, 0,
        FLAG_MEM | FLAG_BOOTDEV | FLAG_AOUT,
        MEM_LOWER, MEM_UPPER, BOOT_DEVICE,
    )
    struct.pack_into(
        "<IIII", buf, 28,
        tabsize, strsize, BASE + AOUT_OFF, 0,   # aout_sym (+28..+40)
    )
    return bytes(buf) + blob


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


def build_loader_and_config(name: bytes, config: bytes) -> bytes:
    """Multiboot struct with bits 8 and 9 (+mem/bootdev) set: config
    table blob at 0x80, loader-name cstring just past it."""
    CONFIG_OFF = 0x80
    name_off = CONFIG_OFF + len(config)
    buf = bytearray(CONFIG_OFF)
    struct.pack_into(
        "<IIII", buf, 0,
        FLAG_MEM | FLAG_BOOTDEV | FLAG_CONFIG | FLAG_LOADER_NAME,
        MEM_LOWER, MEM_UPPER, BOOT_DEVICE,
    )
    struct.pack_into("<I", buf, 60, BASE + CONFIG_OFF)   # config_table
    struct.pack_into("<I", buf, 64, BASE + name_off)     # boot_loader_name
    return bytes(buf) + config + name + b"\x00"


def build_everything(cmdline: bytes, mod_args: list[bytes],
                     drive_list: list[dict],
                     mmap_entries: list[tuple[int, int, int]],
                     payload_size: int = 64) -> bytes:
    """Union of every overlay's targeted data: mem + bootdev + cmdline
    + modules + ELF sections + mmap + drives, all flags set, all
    satellites populated.

    Layout (offsets from BASE):
      0x000  multiboot info struct
      0x080  module descriptors: len(mod_args) x 16 bytes
      0x0D0  arg strings, packed
      0x140  cmdline string
      0x170  drive structures, back-to-back (self-sized)
      0x1B0  mmap entries: len(mmap_entries) x 24 bytes
      0x240  ROM config table blob, then loader-name cstring
      0x280  module payloads, payload_size bytes each, distinct fill bytes
    """
    MODS_OFF, STRINGS_OFF, CMD_OFF = 0x080, 0x0D0, 0x140
    DRIVES_OFF, MMAP_OFF = 0x170, 0x1B0
    CONFIG_OFF, PAYLOAD_OFF = 0x240, 0x280
    count = len(mod_args)
    assert MODS_OFF + count * 16 <= STRINGS_OFF, "descriptors overflow strings"

    str_addrs, off = [], STRINGS_OFF
    for arg in mod_args:
        str_addrs.append(BASE + off)
        off += len(arg) + 1
    assert off <= CMD_OFF, "arg strings overflow cmdline"
    assert CMD_OFF + len(cmdline) + 1 <= DRIVES_OFF, "cmdline overflows drives"

    drive = b"".join(pack_drive(**d) for d in drive_list)
    assert DRIVES_OFF + len(drive) <= MMAP_OFF, "drives overflow mmap"

    mmap = pack_mmap(mmap_entries)
    assert MMAP_OFF + len(mmap) <= CONFIG_OFF, "mmap overflows config"

    name_off = CONFIG_OFF + len(CONFIG_TABLE)
    assert name_off + len(LOADER_NAME) + 1 <= PAYLOAD_OFF, \
        "config+name overflow payloads"

    descs, payloads = b"", b""
    for i, sa in enumerate(str_addrs):
        start = BASE + PAYLOAD_OFF + i * payload_size
        descs += struct.pack("<IIII", start, start + payload_size, sa, 0)
        payloads += bytes([0xAA + 0x11 * i]) * payload_size

    buf = bytearray(PAYLOAD_OFF)
    struct.pack_into(
        "<IIIIIII", buf, 0,
        FLAG_MEM | FLAG_BOOTDEV | FLAG_CMDLINE | FLAG_MODS
        | FLAG_ELF | FLAG_MMAP | FLAG_DRIVES
        | FLAG_CONFIG | FLAG_LOADER_NAME,
        MEM_LOWER, MEM_UPPER, BOOT_DEVICE,
        BASE + CMD_OFF,        # cmdline       (+16)
        count,                 # mods_count    (+20)
        BASE + MODS_OFF,       # mods_addr     (+24)
    )
    struct.pack_into(
        "<IIII", buf, 28,
        ELF_NUM, ELF_ENTSIZE, ELF_ADDR, ELF_SHNDX,   # elf_sec (+28..+40)
    )
    struct.pack_into(
        "<II", buf, 44,
        len(mmap), BASE + MMAP_OFF,                  # mmap_length/addr
    )
    struct.pack_into("<II", buf, 52, len(drive), BASE + DRIVES_OFF)
    struct.pack_into("<I", buf, 60, BASE + CONFIG_OFF)   # config_table
    struct.pack_into("<I", buf, 64, BASE + name_off)     # boot_loader_name
    for arg, addr in zip(mod_args, str_addrs):
        struct.pack_into(f"{len(arg) + 1}s", buf, addr - BASE, arg + b"\x00")
    struct.pack_into(f"{len(descs)}s", buf, MODS_OFF, descs)
    struct.pack_into(f"{len(cmdline) + 1}s", buf, CMD_OFF, cmdline + b"\x00")
    struct.pack_into(f"{len(drive)}s", buf, DRIVES_OFF, drive)
    struct.pack_into(f"{len(mmap)}s", buf, MMAP_OFF, mmap)
    struct.pack_into(f"{len(CONFIG_TABLE)}s", buf, CONFIG_OFF, CONFIG_TABLE)
    struct.pack_into(f"{len(LOADER_NAME) + 1}s", buf, name_off,
                     LOADER_NAME + b"\x00")
    return bytes(buf) + payloads


def main() -> None:
    outdir = Path.cwd() / "testbuild/overlay"
    #outdir = Path(__file__).resolve().parent / "testbuild/overlay"
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
        # bit 7 set: a 1994-vintage three-drive fleet (floppy + two
        # IDE HDDs) with UNEQUAL entry sizes (18/16/16) to exercise the
        # self-sizing array walk
        "drives_1994.bin": build_drives(DRIVES_1994),
        # bits 8+9 set: ROM config table blob (opaque, gate/pointer
        # test only) and a tracer-dye bootloader name cstring
        "loader_and_config.bin": build_loader_and_config(
            LOADER_NAME, CONFIG_TABLE,
        ),
        # bit 4 set: a.out symbol table (the ELF union's other half) —
        # three text symbols with nlist entries and a string table
        "aout_syms.bin": build_aout(AOUT_SYMBOLS),
        # every flag and satellite from all overlays above, in one image
        "everything.bin": build_everything(
            b"/boot/eos.elf console=vga loglevel=7",
            [
                b"/boot/initrd.img root=/dev/hda1",
                b"/boot/font.psf",
                b"/boot/eos.cfg quiet",
            ],
            DRIVES_1994,
            MMAP_ENTRIES,
        ),
    }

    for name, data in overlays.items():
        path = outdir / name
        path.write_bytes(data)
        print(f"{path}  ({len(data)} bytes)")

    print(f"\nload at 0x{BASE:08x}; cmdline ptr (when set) = 0x{BASE + CMDLINE_OFF:08x}")


if __name__ == "__main__":
    main()
