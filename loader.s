global loader                   ; the entry symbol for ELF

MAGIC_NUMBER equ 0x1BADB002     ; define the magic number constant
FLAGS        equ 0x0            ; multiboot flags
CHECKSUM     equ -MAGIC_NUMBER  ; calculate the checksum
                                ; (magic number + checksum + flags should equal 0)
PRINT_START_OFFSET equ 0xB8000 + 15*80*2
VGA_CRTC_IDX_PORT equ 0x3D4          ; VGA CRTC data port
VGA_CRTC_DAT_PORT equ 0x3D5		    ; VGA CRTC index port
CURS_START_IDX equ 0x0A         ; cursor start register index
CURS_END_IDX equ 0x0B           ; cursor end register index

section .data
	msg db "Hello, Eric."
	msg_len equ  $-msg

section .text                   ; start of the text (code) section
align 4                         ; the code must be 4 byte aligned
    dd MAGIC_NUMBER             ; write the magic number to the machine code,
    dd FLAGS                    ; the flags,
    dd CHECKSUM                 ; and the checksum

loader:                         ; the loader label (defined as entry point in linker script)
	mov ecx, 0
.printmsg:
	mov bl, [msg + ecx]
	mov [PRINT_START_OFFSET+ecx*2], bl     ; write character
	mov byte [PRINT_START_OFFSET+ecx*2+1], 0x07 ; write color of char
	inc ecx
	cmp ecx, msg_len
	jne .printmsg

	mov dx, VGA_CRTC_IDX_PORT
	mov al, 0x0E
	out dx, al      ; latch location high bits
	mov dx, VGA_CRTC_DAT_PORT
	mov al, 0x4
	out dx, al      ; set location high bits
	mov dx, VGA_CRTC_IDX_PORT
	mov al, 0x0F
	out dx, al      ; latch location low bits
	mov dx, VGA_CRTC_DAT_PORT
	mov al, 0xBC
	out dx, al      ; set location low bits
	mov dx, VGA_CRTC_IDX_PORT
	mov al, 0x0A
	out dx, al      ; latch cursor start register
	mov dx, VGA_CRTC_DAT_PORT
	mov al, 0x00
	out dx, al      ; set cursor start scanline
	mov dx, VGA_CRTC_IDX_PORT
	mov al, 0x0B
	out dx, al      ; latch cursor end register
	mov dx, VGA_CRTC_DAT_PORT
	mov al, 0x0F
	out dx, al      ; set cursor end scanline

.loop:
    jmp .loop                   ; loop forever
