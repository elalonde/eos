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
ASCII_OFFSET equ 0x30
BLACK_TEXT equ 0x07
HEX_UPPER_ASCII_OFFSET equ 0x37
HEX_LOWER_ASCII_OFFSET equ 0x30
LINE_LEN equ 0x50

section .bss
	align 4                 ; align at 4 bytes
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
	part_dev_msg db ", Partition "
	part_dev_len equ $-part_dev_msg

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
	call fb_skip_ln
	call prn_bl_nfo
	call prn_cursor

.hang:
	; bye bye
	cli
	hlt
	jmp .hang

; skip fb cell offset to next line
; pre:
; - esi contains current fb cell offset
; - ecx contains number of spaces to indent on new line
; post:
; - esi contains updated fb cell offset
; (skipped to next line)
fb_skip_ln:
	push eax
	push ebx
	push ecx
	push edx

	mov ebx, LINE_LEN
	xor edx, edx
	mov eax, esi
	; edx:eax
	div ebx
	neg edx
	add edx, ebx
	add esi, edx
	add esi, ecx

	pop edx
	pop ecx
	pop ebx
	pop eax
	ret

; pre:
; - ebx contains addr of bl info
; - esi contains current fb cell offset
; post:
; - esi contains updated fb cell offset
prn_bl_nfo:
	push eax
	push edx

	mov edx, bl_pre
	mov eax, bl_pre_len
	call prn_msg
	mov ecx, 4

	test byte [ebx], 1
	jz .skipmem
	; print lower
	mov edx, lower_msg
	mov eax, lower_len
	call fb_skip_ln
	call prn_msg
	mov eax, [ebx+4]
	call prn_dec
	mov edx, kb_msg
	mov eax, kb_len
	call prn_msg
	; print upper
	call fb_skip_ln
	mov edx, upper_msg
	mov eax, upper_len
	call prn_msg
	mov eax, [ebx+8]
	call prn_dec
	mov edx, kb_msg
	mov eax, kb_len
	call prn_msg
.skipmem:
	; print boot device
	test byte [ebx], 0x2
	jz .skipboot
	mov edx, boot_dev_msg
	mov eax, boot_dev_len
	call fb_skip_ln
	call prn_msg
	mov eax, [ebx+12]
	call prn_hex
.skipboot:
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
	push ebx
	push ecx
	push esi

	; convert to byte offset
	shl esi, 1
	mov ecx, 0
.prn_loop:
	mov bl, [edx + ecx]
	mov [FB_MMIO_ADDR+esi+ecx*2], bl          ; write character
	mov byte [FB_MMIO_ADDR+esi+ecx*2+1], BLACK_TEXT
	inc ecx
	cmp ecx, eax
	jne .prn_loop

	pop esi
	add esi, ecx
	pop ecx
	pop ebx
	ret

; pre:
; - eax has number to print
; - esi contains current fb cell offset
; post:
; - esi contains updated fb cell offset
prn_hex:
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
	; save and convert to byte offset
	push esi
	shl esi, 1

	; bit count for nibble shift
	mov ecx, 0x1C
	xor edx, edx
.prn_hex_nibble:
	mov ebx, eax
	shr ebx, cl
	; mask all but lowest nibble
	and ebx, 0x0000000F
	cmp bl, 0x0A
	jb .lower_offset
	add bl, HEX_UPPER_ASCII_OFFSET
	jmp .offset_done
.lower_offset:
	add bl, HEX_LOWER_ASCII_OFFSET
.offset_done:
	mov [FB_MMIO_ADDR+esi+edx*2], bl
	mov byte [FB_MMIO_ADDR+esi+edx*2+1], BLACK_TEXT

	inc edx
	sub ecx, 0x04
	cmp edx, 0x08
	jl .prn_hex_nibble

	pop esi
	add esi, edx
	pop edx
	pop ecx
	pop ebx
	pop eax
	ret

; pre:
; - eax has number to print
; - esi contains current fb cell offset
; post:
; - esi contains updated fb cell offset
prn_dec:
	push ebx
	push edx
	push eax
	push ecx
	push esi
	mov ebx, 10
	; convert cell offset to byte offset
	shl esi, 1
	mov ecx, 0
	; store digits on stack
.div_loop:
	xor edx, edx
	; edx:eax
	div ebx
	; store remainder
	push edx
	inc ecx
	test eax, eax
	jnz .div_loop
	mov eax, 0
.prn_digit:
	pop ebx
	add ebx, ASCII_OFFSET
	mov [FB_MMIO_ADDR+esi+eax*2], bl
	mov byte [FB_MMIO_ADDR+esi+eax*2+1], BLACK_TEXT
	inc eax
	dec ecx
	jnz .prn_digit

	pop esi
	add esi, eax
	pop ecx
	pop eax
	pop edx
	pop ebx
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
