%include "multiboot.inc"

global mb_prn_rpt

extern crtc_write_cursor ; crtc.s
extern fb_mem_addr       ; fb.s
extern fb_skip_line      ; fb.s
extern fb_indent_bytes   ; fb.s
extern byte_to_hex       ; util.s
extern prn_byte          ; prn.s
extern prn_hex_byte      ; prn.s
extern prn_hex_dword     ; prn.s
extern prn_cstr          ; prn.s
extern prn_dec           ; prn.s
extern prn_msg           ; prn.s

MB_RPT_INDENT_BYTES equ 0x8
FLG_MEM equ 0x1
FLG_BOOT_DEV equ 0x2
FLG_CMDLINE equ 0x4
FLG_MODULES equ 0x8
BOOT_DEV_OFF equ 0xc
ASCII_FF equ 0x4646

section .bss
	mb_flags resd 1

section .rodata
	mb_pre db "GRUB multiboot report:"
	mb_pre_len equ $-mb_pre
	lower_msg db "Lower memory: "
	lower_len equ $-lower_msg
	upper_msg db "Upper memory: "
	upper_len equ $-upper_msg
	kb_msg db " KB"
	kb_len equ $-kb_msg
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
	push ebx
	mov eax, [ebx]
	mov [mb_flags], eax

	; open lease
	mov edi, [fb_mem_addr]

	call fb_skip_line
	mov esi, mb_pre
	mov ecx, mb_pre_len
	call prn_msg

	; indent lines with report contents
	mov dword [fb_indent_bytes], MB_RPT_INDENT_BYTES

	test byte [mb_flags], FLG_MEM
	jz .skipmem
	; lower mem
	call fb_skip_line
	mov esi, lower_msg
	mov ecx, lower_len
	call prn_msg
	mov eax, [ebx+0x4]
	call prn_dec
	mov esi, kb_msg
	mov ecx, kb_len
	call prn_msg
	; upper mem
	call fb_skip_line
	mov esi, upper_msg
	mov ecx, upper_len
	call prn_msg
	mov eax, [ebx+0x8]
	call prn_dec
	mov esi, kb_msg
	mov ecx, kb_len
	call prn_msg
.skipmem:
	test byte [mb_flags], FLG_BOOT_DEV
	jz .skipboot
	call fb_skip_line
	mov esi, boot_dev_msg
	mov ecx, boot_dev_len
	call prn_msg
	mov eax, [ebx+0xc]
	call prn_boot_dev_nfo
.skipboot:
	; cmdline
	; test flag and also for empty string
	test byte [mb_flags], FLG_CMDLINE
	jz .skipcmdline
	mov eax, [ebx+0x10]
	cmp byte [eax], 0
	jz .skipcmdline
	call fb_skip_line
	mov esi, cmdline_msg
	mov ecx, cmdline_msg_len
	call prn_msg
	mov esi, [ebx+0x10]
	call prn_cstr
.skipcmdline:
	; loaded modules
	test byte [mb_flags], FLG_MODULES
	jz .skipmodules
	call fb_skip_line
	mov esi, modules_msg
	mov ecx, modules_msg_len
	call prn_msg
	mov eax, [ebx+0x14]
	call prn_dec
	mov ecx, [ebx+0x14]
	test ecx, ecx
	jz .skipmodules
	mov eax, [ebx+0x18]
	call prn_boot_modules
.skipmodules:

	; unset indent
	mov dword [fb_indent_bytes], 0x0

	; close lease
	mov [fb_mem_addr], edi
	call crtc_write_cursor
	pop ebx
	ret

; eax contains the boot device information (preserved)
prn_boot_dev_nfo:
	; print boot device
	mov ecx, 3
	call prn_hex_byte

	; print boot partitions, if any
	mov ecx, 2
.prn_partitions_loop:
	; convert partition to hex
	call byte_to_hex
	cmp dx, ASCII_FF
	je .loop_done
	cmp ecx, 2
	jne .prn_period
	mov dl, ' '
	call prn_byte
	mov dl, '('
	call prn_byte
	jmp .prn_partition
.prn_period:
	mov dl, '.'
	call prn_byte
.prn_partition:
	push ecx
	call prn_hex_byte
	pop ecx
	dec ecx
	jns .prn_partitions_loop
.loop_done:
	; iff sentinel encountered on first iteration
	cmp ecx, 2
	je .skip_close_paren
	mov dl, ')'
	call prn_byte
.skip_close_paren:
	ret

; eax is the address of the module array (consumed)
; ecx has count of modules (consumed)
; precondition: ecx >= 1
prn_boot_modules:
	push ebx
	mov ebx, eax
	; increase visual indent
	add dword [fb_indent_bytes], MB_RPT_INDENT_BYTES
.prn_module_loop:
	push ecx
	call fb_skip_line
	mov esi, module_start_addr_msg
	mov ecx, module_start_addr_msg_len
	call prn_msg
	mov eax, [ebx]
	call prn_hex_dword

	add ebx, 4
	call fb_skip_line
	mov esi, module_end_addr_msg
	mov ecx, module_end_addr_msg_len
	call prn_msg
	mov eax, [ebx]
	call prn_hex_dword

	add ebx, 4
	call fb_skip_line
	mov esi, module_args_msg
	mov ecx, module_args_msg_len
	call prn_msg
	mov esi, [ebx]
	call prn_cstr

	; offset 12 is reserved
	add ebx, 8

	call fb_skip_line
	pop ecx
	dec ecx
	jnz .prn_module_loop

	sub dword [fb_indent_bytes], 4
	pop ebx
	ret
