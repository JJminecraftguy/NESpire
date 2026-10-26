#include "nes.inc"

nes_rom_file_mask:
	.string	"*.nes.tns"
title:
	.string	" NESpire  C=key bindings  M=resume game"
	.align	4

.globl rom_menu
rom_menu:
	push	{r4-r11, lr}

	movs	r5, r5
	bmi	2f
	ldr	r0, [r9, #s_path_filename]
1:	ldrb	r2, [r0], #1
	movs	r2, r2
	bne	1b
	sub	r0, #8
	str	r0, [r9, #s_path_extension]
	add	r0, r9, #s_path
	bl	load_rom
	movs	r0, r0
	beq	load_success
2:	ldr	r0, [r9, #s_path_filename]
	adr	r1, nes_rom_file_mask
	swi	e_strcpy

#define liststart r4
#define listend   r5
#define listmax   r8
	@ Using save ram as a buffer to hold list of filenames
	add	liststart, r9, #s_sram
	mov	listend, liststart
	add	listmax, liststart, #0x2000

	sub	sp, #308
	mov	r0, sp
	add	r1, r9, #s_path
	swi	e_NU_Get_First
	movs	r0, r0
	bne	no_files
next_file:
	@ Append filename to list
	mov	r0, listend
	add	r1, sp, #13
1:	teq	r0, listmax
	beq	filename_buf_full
	ldrb	r2, [r1], #1
	movs	r2, r2
	strb	r2, [r0], #1
	bne	1b
	mov	listend, r0

	mov	r0, sp
	swi	e_NU_Get_Next
	movs	r0, r0
	beq	next_file
filename_buf_full:
	mov	r0, sp
	swi	e_NU_Done
no_files:
	add	sp, #308

#define cursor r6
#define pagetop r7
#define pagebottom r8
#define keypressed r10
#define keyrepeat r11
	mov	cursor, liststart
	mov	pagetop, liststart
	mov	keypressed, #0
	mov	keyrepeat, #0

menu_redraw:
	bl	fill_whole_white
	adr	r0, title
	mov	r1, #0
	mov	r2, #40
	mov	r3, #-1
	bl	display_string

	mov	pagebottom, pagetop
	str	r10, [sp, #-4]!
	mov	r10, #640
menu_next_row:
	teq	pagebottom, cursor
	moveq	r0, #0x10
	movne	r0, #' '
	mov	r1, r10
	bl	display_char
	cmp	pagebottom, listend
	bcs	menu_draw_done
	mov	r0, pagebottom
	add	r1, r10, #1
	add	r2, r10, #40
	mov	r3, #0
	bl	display_string
1:	ldrb	r0, [pagebottom], #1
	movs	r0, r0
	bne	1b
	add	r10, #640
	teq	r10, #640 * 15
	bne	menu_next_row
menu_draw_done:
	ldr	r10, [sp], #4
	bl	disp_flip

menu_waitkey:
	mov	r0, #0
	mcr	p15, 0, r0, c7, c0, 4
	bl	kb_read_menu_input

	mov	r1, keypressed
	mov	keypressed, r0

	teq	r0, r1
	movne	keyrepeat, #25
	bne	1f
	movs	keyrepeat, keyrepeat
	subnes	keyrepeat, #1
	bne	menu_waitkey
	mov	keyrepeat, #5
1:

	tst	r0, #0x01
	bne	exit_emulator
	tst	r0, #0x10
	bne	menu_up
	tst	r0, #0x20
	bne	menu_down
	tst	r0, #0x100
	bne	menu_start
	tst	r0, #0x200
	bne	menu_keybinds
	tst	r0, #0x400
	bne	menu_resume
	b	menu_waitkey

@ M in the menu: return to the running game (no-op if none was ever started)
menu_resume:
	ldrb	r1, [r9, #s_game_loaded]
	movs	r1, r1
	beq	menu_waitkey
	mov	r0, #1
	pop	{r4-r11, pc}

menu_keybinds:
	bl	kb_menu
	bl	clear_screen		@ restore the menu background (border color)
	mov	keypressed, #0
	mov	keyrepeat, #0
	b	menu_redraw

menu_up:
	teq	cursor, liststart
	beq	menu_waitkey
1:	sub	cursor, #1
	teq	cursor, liststart
	ldrneb	r0, [cursor, #-1]
	movnes	r0, r0
	bne	1b
	cmp	cursor, pagetop
	movcc	pagetop, cursor
	b	menu_redraw

menu_down:
	mov	r0, cursor
1:	ldrb	r1, [r0], #1
	movs	r1, r1
	bne	1b
	cmp	r0, listend
	bcs	menu_waitkey
	mov	cursor, r0
	cmp	cursor, pagebottom
	bcc	menu_redraw
1:	ldrb	r0, [pagetop], #1
	movs	r0, r0
	bne	1b
	b	menu_redraw

menu_start:
	ldr	r0, [r9, #s_menu_backup]
	movs	r0, r0
	beq	menu_start_load
	@ Opened from a running game: picking the same ROM just resumes it.
	ldr	r1, [r9, #s_path_filename]
	add	r2, r9, #s_path
	sub	r1, r1, r2
	add	r0, r0, r1
	add	r0, r0, #BK_PATH
	mov	r1, cursor
menu_same_cmp:
	ldrb	r2, [r0], #1
	ldrb	r3, [r1], #1
	cmp	r2, r3
	bne	menu_start_diff
	movs	r2, r2
	bne	menu_same_cmp
	mov	r0, #1
	pop	{r4-r11, pc}
menu_start_diff:
	@ Different ROM: clear mapper state before loading it.
	@ If loading fails and the user backs out, the caller restores from backup.
	add	r0, r9, #s_mapper_state
	mov	r1, #0x80
	mov	r2, #0
1:	str	r2, [r0], #4
	subs	r1, r1, #4
	bne	1b
menu_start_load:
	@ Append filename to directory
	ldr	r0, [r9, #s_path_filename]
	mov	r1, cursor
1:	ldrb	r2, [r1], #1
	movs	r2, r2
	strb	r2, [r0], #1
	bne	1b
	sub	r0, #8
	str	r0, [r9, #s_path_extension]

	@ Try to load ROM (full path)
	add	r0, r9, #s_path
	bl	load_rom
	movs	r0, r0
	beq	load_success

	@ Display error message
	mov	r1, #7
	mov	r2, #40
	mov	r3, #-1
	bl	display_string
	adr	r0, error_hdr
	mov	r1, #0
	mov	r2, #7
	mov	r3, #-1
	bl	display_string
	bl	disp_flip
	b	menu_waitkey
error_hdr:
	.string	"ERROR:"
	.align	4

load_success:
	@ Clear save ram (since we used it to hold filenames)
	add	r0, r9, #s_sram
	mov	r1, #0
	mov	r2, #0x2000
	swi	e_memset

	@ If game has battery-backed save ram, try to load from save file
	bl	sram_load

	mov	r0, #1
	strb	r0, [r9, #s_game_loaded]
	mov	r0, #0
	pop	{r4-r11, pc}

@ r0 = character
@ r1 = position (row * 640 + column)
display_char:
	mov	r2, #0
@ r2 = color (0 = normal, -1 = reverse)
display_char_withcolor:
	push	{r4, lr}
	ldr	r12, =disp_fb
	adr	r4, font
	add	r4, r0, lsl #4
	mov	r3, #0x10
	ldr	r0, [r9, #s_hw_color]
	movs	r0, r0
	bne	display_char_16bpp
display_char_4bpp:
	add	r12, r1, lsl #2
2:	ldrb	r1, [r4], #1
	mvn	r0, r2
1:	ror	r0, #24
	lsrs	r1, #1
	eorcs	r0, #0x0F
	lsrs	r1, #1
	eorcs	r0, #0xF0
	adds	r3, #0x40000000
	bcc	1b
	str	r0, [r12], #160
	subs	r3, #1
	bne	2b
	pop	{r4, pc}
display_char_16bpp:
	add	r12, r1, lsl #4
2:	ldrb	r1, [r4], #1
	lsl	r1, #24
1:	mvn	r0, #0
	lsls	r1, #1
	andcs	r0, r0, lsl #16
	lsls	r1, #1
	andcs	r0, r0, lsr #16
	eor	r0, r2
	str	r0, [r12], #4
	adds	r3, #0x40000000
	bcc	1b
	add	r12, #640 - 16
	subs	r3, #1
	bne	2b
	pop	{r4, pc}

	.pool                                    @ ← NEW: literal pool for disp_fb

@ r0 = string
@ r1 = start position
@ r2 = end position
@ r3 = color (0 = normal, -1 = reverse)
.globl	display_string
display_string:
	push	{r4-r7, lr}
	mov	r4, r0
	mov	r5, r1
	mov	r6, r2
	mov	r7, r3

1:	ldrb	r0, [r4]
	movs	r0, r0
	addne	r4, #1
	mov	r1, r5
	add	r5, #1
	mov	r2, r7
	bl	display_char_withcolor
	cmp	r5, r6
	bcc	1b
	pop	{r4-r7, pc}
fill_whole_white:
	push	{r4, lr}
	ldr	r4, =disp_fb
	ldr	r0, [r9, #s_hw_color]
	mov	r1, #0x9600              @ 4bpp: 38400 bytes = whole fb
	cmp	r0, #0
	lslne	r1, r1, #2               @ 16bpp: 153600 bytes = whole fb
	mvn	r3, #0                   @ white
1:	str	r3, [r4], #4
	subs	r1, r1, #4
	bne	1b
	pop	{r4, pc}

	.pool
font:
	.incbin	"font.bin"
