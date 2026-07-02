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

section .bss
	align 4                 ; align at 4 bytes
kernel_stack:
	resb KERNEL_STACK_SIZE  ; reserve stack for the kernel

section .data
	msg db "Hello, Eric."
	msg_len equ  $-msg

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
	; pad a blank line
	add esi, 80

	mov edx, msg
	mov eax, [msg_len]
	call prn_msg
	call prn_cursor

.hang:
	; bye bye
	cli
	hlt
	jmp .hang

; pre:
; - esi contains current fb cell offset
; post:
; - esi contains updated fb cell offset
prn_cursor:
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
	ret

; pre:
; - edx contains pointer to msg
; - eax contains msg len
; - esi contains current fb cell offset
; post:
; - esi contains updated fb cell offset
prn_msg:
	push ecx
	push esi

	; convert to byte offset
	shl esi, 1                  ; convert to byte offset
	mov ecx, 0
.prn_loop:
	mov bl, [edx + ecx]
	mov [FB_MMIO_ADDR+esi+ecx*2], bl          ; write character
	mov byte [FB_MMIO_ADDR+esi+ecx*2+1], BLACK_TEXT
	inc ecx
	cmp ecx, msg_len
	jne .prn_loop

	pop esi
	add esi, ecx
	pop ecx
	ret

; pre:
; - eax has decimal number to prn_
; - esi contains current fb cell offset
; post:
; - esi contains updated fb cell offset
prn_num:
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
.divloop:
	xor edx, edx
	; edx:eax
	div ebx
	; store remainder
	push edx
	inc ecx
	test eax, eax
	jnz .divloop
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
