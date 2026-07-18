%ifndef PRN_INC
%define PRN_INC
;-----------------------------------------------------------------------
; prn_* routines handle framebuffer output.
;
; edi is the absolute byte address of the framebuffer cursor. It
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
;                 preserved: eax/ebp/ebx/ecx/edx/esi
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
; prn_dec_byte    print a single byte at an arbitrary byte index within eax
;                 as a decimal number. no leading zeros.
;                 eax = value (consumed)
;
; prn_dec_wordl   print the lower word portion of eax as a decimal number.
;                 no leading zeros.
;                 eax = value (consumed)
;
; prn_hex_byte    print a single byte at an arbitrary byte index within eax
;                 as a 0x-prefixed 2-digit hexadecimal number.
;                 eax = value (preserved).
;                 ecx = index (consumed)
;
; prn_hex_dword   prints a register as a 0x-prefixed 8-digit hexadecimal
;                 number. Printed in big-endian order.
;                 eax = value (preserved).
;
; prn_hex_wordl   prints the lower word portion of a register as a
;                 0x-prefixed 4-digit hexadecimal number. Printed in
;                 big-endian order.
;                 eax = value (preserved).
;
; prn_hex_qword   prints the contents of two registers as a 0x-prefixed
;                 16 digit hexadecimal number. Printed in big-endian order.
;                 eax = lower dword value (consumed).
;                 edx = upper dword value (consumed).
;-----------------------------------------------------------------------
%endif
