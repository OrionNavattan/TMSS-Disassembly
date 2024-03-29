; =========================================================================
; Sega Mega Drive/Genesis Trademark Security System Bootrom
; Original source code (C) 1990 SEGA Corporation

; Disassembled for SNASM68K by moxniso using Ghidra v9.2.1 (https://ghidra-sre.org/)
; Converted to ASM68K, cleaned up, and labeled/commented by OrionNavattan
; Thanks to Hivebrain for the VDP registers and inspiration for the styling,
; and MarkeyJester for information about the comma in the message text.
; ==========================================================================


		opt	l.					; . is the local label symbol
		opt	ae-					; automatic evens disabled
		opt	ws+					; allow statements to contain white-spaces
		opt	w+					; print warnings

		include "Addresses and Macros.asm"

ROM_Start:
		; CPU vectors
		dc.l   stack_pointer				; initial stack pointer value
        dc.l   EntryPoint					; start of program
		dcb.l	62,ErrorTrap				; all other vectors

ROM_Header:
		dc.b "SEGA GENESIS    "				; hardware system ID (Console name)
        dc.b "(C)SEGA 1990.MAY"					; copyright holder and release date
        dc.b "GENESIS OS                                      "	; Domestic name
        dc.b "GENESIS OS                                      "	; international name
        dc.b "OS 00000000-00"					; serial/version number
        dc.w $5B74						; checksum; interestingly, it does NOT match the ROM. This might be from sample code or from an earlier build of the ROM.
        dc.b "                "					; I/O support
        dc.l ROM_Start						; start address of ROM
        dc.l ROM_End-1						; end address of ROM
        dc.l ram_start						; start address of RAM
        dc.l ram_end						; end address of RAM

        dc.b "                        "				; no SRAM support
        dc.b "                                        "		; notes
        dc.b "U               "					; region (Country code), only North America is set despite this ROM being used worldwide (this may be a leftover from when TMSS was meant to be a region lockout)
; =========================================================================

ErrorTrap:
		bra.s ErrorTrap					; any CPU exceptions that occur while bankswitched to the TMSS ROM are dumped in this infinite loop

; ---------------------------------------------------------------------------
; This is a stripped-down version of the standard ICD_BLK4 init library. it
; does not clear the main RAM (which isn't necessary here since that was a
; workaround for a hardware bug on the Model 1 VA0), nor does it feed the
; usual RAM and register clearing program to the Z80, although values related
; to each of those are still loaded into the registers. Curiously, it, and
; the main test program, also seem to account for a hypothetical hardware
; revision that features this bootrom but NOT the VDP DTACK/RESET lock
; mechanism.

; (Interestingly, descriptions of a prototype TMSS unit (Genesis III)
; displayed in 1990, plus the fact that Accolade was apparently unaware that
; production TMSS units displayed the license message until after they made
; their games TMSS compliant, seems to imply that there was also a variant
; that had the lock mechanism, but NOT this bootrom.)
; ---------------------------------------------------------------------------

EntryPoint:
		lea	SetupValues(pc),a5			; load setup array
        movem.l (a5)+,d5-a4					; first VDP register value, clear_ram loop counter (unused), VDP register increment, Z80 RAM start (unused), Z80 bus request register, Z80 reset register, VDP data port, VDP control port
        move.b  console_version-z80_bus_request(a1),d0		; get console version
        andi.b  #console_revision,d0				; only need version bits
        beq.s   .no_hardware_lock				; if this is a (hypothetical) unit without the VDP lock, branch
        move.l  #'SEGA',tmss_sega-z80_bus_request(a1)		; satisfy the TMSS (yes, this bootrom has to do this too)

	.no_hardware_lock:
		move.w  (a4),d0					; clear write-pending flag in VDP to prevent issues if the 68k has been reset in the middle of writing a command long word to the VDP
        moveq   #0,d0
        movea.l d0,a6
        move.l  a6,usp ; set user stack pointer to 0

		moveq   #sizeof_SetupVDP-1,d1			; number of VDP registers to write
	.setup_vdp_regs:
		move.b	(a5)+,d5				; add $8000 to value
		move.w	d5,(a4)					; move value to	VDP register
		add.w	d7,d5					; next register
        dbf	d1,.setup_vdp_regs				; repeat for all registers

		move.l  #$40000080,(a4)				; clear VRAM with VDP fill command
        move.w  d0,(a3)

	.wait_for_dma:
		move.w  (a4),d4					; get status register
        btst	#dma_status_bit,d4
        bne.s	.wait_for_dma					; wait until the VRAM clear has finished

		move.l	#(vdp_md_display<<16)|(vdp_auto_inc+2),(a4) ; set VDP autoincrement to 2 (one word) and disable DMA
        vdp_comm.l	move,0,cram,write,(a4)			; set VDP to CRAM write
        moveq   #(sizeof_cram/4)-1,d3				; set loop counter to $1F
	.clear_cram:
		move.l  d0,(a3)					; clear the CRAM
        dbf	d3,.clear_cram

		vdp_comm.l	move,0,vsram,write,(a4)		; set VDP to VSRAM write
        moveq	#(sizeof_vsram/4)-1, d4				; set loop counter to $13
	.clear_vsram:
		move.l  d0,(a3)					; clear the VSRAM
        dbf     d4,.clear_vsram

		moveq	#4-1,d5					; number of PSG channels
	.loop_psg:
		move.b  (a5)+,psg_input-vdp_data_port(a3)	; mute all PSG channels
        dbf d5,.loop_psg

		bra.s   LoadTestProgram
; =========================================================================

SetupValues:
		dc.l    vdp_mode_register1			; d5
        dc.l    (sizeof_ram/4)-1				; d6, unused
        dc.l    vdp_mode_register2-vdp_mode_register1		; d7
        dc.l    z80_ram						; a0, unused
        dc.l    z80_bus_request					; a1
        dc.l    z80_reset					; a2, unused
        dc.l    vdp_data_port					; a3
        dc.l    vdp_control_port				; a4

	SetupVDP:
		dc.b	vdp_md_color&$FF			; $80, Mega Drive/Genesis color mode, horizontal interrupts disabled
        dc.b	(vdp_md_display|vdp_ntsc_display|vdp_enable_dma)&$FF ; $81: VDP mode 5, NTSC mode, DMA enabled
        dc.b	(vdp_fg_nametable+(vram_fg>>10))&$FF		; $82: Foreground nametable at $C000
        dc.b	(vdp_window_nametable+(vram_window>>10))&$FF	; $83: Window nametable at $F000
        dc.b	(vdp_bg_nametable+(vram_bg>>13))&$FF		; $84: Background nametable at $E000
        dc.b	(vdp_sprite_table+(vram_sprites>>9))&$FF	; $85: Sprite attribute table at $D800
        dc.b	vdp_sprite_table2&$FF				; $86: Unused (high bit of sprite attribute table for 128KB VRAM)
        dc.b	vdp_bg_color&$FF				; $87: Background color
        dc.b	vdp_sms_hscroll&$FF				; $88: Unused (Mode 4 HScroll register)
        dc.b	vdp_sms_vscroll&$FF				; $89: Unused (Mode 4 VScroll register)
        dc.b	(vdp_hint_counter+$FF)&$FF			; $8A: Scanline where horizontal interrupt will be triggered
        dc.b	(vdp_full_vscroll|vdp_full_hscroll)&$FF		; $8B: Full screen VScroll and HScroll, external interrupts disabled
        dc.b	vdp_320px_screen_width&$FF			; $8C: H40 mode (320 x 224 screen res), no shadow/highlight, no interlace
        dc.b	(vdp_hscroll_table+(vram_hscroll>>10))&$FF	; $8D: HScroll table at $DC00
        dc.b	vdp_nametable_hi&$FF				; $8E: Unused (high bits of fg and bg nametable addresses for 128KB VRAM)
        dc.b	(vdp_auto_inc+1)&$FF				; $8F: Autoincrement 1 byte
        dc.b	(vdp_plane_width_64|vdp_plane_height_32)&$FF	; $90: 64x32 plane size
        dc.b	vdp_window_x_pos&$FF				; $91: Window Plane X pos
        dc.b	vdp_window_y_pos&$FF				; $92: Window Plane Y pos
		dc.w 	sizeof_vram-1				; $93/94: DMA length
        dc.w	0						; $95/96: DMA source
        dc.b 	vdp_dma_vram_fill&$FF				; $97: DMA fill

    	arraysize	SetupVDP

		dc.b	tPSG1|$1F,tPSG2|$1F,tPSG3|$1F,tPSG4|$1F	; PSG mute values
; =========================================================================

LoadTestProgram:
		lea	(RAM_Program_Start).w,a0		; RAM address to copy test code to
        lea	Test_Registers(pc),a1				; array with register values to be used during test and loading the license message
        movem.l	(a1)+,d4-d7/a2-a6				; set new registers

		move.w	#(sizeof_RAM_Code/2)-1,d0		; set loop counter to $3F
	.copy_to_ram:
		move.w	(a1)+,(a0)+				; copy test program to RAM
		dbf	d0,.copy_to_ram

		jsr	(RAM_Program_Start).w			; jump to the code we just copied; we will not be returning here if the cartridge passes the test

FailLoop:
		bra.s	FailLoop				; if the cartridge failed the test, the program ends in this infinite loop
; =========================================================================

Test_Registers:
		dc.l	' SEG'					; d4
        vdp_comm.l	dc,(vram_fg+((sizeof_vram_row_64*11)+(2*10))),vram,write ; d5 ; VRAM write at $C594 (Line 11, column 10), start location in FG nametable of first line of license message
        dc.l	(sizeof_LicenseFont/4)-1			; d6; loops to copy license message font to VRAM
        dc.l    'SEGA'						; d7
        dc.l    tmss_sega					; a2
        dc.l    tmss_bankswitch					; a3
        dc.l    vdp_control_port				; a4
        dc.l    vdp_data_port					; a5
        dc.l    console_version					; a6

; ---------------------------------------------------------------------------
; Everything from here to 'arraysize RAM_Code' runs from RAM.
; This is an excellent example of relocatable code: all branches within this
; code are relative, meaning we do not have to use ASM68K's obj function
; to assemble it.
; ---------------------------------------------------------------------------

RAM_Code:
		bset	#0,(a3)					; bankswitch to cartridge
		cmp.l	(ROM_Header).w,d7			; is 'SEGA' at the start of the ROM header?
		beq.s	.pass					; if so, cartridge has passed test

		cmp.l	(ROM_Header).w,d4			; if 'SEGA' was not found, try ' SEG' (perhaps accommodating an early game with a typo in the header?)
		bne.s	.fail					; if that is not found, cartridge has failed the test

		cmpi.b 	#'A',(ROM_Header+4).w			; if ' SEG' was found, check for the last 'A'
		beq.s	.pass					; if that is found, cartridge has passed test

	.fail:
		bclr	#0,(a3)					; bankswitch back to TMSS ROM
		move.b	(a6),d0					; get version register
		andi.b 	#console_revision,d0			; only hardware revision bits
		beq.s	.done					; if no VDP lock, branch
		move.l	#0,(a2)					; lock the VDP

	.done:
		rts						; if we're here, cartridge failed TMSS check; return and trap in FailLoop

; ---------------------------------------------------------------------------
; If cartridge passed the test, load the message assets and display it for
; several seconds.
; ---------------------------------------------------------------------------

.pass:
		bclr	#0,(a3)					; bankswitch back to the TMSS ROM
		jsr	(LoadPal).l				; copy the palette to CRAM
		vdp_comm.l	move,vram_LicenseFont,vram,write,(a4) ; set VDP to VRAM write at address $C20

	.load_font:
		move.l	(a1)+,(a5)				; copy the character set for the license message to VRAM
		dbf	d6,.load_font

		jsr (Load_Tilemap).l				; copy the ASCII-based tilemap for the license message to VRAM

		move.w	#vdp_enable_display|vdp_md_display,(a4)	; enable display, showing the license message
		move.w	#$3C,d0
		bsr.s	DelayLoop				; wait for a few seconds

		move.w	#vdp_md_display,(a4)			; disable display
		move.b	(a6),d0					; get version register
		andi.b	#console_revision,d0			; only hardware revision bits

		beq.s	.hand_off_to_cart			; if no VDP lock, branch
		move.l	#0,(a2)					; lock the VDP (the cartridge will have to unlock it as the second part of the TMSS check)


	.hand_off_to_cart:
		bset	#0,(a3)					; bankswitch back to cartridge (and stay there permanently)
		moveq	#0,d0					; clear d0
		movea.l	d0,a0					; clear a0; it will now be pointing at start of cartridge's vector table
		movea.l	(a0)+,sp				; load initial stack pointer value from cartridge into stack pointer
		movea.l	(a0)+,a0				; load start vector from cartridge into a0
		jmp	(a0)					; hand off to the cartridge by jumping to its start vector
; =========================================================================

DelayLoop:							; double-nested loop to delay for a couple seconds while the license message is displayed
		move.w	#$95CE,d1				; set inner loop counter to 38,350

	.inner_delay_loop:
		dbf d1,.inner_delay_loop
		dbf d0,DelayLoop				; repeat the inner loop 60 times
		rts

		arraysize	RAM_Code
		; End of RAM code
; =========================================================================

Pal_Text_Data:
		dc.w	2-1					; palette size
		dc.w	cWhite					; white
		dc.w	$EE8					; blue (for unused SEGA logo text)

	;.license_font:
		incbin	"License Text Font.bin"			;  character set for license message (also includes an unused mini SEGA logo)

	;.license_mappings:
		dc.b	"   produced by or",endline
		dc.b	" under license from",endline
		dc.b	"sega,enterprises ltd{",endstring	; opening curly brace represents a period, comma may have been meant for a TM symbol or related
; =========================================================================

LoadPal:
		move.w	(a1)+,d0				; set loop counter to the palette size ($1, aka 2 colors)
		vdp_comm.l	move,2,cram,write,(a4)		; set VDP to CRAM write at Line 1, Entry 3

	.cram_loop:
		move.w 	(a1)+,(a5)				; copy the palette to CRAM
		dbf	d0,.cram_loop
		rts
; =========================================================================

Load_Tilemap:
		move.l	d5,(a4)					; on first run, set VDP to VRAM write at $C594; on all subsequent runs, set write address for new line

	.main:
		moveq	#0,d1
		move.b 	(a1)+,d1				; get current byte of license text
		bmi.s	.next_line				; if it's the line terminator, branch
		bne.s	.set					; if not zero, branch
		rts						; if zero, we are done

	.set:
		move.w	d1,(a5)					; copy current byte to VRAM as word, making it into a tilemap entry
		bra.s	.main					; next byte

	.next_line:
		addi.l	#$1000000,d5				; add $1000000 to make VDP command longword to start the next line
		bra.s	Load_Tilemap				; set new write address
; =========================================================================

		dcb.l	19,$FFFFFFFF				; padding
ROM_End:
		end
