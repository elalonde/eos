global load_eos                 ; the entry symbol for ELF
extern __bss_start              ; defined by linker
extern __bss_end

MAGIC_NUMBER equ 0x1BADB002     ; define the magic number constant
FLAGS        equ 0x0            ; multiboot flags
CHECKSUM     equ -MAGIC_NUMBER  ; calculate the checksum
                                ; (magic number + checksum + flags should equal 0)
FB_MMIO_ADDR      equ 0xB8000   ; framebuffer memory addr
VGA_CRTC_IDX_PORT equ 0x3D4     ; VGA CRTC index port
VGA_CRTC_DAT_PORT equ 0x3D5     ; VGA CRTC data port
KERNEL_STACK_SIZE equ 4096      ; size of stack in bytes
BLACK_TEXT equ 0x07
HEX_GT_TEN_ASCII_OFFSET equ 0x37
HEX_LT_TEN_ASCII_OFFSET equ 0x30
LINE_LEN equ 0x50
BL_REPORT_INDENT_LEN equ 0x4

section .bss
	align 4                 ; align at 4 bytes
	fb_indent_len resd 1
kernel_stack:
	resb KERNEL_STACK_SIZE  ; reserve stack for the kernel

section .rodata
	hex_pre db "0x"
	hex_pre_len equ $-hex_pre
	welcome db "Welcome to eos."
	welcome_len equ $-welcome
	bl_pre db "Bootloader report:"
	bl_pre_len equ $-bl_pre
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
	modules_msg db "Loaded module count: "
	modules_msg_len equ $-modules_msg
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
	elf_sect_table_mmap_msg db "Memory map length: "
	elf_sect_table_mmap_msg_len equ $-elf_sect_table_mmap_msg
	bytes_msg db " bytes"
	bytes_msg_len equ $-bytes_msg

section .text
	align 4                 ; the code must be 4 byte aligned
	dd MAGIC_NUMBER         ; write the magic number to the machine code,
	dd FLAGS                ; the flags,
	dd CHECKSUM             ; and the checksum

load_eos:
	; zero out .bss region
	cld                   ; direction
	mov eax, 0            ; value
	mov edi, __bss_start  ; destination
	mov ecx, __bss_end
	sub ecx, edi          ; byte count
	shr ecx, 2            ; convert to dword count
	rep stosd             ; zero and repeat
	
	; point esp to the start of the stack (grows down)
	mov esp, kernel_stack + KERNEL_STACK_SIZE

	call crtc_read_fb_cell
	call fb_skip_ln

	mov edx, welcome
	mov eax, welcome_len
	call prn_msg
	mov eax, 0xdeadbeef
	call prn_hex_num
	call prn_cursor

.hang:
	; bye bye
	cli
	hlt
	jmp .hang

; skip fb cell offset to next line
; pre:
; - esi contains current fb cell offset
; - fb_indent_len contains number of spaces to indent on new line
; post:
; - esi contains updated fb cell offset
fb_skip_ln:
	push eax
	push ebx
	push edx

	mov ebx, LINE_LEN
	xor edx, edx
	mov eax, esi
	; edx:eax
	div ebx
	neg edx
	add edx, ebx
	add esi, edx
	add esi, [fb_indent_len]

	pop edx
	pop ebx
	pop eax
	ret

; pre:
; - eax contains pointer to c string
; - esi contains current fb cell offset
; post:
; - esi contains updated fb cell offset
prn_cstr:
	push eax
	push ebx
	push ecx
	push esi

	; byte offset
	shl esi, 1
	xor ecx, ecx
.prn_loop:
	mov bl, [eax+ecx]
	test bl, bl
	jz .end
	mov [FB_MMIO_ADDR+esi+ecx*2], bl
	mov byte [FB_MMIO_ADDR+esi+ecx*2+1], BLACK_TEXT
	inc ecx
	jmp .prn_loop
.end:
	pop esi
	add esi, ecx
	pop ecx
	pop ebx
	pop eax
	ret

; pre:
; - ebx contains addr of bl info
; - esi contains current fb cell offset
; post:
; - esi contains updated fb cell offset
prn_bl_rpt:
	push eax
	push ecx
	push edx

	mov dword [fb_indent_len], BL_REPORT_INDENT_LEN
	mov edx, bl_pre
	mov eax, bl_pre_len
	call prn_msg

	test byte [ebx], 1
	jz .skipmem
	; lower mem
	mov edx, lower_msg
	mov eax, lower_len
	call fb_skip_ln
	call prn_msg
	mov eax, [ebx+4]
	call prn_dec
	mov edx, kb_msg
	mov eax, kb_len
	call prn_msg
	; upper mem
	call fb_skip_ln
	mov edx, upper_msg
	mov eax, upper_len
	call prn_msg
	mov eax, [ebx+8]
	call prn_dec
	mov edx, kb_msg
	mov eax, kb_len
	call prn_msg
	call fb_skip_ln
