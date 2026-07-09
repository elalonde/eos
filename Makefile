BUILD_DIR = build
UT_BUILD_DIR = testbuild
OVERLAY_BUILD_DIR = $(UT_BUILD_DIR)/overlay
SRC_DIR = src
ISO_BUILD_DIR = $(BUILD_DIR)/isobuild
BOOT_BUILD_DIR = $(ISO_BUILD_DIR)/boot
GRUB_SRC_DIR = $(SRC_DIR)/iso/boot/grub
GRUB_BUILD_DIR = $(BOOT_BUILD_DIR)/grub
ISO = $(BUILD_DIR)/eos.iso
KERNEL = $(BOOT_BUILD_DIR)/kernel.elf
GRUB_CFG = $(GRUB_BUILD_DIR)/grub.cfg
GRUB_SRC = $(GRUB_SRC_DIR)/grub.cfg
INCS := $(wildcard $(SRC_DIR)/*.inc)
SRCS := $(wildcard $(SRC_DIR)/*.c) $(wildcard $(SRC_DIR)/*.s)
OBJS := $(patsubst $(SRC_DIR)/%.s,$(BUILD_DIR)/%.o,$(patsubst $(SRC_DIR)/%.c,$(BUILD_DIR)/%.o,$(SRCS)))
UT_OVERLAY_BINS := \
	$(OVERLAY_BUILD_DIR)/aout_syms.bin \
	$(OVERLAY_BUILD_DIR)/cmdline_empty.bin \
	$(OVERLAY_BUILD_DIR)/cmdline_flag_clear.bin \
	$(OVERLAY_BUILD_DIR)/cmdline_populated.bin \
	$(OVERLAY_BUILD_DIR)/drives_1994.bin \
	$(OVERLAY_BUILD_DIR)/everything.bin \
	$(OVERLAY_BUILD_DIR)/modules_3.bin
UT_OVERLAY_SENTINEL := $(OVERLAY_BUILD_DIR)/.sentinal
UT_OVERLAY_GENERATOR := bin/gen_overlays.py

CC = gcc
CFLAGS = -m32 -nostdlib -nostdinc -fno-builtin -fno-stack-protector \
	-nostartfiles -nodefaultlibs -Wall -Wextra -Werror
LDFLAGS = -T $(SRC_DIR)/link.ld -melf_i386
AS = nasm
ASFLAGS = -f elf -Isrc

.PHONY: all run debug clean gdb test testclean

all: $(ISO)

run: $(ISO)
	qemu-system-i386 -cdrom $(ISO)

debug: $(ISO)
	qemu-system-i386 \
		-d int,cpu_reset \
		-no-reboot \
		-cdrom $(ISO) \
		-gdb tcp::1234 \
		-S

gdb:
	gdb -ex "target remote localhost:1234" \
		-ex "hbreak load_eos" \
		$(KERNEL)

test: $(UT_OVERLAY_SENTINEL) $(ISO) | $(UT_BUILD_DIR) \
$(OVERLAY_BUILD_DIR)
	echo "todo"

testclean:
	rm -rf $(UT_BUILD_DIR)/*

$(UT_OVERLAY_SENTINEL): $(UT_OVERLAY_BINS)
	touch $(UT_OVERLAY_SENTINEL)

$(UT_OVERLAY_BINS): $(UT_OVERLAY_GENERATOR)
	bin/gen_overlays.py

$(ISO): $(KERNEL) $(GRUB_CFG) | $(ISO_BUILD_DIR)
	grub-mkrescue -o $(ISO) $(ISO_BUILD_DIR)

$(KERNEL): $(OBJS) | $(BOOT_BUILD_DIR)
	ld $(LDFLAGS) $(OBJS) -o $(KERNEL)

$(GRUB_CFG): $(GRUB_SRC) | $(GRUB_BUILD_DIR)
	install --mode=0644 $< $@

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.s $(INCS) | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $< -o $@

$(BOOT_BUILD_DIR) $(GRUB_BUILD_DIR) $(BUILD_DIR) $(ISO_BUILD_DIR) \
$(UT_BUILD_DIR) $(OVERLAY_BUILD_DIR):
	mkdir -p $@

clean:
	rm -rf $(BUILD_DIR)/*
