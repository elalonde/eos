%ifndef FB_INC
%define FB_INC
;-----------------------------------------------------------------------
; fb_* routines control screen and cursor mechanics.
;
; edi is the absolute byte address of the framebuffer cursor, and
; is updated to new cursor location. routines honor indentation via
; [fb_indent_bytes].
;
; register contract, unless otherwise specified:
;     trashed: eax/ecx/edx
;     preserved: ebx/ebp/esi
;
; variables:
; fb_indent_bytes: dword, byte-currency indent applied at every row
;               start (skip and scroll paths). writers set policy;
;               fb_* and prn_* honor it. zero = no indent.
; fb_mem_addr   dword, absolute fb byte address of the cursor.
;               canonical only between print runs. leaseholders load
;               edi from it and store edi back; nobody else
;               reads or writes it. zero until boot inheritance
;               (crtc_read_fb_addr) seats it.
;
; routines:
; fb_scroll:    takes no arguments and moves entire screen up one row. final
;               row is blank. edi is updated to new cursor placement.
;               preserved: eax/ebp/ebx/ecx/edx/esi
;
; fb_skip_line: takes edi in, scrolls if necessary, and updates edi to new
;               cursor placement.
;
;-----------------------------------------------------------------------

FB_SCROLL_BOUNDARY_ADDR equ 0xB8FA0
FB_MMIO_ADDR            equ 0xB8000   ; framebuffer memory addr
FB_SCROLL_LEN_BYTES     equ 0xF00
LINE_LEN_BYTES          equ 0xA0
FB_ATTR_GREY_ON_BLACK   equ 0x07
%endif
