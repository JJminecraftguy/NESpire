#include "nes.inc"

.globl main
main:
	push	{r4-r11, lr}
	@ Allocate the state data structure from the stack and zero it out
	mov	r5, sp
	sub	sp, sp, #s_SIZE
	bic	sp, sp, #s_ALIGN - 1
	mov	r9, sp
	mov	r4, #0
	mov	r6, #s_SIZE
1:	subs	r6, r6, #4
	str	r4, [r9, r6]
	bne	1b
	str	r5, [r9, #s_saved_sp]

	@ Get our folder path
	add	r4, r9, #s_path
	mov	r2, r4
	subs	r5, r0, #1		@ argc - 1
	ldrpl	r1, [r1, r5, lsl #2]	@ argv[argc - 1]
	movpls	r1, r1
	ble	2f
1:	ldrb	r0, [r1], #1
	strb	r0, [r4], #1
	teq	r0, #'\'
	teqne	r0, #'/'
	moveq	r2, r4
	movs	r0, r0
	bne	1b
2:	str	r2, [r9, #s_path_filename]

	@ Check hardware type
	ldr	r0, =0x900A0000
	ldr	r0, [r0]
	bic	r0, #0xFF000000
	cmp	r0, #0x10
	bne	1f
	@ Non-CX
	mov	r0, #0xDC000000
	add	r0, #0x08
	adr	r1, interrupt_handler_noncx
	mvn	r2, #0
	mov	r3, #0
	mov	r4, #3
	b	2f
1:
	sub	r0, #0x100
	cmp	r0, #0x001
	beq	cx
	sub	r0, #0x100
	cmp	r0, #0x002 @ CX II
	bne	unknown_hardware
cx:
	@ CX
	mov	r0, #0xDC000000
	add	r0, #0x10
	adr	r1, interrupt_handler_cx
	mov	r2, #0
	mov	r3, #1
	mov	r4, #1
2:
	str	r0, [r9, #s_hw_irq_masks]
	str	r1, [r9, #s_hw_irq_handler]
	str	r2, [r9, #s_hw_keypad_invert]
	str	r3, [r9, #s_hw_color]
	str	r4, [r9, #s_frameskip]

	bl	disp_init
	movs	r0, r0
	beq	unknown_hardware
	add	r0, r9, #s_path
	ldr	r1, [r9, #s_path_filename]
	bl	kb_init
	bl	init_interrupts
	bl	init_keypad
	bl	toggle_border
	bl	rom_menu
start_game:
	bl	clear_screen
	bl	disp_flip

	@ Set CPU to power-on state
	mov	cpu_a, #0
	mov	cpu_x, #0
	mov	cpu_y, #0
	mov	cpu_sp, #0x100          @ RESET will bring this to 0x1FD
	mov	cpu_flags, #0

	@ Start CPU emulation
	b	reset

.globl	exit_emulator
exit_emulator:
	ldr	r0, [r9, #s_prg_ptr]
	swi	e_free
	ldr	r0, save_state_ptr
	swi	e_free
	ldr	r0, [r9, #s_menu_backup]
	swi	e_free
	bl	restore_interrupts
	bl	disp_shutdown
unknown_hardware:
	ldr	sp, [r9, #s_saved_sp]
	pop	{r4-r11, pc}

init_interrupts:
	str	r9, [pc, #state_ptr - (.+8)]

	msr	cpsr_c, #0xD3           @ Interrupts off

	@ Disable everything except the timer interrupt (IRQ 19)
	ldr	r0, [r9, #s_hw_irq_masks]
	ldr	r2, [r0]
	str	r2, [r9, #s_saved_irq_mask]
	str	r2, [r0, #4]
	mov	r2, #1 << 19
	str	r2, [r0]

	@ Set the IRQ vector
	mov	r1, #0xA4000000
	ldr	r2, [r1, #0x38]
	str	r2, [r9, #s_saved_irq_handler]
	ldr	r2, [r9, #s_hw_irq_handler]
	str	r2, [r1, #0x38]

	msr	cpsr_c, #0x13           @ Interrupts on
	bx	lr

interrupt_handler_cx:
	push	{r0-r1, lr}
	ldr	r0, =0x900D0000
	mov	r1, #1
	str	r1, [r0, #0x0C]
	b	interrupt_handler_common
interrupt_handler_noncx:
	push	{r0-r1, lr}
	mov	r0, #0xDC000000
	ldr	r1, =0x900A0000
	ldr	lr, [r0, #0x24]
	ldr	lr, [r0, #0x28]
	mov	lr, #1
	str	lr, [r1, #0x20]
	mov	lr, #1 << 19
	str	lr, [r0, #0x04]
	mov	lr, #8
	str	lr, [r0, #0x2C]
interrupt_handler_common:
	@ Advance the frame timer by 3/300 of a second
	ldr	r1, [pc, #state_ptr - (.+8)]
	ldrb	lr, [r1, #s_frame_timer]
	add	lr, lr, #3
	strb	lr, [r1, #s_frame_timer]
	pop	{r0-r1, lr}
	subs	pc, lr, #4
	.pool
state_ptr:
	.word	0

restore_interrupts:
	msr	cpsr_c, #0xD3           @ Interrupts off

	ldr	r0, [r9, #s_hw_irq_masks]
	mvn	r2, #0
	str	r2, [r0, #4]
	ldr	r2, [r9, #s_saved_irq_mask]
	str	r2, [r0]

	mov	r1, #0xA4000000
	ldr	r2, [r9, #s_saved_irq_handler]
	str	r2, [r1, #0x38]
	bx	lr

save_state:
	ldr	r7, save_state_ptr
	cmp	r7, #0
	bne	1f
	mov	r0, #0x4400
	mov	r6, lr
	ldrb	r1, [r9, #s_rom_header + 5]
	movs	r1, r1
	addeq	r0, r0, #0x2000
	swi	e_malloc
	mov	lr, r6
	movs	r7, r0
	bxeq	lr
	str	r7, save_state_ptr

1:	mov	r6, #0x4400
	mov	r10, r9
sstate_loop:
	ldm	r10!, {r0-r3}
	stm	r7!, {r0-r3}
	subs	r6, r6, #16
	bne	sstate_loop
	ldrb	r1, [r9, #s_rom_header + 5]
	movs	r1, r1
	bne	1f
	mov	r6, #0x2000
	ldr	r10, [r9, #s_chr_ptr]
sstate_loop2:
	ldm	r10!, {r0-r3}
	stm	r7!, {r0-r3}
	subs	r6, r6, #16
	bne	sstate_loop2

1:	adr	r11, saved_state_cpu_status
	ldm	sp, {r0-r3, r6-r7, r10}
	stm	r11, {r0-r3, r6-r7, r10}
	bx	lr

load_state:
	ldr	r7, save_state_ptr
	cmp	r7, #0
	bxeq	lr
	mov	r6, #0x4400
	mov	r10, r9
lstate_loop:
	ldm	r7!, {r0-r3}
	stm	r10!, {r0-r3}
	subs	r6, r6, #16
	bne	lstate_loop
	ldrb	r1, [r9, #s_rom_header + 5]
	movs	r1, r1
	bne	1f
	mov	r6, #0x2000
	ldr	r10, [r9, #s_chr_ptr]
lstate_loop2:
	ldm	r7!, {r0-r3}
	stm	r10!, {r0-r3}
	subs	r6, r6, #16
	bne	lstate_loop2

1:	adr	r11, saved_state_cpu_status
	ldm	r11, {r0-r3, r6-r7, r10}
	stm	sp, {r0-r3, r6-r7, r10}
	bx	lr

save_state_ptr: .word 0

saved_state_cpu_status:
	.rept 7
	.word 0
	.endr

.globl newframe
newframe:
	str	lr, [sp, #-4]!

	@ Length counter tick: 4 rounds × 4 channels per frame = 240 Hz
	mov	r4, #4
tick_round:
	mov	r0, #0
tick_channel:
	mov	r1, #1
	mov	r1, r1, lsl r0
	ldrb	r2, [r9, #s_apu_enable]
	tst	r2, r1
	beq	tick_next
	ldrb	r2, [r9, #s_apu_halt]
	tst	r2, r1
	bne	tick_next
	add	r3, r9, #s_apu_length
	ldrb	r2, [r3, r0]
	cmp	r2, #0
	subne	r2, r2, #1
	strneb	r2, [r3, r0]
tick_next:
	add	r0, r0, #1
	cmp	r0, #4
	bne	tick_channel
	subs	r4, r4, #1
	bne	tick_round

	@ Only present the frame if it was actually rendered (not frameskipped)
	ldr	r0, [r9, #s_frameskip_cur]
	cmp	r0, #0
	bleq	disp_flip

	ldrb	r0, [r9, #s_message_timer]
	subs	r0, #1
	strplb	r0, [r9, #s_message_timer]

	ldr	r0, [r9, #s_frameskip_cur]
	ldr	r10, [r9, #s_frameskip]
	subs	r0, r0, #1
	addmi	r0, r0, r10
	str	r0, [r9, #s_frameskip_cur]

	mov	r8, #0
pause_loop:

@ Command keys are polled by kb_read_commands (keybind.c):
@ bits 0-9 = emulator commands, bit 10 = open the key binding menu
	bl	kb_read_commands
	mov	r4, r0
	tst	r4, #1 << 10
	blne	do_keymenu
	tst	r4, #1 << 11
	blne	do_gamemenu
	bic	r4, r4, #(1 << 10) | (1 << 11)

	ldr	r5, [r9, #s_command_keys_pressed]
	str	r4, [r9, #s_command_keys_pressed]
	bic	r5, r4, r5

	tst	r5, #1 << 0;	blne	frameskip_inc
	tst	r5, #1 << 1;	blne	frameskip_dec
	tst	r5, #1 << 2;	blne	save_state
	tst	r5, #1 << 3;	blne	load_state
	tst	r5, #1 << 4;	blne	toggle_border   @ B (Border)
	tst	r5, #1 << 5;	mvnne	r8, r8          @ P (Pause)
	tst	r4, #1 << 6;	bne	exit_emulator   @ Q (Quit)
	tst	r5, #1 << 7;	blne	invert_colors   @ R (Reverse)
	tst	r5, #1 << 8;	blne	sram_save       @ S (Save SRAM)
	tst	r5, #1 << 12;	blne	do_reset        @ R (Reset emulator)
	tst	r4, #1 << 9;	bne	fast_forward    @ * (fast-forward)

	@ Keep looping until the frame timer reaches 5/300 (1/60) of a second
	ldrb	r0, [r9, #s_frame_timer]
	subs	r0, r0, #5
	movcc	r0, #0
	mcrcc	p15, 0, r0, c7, c0, 4
	bcc	pause_loop
	strb	r0, [r9, #s_frame_timer]
#ifdef DEBUG
	bl	fps_counter
#endif
	movs	r8, r8
	bne	pause_loop
fast_forward:
	mov	lr, pc
	ldr	pc, [r9, #s_keypad_read_input]
	str	r0, [r9, #s_input_status]

	ldr	pc, [sp], #4

init_keypad:
	push	{lr}
	swi	e_keypad_type
	ldrh	r0, [r0]
	cmp	r0, #4
	beq	init_keypad_tpad
	cmp	r0, #3
	beq	init_keypad_tpad
init_keypad_clickpad:
	adr	r1, clickpad_command_map
	adr	r2, clickpad_read_input
	b	init_keypad_save
init_keypad_tpad:
	mov	r0, #0xFF
	mov	r1, #0xFF
	adr	r2, touchpad_info_page
	swi	e_touchpad_write
	mov	r0, #0x04
	mov	r1, #0x07
	add	r2, r9, #s_touchpad_size
	swi	e_touchpad_read
	mov	r0, #0xFF
	mov	r1, #0xFF
	adr	r2, touchpad_main_page
	swi	e_touchpad_write

	adr	r1, touchpad_command_map
	adr	r2, touchpad_read_input
init_keypad_save:
	ldr	r2, =kb_read_input
	str	r1, [r9, #s_keypad_command_map]
	str	r2, [r9, #s_keypad_read_input]
	pop	{pc}

touchpad_info_page:
	.byte	0x10
touchpad_main_page:
	.byte	0x04

	@       +    -    7    9    B    P    Q    R    S    *
clickpad_command_map:
	.byte	0x11,0x21,0x37,0x33,0x64,0x28,0x26,0x24,0x22,0x31
touchpad_command_map:
	.byte	0x62,0x52,0x37,0x33,0x45,0x22,0x21,0x20,0x16,0x48

	.align	4

clickpad_read_input:
	mov	r2, #0
	ldr	r0, =0x900E0000
	ldr	r3, [r9, #s_hw_keypad_invert]
	ldr	r1, [r0, #0x14]
	eor	r1, r3
	tst	r1, #1 << 25;	orrne	r2, r2, #0x10000	@ x^2 (2P A)
	tst	r1, #1 << 9;	orrne	r2, r2, #0x20000	@ 10^x (2P B)
	tst	r1, #1 << 21;	orrne	r2, r2, #0x100000	@ 8 (2P Up)
	tst	r1, #1 << 5;	orrne	r2, r2, #0x200000	@ 5 (2P Down)
	tst	r1, #1 << 7;	orrne	r2, r2, #0x400000	@ 4 (2P Left)
	tst	r1, #1 << 3;	orrne	r2, r2, #0x800000	@ 6 (2P Right)

	ldrd	r0, [r0, #0x18]
	eor	r0, r3
	eor	r1, r3
	tst	r0, #1 << 25;	orrne	r2, r2, #0x08	@ Caps (Start)
	tst	r1, #1 << 7;	orrne	r2, r2, #0x01	@ Esc (A)
	tst	r1, #1 << 9;	orrne	r2, r2, #0x02	@ Tab (B)
	tst	r1, #1 << 16;	orrne	r2, r2, #0x10	@ Up
	tst	r1, #1 << 18;	orrne	r2, r2, #0x80	@ Right
	tst	r1, #1 << 20;	orrne	r2, r2, #0x20	@ Down
	tst	r1, #1 << 22;	orrne	r2, r2, #0x40	@ Left
	tst	r1, #1 << 24;	orrne	r2, r2, #0x04	@ Clear (Select)
	tst	r0, #1 << 23;	orrne	r2, r2, #0x40000	@ Var (2P Select)
	tst	r1, #1 << 25;	orrne	r2, r2, #0x80000	@ Ctrl (2P Start)
	tst	r1, #1 << 5;	orrne	r2, r2, #0x100	@ Menu (2P Microphone)

	mov	r0, r2
	bx	lr

touchpad_read_input:
	push	{r4, lr}
	mov	r4, #0

	ldr	r0, =0x900E0000
	ldr	r2, [r9, #s_hw_keypad_invert]
	ldr	r1, [r0, #0x14]
	eor	r1, r2
	tst	r1, #1 << 7;	orrne	r4, r4, #0x400000	@ 4 (2P Left)
	tst	r1, #1 << 3;	orrne	r4, r4, #0x800000	@ 6 (2P Right)

	ldrd	r0, [r0, #0x18]
	eor	r0, r2
	eor	r1, r2
	tst	r1, #1 << 7;	orrne	r4, r4, #0x01	@ Esc (A)
	tst	r1, #1 << 9;	orrne	r4, r4, #0x02	@ Tab (B)
	tst	r0, #1 << 25;	orrne	r4, r4, #0x04	@ Clear (Select)
	tst	r1, #1 << 24;	orrne	r4, r4, #0x08	@ Caps (Start)
	tst	r0, #1 << 7;	orrne	r4, r4, #0x10000	@ = (2P A)
	tst	r0, #1 << 9;	orrne	r4, r4, #0x20000	@ ^ (2P B)
	tst	r0, #1 << 17;	orrne	r4, r4, #0x40000	@ Var (2P Select)
	tst	r1, #1 << 25;	orrne	r4, r4, #0x80000	@ Ctrl (2P Start)
	tst	r1, #1 << 6;	orrne	r4, r4, #0x100000	@ 8 (2P Up)
	tst	r0, #1 << 22;	orrne	r4, r4, #0x200000	@ 5 (2P Down)
	tst	r1, #1 << 5;	orrne	r4, r4, #0x100	@ Menu (2P Microphone)

	sub	sp, #0x0C
	mov	r0, #0x02
	mov	r1, #0x0A
	add	r2, sp, #0x02
	swi	e_touchpad_read
	movs	r0, r0
	beq	1f
	ldrb	r0, [sp, #0x0A]
	tst	r0, #0x01
	beq	1f

	ldrb	r0, [sp, #0x02]
	ldrb	r1, [sp, #0x03]
	ldrb	r2, [r9, #s_touchpad_size]
	ldrb	r3, [r9, #s_touchpad_size+1]
	orr	r0, r1, r0, lsl #8
	orr	r2, r3, r2, lsl #8
	add	r0, r0, lsl #1
	cmp	r0, r2;         orrcc	r4, r4, #0x40	@ Left
	cmp	r0, r2, lsl #1; orrcs	r4, r4, #0x80	@ Right

	ldrb	r0, [sp, #0x04]
	ldrb	r1, [sp, #0x05]
	ldrb	r2, [r9, #s_touchpad_size+2]
	ldrb	r3, [r9, #s_touchpad_size+3]
	orr	r0, r1, r0, lsl #8
	orr	r2, r3, r2, lsl #8
	add	r0, r0, lsl #1
	cmp	r0, r2;         orrcc	r4, r4, #0x20	@ Down
	cmp	r0, r2, lsl #1; orrcs	r4, r4, #0x10	@ Up
1:
	add	sp, #0x0C

	mov	r0, r4
	pop	{r4, pc}

@ Open the key binding menu from inside the frame loop
do_keymenu:
	str	lr, [sp, #-4]!
	bl	kb_menu
	bl	clear_screen
	bl	disp_flip
	mov	r0, #0
	strb	r0, [r9, #s_frame_timer]      @ don't try to catch up on lost time
	mov	r4, #0
	str	r4, [r9, #s_command_keys_pressed]
	ldr	pc, [sp], #4

@ r0 = dest, r1 = src, r2 = byte count (multiple of 4)
copy_words:
1:	ldr	r3, [r1], #4
	str	r3, [r0], #4
	subs	r2, r2, #4
	bne	1b
	bx	lr

@ r0 = dest, r1 = byte count (multiple of 4)
zero_words:
	mov	r2, #0
1:	str	r2, [r0], #4
	subs	r1, r1, #4
	bne	1b
	bx	lr

@ M pressed during play: open the ROM list without losing the running game.
@ The running game stays in RAM and is only discarded if a *different* ROM
@ is picked from the list.
@
@ NOTE: BK_EXT (0x2200), BK_HDR (0x2204) and BK_HDR+(prg_ptr-hdr) (0x2218)
@ all exceed the ARM LDR/STR 12-bit immediate range (4095), and BK_HDR is
@ also not encodable as an ADD immediate.  Addresses are computed by
@ combining #0x2200 (encodable) with a small in-range offset.
do_gamemenu:
	ldrb	r0, [r9, #s_game_loaded]
	movs	r0, r0
	moveq	r4, #0
	bxeq	lr
	push	{lr}
	bl	kb_wait_release
	mov	r0, #BK_SIZE
	swi	e_malloc
	movs	r6, r0
	beq	gm_done
	str	r6, [r9, #s_menu_backup]

	@ Backup SRAM: BK_SRAM == 0, so r6 is already the destination.
	mov	r0, r6
	add	r1, r9, #s_sram
	mov	r2, #0x2000
	bl	copy_words

	@ Backup path: BK_PATH == 0x2000 (encodable as ADD immediate).
	add	r0, r6, #0x2000
	add	r1, r9, #s_path
	mov	r2, #0x200
	bl	copy_words

	@ Backup s_path_extension: BK_EXT == 0x2200.
	add	r0, r6, #0x2200
	ldr	r1, [r9, #s_path_extension]
	str	r1, [r0]

	@ Backup s_rom_header..s_path_filename: BK_HDR == 0x2204 = 0x2200 + 4.
	add	r0, r6, #0x2200
	add	r0, r0, #4
	add	r1, r9, #s_rom_header
	mov	r2, #HDR_SIZE
	bl	copy_words

	mvn	r5, #0				@ r5 < 0: don't auto-load a ROM
	bl	rom_menu
	movs	r7, r0				@ 1 = resume current game, 0 = new ROM was loaded
	beq	gm_new_game

	@ ---- Resume the running game ----
	add	r0, r9, #s_sram
	mov	r1, r6
	mov	r2, #0x2000
	bl	copy_words

	add	r0, r9, #s_path
	add	r1, r6, #0x2000
	mov	r2, #0x200
	bl	copy_words

	add	r0, r6, #0x2200
	ldr	r0, [r0]
	str	r0, [r9, #s_path_extension]

	add	r0, r9, #s_rom_header
	add	r1, r6, #0x2200
	add	r1, r1, #4
	mov	r2, #HDR_SIZE
	bl	copy_words

	mov	r0, r6
	swi	e_free
	mov	r0, #0
	str	r0, [r9, #s_menu_backup]
	bl	kb_wait_release
	bl	clear_screen
	bl	disp_flip
	b	gm_done                 @ ← add this line

do_reset:
	ldrb	r0, [r9, #s_game_loaded]
	movs	r0, r0
	bxeq	lr			@ no game loaded, no-op

	@ Free the current ROM and save-state buffers
	ldr	r0, [r9, #s_prg_ptr]
	swi	e_free
	mov	r0, #0
	str	r0, [r9, #s_prg_ptr]

	ldr	r0, save_state_ptr
	swi	e_free
	mov	r0, #0
	str	r0, save_state_ptr

	ldr	r0, [r9, #s_path_extension]
	adr	r1, reset_rom_ext
	swi	e_strcpy

	add	r0, r9, #s_path
	bl	load_rom
	movs	r0, r0
	bne	exit_emulator

	bl	sram_load

	mov	r0, r9
	mov	r1, #0x800
	bl	zero_words
	add	r0, r9, #0x800
	add	r0, r0, #0x24
	mov	r1, #0x5C
	bl	zero_words
	add	r0, r9, #0x8C0
	mov	r1, #0x140
	bl	zero_words
	add	r0, r9, #s_spr_loc_table
	mov	r1, #0x1800
	add	r1, r1, #0x70
	bl	zero_words

	add	r0, r9, #0x0B10
	add	r0, r0, #0x03
	mov	r1, #24
	bl	zero_words

	mov	r0, #0
	str	r0, [r9, #s_frameskip_cur]
	strb	r0, [r9, #s_spr_loc_table_valid]
	strb	r0, [r9, #s_palette_cache_valid]
	strb	r0, [r9, #s_message_timer]
	strb	r0, [r9, #s_frame_timer]
	str	r0, [r9, #s_command_keys_pressed]

	bl	kb_wait_release

	mov	sp, r9
	b	start_game

reset_rom_ext:
	.string	"nes.tns"
	.align	4

gm_done:
	mov	r0, #0
	strb	r0, [r9, #s_frame_timer]		@ don't catch up on menu time
	mov	r4, #0
	pop	{pc}

	@ ---- A different ROM was loaded: discard the old game ----
gm_new_game:
	@ s_prg_ptr lives at BK_HDR + (s_prg_ptr - s_rom_header) = 0x2204 + 0x14 = 0x2218.
	add	r0, r6, #0x2200
	ldr	r0, [r0, #0x18]
	swi	e_free				@ old PRG+CHR buffer

	ldr	r0, save_state_ptr
	swi	e_free				@ old save state
	mov	r0, #0
	str	r0, save_state_ptr

	mov	r0, r6
	swi	e_free				@ backup buffer
	mov	r0, #0
	str	r0, [r9, #s_menu_backup]

	@ Wipe emulated machine state (load_rom already reinstalled memory maps)
	mov	r0, r9				@ 0000-07FF: NES RAM
	mov	r1, #0x800
	bl	zero_words

	add	r0, r9, #0x800			@ 0824-087F: flags, interrupts, input
	add	r0, r0, #0x24
	mov	r1, #0x5C
	bl	zero_words

	add	r0, r9, #0x8C0			@ 08C0-09FF: palette, PPU regs, OAM
	mov	r1, #0x140
	bl	zero_words

	add	r0, r9, #s_spr_loc_table		@ 0B90-23FF: sprite table + name tables
	mov	r1, #0x1800
	add	r1, r1, #0x70
	bl	zero_words

	mov	r0, #0
	str	r0, [r9, #s_frameskip_cur]
	strb	r0, [r9, #s_spr_loc_table_valid]
	strb	r0, [r9, #s_palette_cache_valid]
	strb	r0, [r9, #s_message_timer]
	strb	r0, [r9, #s_frame_timer]
	str	r0, [r9, #s_command_keys_pressed]
	bl	kb_wait_release
	mov	sp, r9				@ abandon the old call stack
	b	start_game

frameskip_inc:
	add	r10, #1
	cmp	r10, #7
	subeq r10, #1
	str	r10, [r9, #s_frameskip]
	bx lr

frameskip_dec:
	subs	r10, #1
	addeq r10, #1
	str	r10, [r9, #s_frameskip]
	bx lr

	.pool
