%include "multiboot.inc"

global mb_prn_rpt

extern crtc_write_cursor ; crtc.s
extern fb_mem_addr       ; fb.s
extern fb_skip_line      ; fb.s
extern fb_indent_bytes   ; fb.s
extern byte_to_hex       ; util.s
extern prn_byte          ; prn.s
extern prn_cstr          ; prn.s
extern prn_dec           ; prn.s
extern prn_dec_byte      ; prn.s
extern prn_dec_wordl     ; prn.s
extern prn_hex_byte      ; prn.s
extern prn_hex_dword     ; prn.s
extern prn_hex_qword     ; prn.s
extern prn_msg           ; prn.s

MB_RPT_INDENT_BYTES equ 0x8
FLG_MEM equ 0x1
FLG_BOOT_DEV equ 0x2
FLG_CMDLINE equ 0x4
FLG_MODULES equ 0x8
FLG_ELF_SECTS equ 0x20
FLG_MMAP_ENTRIES equ 0x40
FLG_DRIVE_INFO equ 0x80
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
	b_msg db " bytes"
	b_msg_len equ $-b_msg
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
	elf_h_cnt_msg db "ELF section header count: "
	elf_h_cnt_msg_len equ $-elf_h_cnt_msg
	elf_sect_entry_siz_msg db "ELF section header entry size: "
	elf_sect_entry_siz_msg_len equ $-elf_sect_entry_siz_msg
	elf_sect_table_addr_msg db "ELF section header table addr: "
	elf_sect_table_addr_msg_len equ $-elf_sect_table_addr_msg
	elf_sect_table_str_idx_msg db "ELF section header string table index: "
	elf_sect_table_str_idx_msg_len equ $-elf_sect_table_str_idx_msg
	mmap_length_msg db "Memory map length: "
	mmap_length_msg_len equ $-mmap_length_msg
	mmap_addr_msg db "Memory map start address: "
	mmap_addr_msg_len equ $-mmap_addr_msg
	mmap_entry_siz_msg db "Memory map entry size: "
	mmap_entry_siz_len equ $-mmap_entry_siz_msg
	mmap_entry_addr_msg db "Memory map entry addr: "
	mmap_entry_addr_len equ $-mmap_entry_addr_msg
	mmap_entry_len_msg db "Memory map entry length: "
	mmap_entry_len_msg_len equ $-mmap_entry_len_msg
	mmap_entry_type_msg db "Memory map entry type: "
	mmap_entry_type_msg_len equ $-mmap_entry_type_msg
	mmap_type_avail_mem_msg db "Available RAM"
	mmap_type_avail_mem_msg_len equ $-mmap_type_avail_mem_msg
	mmap_type_resv_msg db "Reserved"
	mmap_type_resv_msg_len equ $-mmap_type_resv_msg
	mmap_type_acpi_msg db "ACPI Reclaimable"
	mmap_type_acpi_msg_len equ $-mmap_type_acpi_msg
	mmap_type_acpi_nvs_msg db "ACPI NVS"
	mmap_type_acpi_nvs_msg_len equ $-mmap_type_acpi_nvs_msg
	mmap_type_bad_ram_msg db "Bad RAM"
	mmap_type_bad_ram_msg_len equ $-mmap_type_bad_ram_msg
	mmap_type_unknown_msg db "Unknown"
	mmap_type_unknown_msg_len equ $-mmap_type_unknown_msg
	drives_arr_len_msg db "Drive information memory size: "
	drives_arr_len_msg_len equ $-drives_arr_len_msg
	drives_addr_msg db "Drive information address: "
	drives_addr_msg_len equ $-drives_addr_msg
	drive_entry_siz_msg db "Drive entry size: "
	drive_entry_siz_msg_len equ $-drive_entry_siz_msg
	drive_bios_num_msg db "Drive BIOS number: "
	drive_bios_num_msg_len equ $-drive_bios_num_msg
	drive_mode_msg db "Drive mode: "
	drive_mode_msg_len equ $-drive_mode_msg
	drive_cyl_msg db "Drive cylinders: "
	drive_cyl_msg_len equ $-drive_cyl_msg
	drive_head_msg db "Drive heads: "
	drive_head_msg_len equ $-drive_head_msg
	drive_sect_msg db "Drive sectors: "
	drive_sect_msg_len equ $-drive_sect_msg

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
	; elf section headers
	test byte [mb_flags], FLG_ELF_SECTS
	jz .skip_elf_sects
	call fb_skip_line
	call prn_elf_sects
