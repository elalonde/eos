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
FLAG_APM = 1 << 10
FLAG_VBE = 1 << 11
FLAG_FRAMEBUFFER = 1 << 12

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

# APM table (flag bit 10): pointer at struct offset 68 to a 20-byte
# table, APM BIOS spec 1.2 layout. Nine mostly-word fields, so the
# failure modes are adjacent-word transposition and half-word /
# byte-order confusion — every tracer word is unique fleet-wide and
# none is palindromic (high byte always differs from low byte).
# version is the one period-real value (APM 1.2); the rest is dye.
APM_TABLE = dict(
    version=0x0102,        # APM 1.2, BCD-flavored major.minor
    cseg=0xF0C1,
    offset=0x000BD2E4,     # the lone dword, splitting the word runs
    cseg_16=0xF1C2,
    dseg=0xF2D3,
    flags=0x0A21,
    cseg_len=0xFE10,
    cseg_16_len=0xFE21,
    dseg_len=0xFE32,
)

# VBE satellites (flag bit 11): the two pointers target blocks the
# video BIOS filled. Their internal layouts belong to the VBE spec,
# not multiboot, and eos prints only the pointers — so the fixture
# blocks are OPAQUE dye, not modeled structures. The control block
# leads with the period-correct "VESA" signature so a hex dump is
# instantly recognizable; the mode block gets a distinct fill. If eos
# ever parses interiors, these must grow into real VBE-spec layouts.
VBE_CONTROL_BLOB = b"VESA" + bytes([0xB6]) * 28
VBE_MODE_BLOB = bytes([0xB7]) * 32

# vbe_mode: the word's individual bits carry meaning (a convention not
# yet discussed in the project) — treated as an opaque tracer here.
# seg:off is the far-pointer idiom again (VBE 2.0 protected-mode
# entry, segment stored first); len completes the triple. The spec
# defines all-zero here as "interface not available" — these are
# deliberately nonzero so the populated path is what gets exercised.
# Tracers unique fleet-wide, non-palindromic.
VBE_MODE = 0x4115
VBE_IF_SEG = 0xC0A5
VBE_IF_OFF = 0x96B4
VBE_IF_LEN = 0x00C8

# Framebuffer fields (flag bit 12), struct offsets 88..115. Period
# flavor matches drives_1994: a 1024x768 mode on a 1994-vintage card
# is 8bpp INDEXED (type 0) — a 1 MB card hasn't the RAM for direct
# color at that resolution — so indexed is this fleet's native
# variant, with the palette satellite that entails. Types 1 (RGB)
# and 2 (EGA text) are the union's other legs, unfixtured for now.
# pitch is deliberately NOT width*bytes (1152 vs 1024): a padded
# scanline is legal, and pitch/width conflation must not be able to
# hide. addr is a period-plausible sub-4GiB LFB — which means the
# qword's high dword is zero and a half-swap there is invisible;
# accepted trade, flavor over dye.
FB_ADDR = 0x00000000E0000000
FB_PITCH = 1152
FB_WIDTH = 1024
FB_HEIGHT = 768
FB_BPP = 8
FB_TYPE_INDEXED = 0

# The palette satellite: 3-byte RGB descriptors. The canonical VGA
# 16-color set — period-correct, and its 0x00/0x55/0xAA/0xFF bytes
# make a gdb dump self-identifying.
FB_PALETTE = [
    (0x00, 0x00, 0x00), (0x00, 0x00, 0xAA),
    (0x00, 0xAA, 0x00), (0x00, 0xAA, 0xAA),
    (0xAA, 0x00, 0x00), (0xAA, 0x00, 0xAA),
    (0xAA, 0x55, 0x00), (0xAA, 0xAA, 0xAA),
    (0x55, 0x55, 0x55), (0x55, 0x55, 0xFF),
    (0x55, 0xFF, 0x55), (0x55, 0xFF, 0xFF),
    (0xFF, 0x55, 0x55), (0xFF, 0x55, 0xFF),
    (0xFF, 0xFF, 0x55), (0xFF, 0xFF, 0xFF),
]


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


