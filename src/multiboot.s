%include "multiboot.inc"

global mb_prn_rpt

extern crtc_write_cursor ; crtc.s
extern fb_mem_addr       ; fb.s
extern fb_skip_line      ; fb.s
extern fb_indent_bytes   ; fb.s
extern prn_msg           ; prn.s

MB_RPT_INDENT_BYTES equ 0x8

section .rodata
	mb_pre db "GRUB multiboot report:"
	mb_pre_len equ $-mb_pre
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
	mmap_legth_msg_len equ $-mmap_length_msg
	mmap_addr_msg db "Memory map start address: "
	mmap_addr_msg_len equ $-mmap_addr_msg

section .text

mb_prn_rpt:
	mov edi, [fb_mem_addr]

	call fb_skip_line
	mov esi, mb_pre
	mov ecx, mb_pre_len
	call prn_msg

	; indent lines with report contents
	mov dword [fb_indent_bytes], MB_RPT_INDENT_BYTES

	mov dword [fb_indent_bytes], 0x0

	; close lease
	mov [fb_mem_addr], edi
	call crtc_write_cursor
	ret
