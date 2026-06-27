global eos                      ; the entry symbol for ELF

MAGIC_NUMBER equ 0x1BADB002     ; define the magic number constant
FLAGS        equ 0x0            ; multiboot flags
CHECKSUM     equ -MAGIC_NUMBER  ; calculate the checksum
                                ; (magic number + checksum + flags should equal 0)
PRINT_START_OFFSET equ 0xB8000 + 15*80*2
VGA_CRTC_IDX_PORT equ 0x3D4     ; VGA CRTC index port
VGA_CRTC_DAT_PORT equ 0x3D5		; VGA CRTC data port

section .rodata
                                ; blinking cursor (register, value) pairs
	cursor db 0x0E, 0x04        ; set cursor location high bits
           db 0x0F, 0xBC        ; set cursor location low bits
		   db 0x0A, 0x00        ; set cursor start scanline
		   db 0x0B, 0x0F        ; set cursor end scanline
    cursor_len equ $-cursor

section .data
	msg db "Hello, Eric."
	msg_len equ  $-msg

section .text                   ; start of the text (code) section
align 4                         ; the code must be 4 byte aligned
    dd MAGIC_NUMBER             ; write the magic number to the machine code,
    dd FLAGS                    ; the flags,
    dd CHECKSUM                 ; and the checksum

eos:                            ; the entry label (defined as entry point in linker script)

	mov ecx, 0
.printmsg:
	mov bl, [msg + ecx]
	mov [PRINT_START_OFFSET+ecx*2], bl     ; write character
	mov byte [PRINT_START_OFFSET+ecx*2+1], 0x07 ; write color of char
	inc ecx
	cmp ecx, msg_len
	jne .printmsg

	mov ecx, 0
.printcursor:
	mov dx, VGA_CRTC_IDX_PORT
	mov al, [cursor+ecx]
	out dx, al                 ; latch register
	mov dx, VGA_CRTC_DAT_PORT
	mov al, [cursor+ecx+1]
	out dx, al                 ; write data
	add ecx, 2 ; next pair
	cmp ecx, cursor_len
	jne .printcursor

.loop:
    jmp .loop                   ; loop forever
