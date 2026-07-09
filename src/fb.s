%include "fb.inc"

global fb_indent_bytes
global fb_mem_addr
global fb_scroll
global fb_skip_line

section .bss
	align 4
	fb_indent_bytes resd 1
	fb_mem_addr resd 1

section .text
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
	mov ah, FB_ATTR_GREY_ON_BLACK
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
