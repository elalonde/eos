%ifndef UTIL_INC
%define UTIL_INC

;-----------------------------------------------------------------------
; util.* are routines for register-to-register conversions.
;
; eax/ecx/edx trashed unless noted. ebx/ebp/esi/edi preserved.
;
; byte_to_hex     convert a byte into ascii hexadecimal representation.
;                 eax = value, ecx = byte index. both preserved.
;                 returns ascii pair in dh,dl.
;-----------------------------------------------------------------------
HEX_GT_TEN_ASCII_OFFSET equ 0x37
HEX_LT_TEN_ASCII_OFFSET equ 0x30
%endif