def pack_apm(version: int, cseg: int, offset: int, cseg_16: int,
             dseg: int, flags: int, cseg_len: int, cseg_16_len: int,
             dseg_len: int) -> bytes:
    """One multiboot APM table: version(2) cseg(2) offset(4) cseg_16(2)
    dseg(2) flags(2) cseg_len(2) cseg_16_len(2) dseg_len(2) = 20 bytes.
    Mixed-width — the lone dword at +4 splits the word runs, so this is
    fixed-base-plus-displacement territory, not a uniform array."""
    return struct.pack(
        "<HHIHHHHHH", version, cseg, offset, cseg_16,
        dseg, flags, cseg_len, cseg_16_len, dseg_len,
    )


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


def build_apm(table: dict) -> bytes:
    """Multiboot struct with bit 10 (+mem/bootdev) set: apm_table
    pointer at offset 68, the 20-byte table satellite at 0x80."""
    APM_OFF = 0x80
    buf = bytearray(APM_OFF)
    struct.pack_into(
        "<IIII", buf, 0,
        FLAG_MEM | FLAG_BOOTDEV | FLAG_APM,
        MEM_LOWER, MEM_UPPER, BOOT_DEVICE,
    )
    struct.pack_into("<I", buf, 68, BASE + APM_OFF)
    return bytes(buf) + pack_apm(**table)


def build_vbe() -> bytes:
    """Multiboot struct with bit 11 (+mem/bootdev) set: two dword
    pointers then four words at offsets 72..87. Control block at 0x80,
    mode block packed just past it."""
    CTRL_OFF = 0x80
    mode_off = CTRL_OFF + len(VBE_CONTROL_BLOB)
    buf = bytearray(CTRL_OFF)
    struct.pack_into(
        "<IIII", buf, 0,
        FLAG_MEM | FLAG_BOOTDEV | FLAG_VBE,
        MEM_LOWER, MEM_UPPER, BOOT_DEVICE,
    )
    struct.pack_into(
        "<IIHHHH", buf, 72,
        BASE + CTRL_OFF, BASE + mode_off,
        VBE_MODE, VBE_IF_SEG, VBE_IF_OFF, VBE_IF_LEN,
    )
    return bytes(buf) + VBE_CONTROL_BLOB + VBE_MODE_BLOB


def pack_palette(palette: list[tuple[int, int, int]]) -> bytes:
    """Palette satellite: 3-byte red/green/blue descriptors,
    back-to-back, no count field — the count lives in the struct's
    framebuffer_palette_num_colors, nowhere in the satellite."""
    return b"".join(struct.pack("<BBB", r, g, b) for r, g, b in palette)


def pack_fb_fields(buf: bytearray, palette_addr: int,
                   num_colors: int) -> None:
    """Framebuffer fields into struct offsets 88..115: addr(8)
    pitch(4) width(4) height(4) bpp(1) type(1), then the color_info
    union at 110 in its type-0 (indexed) shape: palette_addr(4)
    palette_num_colors(2). The union's shape is selected by the type
    BYTE at 109 — a value-discriminated union, unlike the flag-bit-
    discriminated syms union."""
    struct.pack_into(
        "<QIIIBB", buf, 88,
        FB_ADDR, FB_PITCH, FB_WIDTH, FB_HEIGHT, FB_BPP, FB_TYPE_INDEXED,
    )
    struct.pack_into("<IH", buf, 110, palette_addr, num_colors)


