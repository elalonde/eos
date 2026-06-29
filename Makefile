BUILD_DIR = build
SRC_DIR = src
ISO_BUILD_DIR = $(BUILD_DIR)/iso
BOOT_BUILD_DIR = $(ISO_BUILD_DIR)/boot
GRUB_SRC_DIR = $(SRC_DIR)/iso/boot/grub
GRUB_BUILD_DIR = $(BOOT_BUILD_DIR)/grub
ISO = $(BUILD_DIR)/eos.iso
KERNEL = $(BOOT_BUILD_DIR)/kernel.elf
GRUB_CFG = $(GRUB_BUILD_DIR)/grub.cfg
GRUB_SRC = $(GRUB_SRC_DIR)/grub.cfg
SRCS := $(wildcard $(SRC_DIR)/*.c) $(wildcard $(SRC_DIR)/*.s)
OBJS := $(patsubst $(SRC_DIR)/%.s,$(BUILD_DIR)/%.o,$(patsubst $(SRC_DIR)/%.c,$(BUILD_DIR)/%.o,$(SRCS)))

CC = gcc
CFLAGS = -m32 -nostdlib -nostdinc -fno-builtin -fno-stack-protector \
	-nostartfiles -nodefaultlibs -Wall -Wextra -Werror
LDFLAGS = -T $(SRC_DIR)/link.ld -melf_i386
AS = nasm
ASFLAGS = -f elf

.PHONY: all run debug clean gdb

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

$(ISO): $(KERNEL) $(GRUB_CFG) | $(ISO_BUILD_DIR)
	grub-mkrescue -o $(ISO) $(ISO_BUILD_DIR)

$(KERNEL): $(OBJS) | $(BOOT_BUILD_DIR)
	ld $(LDFLAGS) $(OBJS) -o $(KERNEL)

$(GRUB_CFG): $(GRUB_SRC) | $(GRUB_BUILD_DIR)
	install --mode=0644 $< $@

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.s | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $< -o $@

$(BOOT_BUILD_DIR) $(GRUB_BUILD_DIR) $(BUILD_DIR) $(ISO_BUILD_DIR):
	mkdir -p $@

clean:
	rm -rf $(BUILD_DIR)/*