.skip_elf_sects:
	; mmap_length and addresses
	test byte [mb_flags], FLG_MMAP_ENTRIES
	jz .skip_mmap_entries
	call fb_skip_line
	mov esi, mmap_length_msg
	mov ecx, mmap_length_msg_len
	call prn_msg
	; mmap entry array length
	mov eax, [ebx+0x2c]
	call prn_dec
	mov esi, b_msg
	mov ecx, b_msg_len
	call prn_msg
	; mmap starting address
	call fb_skip_line
	mov ecx, [ebx+0x2c]
	test ecx, ecx
	jz .skip_mmap_entries
	mov esi, mmap_addr_msg
	mov ecx, mmap_addr_msg_len
	call prn_msg
	mov eax, [ebx+0x30]
	call prn_hex_dword
	mov ecx, [ebx+0x2c]
	; mmap entries
	call prn_mmap_entries
.skip_mmap_entries:
	test byte [mb_flags], FLG_DRIVE_INFO
	jz .skip_drive_info
	; drive information
	call fb_skip_line
	mov esi, drives_arr_len_msg
	mov ecx, drives_arr_len_msg_len
	call prn_msg
	mov eax, [ebx+0x34]
	call prn_dec
	mov esi, b_msg
	mov ecx, b_msg_len
	call prn_msg
	; drive information addr
	call fb_skip_line
	mov esi, drives_addr_msg
	mov ecx, drives_addr_msg_len
	call prn_msg
	mov eax, [ebx+0x38]
	call prn_hex_dword
	mov ecx, [ebx+0x34]
	call prn_drive_info
.skip_drive_info:
	; unset indent
	mov dword [fb_indent_bytes], 0x0
	; close lease
	mov [fb_mem_addr], edi
	call crtc_write_cursor
	pop ebx
	ret

; print drive volume information array
; eax is the address of the array start (consumed)
; ecx is the number of bytes in the array (consumed)
; trashed: eax/ecx/edx/esi
prn_drive_info:
	push ebx
	push ecx
	mov ebx, eax
.drive_loop:
	call fb_skip_line
	mov esi, drive_entry_siz_msg
	mov ecx, drive_entry_siz_msg_len
	call prn_msg
	mov eax, [ebx]
	call prn_dec
	call fb_skip_line
	mov esi, drive_bios_num_msg
	mov ecx, drive_bios_num_msg_len
	call prn_msg
	mov eax, [ebx+0x4]
	mov ecx, 0
	call prn_hex_byte
	call fb_skip_line
	mov esi, drive_mode_msg
	mov ecx, drive_mode_msg_len
	call prn_msg
	mov eax, [ebx+0x4]
	mov ecx, 1
	call prn_hex_byte
	call fb_skip_line
	mov esi, drive_cyl_msg
	mov ecx, drive_cyl_msg_len
	call prn_msg
	mov eax, [ebx+0x6]
	call prn_dec_wordl
	call fb_skip_line
	mov esi, drive_head_msg
	mov ecx, drive_head_msg_len
	call prn_msg
	mov eax, [ebx+0x8]
	mov ecx, 0
	call prn_dec_byte
	call fb_skip_line
	mov esi, drive_sect_msg
	mov ecx, drive_sect_msg_len
	call prn_msg
	mov eax, [ebx+0x9]
	mov ecx, 0
	call prn_dec_byte
	mov eax, [ebx]
	add ebx, eax
	pop ecx
	sub ecx, eax
	jbe .done
	push ecx
	jmp .drive_loop
.done:
	pop ebx
	ret

; print mmap entry array
; eax is the address of the array start (consumed)
; ecx is the number of bytes in the array (consumed)
; preserved: ebx/ebp
; trashed: eax/ecx/edx/esi
prn_mmap_entries:
	push ebx
	mov ebx, eax

	add dword [fb_indent_bytes], MB_RPT_INDENT_BYTES
	push ecx
