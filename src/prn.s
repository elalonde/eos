%include "fb.inc"
%include "prn.inc"

global prn_byte
global prn_msg
global prn_cstr
global prn_dec
global prn_hex_byte
global prn_hex_dword
global prn_hex_word
global prn_hex_qword

extern byte_to_hex
extern fb_scroll
extern fb_indent_bytes
extern fb_mem_addr

prn_byte:
	cmp edi, FB_SCROLL_BOUNDARY_ADDR
	jb .skip_scroll
	call fb_scroll
.skip_scroll:
	mov byte [edi], dl
	mov byte [edi+1], FB_ATTR_GREY_ON_BLACK
	add edi, 2
	ret

prn_msg:
	push esi
	add ecx, esi
	cmp ecx, esi
	je .done
.prn_loop:
	mov dl, [esi]
	call prn_byte
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
	call prn_byte
	inc eax
	jmp .prn_loop
.end:
	; inc past nul
	inc eax
	ret

prn_hex_qword:
	push esi

	push edx
	mov dl, '0'
	call prn_byte
	mov dl, 'x'
	call prn_byte
	pop edx
	mov ecx, 3
	xor esi, esi
	push eax
	mov eax, edx
.prn_byte_loop:
	call byte_to_hex
	call prn_ascii_pair
	dec ecx
	jns .prn_byte_loop
	cmp esi, 1
	jae .done
	; set up next register
	inc esi
	pop eax
	mov ecx, 3
	jmp .prn_byte_loop
.done:
	pop esi
	ret

prn_hex_dword:
	mov ecx, 3
	jmp prn_hex_internal

prn_hex_word:
	mov ecx, 1
	jmp prn_hex_internal

prn_hex_byte:
	push eax
	; convert from byte index to shift length
	shl ecx, 3

	; move target within eax to low byte
	shr eax, cl

	mov ecx, 0
	call prn_hex_internal
	pop eax
	ret

; prn_hex_internal  prints the desired byte portion of eax,
;                   starting at index specified in ecx, in big-endian
;                   order, as a 0x-prefixed hexadecimal number.
;                   eax = value (preserved)
;                   ecx = index (consumed)
;                   trashed: edx
prn_hex_internal:
	mov dl, '0'
	call prn_byte
	mov dl, 'x'
	call prn_byte
.prn_byte_loop:
	call byte_to_hex
	call prn_ascii_pair
	dec ecx
	jns .prn_byte_loop
	ret

; prn_ascii_pair  prints the contents of dh,dl in big-endian order.
;                 dh,dl = ascii chars (consumed).
;                 eax/ecx/ebx/ebp/esi preserved.
prn_ascii_pair:
	push edx
	mov dl, dh
	call prn_byte
	pop edx
	call prn_byte
	ret

prn_dec:
	push ebx
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
	; save ecx
	mov ebx, ecx
.prn_digit_loop:
	pop edx
	add dl, '0'
	call prn_byte
	dec ebx
	jnz .prn_digit_loop
	pop ebx
	ret

