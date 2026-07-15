%include "fb.inc"
%include "prn.inc"

global prn_byte
global prn_msg
global prn_cstr
global prn_dec
global prn_hex_dword
global prn_hex_word

extern byte_to_hex
extern fb_scroll
extern fb_indent_bytes
extern fb_mem_addr

prn_byte:
	cmp edi, FB_SCROLL_BOUNDARY_ADDR
	jb .skip_scroll
	push edx
	call fb_scroll
	pop edx
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

prn_hex_dword:
	mov ecx, 3
	jmp prn_hex_word_internal

prn_hex_word:
	mov ecx, 1
	jmp prn_hex_word_internal

; prn_hex_word_internal  prints the desired portion of eax, starting
;                        at index specified in ecx, in big-endian
;                        order, as a 0x-prefixed hexadecimal number.
;                        eax = value (preserved)
;                        ecx = index (consumed)
prn_hex_word_internal:
	push eax
	push ecx
	mov dl, '0'
	call prn_byte
	mov dl, 'x'
	call prn_byte
	pop ecx
	pop eax
.prn_byte_loop:
	push ecx
	push eax
	call byte_to_hex
	call prn_ascii_pair
	pop eax
	pop ecx
	dec ecx
	jns .prn_byte_loop
	ret

; prn_ascii_pair  prints the contents of dh,dl in big-endian order.
;                 dh,dl = ascii chars (consumed).
;                 eax/ecx/edx trashed
;                 ebx/ebp/esi preserved.
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

