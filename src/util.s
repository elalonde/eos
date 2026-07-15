%include "util.inc"

global byte_to_hex

section .text
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

