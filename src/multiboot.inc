%ifndef MULTIBOOT_INC
%define MULTIBOOT_INC

;-----------------------------------------------------------------------
;
; mb_prn_rpt: prints GRUB multiboot report contents to screen
;
; ebx points to the multiboot info structure (preserved).
;
; [fb_mem_addr] contains the absolute byte address of the framebuffer
; cursor. this routine updates [fb_mem_addr], and the hardware cursor
; before return.
;
; eax/ecx/edx/edi trashed. ebx/ebp/esi preserved.
;
;-----------------------------------------------------------------------
%endif
