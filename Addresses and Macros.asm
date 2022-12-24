; ---------------------------------------------------------------------------
; Standard Mega Drive hardware addresses
; ---------------------------------------------------------------------------

; VDP addressses
vdp_data_port:		equ $C00000
vdp_control_port:	equ $C00004
	dma_status_bit:		equ 1				; 1 if a DMA is in progress
	
	; VDP register settings
	vdp_mode_register1:	equ $8000
	vdp_md_color:		equ vdp_mode_register1+4	; Mega Drive colour mode
	
	vdp_mode_register2:	equ $8100
	vdp_enable_display:	equ vdp_mode_register2+$40	; if not set, fill display with bg colour
	vdp_enable_dma:		equ vdp_mode_register2+$10	; enable DMA operations
	vdp_ntsc_display:	equ vdp_mode_register2		; 224px screen height (NTSC)
	vdp_md_display:		equ vdp_mode_register2+4	; mode 5 Mega Drive display
	
	vdp_fg_nametable:	equ $8200			; fg (plane A) nametable setting
	vdp_window_nametable:	equ $8300			; window nametable setting
	vdp_bg_nametable:	equ $8400			; bg (plane B) nametable setting
	vdp_sprite_table:	equ $8500			; sprite table setting
	vdp_sprite_table2:	equ $8600			; sprite table setting for 128kB VRAM
	vdp_bg_color:		equ $8700			; bg colour id (+0..$3F)
	vdp_sms_hscroll:	equ $8800
	vdp_sms_vscroll:	equ $8900
	vdp_hint_counter:	equ $8A00			; number of lines between horizontal interrupts
	
	vdp_mode_register3:	equ $8B00

	vdp_full_vscroll:	equ vdp_mode_register3		; full screen vertical scroll mode
	vdp_full_hscroll:	equ vdp_mode_register3		; full screen horizontal scroll mode
	
	vdp_mode_register4:	equ $8C00
	vdp_320px_screen_width:	equ vdp_mode_register4+$81	; 320px wide screen mode
	
	vdp_hscroll_table:	equ $8D00			; horizontal scroll table setting
	vdp_nametable_hi:	equ $8E00			; high bits of fg/bg nametable settings for 128kB VRAM
	vdp_auto_inc:		equ $8F00			; value added to VDP address after each write
	
	vdp_plane_size:		equ $9000			; fg/bg plane dimensions
	vdp_plane_height_32:	equ vdp_plane_size		; height = 32 cells (256px)
	vdp_plane_width_64:	equ vdp_plane_size+1		; width = 64 cells (512px)
	
	vdp_window_x_pos:	equ $9100
	vdp_window_y_pos:	equ $9200
	vdp_dma_length_low:	equ $9300
	vdp_dma_length_hi:	equ $9400
	vdp_dma_source_low:	equ $9500
	vdp_dma_source_mid:	equ $9600
	vdp_dma_source_hi:	equ $9700
	vdp_dma_vram_fill:	equ vdp_dma_source_hi+$80	; DMA VRAM fill mode
	vdp_dma_vram_copy:	equ vdp_dma_source_hi+$C0	; DMA VRAM to VRAM copy mode

psg_input:		equ $C00011
z80_ram:		equ $A00000				; start of Z80 RAM

; I/O addresses
console_version:	equ $A10001
	console_revision:	equ $F				; revision id in bits 0-3; revision 0 has no TMSS

; Z80 addresses
z80_bus_request:	equ $A11100
z80_reset:		equ $A11200
tmss_sega:		equ $A14000				; contains the string "SEGA"
tmss_bankswitch:		equ $A14101

; Memory sizes
sizeof_ram:		equ $10000
sizeof_vram:	equ $10000
sizeof_vsram:	equ $50
sizeof_cram:	equ $80

ram_start: 		equ $FF0000
ram_end: 		equ $FFFFFF

; ===========================================================================
; Addresses and constants specific to this program
; ---------------------------------------------------------------------------

vram_fg:		equ	$C000
vram_bg:		equ	$E000
vram_window:	equ $F000
vram_sprites:	equ	$D800
vram_hscroll:	equ	$DC00

vram_LicenseFont:	equ	$C20				; location in VRAM where license font is loaded

RAM_Program_Start: 	equ	$FFFFC000			; location in RAM where TMSS test code is copied

stack_pointer:		equ	$FFFF00
						
sizeof_LicenseFont:	equ	filesize("License Text Font.bin")

; Flag values used in license text string
endline:	equ $FF
endstring:	equ 0

; ===========================================================================
; Macros to improve code readability
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; Test if an argument is used
; ---------------------------------------------------------------------------

ifarg:		macros
		if strlen("\1")>0

; ---------------------------------------------------------------------------
; Make a 68K instruction with a VDP command longword or word as the source 
; (more or less replicating the vdpComm function in Sonic 2 AS)
; input: 68k instruction mnemonic, VRAM/VSRAM/CRAM offset, destination RAM
; (vram/vsram/cram), operation (read/write/dma), destination of 68K instruction,
; additional adjustment to command longword (shifts, ANDs)
; ---------------------------------------------------------------------------

vdp_comm:	macro inst,addr,cmdtarget,cmd,dest,adjustment

		local type
		local rwd
	
		if stricmp ("\cmdtarget","vram")
		type: =	$21					; %10 0001
		elseif stricmp ("\cmdtarget","cram")
		type: = $2B					; %10 1011
		elseif stricmp ("\cmdtarget","vsram")
		type: = $25					; %10 0101
		else inform 2,"Invalid VDP command destination (must be vram, cram, or vsram)."
		endc
	
		if stricmp ("\cmd","read")
		rwd: =	$C					; %00 1100
		elseif stricmp ("\cmd","write")
		rwd: = 7					; %00 0111
		elseif stricmp ("\cmd","dma")
		rwd: = $27					; %10 0111
		else inform 2,"Invalid VDP command type (must be read, write, or dma)."
		endc

		ifarg \dest			
			\inst\.\0	#(((type&rwd)&3)<<30)|((addr&$3FFF)<<16)|(((type&rwd)&$FC)<<2)|((addr&$C000)>>14)\adjustment\,\dest
		else	
			\inst\.\0	(((type&rwd)&3)<<30)|((addr&$3FFF)<<16)|(((type&rwd)&$FC)<<2)|((addr&$C000)>>14)\adjustment\	
		endc
		endm
		
; ---------------------------------------------------------------------------
; Make a size constant for an assembly array.
; input: array start label
; ---------------------------------------------------------------------------	

arraysize:	macro	arrayname
sizeof_\arrayname: equ	*-\arrayname
		endm						
