%include "multiboot.inc"
global load_eos             ; the entry symbol for ELF

extern __bss_start          ; link.ld
extern __bss_end            ; link.ld
extern crtc_write_scanline  ; crtc.s
extern crtc_read_fb_addr    ; crtc.s
extern crtc_write_cursor    ; crtc.s
extern fb_mem_addr          ; fb.s
extern fb_skip_line         ; fb.s
extern mb_prn_rpt           ; multiboot.s
extern prn_msg              ; prn.s

KERNEL_STACK_SIZE equ 4096
MAGIC_NUMBER equ 0x1BADB002     ; define the magic number constant
FLAGS        equ 0x0            ; multiboot flags
CHECKSUM     equ -MAGIC_NUMBER  ; calculate the checksum
                                ; (magic number + checksum + flags should equal 0)
CODE_SEG equ code_descriptor - gdt_start
DATA_SEG equ data_descriptor - gdt_start

section .bss
	align 4
kernel_stack:
	resb KERNEL_STACK_SIZE

section .rodata
	welcome db "Welcome to eos."
	welcome_len equ $-welcome

section .multiboot
	align 4
	; write multiboot flags and checksum
	dd MAGIC_NUMBER
	dd FLAGS
	dd CHECKSUM

section .data
gdt_start:
	; selector 0
	dq 0      ; nul entry
code_descriptor:
	; selector 1 (code)
	dw 0xFFFF ; 16 bits of limit
	dw 0      ; 16 bits of base
	db 0      ; 8 bits of base
	db 0x9A   ; lower:type, upper: S,DPL,P
	db 0xCF   ; lower:limit,upper: A,L,D,G
	db 0      ; 8 bits of base
data_descriptor:
	; selector 2 (data)
	dw 0xFFFF ; 16 bits of limit
	dw 0      ; 16 bits of base
	db 0      ; 8 bits of base
	db 0x92   ; lower:type, upper: S,DPL,P
	db 0xCF   ; lower:limit,upper: A,L,D,G
	db 0      ; 8 bits of base
gdt_end:
gdt_descriptor:
	dw gdt_end - gdt_start - 1  ; Limit (Size of GDT minus 1)
	dd gdt_start                ; Base Address of GDT

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

	; set up gdt and flush segment registers
	cli
	lgdt [gdt_descriptor]
	mov ax, DATA_SEG
	mov ds, ax
	mov es, ax
	mov fs, ax
	mov gs, ax
	; update ss and stack pointer in lockstep
	mov ss, ax
	mov esp, kernel_stack + KERNEL_STACK_SIZE

	; flush CS register
	jmp CODE_SEG:flush_cs_register
flush_cs_register:
	; set color for all screen writes
	call crtc_write_scanline
	; load and store fb address
	call crtc_read_fb_addr
	mov [fb_mem_addr], eax
	mov edi, eax

	call fb_skip_line
	mov esi, welcome
	mov ecx, welcome_len
	call prn_msg
	call fb_skip_line
	; close lease
	mov [fb_mem_addr], edi
	call crtc_write_cursor

	; generate multiboot report
	call mb_prn_rpt
.hang:
	; bye bye
	cli
	hlt
	jmp .hang