.skipmem:
	; boot device
	test byte [ebx], 0x2
	jz .skipboot
	mov edx, boot_dev_msg
	mov eax, boot_dev_len
	call prn_msg
	mov eax, [ebx+12]
	call prn_boot_dev_nfo
	call fb_skip_ln
.skipboot:
	; cmdline
	; test flag and also for empty string
	test byte [ebx], 0x4
	jz .skipcmdline
	mov eax, [ebx+16]
	mov ecx, [eax]
	test cl, cl
	jz .skipcmdline
	mov edx, cmdline_msg
	mov eax, cmdline_msg_len
	call prn_msg
	mov eax, [ebx+16]
	call prn_cstr
	call fb_skip_ln
.skipcmdline:
	; loaded modules
	test byte [ebx], 0x8
	jz .skipmodules
	mov edx, modules_msg
	mov eax, modules_msg_len
	call prn_msg
	mov eax, [ebx+20]
	call prn_dec
	call fb_skip_ln
	test al, al
	jz .skipmodules
.skipmodules:
	; todo: test 0x16 for a.out sections
	test byte [ebx], 0x32
	jz .skip_elf_sects
	call prn_elf_sects
	call fb_skip_ln
.skip_elf_sects:
	test byte [ebx], 0x64
	jz .skip_mmap_sects
	mov edx, elf_sect_table_mmap_msg
	mov eax, elf_sect_table_mmap_msg_len
	call prn_msg
	mov eax, [ebx+44]
	mov edx, bytes_msg
	mov eax, bytes_msg_len
	call prn_dec
	call fb_skip_ln
.skip_mmap_sects:
	mov dword [fb_indent_len], 0
	pop edx
	pop ecx
	pop eax
	ret

; pre:
; - esi contains current fb cell offset
; - ebx contains bootloader report table
; post:
; - esi contains updated fb cell offset
prn_elf_sects:
	push eax
	push edx

	mov edx, elf_h_cnt_msg
	mov eax, elf_h_cnt_msg_len
	call prn_msg
	mov eax, [ebx+28]
	call prn_dec
	call fb_skip_ln

	mov edx, elf_sect_entry_siz_msg
	mov eax, elf_sect_entry_siz_msg_len
	call prn_msg
	mov eax, [ebx+32]
	call prn_dec
	call fb_skip_ln

	mov edx, elf_sect_table_addr_msg
	mov eax, elf_sect_table_addr_msg_len
	call prn_msg
	mov eax, [ebx+36]
	call prn_hex_num
	call fb_skip_ln

	mov edx, elf_sect_table_str_idx_msg
	mov eax, elf_sect_table_str_idx_msg_len
	call prn_msg
	mov eax, [ebx+40]
	call prn_hex_num

	pop edx
	pop eax
	ret

; pre:
; - esi contains current fb cell offset
; post:
; - esi contains updated fb cell offset
prn_cursor:
	push eax
	push ebx
	push esi

	mov al, 0x0E
	mov ebx, esi
	shr ebx, 8
	; high bits
	call crtc_write
	mov al, 0x0F
	mov ebx, esi
	; low bits
	call crtc_write
	mov al, 0x0A
	mov ebx, 0
	; scanline start
	call crtc_write
	mov al, 0x0B
	mov ebx, 0x0F
	; scanline end
	call crtc_write

	pop esi
	inc esi
	pop ebx
	pop eax
	ret

; pre:
; - edx contains pointer to msg
; - eax contains msg len
; - esi contains current fb cell offset
; post:
; - esi contains updated fb cell offset
prn_msg:
	push eax
	push ebx
	push ecx
	push edx

	test eax, eax
	jz .done

	mov ebx, eax
	mov eax, edx
	xor ecx, ecx
.prn_loop:
	mov dl, [eax + ecx]
	call prn_byte
	inc ecx
	cmp ecx, ebx
	jb .prn_loop
.done:

	pop edx
	pop ecx
	pop ebx
	pop eax
	ret

; pre
; - eax contains byte to convert
; - ecx is byte index of interest in eax
; post:
; - lowest 2 bytes in edx contains the hex representation
byte_to_hex:
	push eax
	push ecx

	; byte index to shift length
	shl ecx, 3
	; move to index 0
	shr eax, cl

	xor edx, edx
	mov dl, al
	; high nibble
	shr dl, 4

	and eax, 0x0000000F
	cmp al, 0xA
	jb .lower_lt_ten
	add al, HEX_GT_TEN_ASCII_OFFSET
	jmp .lower_done
.lower_lt_ten:
	add al, HEX_LT_TEN_ASCII_OFFSET
