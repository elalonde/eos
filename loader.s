global loader                   ; the entry symbol for ELF

MAGIC_NUMBER equ 0x1BADB002     ; define the magic number constant
FLAGS        equ 0x0            ; multiboot flags
CHECKSUM     equ -MAGIC_NUMBER  ; calculate the checksum
PRINT_START_OFFSET equ 0xB8000 + 15*80*2
                                ; (magic number + checksum + flags should equal 0)
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
	;mov [0xB8000+ecx*2], bl     ; write character
	mov [PRINT_START_OFFSET+ecx*2], bl     ; write character
	mov byte [PRINT_START_OFFSET+ecx*2+1], 0x07 ; write color of char
	inc ecx
	cmp ecx, msg_len
	jne .printmsg

.loop:
    jmp .loop                   ; loop forever
