%ifndef PRN_INC
%define PRN_INC
;-----------------------------------------------------------------------
; prn_* routines handle framebuffer output.
;
; EDI is the absolute byte address of the framebuffer cursor. It
; is advanced to new cursor location on return. All routines will scroll
; if necessary and honor indentation via [fb_indent_bytes].
;
; callers lease edi from [fb_mem_addr] and store it back when printing
; completes.
;
; eax/ecx/edx trashed unless noted. ebx/ebp/esi preserved.
;
; prn_byte        print a byte to framebuffer.
;                 dl = byte to print.
;
; prn_msg         print a string to framebuffer.
;                 esi = base (preserved), ecx = count (consumed).
;
; prn_cstr        print a cstring to framebuffer.
;                 esi = cstr (preserved). on return, eax points past the nul.
;
; prn_dec         print a register as a decimal value to framebuffer. no
;                 leading zeros.
;                 eax = value (consumed)
;
; prn_hex_num     prints a register as a 0x-prefixed 8-digit hexadecimal
;                 number.
;                 eax = value (preserved).
;-----------------------------------------------------------------------
%endif