def build_fb_indexed(palette: list[tuple[int, int, int]]) -> bytes:
    """Multiboot struct with bit 12 (+mem/bootdev) set, type 0
    (indexed): framebuffer fields at 88..115, palette satellite at
    0x80. First fixture whose struct reads run past offset 88 — and
    the struct now ends at 116, twelve bytes shy of the 0x80
    satellite convention."""
    PALETTE_OFF = 0x80
    buf = bytearray(PALETTE_OFF)
    struct.pack_into(
        "<IIII", buf, 0,
        FLAG_MEM | FLAG_BOOTDEV | FLAG_FRAMEBUFFER,
        MEM_LOWER, MEM_UPPER, BOOT_DEVICE,
    )
    pack_fb_fields(buf, BASE + PALETTE_OFF, len(palette))
    return bytes(buf) + pack_palette(palette)


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
                     payload_size: int = 64,
                     symtab: str = "elf") -> bytes:
    """Union of every overlay's targeted data: mem + bootdev + cmdline
    + modules + symbol fields + mmap + drives + config + loader name
    + APM + VBE + framebuffer (type 0, indexed, palette satellite),
    all satellites populated.

    Offsets 28..40 are ONE union — a.out (bit 4) or ELF (bit 5), never
    both — so "everything" is necessarily a two-variant family:
    symtab="elf" fills the union's ELF half, symtab="aout" the a.out
    half (satellite in its dedicated slot, which the elf variant
    leaves zeroed).

    Layout (offsets from BASE):
      0x000  multiboot info struct
      0x080  module descriptors: len(mod_args) x 16 bytes
      0x0D0  arg strings, packed
      0x140  cmdline string
      0x170  drive structures, back-to-back (self-sized)
      0x1B0  mmap entries: len(mmap_entries) x 24 bytes
      0x240  ROM config table blob, then loader-name cstring
      0x280  APM table, 20 bytes
      0x2A0  VBE control block, then mode block
      0x2E0  a.out symbol satellite (aout variant only)
      0x340  framebuffer palette: 16 x 3-byte RGB descriptors
      0x380  module payloads, payload_size bytes each, distinct fill bytes
    """
    assert symtab in ("elf", "aout"), "symtab must be 'elf' or 'aout'"
    MODS_OFF, STRINGS_OFF, CMD_OFF = 0x080, 0x0D0, 0x140
    DRIVES_OFF, MMAP_OFF = 0x170, 0x1B0
    CONFIG_OFF, APM_OFF, VBE_OFF = 0x240, 0x280, 0x2A0
    AOUT_OFF, PALETTE_OFF, PAYLOAD_OFF = 0x2E0, 0x340, 0x380
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
    assert name_off + len(LOADER_NAME) + 1 <= APM_OFF, \
        "config+name overflow apm"

    apm = pack_apm(**APM_TABLE)
    assert APM_OFF + len(apm) <= VBE_OFF, "apm overflows vbe"

    vbe_mode_off = VBE_OFF + len(VBE_CONTROL_BLOB)
    assert vbe_mode_off + len(VBE_MODE_BLOB) <= AOUT_OFF, \
        "vbe blocks overflow aout"

    aout_blob, tabsize, strsize = pack_aout_syms(AOUT_SYMBOLS)
    assert AOUT_OFF + len(aout_blob) <= PALETTE_OFF, \
        "aout satellite overflows palette"

    palette = pack_palette(FB_PALETTE)
    assert PALETTE_OFF + len(palette) <= PAYLOAD_OFF, \
        "palette overflows payloads"

    descs, payloads = b"", b""
    for i, sa in enumerate(str_addrs):
        start = BASE + PAYLOAD_OFF + i * payload_size
        descs += struct.pack("<IIII", start, start + payload_size, sa, 0)
        payloads += bytes([0xAA + 0x11 * i]) * payload_size

    symflag = FLAG_ELF if symtab == "elf" else FLAG_AOUT
    buf = bytearray(PAYLOAD_OFF)
    struct.pack_into(
        "<IIIIIII", buf, 0,
        FLAG_MEM | FLAG_BOOTDEV | FLAG_CMDLINE | FLAG_MODS
        | symflag | FLAG_MMAP | FLAG_DRIVES
        | FLAG_CONFIG | FLAG_LOADER_NAME | FLAG_APM | FLAG_VBE
        | FLAG_FRAMEBUFFER,
        MEM_LOWER, MEM_UPPER, BOOT_DEVICE,
        BASE + CMD_OFF,        # cmdline       (+16)
        count,                 # mods_count    (+20)
        BASE + MODS_OFF,       # mods_addr     (+24)
    )
    if symtab == "elf":
        struct.pack_into(
            "<IIII", buf, 28,
            ELF_NUM, ELF_ENTSIZE, ELF_ADDR, ELF_SHNDX,  # elf_sec (+28..+40)
        )
    else:
        struct.pack_into(
            "<IIII", buf, 28,
            tabsize, strsize, BASE + AOUT_OFF, 0,       # aout_sym (+28..+40)
        )
    struct.pack_into(
        "<II", buf, 44,
        len(mmap), BASE + MMAP_OFF,                  # mmap_length/addr
    )
    struct.pack_into("<II", buf, 52, len(drive), BASE + DRIVES_OFF)
    struct.pack_into("<I", buf, 60, BASE + CONFIG_OFF)   # config_table
    struct.pack_into("<I", buf, 64, BASE + name_off)     # boot_loader_name
    struct.pack_into("<I", buf, 68, BASE + APM_OFF)      # apm_table
    struct.pack_into(
        "<IIHHHH", buf, 72,                              # vbe_* (+72..+87)
        BASE + VBE_OFF, BASE + vbe_mode_off,
        VBE_MODE, VBE_IF_SEG, VBE_IF_OFF, VBE_IF_LEN,
    )
    pack_fb_fields(buf, BASE + PALETTE_OFF, len(FB_PALETTE))  # fb (+88..+115)
    for arg, addr in zip(mod_args, str_addrs):
        struct.pack_into(f"{len(arg) + 1}s", buf, addr - BASE, arg + b"\x00")
    struct.pack_into(f"{len(descs)}s", buf, MODS_OFF, descs)
    struct.pack_into(f"{len(cmdline) + 1}s", buf, CMD_OFF, cmdline + b"\x00")
    struct.pack_into(f"{len(drive)}s", buf, DRIVES_OFF, drive)
    struct.pack_into(f"{len(mmap)}s", buf, MMAP_OFF, mmap)
    struct.pack_into(f"{len(CONFIG_TABLE)}s", buf, CONFIG_OFF, CONFIG_TABLE)
    struct.pack_into(f"{len(LOADER_NAME) + 1}s", buf, name_off,
                     LOADER_NAME + b"\x00")
    struct.pack_into(f"{len(apm)}s", buf, APM_OFF, apm)
    struct.pack_into(f"{len(VBE_CONTROL_BLOB)}s", buf, VBE_OFF,
                     VBE_CONTROL_BLOB)
    struct.pack_into(f"{len(VBE_MODE_BLOB)}s", buf, vbe_mode_off,
                     VBE_MODE_BLOB)
    struct.pack_into(f"{len(palette)}s", buf, PALETTE_OFF, palette)
    if symtab == "aout":
        struct.pack_into(f"{len(aout_blob)}s", buf, AOUT_OFF, aout_blob)
    return bytes(buf) + payloads


