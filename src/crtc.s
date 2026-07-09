%include "crtc.inc"
%include "fb.inc"

global crtc_read_fb_addr
global crtc_write_cursor
global crtc_write_scanline

CRTC_IDX_PORT equ 0x3D4
CRTC_DAT_PORT equ 0x3D5
CRTC_REG_CURS_LOC_HIGH equ 0x0E
CRTC_REG_CURS_LOC_LOW equ 0x0F
CRTC_REG_CURS_SCANLINE_START equ 0x0A
CRTC_REG_CURS_SCANLINE_STOP equ 0x0B
CRTC_SCANLINE_LOC_TOP equ 0x00
CRTC_SCANLINE_LOC_BOT equ 0x0F
CRTC_CURS_START equ 0x0A

crtc_read_fb_addr:
	; latch and read cursor location high
	mov dx, CRTC_IDX_PORT
	mov al, CRTC_REG_CURS_LOC_HIGH
	out dx, al
	mov dx, CRTC_DAT_PORT
	in al, dx
	movzx eax, al
	; move to upper byte
	shl eax, 8
	; latch and read cursor location low
	mov dx, CRTC_IDX_PORT
	mov al, CRTC_REG_CURS_LOC_LOW
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