.mmap_entry_loop:
	call fb_skip_line
	mov esi, mmap_entry_siz_msg
	mov ecx, mmap_entry_siz_len
	call prn_msg
	mov eax, [ebx]
	call prn_dec
	mov esi, b_msg
	mov ecx, b_msg_len
	call prn_msg
	; mem addr (u64)
	call fb_skip_line
	mov esi, mmap_entry_addr_msg
	mov ecx, mmap_entry_addr_len
	call prn_msg
	mov eax, [ebx+0x4]
	mov edx, [ebx+0x8]
	call prn_hex_qword
	; mem length (u64)
	call fb_skip_line
	mov esi, mmap_entry_len_msg
	mov ecx, mmap_entry_len_msg_len
	call prn_msg
	mov eax, [ebx+0xc]
	mov edx, [ebx+0x10]
	call prn_hex_qword
	mov esi, b_msg
	mov ecx, b_msg_len
	call prn_msg
	; type
	call fb_skip_line
	mov esi, mmap_entry_type_msg
	mov ecx, mmap_entry_type_msg_len
	call prn_msg
	mov eax, [ebx+0x14]
	call prn_mmap_entry_type
	; retrieve recorded size of this mmap entry
	mov eax, [ebx]
	; now account for the size of the dword at [ebx] itself.
	; spec says that the value stored there does not account
	; for itself.
	add eax, 4
	; point ebx at next entry
	add ebx, eax
	pop ecx
	sub ecx, eax
	jbe .done
	push ecx
	jmp .mmap_entry_loop
.done:
	sub dword [fb_indent_bytes], MB_RPT_INDENT_BYTES
	pop ebx
	ret

; print mmap entry type via compare chain
; eax holds the type (preserved)
; trashed: esi/ecx
; preserved: eax
prn_mmap_entry_type:
	cmp eax, 0x01
	je .avail_mem
	cmp eax, 0x02
	je .resv
	cmp eax, 0x03
	je .acpi_recl
	cmp eax, 0x04
	je .acpi_nvs
	cmp eax, 0x05
	je .bad_ram
	mov esi, mmap_type_unknown_msg
	mov ecx, mmap_type_unknown_msg_len
	call prn_msg
	ret
.avail_mem:
	mov esi, mmap_type_avail_mem_msg
	mov ecx, mmap_type_avail_mem_msg_len
	call prn_msg
	ret
.resv:
	mov esi, mmap_type_resv_msg
	mov ecx, mmap_type_resv_msg_len
	call prn_msg
	ret
.acpi_recl:
	mov esi, mmap_type_acpi_msg
	mov ecx, mmap_type_acpi_msg_len
	call prn_msg
	ret
.acpi_nvs:
	mov esi, mmap_type_acpi_nvs_msg
	mov ecx, mmap_type_acpi_nvs_msg_len
	call prn_msg
	ret
.bad_ram:
	mov esi, mmap_type_bad_ram_msg
	mov ecx, mmap_type_bad_ram_msg_len
	call prn_msg
	ret

; print elf section header information
; ebx contains the multiboot report (preserved)
; preserved: ebx/ebp
; trashed: eax/ecx/esi
prn_elf_sects:
	mov esi, elf_h_cnt_msg
	mov ecx, elf_h_cnt_msg_len
	call prn_msg
	mov eax, [ebx+0x1c]
	call prn_dec
	call fb_skip_line

	mov esi, elf_sect_entry_siz_msg
	mov ecx, elf_sect_entry_siz_msg_len
	call prn_msg
	mov eax, [ebx+0x20]
	call prn_dec
	call fb_skip_line

	mov esi, elf_sect_table_addr_msg
	mov ecx, elf_sect_table_addr_msg_len
	call prn_msg
	mov eax, [ebx+0x24]
	call prn_hex_dword
	call fb_skip_line

	mov esi, elf_sect_table_str_idx_msg
	mov ecx, elf_sect_table_str_idx_msg_len
	call prn_msg
	mov eax, [ebx+0x28]
	call prn_dec
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
	pop ecx
	dec ecx
	jnz .prn_module_loop

	sub dword [fb_indent_bytes], 8
	pop ebx
	ret