def main() -> None:
    outdir = Path.cwd() / "testbuild/overlay"
    #outdir = Path(__file__).resolve().parent / "testbuild/overlay"
    outdir.mkdir(exist_ok=True, parents=True)

    everything_args = dict(
        cmdline=b"/boot/eos.elf console=vga loglevel=7",
        mod_args=[
            b"/boot/initrd.img root=/dev/hda1",
            b"/boot/font.psf",
            b"/boot/eos.cfg quiet",
        ],
        drive_list=DRIVES_1994,
        mmap_entries=MMAP_ENTRIES,
    )

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
        # bit 10 set: the 20-byte APM table, transposition-hostile
        # word tracers
        "apm.bin": build_apm(APM_TABLE),
        # bit 11 set: VBE pointer pair to opaque signature blocks plus
        # the mode/seg/off/len word run
        "vbe.bin": build_vbe(),
        # bit 12 set, type 0: the 1994-native framebuffer — 1024x768x8
        # indexed, VGA 16-color palette satellite, padded pitch
        "fb_indexed_1994.bin": build_fb_indexed(FB_PALETTE),
        # every flag and satellite from all overlays above, in one
        # image — union offsets 28..40 carry the ELF half here
        "everything.bin": build_everything(**everything_args),
        # same image with the union's a.out half: bit 4 for bit 5,
        # symbol satellite populated in its slot
        "everything_aout.bin": build_everything(
            **everything_args, symtab="aout",
        ),
    }

    for name, data in overlays.items():
        path = outdir / name
        path.write_bytes(data)
        print(f"{path}  ({len(data)} bytes)")

    print(f"\nload at 0x{BASE:08x}; cmdline ptr (when set) = 0x{BASE + CMDLINE_OFF:08x}")


if __name__ == "__main__":
    main()
