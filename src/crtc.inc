%ifndef CRTC_INC
%define CRTC_INC
;-----------------------------------------------------------------------
; crtc_* routines drive the VGA CRT controller.
;
; all operations require latching at crtc index and data ports to configure
; registers. the device holds one latched index across calls, so register
; sequences must not be interrupted by other crtc access.
;
; eax/ecx/edx are trashed; other registers preserved.
;
; crtc_read_fb_addr    reads the hw cursor; returns it in eax as
;                      an absolute framebuffer byte address.
; crtc_write_cursor    edi = absolute cursor byte addr. used to write cursor
;                      location.
; crtc_write_scanline  configures cursor shape; shape is preserved until
;                      changed.
;-----------------------------------------------------------------------

%endif
