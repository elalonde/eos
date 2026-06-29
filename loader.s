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

section .bss
	align 4                 ; align at 4 bytes
kernel_stack:                   ; label points to beginning of memory
	resb KERNEL_STACK_SIZE  ; reserve stack for the kernel

section .data
	msg db "Hello, Eric."
	msg_len equ  $-msg

section .text                   ; start of the text (code) section
	align 4                 ; the code must be 4 byte aligned
	dd MAGIC_NUMBER         ; write the magic number to the machine code,
	dd FLAGS                ; the flags,
	dd CHECKSUM             ; and the checksum

load_eos:                       ; the entry label (defined as entry point in linker script)
	; zero out .bss region
	cld                   ; direction
	mov eax, 0            ; value
	mov edi, __bss_start  ; destination
	mov ecx, __bss_end
	sub ecx, edi          ; byte count
	shr ecx, 2            ; convert to dword count
	rep stosd             ; zero and repeat

	mov esp, kernel_stack + KERNEL_STACK_SIZE   ; point esp to the start of the
                                                    ; stack (end of memory area)
	call crtc_read_fb_cell
	mov eax, esi
	shl eax, 1                  ; convert to byte offset
	add eax, 160                ; pad one line
	add esi, 80 + msg_len       ; compute placement of cursor

	; print out boot message to screen
	mov ecx, 0
.printmsg:
	mov bl, [msg + ecx]
	mov [FB_MMIO_ADDR+eax+ecx*2], bl          ; write character
	mov byte [FB_MMIO_ADDR+eax+ecx*2+1], 0x07 ; write color of char
	inc ecx
	cmp ecx, msg_len
	jne .printmsg

	; print cursor
	mov al, 0x0E
	mov ebx, esi
	shr ebx, 8
	call crtc_write            ; write cursor pos high bits
	mov al, 0x0F
	mov ebx, esi
	call crtc_write            ; write cursor pos low bits
	mov al, 0x0A
	mov ebx, 0
	call crtc_write            ; write scanline start pos
	mov al, 0x0B
	mov ebx, 0x0F
	call crtc_write            ; write scanline end pos

.hang:
	; bye bye
	cli
	hlt
	jmp .hang

; get crtc cell offset in fb left by bootloader
; postcondition: esi holds cell offset
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

; routine for pmio to crtc
; preconditions:
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
