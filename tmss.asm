; Trademark Security System bootrom for Sega Genesis
; (C) 1990 SEGA Corporation

; Disassembled for SNASM68K by moxniso using Ghidra v9.2.1 (https://ghidra-sre.org/) 
; Converted to ASM68K and labeled/commented by OrionNavattan
; Thanks to Hivebrain for the VDP registers and inspiration for the styling

		opt	l.					; . is the local label symbol
		opt	ae-					; automatic evens disabled by default	
		opt	ws+					; allow statements to contain white-spaces
		opt	w+					; print warnings

		include "Addresses and Macros.asm"


RomStart:
		; CPU vectors
		dc.l   stack_pointer				; initial stack pointer value
        dc.l   EntryPoint					; start of program
		dcb.l	62,ErrorTrap				; all other vectors

ROM_Header:
		dc.b "SEGA GENESIS    "				; Hardware system ID (Console name)
        dc.b "(C)SEGA 1990.MAY"					; Copyright holder and release date 
        dc.b "GENESIS OS                                      "	; Domestic name                      
        dc.b "GENESIS OS                                      "	; International name 
        dc.b "OS 00000000-00"					; Serial/version number
        dc.w $5B74						; Checksum (either non-standard or a leftover from sample code, as it does NOT match what fixheadr computes)
        dc.b "                "					; I/O support 
        dc.l RomStart						; Start address of ROM
        dc.l ROM_End-1						; End address of ROM
        dc.l ram_start						; Start address of RAM
        dc.l ram_end						; End address of RAM

        dc.b "                        "				; No SRAM support
        dc.b "                                        "		; Notes
        dc.b "U               "					; Region (Country code), only NA is set despite this ROM being used worldwide

ErrorTrap: 
		bra.s ErrorTrap					; any CPU exceptions that occur while bankswitched to the TMSS ROM are dumped in this infinite loop

EntryPoint:
		; This is a stripped-down version of the standard Mega Drive/Genesis setup library:
		; it does not clear the main RAM nor does it feed the usual RAM and registering clearing program
		; to the Z80, although values related to each of those are still loaded into the registers.
		; Curiously, it, and the main test program, also seem to account for a hypothetical 
		; hardware revision that features this bootrom but NOT the VDP DTACK lock mechanism.
		
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
        	
		move.l	#(vdp_md_display<<16)|(vdp_auto_inc+2),(a4) ; set VDP autoincrement to 2 (one word), and disable DMA
        vdp_comm.l	move,0,cram,write,(a4)			; set VDP to CRAM write
        moveq   #(sizeof_cram/4)-1,d3				; set loop counter to $1F
	.clear_cram:
		move.l  d0,(a3)					; clear the CRAM
        dbf	d3,.clear_cram
        	
		vdp_comm.l	move,0,vsram,write,(a4)
        moveq	#(sizeof_vsram/4)-1, d4				; set loop counter to $13
	.clear_vsram:
		move.l  d0,(a3)					; clear the VSRAM
        dbf     d4,.clear_vsram
        	
		moveq	#4-1,d5					; number of PSG channels
	.loop_psg:
		move.b  (a5)+,psg_input-vdp_data_port(a3)	; mute all PSG channels
        dbf d5,.loop_psg
        
		bra.s   LoadTestProgram

SetupValues:
		dc.l    vdp_mode_register1			; d5
        dc.l    (sizeof_ram/4)-1				; d6, unused
        dc.l    vdp_mode_register2-vdp_mode_register1		; d7
        dc.l    z80_ram						; a0
        dc.l    z80_bus_request					; a1
        dc.l    z80_reset					; a2
        dc.l    vdp_data_port					; a3
        dc.l    vdp_control_port				; a4

	SetupVDP:
		dc.b	vdp_md_color&$FF			; $80, Mega Drive/Genesis color mode, horizontal interrupts disabled
        dc.b	(vdp_md_display|vdp_ntsc_display|vdp_enable_dma)&$FF ; $81: VDP mode 5, DMA enabled, NTSC mode, DMA enabled
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

		dc.b	$9F,$BF,$DF,$FF				; PSG mute values
		

LoadTestProgram:
		lea	(RAM_Program_Start).w,a0		; RAM address to copy test code to
        lea	RAM_Regs(pc),a1
        movem.l	(a1)+,d4-d7/a2-a6				; set new registers
        
		move.w	#(sizeof_RAM_Code/2)-1,d0		; set loop counter to 63
	.copy_to_ram: 
		move.w	(a1)+,(a0)+				; copy test program to RAM  
		dbf	d0,.copy_to_ram	
	
		jsr	(RAM_Program_Start).w			; jump to the code we just copied. we will not be returning here if the cartridge passes the test

FailLoop: 	
		bra.s	FailLoop				; if the cartridge failed the test, the program ends in this infinite loop

RAM_Regs:
		dc.l	' SEG'					;d4
        vdp_comm.l	dc,(vram_fg+$594),vram,write		;d5 ; VRAM write at $C594, location where mappings for license message are written
        dc.l	(sizeof_LicenseFont/4)-1			;d6 ; loops to copy license message text to VRAM

        dc.l    'SEGA'						;d7
        dc.l    tmss_sega					;a2
        dc.l    tmss_bankswitch					;a3
        dc.l    vdp_control_port				;a4
        dc.l    vdp_data_port					;a5
        dc.l    console_version					;a6

RAM_Code:
;Test_Cart:
		; Everything from here to 'arraysize RAM_Code' runs from RAM.
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
		andi.b 	#console_revision,d0
		beq.s	.done					; if no VDP lock, branch
		move.l	#0,(a2)					; lock the VDP
	.done:
		rts						; if we're here, cartridge failed TMSS check; return and trap in FailLoop

.pass:
		bclr	#0,(a3)					; bankswitch back to the TMSS ROM
		jsr	LoadPal					; upload the palette to CRAM
		vdp_comm.l	move,vram_LicenseFont,vram,write,(a4) ; set VDP to VRAM write at address $C20

	.load_font:
		move.l	(a1)+,(a5)				; copy the character set for the license message to VRAM
		dbf	d6,.load_font

		jsr Load_Mappings				; copy the ASCII-based mappings for the license message to VRAM
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
		movea.l	d0,a0					; clear a0; it will now be pointing at cartridge's vector table
		movea.l	(a0)+,sp				; load initial stack pointer value from cartridge into stack pointer
		movea.l	(a0)+,a0				; load start vector from cartridge into a0
		jmp	(a0)					; hand off to the cartridge by jumping to its start vector



DelayLoop:							; double-nested loop to delay for a couple seconds while the license message is displayed
		move.w	#$95CE,d1				; set inner loop counter to 38,350

	.inner_delay_loop:
		dbf d1,.inner_delay_loop
		dbf d0,DelayLoop				; repeat the inner loop 60 times
		rts
		arraysize	RAM_Code	

Pal_Text_Data:
		dc.w	1					; palette size
		dc.w	$EEE					; white
		dc.w	$EE8					; blue (for unused SEGA logo text)

	;.license_font:
		incbin	"License Text Font.bin"			;  character set for license message (also includes an unused mini SEGA logo)

	;.license_mappings:
		dc.b	"   produced by or",endline 
		dc.b	" under license from",endline 
		dc.b	"sega,enterprises ltd{",endstring	; opening curly brace represents a period, not sure what comma does


LoadPal: 
		move.w	(a1)+,d0				; set loop counter to the palette size ($1, aka 2 colors)
		vdp_comm.l	move,2,cram,write,(a4)		; set VDP to CRAM write at Line 1, Entry 3

	.cram_loop:
		move.w 	(a1)+,(a5)				; copy the palette to CRAM
		dbf	d0,.cram_loop
		rts

Load_Mappings:
		move.l	d5,(a4)					; on first run, set VDP to VRAM write at $C594; on all subsequent runs, set write address for new line

	.main:
		moveq	#0,d1
		move.b 	(a1)+,d1				; copy current byte of mappings to d1
		bmi.s	.skip_ahead				; if it is the line terminator, branch
		bne.s	.set					; if not zero, branch
		rts						; if zero, we are done

	.set:
		move.w	d1,(a5)					; copy current mapping to VRAM as word
		bra.s	.main					; next byte

	.skip_ahead:
		addi.l	#$1000000,d5				; add $1000000 to make VDP command longword to start the next line
		bra.s	Load_Mappings				; set new write address

		dcb.l	19,$FFFFFFFF				; padding
ROM_End:
		end