.lower_done:
	cmp dl, 0xA
	jb .upper_lt_ten
	add dl, HEX_GT_TEN_ASCII_OFFSET
	jmp .upper_done
.upper_lt_ten:
	add dl, HEX_LT_TEN_ASCII_OFFSET
.upper_done:
	mov dh, dl
	mov dl, al
	pop ecx
	pop eax
	ret

; - dl contains the byte to print
; - esi contains current fb cell offset
; post:
; - esi contains updated fb cell offset
prn_byte:
	push esi

	; byte offset
	shl esi, 1

	mov [FB_MMIO_ADDR+esi], dl
	mov byte [FB_MMIO_ADDR+esi+1], BLACK_TEXT

	; cell offset
	pop esi
	inc esi
	ret

; print a byte which grew into 16 bits as a result
; of conversion to ascii hex representation
; pre:
; - dx contains the 16 bit word to print
; - esi contains current fb cell offset
; post:
; - esi contains updated fb cell offset
prn_hex_byte:
	; print dh
	push edx
	mov dl, dh
	call prn_byte
	pop edx

	; print dl
	call prn_byte

	ret

; pre:
; - eax has number to print
; - esi contains current fb cell offset
; post:
; - esi contains updated fb cell offset
prn_hex_num:
	push eax
	push ebx
	push ecx
	push edx

	; dance to print 0x (updates esi)
	mov ebx, eax
	mov edx, hex_pre
	mov eax, hex_pre_len
	call prn_msg
	mov eax, ebx

	mov ecx, 3
.prn_byte_loop:
	call byte_to_hex
	call prn_hex_byte
	dec ecx
	jns .prn_byte_loop

	pop edx
	pop ecx
	pop ebx
	pop eax
	ret
; pre:
; - esi contains current fb cell offset
; - eax contains boot device information
; post:
; - esi contains updated fb cell offset
prn_boot_dev_nfo:
	push eax
	push ebx
	push ecx
	push edx

	; dance to print 0x (updates esi)
	mov ebx, eax
	mov edx, hex_pre
	mov eax, hex_pre_len
	call prn_msg
	mov eax, ebx

	; print boot device
	mov ecx, 3
	call byte_to_hex
	call prn_hex_byte

	mov ecx, 2
.prn_partitions_loop:
	call byte_to_hex
	cmp dx, 0x6666 ; 0xFF
	je .loop_done
	push edx
	cmp ecx, 2
	jne .prn_period
	push edx
	mov dl, '('
	call prn_byte
	pop edx
	jmp .prn_partition
.prn_period:
	push edx
	mov dl, '.'
	call prn_byte
	pop edx
.prn_partition:
	pop edx
	call prn_byte
	dec ecx
	jns .prn_partitions_loop
.loop_done:
	; iff sentinel encountered on first iteration
	cmp ecx, 2
	je .skip_close_paren
	mov dl , ')'
	call prn_byte
.skip_close_paren:
	pop edx
	pop ecx
	pop ebx
	pop eax
	ret

; pre:
; - eax is number to print
; - esi contains current fb cell offset
; post:
; - esi contains updated fb cell offset
prn_dec:
	push eax
	push ebx
	push ecx
	push edx

	mov ebx, 10
	xor ecx, ecx
.div_loop:
	xor edx, edx
	; edx:eax
	div ebx
	; store remainder
	push edx
	inc ecx
	test eax, eax
	jnz .div_loop
.prn_digit_loop:
	pop edx
	add dl, '0'
	call prn_byte
	dec ecx
	jnz .prn_digit_loop

	pop edx
	pop ecx
	pop ebx
	pop eax
	ret

; post: esi contains the fb cell offset
crtc_read_fb_cell:
	push eax
	push ebx
	push edx
	mov dx, VGA_CRTC_IDX_PORT
	mov al, 0x0F
	out dx, al                  ; latch index
	mov dx, VGA_CRTC_DAT_PORT
	in al, dx                   ; get data
	mov bl, al                  ; store low bits
	mov dx, VGA_CRTC_IDX_PORT
	mov al, 0x0E
	out dx, al                  ; latch index
	mov dx, VGA_CRTC_DAT_PORT
	in al, dx                   ; get data
	movzx eax, al               ; widen
	shl eax, 8                  ; shift to high bits
	or al, bl                   ; set low bits
	mov esi, eax
	pop edx
	pop ebx
	pop eax
	ret

; pre:
;  al has register to latch
;  bl has data to write
crtc_write:
	push edx
	mov dx, VGA_CRTC_IDX_PORT
	out dx, al                 ; latch register
	mov dx, VGA_CRTC_DAT_PORT
	mov al, bl
	out dx, al                 ; write data
	pop edx
	ret
