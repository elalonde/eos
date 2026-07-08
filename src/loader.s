global load_eos                 ; the entry symbol for ELF
extern __bss_start              ; defined by linker
extern __bss_end

MAGIC_NUMBER equ 0x1BADB002     ; define the magic number constant
FLAGS        equ 0x0            ; multiboot flags
CHECKSUM     equ -MAGIC_NUMBER  ; calculate the checksum
                                ; (magic number + checksum + flags should equal 0)
FB_MMIO_ADDR      equ 0xB8000   ; framebuffer memory addr
CRTC_IDX_PORT equ 0x3D4     ; VGA CRTC index port
CRTC_DAT_PORT equ 0x3D5     ; VGA CRTC data port
CRTC_REG_CURS_LOC_HIGH equ 0x0E
CRTC_REG_CURS_LOC_LOW equ 0x0F
CRTC_REG_CURS_SCANLINE_START equ 0x0A
CRTC_REG_CURS_SCANLINE_STOP equ 0x0B
CRTC_SCANLINE_LOC_TOP equ 0x00
CRTC_SCANLINE_LOC_BOT equ 0x0F
CRTC_CURS_START equ 0x0A
KERNEL_STACK_SIZE equ 4096
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
	align 4
	fb_indent_bytes resd 1
	fb_mem_addr resd 1
kernel_stack:
	resb KERNEL_STACK_SIZE

section .rodata
	welcome db "Welcome to eos."
	welcome_len equ $-welcome
	bl_pre db "GRUB multiboot report:"
	bl_pre_len equ $-bl_pre

section .text
	align 4
	; write multiboot flags and checksum
	dd MAGIC_NUMBER
	dd FLAGS
	dd CHECKSUM

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

;-----------------------------------------------------------------------
; prn_* routines handle framebuffer output.
;
; EDI is the absolute byte address of the framebuffer cursor. It
; is advanced on return to new cursor location. all routines will scroll
; if necessary and honor indentation via [fb_indent_bytes].
;
; callers lease edi from [fb_mem_addr] and store it back when printing
; completes.
;
; eax/ecx/edx trashed unless noted. ebx/ebp/esi preserved.
;
; prn_byte      dl = byte to print.
; prn_msg       esi = base (preserved), ecx = count (consumed).
; prn_cstr      esi = cstr (preserved). eax points past the nul.
;-----------------------------------------------------------------------
prn_byte:
	cmp edi, FB_SCROLL_BOUNDARY_ADDR
	jb .skip_scroll
	push edx
	call fb_scroll
	pop edx
.skip_scroll:
	mov byte [edi], dl
	mov byte [edi+1], BLACK_TEXT
	add edi, 2
	ret

prn_msg:
	push esi
	add ecx, esi
	cmp ecx, esi
	je .done
.prn_loop:
	mov dl, [esi]
	push ecx
	call prn_byte
	pop ecx
	inc esi
	cmp esi, ecx
	jb .prn_loop
.done:
	pop esi
	ret

prn_cstr:
	mov eax, esi
.prn_loop:
	mov dl, [eax]
	test dl, dl
	jz .end
	push eax
	call prn_byte
	pop eax
	inc eax
	jmp .prn_loop
.end:
	; inc past nul
	inc eax
	ret

;-----------------------------------------------------------------------
; crtc_* routines drive the VGA CRT controller.
;
; all operations require latching at crtc index and data ports to configure
; registers. the device holds one latched index across calls, so register
; sequences must not be interrupted by other crtc access.
;
; eax/ecx/edx are trashed; other registers rest preserved.
;
; crtc_write           al = register index, cl = data
; crtc_read_fb_addr    reads the hw cursor; returns it in eax as
;                      an absolute framebuffer byte address.
; crtc_write_cursor    edi = absolute cursor byte addr. used to write cursor
;                      location.
; crtc_write_scanline  configures cursor shape; shape is preserved until
;                      changed.
;-----------------------------------------------------------------------
crtc_read_fb_addr:
	; latch and read cursor location high
	mov dx, CRTC_IDX_PORT
	mov al, CRTC_HIGH_BYTE
	out dx, al
	mov dx, CRTC_DAT_PORT
	in al, dx
	movzx eax, al
	; move to upper byte
	shl eax, 8
	; latch and read cursor location low
	mov dx, CRTC_IDX_PORT
	mov al, CRTC_LOW_BYTE
	out dx, al
	mov dx, CRTC_DAT_PORT
	in al, dx
	; convert cell offset to mem addr
	shl eax, 1
	add eax, FB_MMIO_ADDR
	ret

crtc_write_cursor:
	; tmp space
	push ebx

	; convert mem addr to crtc cell offset
	mov ecx, edi
	sub ecx, FB_MMIO_ADDR
	shr ecx, 1
	mov ebx, ecx

	; mov high byte into low bits
	shr ecx, 0x08
	mov al, CRTC_REG_CURS_LOC_HIGH
	call crtc_write

	mov ecx, ebx
	mov al, CRTC_REG_CURS_LOC_LOW
	call crtc_write

	pop ebx
	ret

crtc_write_scanline:
	mov ecx, CRTC_SCANLINE_LOC_TOP
	mov al, CRTC_REG_CURS_SCANLINE_START
	call crtc_write

	mov ecx, CRTC_SCANLINE_LOC_BOT
	mov al, CRTC_REG_CURS_SCANLINE_STOP
	call crtc_write
	ret


; al has register
; cl has data
crtc_write:
	mov dx, CRTC_IDX_PORT
	out dx, al
	mov dx, CRTC_DAT_PORT
	mov al, cl
	out dx, al
	ret

;-----------------------------------------------------------------------
; fb_* routines control screen and cursor mechanics.
;
; EDI is the absolute byte address of the framebuffer cursor, and
; is updated to new cursor location. routines honor indentation via
; [fb_indent_bytes].
;
; register contract:
;     trashed: eax/ecx/edx
;     preserved: ebx/ebp/esi
;
; fb_scroll     takes no arguments and moves entire screen up one row. final
;               row is blank. EDI is updated to new cursor placement.
; fb_skip_line  takes EDI in, scrolls if necessary, and updates EDI to new
;               cursor placement.
;-----------------------------------------------------------------------
fb_scroll:
	push esi
	mov esi, FB_MMIO_ADDR+LINE_LEN_BYTES
	mov edi, FB_MMIO_ADDR
	mov ecx, FB_SCROLL_LEN_BYTES
	rep movsb
	; blank last line and move cursor
	; back on screen
	mov edi, FB_SCROLL_BOUNDARY_ADDR-LINE_LEN_BYTES
	push edi
	mov al, ' '
	mov ah, BLACK_TEXT
	mov ecx, LINE_LEN_BYTES
	shr ecx, 1 ; word count
	rep stosw
	pop edi
	; honor global indent
	add edi, [fb_indent_bytes]
	pop esi
	ret

fb_skip_line:
	push ebx
	mov eax, edi
	; bytes since beginning of fb
	sub eax, FB_MMIO_ADDR
	mov ebx, LINE_LEN_BYTES
	xor edx, edx
	div ebx
	sub ebx, edx ; bytes until next row
	add edi, ebx ; new cursor addr
	cmp edi, FB_SCROLL_BOUNDARY_ADDR
	jb .skip_scroll
	call fb_scroll
	pop ebx
	ret
.skip_scroll:
	add edi, [fb_indent_bytes]
	pop ebx
	ret
