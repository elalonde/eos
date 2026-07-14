%include "multiboot.inc"
%include "fb.inc"

global prn_mb_rpt
extern fb_mem_addr

MB_RPT_INDENT_LEN equ 0x4

section .rodata
	bl_pre db "GRUB multiboot report:"
	bl_pre_len equ $-bl_pre
	lower_msg db "Lower memory: "
	lower_len equ $-lower_msg
	upper_msg db "Upper memory: "
	upper_len equ $-upper_msg
	boot_dev_msg db "Boot device: Drive "
	boot_dev_len equ $-boot_dev_msg
	cmdline_msg db "cmdline: "
	cmdline_msg_len equ $-cmdline_msg
	modules_msg db "Boot module count: "
	modules_msg_len equ $-modules_msg
	module_start_addr_msg db "Module start address: "
	module_start_addr_msg_len equ $-module_start_addr_msg
	module_end_addr_msg db "Module boundary address: "
	module_end_addr_msg_len equ $-module_end_addr_msg
	module_args_msg db "Module arguments: "
	module_args_msg_len equ $-module_args_msg
	elf_sect_msg db "ELF section information: "
	elf_sect_len equ $-elf_sect_msg
	elf_h_cnt_msg db "ELF header count: "
	elf_h_cnt_msg_len equ $-elf_h_cnt_msg
	elf_sect_entry_siz_msg db "ELF section header entry size: "
	elf_sect_entry_siz_msg_len equ $-elf_sect_entry_siz_msg
	elf_sect_table_addr_msg db "ELF section header table addr: "
	elf_sect_table_addr_msg_len equ $-elf_sect_table_addr_msg
	elf_sect_table_str_idx_msg db "ELF section header string table index: "
	elf_sect_table_str_idx_msg_len equ $-elf_sect_table_str_idx_msg
	mmap_length_msg db "Memory map length: "
	mmap_legth_msg_len equ $-elf_sect_table_mmap_msg
	mmap_addr_msg "Memory map start address: "
	mmap_addr_msg_len equ $-mmap_addr_msg

section .text

prn_mb_rpt:
	mov edi, [fb_mem_addr]
	mov dword [fb_indent_len], MB_RPT_INDENT_LEN

	mov edx, bl_pre
	mov eax, bl_pre_len
	call prn_msg


	mov [fb_mem_addr], edi
	ret
