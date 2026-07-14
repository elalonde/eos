%include "fb.inc"
global load_eos                 ; the entry symbol for ELF
extern __bss_start              ; defined by linker
extern __bss_end
extern fb_mem_addr
extern crtc_write_scanline
extern crtc_read_fb_addr
extern crtc_write_cursor
extern prn_msg

MAGIC_NUMBER equ 0x1BADB002     ; define the magic number constant
FLAGS        equ 0x0            ; multiboot flags
CHECKSUM     equ -MAGIC_NUMBER  ; calculate the checksum
KERNEL_STACK_SIZE equ 4096
                                ; (magic number + checksum + flags should equal 0)
BL_REPORT_INDENT_LEN equ 0x4

section .bss
	align 4
kernel_stack:
	resb KERNEL_STACK_SIZE

section .rodata
	welcome db "Welcome to eos."
	welcome_len equ $-welcome
	bl_pre db "GRUB multiboot report:"
	bl_pre_len equ $-bl_pre

section .multiboot
	align 4
	; write multiboot flags and checksum
	dd MAGIC_NUMBER
	dd FLAGS
	dd CHECKSUM

section .text
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
	call crtc_write_scanline

	call crtc_read_fb_addr
	mov [fb_mem_addr], eax
	mov edi, eax

	mov esi, welcome
	mov ecx, welcome_len
	call prn_msg
	mov [fb_mem_addr], edi
	call crtc_write_cursor

	;call prn_bl_rpt

.hang:
	; bye bye
	cli
	hlt
	jmp .hang

