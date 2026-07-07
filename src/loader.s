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
LINE_LEN_BYTES equ 0xA0
BL_REPORT_INDENT_LEN equ 0x4
FB_SCROLL_BOUNDARY_ADDR equ 0xB8FA0
CRTC_HIGH_BYTE equ 0x0E
CRTC_LOW_BYTE equ 0x0F
FB_SCROLL_LEN_BYTES equ 0xF00

section .bss
	align 4                 ; align at 4 bytes
	fb_indent_bytes resd 1
	fb_mem_addr resd 1
kernel_stack:
	resb KERNEL_STACK_SIZE  ; reserve stack for the kernel

section .rodata
	welcome db "Welcome to eos."
	welcome_len equ $-welcome
	bl_pre db "GRUB multiboot report:"
	bl_pre_len equ $-bl_pre

section .text
	align 4                 ; the code must be 4 byte aligned
	dd MAGIC_NUMBER         ; write the magic number to the machine code,
	dd FLAGS                ; the flags,
	dd CHECKSUM             ; and the checksum

load_eos:
	; zero out .bss region
	cld
	mov eax, 0
	mov edi, __bss_start
	mov ecx, __bss_end
	sub ecx, edi
	shr ecx, 2
	rep stosd

	; set stack pointer
	mov esp, kernel_stack + KERNEL_STACK_SIZE

	call crtc_read_fb_cell
	call fb_newline

	;mov edx, welcome
	;mov eax, welcome_len
	;call prn_msg
	;call fb_newline

	;call prn_bl_rpt
	;call prn_cursor

.hang:
	; bye bye
	cli
	hlt
	jmp .hang


fb_scroll:
	push esi
	push edi
	mov esi, FB_MMIO_ADDR+LINE_LEN_BYTES
	mov edi, FB_MMIO_ADDR
	mov ecx, FB_SCROLL_LEN_BYTES
	rep movsb
	; blank last line
	mov edi, FB_SCROLL_BOUNDARY_ADDR-LINE_LEN_BYTES
	mov al, ' '
	mov ah, BLACK_TEXT
	mov ecx, LINE_LEN_BYTES
	shr ecx, 1 ; word count
	rep stosw
	pop edi
	pop esi
	ret

fb_newline:
	push ebx
	mov eax, [fb_mem_addr]
	push eax
	; bytes since beginning of fb
	sub eax, FB_MMIO_ADDR
	mov ebx, LINE_LEN_BYTES
	xor edx, edx
	div ebx
	sub ebx, edx ; bytes to next row
	pop eax
	add eax, ebx ; new cursor addr
	cmp eax, FB_SCROLL_BOUNDARY_ADDR
	jb .skip_scroll
	push eax
	call fb_scroll
	pop eax
	; move cursor back on screen
	sub eax, LINE_LEN_BYTES
.skip_scroll:
	add eax, [fb_indent_bytes]
	mov [fb_mem_addr], eax
	pop ebx
	ret

crtc_read_fb_cell:
	; latch and read cursor location high
	mov dx, VGA_CRTC_IDX_PORT
	mov al, CRTC_HIGH_BYTE
	out dx, al
	mov dx, VGA_CRTC_DAT_PORT
	in al, dx
	movzx eax, al
	; move to upper byte
	shl eax, 8
	; latch and read cursor location low
	mov dx, VGA_CRTC_IDX_PORT
	mov al, CRTC_LOW_BYTE
	out dx, al
	mov dx, VGA_CRTC_DAT_PORT
	in al, dx
	; convert cell offset to mem addr
	shl eax, 1
	add eax, FB_MMIO_ADDR
	mov [fb_mem_addr], eax
	ret
