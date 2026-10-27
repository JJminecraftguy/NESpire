#include "nes.inc"

.globl	mem_read_split
.globl	mem_read
.globl	mem_write_split
.globl	mem_write
.globl	mem_jump_split
.globl	mem_jump

@ Input:
@   r2 = address low byte (split), full address (unsplit)
@   r3 = address high byte (split)
@ Output:
@   r0 = byte read
@   r2 = full address
@   r3 invalidated
@   All other registers preserved

mem_read_split:
	add	r2, r2, r3, lsl #8
mem_read:
	mov	r3, r2, lsr #13
	add	pc, pc, r3, lsl #4
	nop
mem_read_ram:
@ 0000-1FFF: RAM
	bic	r3, r2, #0x11800
	ldrb	r0, [r9, r3]
	strb	r0, [r9, #s_cpu_bus]
	bx	lr
@ 2000-3FFF: PPU registers
	and	r3, r2, #7
	add	r3, pc, r3, lsl #2
	add	pc, r3, #ppu_read_table - (. + 4)
	nop
@ 4000-401F: 2A03 registers
@ 4020-5FFF: Expansion ROM
	sub	r3, r2, #0x4000
	cmp	r3, #0x20
	bcc	mem_read_4000_to_401F
	b	mem_read_mapper_wrapper
@ 6000-7FFF: SRAM
	add	r3, r9, #s_sram - 0x6000
	ldrb	r0, [r3, r2]
	strb	r0, [r9, #s_cpu_bus]
	bx	lr
@ 8000-9FFF: ROM
	ldr	r3, [r9, #s_mem_map + 0x10]
	ldrb	r0, [r3, r2]
	strb	r0, [r9, #s_cpu_bus]
	bx	lr
@ A000-BFFF: ROM
	ldr	r3, [r9, #s_mem_map + 0x14]
	ldrb	r0, [r3, r2]
	strb	r0, [r9, #s_cpu_bus]
	bx	lr
@ C000-DFFF: ROM
	ldr	r3, [r9, #s_mem_map + 0x18]
	ldrb	r0, [r3, r2]
	strb	r0, [r9, #s_cpu_bus]
	bx	lr
@ E000-FFFF: ROM
	ldr	r3, [r9, #s_mem_map + 0x1C]
	ldrb	r0, [r3, r2]
	strb	r0, [r9, #s_cpu_bus]
	bx	lr
@ 10000-100FE: RAM (overflow)
	b	mem_read_ram
mem_read_bad:
	ldrb	r0, [r9, #s_cpu_bus]
	bx	lr
mem_read_ppu_openbus:
	ldrb	r0, [r9, #s_ppu_bus]
	strb	r0, [r9, #s_cpu_bus]
	bx	lr
ppu_read_table:
	b	mem_read_ppu_openbus    @ $2000
	b	mem_read_ppu_openbus    @ $2001
	b	mem_read_2002
	b	mem_read_ppu_openbus    @ $2003
	b	mem_read_2004
	b	mem_read_ppu_openbus    @ $2005
	b	mem_read_ppu_openbus    @ $2006
mem_read_2007:
	ldr	r2, [r9, #s_ppu_address]
	bic	r2, r2, #0xC000
	mov	r3, r2, lsr #10
	add	r3, r9, r3, lsl #2

	@ Buffered VRAM read
	ldr	r3, [r3, #s_ppu_mem_map]
	ldrb	r0, [r9, #s_ppu_data]
	ldrb	r3, [r3, r2]
	strb	r3, [r9, #s_ppu_data]

	@ Palette is read directly, with open bus on upper 2 bits
	cmp	r2, #0x3F00
	andcs	r2, r2, #0x1F
	addcs	r3, r9, #s_ppu_palette
	ldrcsb	r0, [r3, r2]            @ r0 = palette byte
	ldrcsb	r3, [r9, #s_ppu_bus]    @ r3 = open bus
	andcs	r3, r3, #0xC0           @ keep upper 2 bits
	orrcs	r0, r0, r3              @ combine
	strcsb	r0, [r9, #s_ppu_bus]    @ update bus with returned value

	@ Advance ppu_address by 1 or 32
	ldr	r3, [r9, #s_ppu_control]
	ldr	r2, [r9, #s_ppu_address]
	tst	r3, #0x04
	addeq	r2, r2, #0x0001
	addne	r2, r2, #0x0020
	bic	r2, r2, #0x8000
	str	r2, [r9, #s_ppu_address]
	@ Fix our flagrant mangling of r2
	mov	r2, #0x2000
	add	r2, r2, #0x7
	strb	r0, [r9, #s_cpu_bus]
	bx	lr
mem_read_2004:
	ldrb	r3, [r9, #s_ppu_oam_addr]
	add	r0, r9, #s_ppu_oam_ram
	ldrb	r0, [r0, r3]
	and	r3, r3, #0x03
	cmp	r3, #0x02
	andeq	r0, r0, #0xE3
	strb	r0, [r9, #s_cpu_bus]
	bx	lr
mem_read_2002:
	ldrb	r0, [r9, #s_ppu_status]
	bic	r3, r0, #0x80           @ status w/ vblank cleared
	strb	r3, [r9, #s_ppu_status]
	and	r0, r0, #0xE0           @ keep VBL/S0/OV for the return value
	ldrb	r3, [r9, #s_ppu_bus]
	and	r3, r3, #0x1F           @ open bus for lower 5 bits
	orr	r0, r0, r3
	strb	r0, [r9, #s_cpu_bus]    @ CPU data bus
	strb	r0, [r9, #s_ppu_bus]    @ also PPU I/O latch
	mov	r3, #0x00
	strb	r3, [r9, #s_ppu_scroll+2]  @ clear write latch
	bx	lr

mem_read_mapper_wrapper:
	ldrb	r0, [r9, #s_cpu_bus]
	str	lr, [sp, #-4]!
	adr	lr, 1f
	ldr	pc, [r9, #s_mapper_read_lo]
1:	strb	r0, [r9, #s_cpu_bus]
	ldr	lr, [sp], #4
	bx	lr

mem_read_4000_to_401F:
	cmp	r3, #0x15
	beq	mem_read_4015
	cmp	r3, #0x16
	beq	mem_read_4016
	cmp	r3, #0x17
	beq	mem_read_4017
	b	mem_read_bad
mem_read_4015:
	ldrb	r0, [r9, #s_apu_frame_irq]
	mov	r0, r0, lsl #6
	ldrb	r2, [r9, #s_dmc_irq]
	mov	r2, r2, lsl #7
	orr	r0, r0, r2
	ldrb	r2, [r9, #s_apu_length + 0]
	cmp	r2, #0
	orrne	r0, r0, #1
	ldrb	r2, [r9, #s_apu_length + 1]
	cmp	r2, #0
	orrne	r0, r0, #2
	ldrb	r2, [r9, #s_apu_length + 2]
	cmp	r2, #0
	orrne	r0, r0, #4
	ldrb	r2, [r9, #s_apu_length + 3]
	cmp	r2, #0
	orrne	r0, r0, #8
	ldrb	r3, [r9, #s_cpu_bus]
	and	r3, r3, #0x20
	orr	r0, r0, r3
	mov	r3, #0
	strb	r3, [r9, #s_apu_frame_irq]
	strb	r3, [r9, #s_dmc_irq]
	strb	r3, [r9, #s_irq_from_apu]
	bx	lr
mem_read_4016:
	ldr	r3, [r9, #s_input_queue]
	and	r0, r3, #1
	mov	r3, r3, lsr #1
	tst	r3, #0x80
	orreq	r3, r3, #0x80
	orrne	r0, r0, #4
	ldrb	r2, [r9, #s_cpu_bus]
	and	r2, r2, #0xE0
	orr	r0, r0, r2
	strb	r3, [r9, #s_input_queue]
	strb	r0, [r9, #s_cpu_bus]
	bx	lr
mem_read_4017:
	ldrb	r3, [r9, #s_input_queue + 2]
	and	r0, r3, #1
	mov	r3, r3, lsr #1
	orr	r3, r3, #0x80
	ldrb	r2, [r9, #s_cpu_bus]
	and	r2, r2, #0xE0
	orr	r0, r0, r2
	strb	r3, [r9, #s_input_queue + 2]
	strb	r0, [r9, #s_cpu_bus]
	bx	lr

@ Input:
@   r0 = byte to write (high bits ignored)
@   r2 = address low byte (split), full address (unsplit)
@   r3 = address high byte (split)
@ Output:
@   r0, r2, r3 invalidated
@   All other registers preserved

mem_write_split:
	add	r2, r2, r3, lsl #8
mem_write:
	@ All CPU writes drive the shared data bus; the last value stays there
	@ until the next access. This is what "PPU open bus" reads return.
	strb	r0, [r9, #s_ppu_bus]
	strb	r0, [r9, #s_cpu_bus]
	mov	r3, r2, lsr #13
	add	pc, pc, r3, lsl #4
	nop
@ 0000-1FFF: RAM
mem_write_ram:
	bic	r3, r2, #0x11800
	strb	r0, [r9, r3]
	bx	lr
	nop
@ 2000-3FFF: PPU registers
	and	r3, r2, #7
	add	r3, pc, r3, lsl #2
	add	pc, r3, #ppu_write_table - (. + 4)
	nop
@ 4000-401F: 2A03 registers
@ 4020-5FFF: Mapper registers
	sub	r3, r2, #0x4000
	cmp	r3, #0x20
	bcc	mem_write_4000_to_401F
	b	mem_write_4020_to_5FFF
@ 6000-7FFF: SRAM
	add	r3, r9, #s_sram - 0x6000
	strb	r0, [r3, r2]
	b	mem_write_6000_to_7FFF
	nop
@ 8000-FFFF: Mapper registers
	.rept	4
		str	lr, [sp, #-4]!
		adr	lr, return_from_mapper
		ldr	pc, [r9, #s_mapper]
		nop
	.endr
@ 10000-100FE: RAM (overflow)
	b	mem_write_ram
return_from_mapper:
	ldr	r0, [r9, #s_pc_base]
	ldr	lr, [sp], #4
	sub	r4, r4, #1
	sub	r2, r4, r0
	b	mem_jump

ppu_write_table:
	b	mem_write_2000
	b	mem_write_2001
	bx	lr	@ No-op
	b	mem_write_2003
	b	mem_write_2004
	b	mem_write_2005
	b	mem_write_2006
@ Reg 2007:
mem_write_2007:
	ldr	r2, [r9, #s_ppu_address]
	bic	r2, r2, #0xC000

	cmp	r2, #0x3F00
	bcs	mem_write_2007_palette
	mov	r3, r2, lsr #10
	push	{r2}
	ldrb	r2, [r9, #s_mapper_chr_ro]
	mov	r2, r2, lsr r3
	add	r3, r9, r3, lsl #2
	ldr	r3, [r3, #s_ppu_mem_map]
	tst	r2, #1
	pop	{r2}
	streqb	r0, [r3, r2]

	b	mem_write_2007_common
mem_write_2007_palette:
	and	r0, r0, #0x3F
	and	r2, r2, #0x1F

	@ +00/+10, +04/+14, +08/+18, +0C/+1C are mirrored pairs
	add	r3, r9, #s_ppu_palette
	tst	r2, #0x03
	strb	r0, [r3, r2]
	eoreq	r2, r2, #0x10
	streqb	r0, [r3, r2]

	mov	r0, #0
	strb	r0, [r9, #s_palette_cache_valid]
mem_write_2007_common:
	@ Advance ppu_address by 1 or 32
	ldr	r3, [r9, #s_ppu_control]
	ldr	r2, [r9, #s_ppu_address]
	tst	r3, #0x04
	addeq	r2, r2, #0x0001
	addne	r2, r2, #0x0020
	bic	r2, r2, #0x8000
	str	r2, [r9, #s_ppu_address]
	bx	lr

@ Reg 2006: Set PPU address, first hi byte, then lo
mem_write_2006:
	ldr	r3, [r9, #s_ppu_scroll]
	tst	r3, #0x10000
	eor	r3, r3, #0x10000
	str	r3, [r9, #s_ppu_scroll]
	bne	mem_write_2006_second
mem_write_2006_first:
	and	r0, r0, #0x3F
	strb	r0, [r9, #s_ppu_scroll + 1]
	bx	lr
mem_write_2006_second:
	strb	r0, [r9, #s_ppu_scroll]
	strb	r0, [r9, #s_ppu_address]
	mov	r0, r3, lsr #8
	strb	r0, [r9, #s_ppu_address + 1]
	bx	lr
@ Reg 2005: Set scroll position, first x, then y
mem_write_2005:
	ldr	r3, [r9, #s_ppu_scroll]
	and	r0, r0, #0xFF
	tst	r3, #0x10000
	eor	r3, r3, #0x10000
	bne	mem_write_2005_second
mem_write_2005_first:
	bic	r3, r3, #0xE0000000
	bic	r3, r3, #0x0000001F
	orr	r3, r3, r0, ror #3
	str	r3, [r9, #s_ppu_scroll]
	bx	lr
mem_write_2005_second:
	mov	r0, r0, ror #3
	bic	r3, r3, #0x03E0
	orr	r3, r3, r0, lsl #5
	bic	r3, r3, #0x7000
	orr	r3, r3, r0, lsr #17
	str	r3, [r9, #s_ppu_scroll]
	bx	lr
@ Reg 2004: Sprite data
mem_write_2004:
	ldrb	r3, [r9, #s_ppu_oam_addr]
	add	r2, r9, #s_ppu_oam_ram
	strb	r0, [r2, r3]
	add	r3, r3, #1
	strb	r3, [r9, #s_ppu_oam_addr]
	mov	r0, #0
	strb	r0, [r9, #s_spr_loc_table_valid]
	bx	lr
@ Reg 2003: Sprite address
mem_write_2003:
	strb	r0, [r9, #s_ppu_oam_addr]
	bx	lr
@ Reg 2001: PPU Mask
mem_write_2001:
	strb	r0, [r9, #s_ppu_mask]
	bx	lr
@ Reg 2000: PPU Control
mem_write_2000:
	ldrb	r2, [r9, #s_ppu_control]
	eor	r2, r2, r0
	tst	r2, #0x20
	movne	r3, #0
	strneb	r3, [r9, #s_spr_loc_table_valid]
	@and	r2, r2, r0
	ldr	r3, [r9, #s_ppu_scroll]
	strb	r0, [r9, #s_ppu_control]
	bic	r3, #0x0C00
	and	r0, r0, #0x03
	orr	r3, r3, r0, lsl #10
	str	r3, [r9, #s_ppu_scroll]
	@ Generate NMI if 2002.b7 set and 2000.b7 changed from 0 to 1
	@ Cause graphical errors as irq is sampled scanline-by-scanline
	@tst	r2, #0x80
	@bxeq	lr
	@ldrb	r2, [r9, #s_ppu_status]
	@and	r2, r2, #0x80
	@strb	r2, [r9, #s_nmi_reset]
	bx	lr

mem_write_4000_to_401F:
	cmp	r3, #0x00
	beq	mem_write_halt_pulse
	cmp	r3, #0x03
	beq	mem_write_length_load
	cmp	r3, #0x04
	beq	mem_write_halt_pulse
	cmp	r3, #0x07
	beq	mem_write_length_load
	cmp	r3, #0x08
	beq	mem_write_halt_triangle
	cmp	r3, #0x0B
	beq	mem_write_length_load
	cmp	r3, #0x0C
	beq	mem_write_halt_pulse
	cmp	r3, #0x0F
	beq	mem_write_length_load
	cmp	r3, #0x10
	beq	mem_write_4010
	cmp	r3, #0x11
	beq	mem_write_4011
	cmp	r3, #0x12
	beq	mem_write_4012
	cmp	r3, #0x13
	beq	mem_write_4013
	cmp	r3, #0x14
	beq	mem_write_4014
	cmp	r3, #0x15
	beq	mem_write_4015
	cmp	r3, #0x16
	beq	mem_write_4016
	cmp	r3, #0x17
	beq	mem_write_4017
	bx	lr

mem_write_halt_pulse:
	tst	r0, #0x20
	b	mem_write_halt_common

mem_write_halt_triangle:
	tst	r0, #0x80

mem_write_halt_common:
	push	{r1, r2, r3}
	mov	r1, r3, lsr #2
	mov	r2, #1
	mov	r2, r2, lsl r1
	ldrb	r1, [r9, #s_apu_halt]
	biceq	r1, r1, r2
	orrne	r1, r1, r2
	strb	r1, [r9, #s_apu_halt]
	pop	{r1, r2, r3}
	bx	lr

mem_write_length_load:
	push	{r1, r2, r3}
	mov	r1, r3, lsr #2
	mov	r2, #1
	mov	r2, r2, lsl r1
	ldrb	r3, [r9, #s_apu_enable]
	tst	r3, r2
	beq	1f
	mov	r3, r0, lsr #3
	and	r3, r3, #0x1F
	ldr	r2, =apu_length_table
	ldrb	r3, [r2, r3]
	add	r2, r9, #s_apu_length
	strb	r3, [r2, r1]
1:	pop	{r1, r2, r3}
	bx	lr

	.pool
	.align 4
apu_length_table:
	.byte 10, 254, 20, 2, 40, 4, 80, 6, 160, 8, 60, 10, 14, 12, 26, 14
	.byte 12, 16, 24, 18, 48, 20, 96, 22, 192, 24, 72, 26, 16, 28, 32, 30

mem_write_4010:
	strb	r0, [r9, #s_dmc_ctrl]
	bx	lr
mem_write_4011:
	bx	lr
mem_write_4012:
	bx	lr
mem_write_4013:
	strb	r0, [r9, #s_dmc_length]
	bx	lr
mem_write_4015:
	and	r2, r0, #0x0F
	strb	r2, [r9, #s_apu_enable]
	mov	r3, #0
	tst	r2, #1
	streqb	r3, [r9, #s_apu_length + 0]
	tst	r2, #2
	streqb	r3, [r9, #s_apu_length + 1]
	tst	r2, #4
	streqb	r3, [r9, #s_apu_length + 2]
	tst	r2, #8
	streqb	r3, [r9, #s_apu_length + 3]
	tst	r0, #0x10
	bxeq	lr
	ldrb	r2, [r9, #s_dmc_ctrl]
	tst	r2, #0x40
	bxne	lr
	tst	r2, #0x80
	bxeq	lr
	mov	r2, #1
	str	r2, [r9, #s_dmc_countdown]
	mov	r2, #0
	strb	r2, [r9, #s_dmc_irq]
	bx	lr
mem_write_4016:
	ldr	r0, [r9, #s_input_status]
	str	r0, [r9, #s_input_queue]
	bx	lr

mem_write_4017:
	tst	r0, #0x40
	movne	r3, #1
	moveq	r3, #0
	strb	r3, [r9, #s_apu_frame_inhibit]
	tst	r0, #0x80
	movne	r3, #1
	moveq	r3, #0
	strb	r3, [r9, #s_apu_frame_mode]
	ldrb	r3, [r9, #s_apu_frame_irq]
	cmp	r3, #0
	ldrneb	r3, [r9, #s_apu_frame_inhibit]
	cmpne	r3, #0
	moveq	r3, #1
	movne	r3, #0
	strb	r3, [r9, #s_irq_from_apu]
	tst	r0, #0x80
	bxeq	lr
	push	{r1, lr}
	bl	apu_clock_length
	pop	{r1, lr}
	bx	lr

mem_write_4014:
	push	{r1}

	@ Store 256 bytes to OAM RAM
	mov	r0, r0, lsl #8
	mov	r2, r0, lsr #13
	add	r2, r9, r2, lsl #2
	ldr	r2, [r2, #s_mem_map]
	add	r0, r2, r0

	ldrb	r3, [r9, #s_ppu_oam_addr]
	add	r2, r9, #s_ppu_oam_ram
	add	r2, r2, r3
	rsb	r3, r3, #0x100
mem_write_4014_loop:
	ldrb	r1, [r0], #1
	subs	r3, r3, #1
	strb	r1, [r2], #1
	bne	mem_write_4014_loop

	ldrb	r3, [r9, #s_ppu_oam_addr]
	add	r2, r9, #s_ppu_oam_ram
	cmp	r3, #0
	beq	mem_write_4014_done
mem_write_4014_loop2:
	ldrb	r1, [r0], #1
	subs	r3, r3, #1
	strb	r1, [r2], #1
	bne	mem_write_4014_loop2
mem_write_4014_done:
	mov	r0, #0
	strb	r0, [r9, #s_spr_loc_table_valid]
	pop	{r1}
	@ CPU is paused for 513 cycles while the transfer completes
	sub	cpu_cycles, cpu_cycles, #512 * CPU_CYCLE_LENGTH
	sub	cpu_cycles, cpu_cycles, #1 * CPU_CYCLE_LENGTH
	bx	lr

mem_write_6000_to_7FFF:
	ldr	r3, [r9, #s_mapper_use_6000]
	tst	r3, #1
	bxeq	lr
mem_write_4020_to_5FFF:
	str	lr, [sp, #-4]!
	adr	lr, return_from_mapper
	ldr	pc, [r9, #s_mapper_write_lo]

mem_jump_split:
	add	r2, r2, r3, lsl #8
mem_jump:
	cmp	r2, #0x6000
	bcc	mem_jump_low
mem_jump_ok:
	mov	r0, r2, lsr #13
	add	r0, r9, r0, lsl #2
	ldr	r0, [r0, #s_mem_map]
	str	r0, [r9, #s_pc_base]
	add	cpu_pc, r0, r2
	ldrb	r1, [cpu_pc], #1
	add	r3, r0, #0x10000
	cmp	cpu_pc, r3
	beq	mem_jump_wrap
	bx	lr
mem_jump_wrap:
	ldr	r0, [r9, #s_mem_map + 0]
	str	r0, [r9, #s_pc_base]
	mov	cpu_pc, r0
	bx	lr
mem_jump_low:
	cmp	r2, #0x2000
	biccc	r2, r2, #0x1800
	bcc	mem_jump_ok
	cmp	r2, #0x4000
	bcc	mem_jump_error
	cmp	r2, #0x6000
	bcs	mem_jump_error
	@ $4000-$5FFF: open bus. Set data bus, redirect to stub.
	@ The stub is `LSR $56 (zp,X); operand $56; RTS`, which matches what
	@ real hardware executes for JSR $5600 when the bus has $56.
	mov	r0, r2, lsr #8
	strb	r0, [r9, #s_cpu_bus]
	adr	r0, mem_jump_openbus_stub
	str	r0, [r9, #s_pc_base]
	mov	cpu_pc, r0
	ldrb	r1, [cpu_pc], #1
	bx	lr
mem_jump_error:
	ERROR	0x0001
mem_jump_openbus_stub:
	.byte	0x56, 0x56, 0x60  @ LSR $56 (zp,X); operand $56; RTS

.globl remap_pc
remap_pc:
	mov	r0, r2, lsr #13
	add	r0, r9, r0, lsl #2
	ldr	r0, [r0, #s_mem_map]
	str	r0, [r9, #s_pc_base]
	add	cpu_pc, r0, r2
	bx	lr

	.balign 4
	.arm
	.type apu_clock_length, %function
.globl apu_clock_length
apu_clock_length:
	push	{r1, r2, r3}
	ldrb	r1, [r9, #s_apu_halt]
	ldrb	r2, [r9, #s_apu_enable]
	tst	r2, #1
	beq	81f
	tst	r1, #1
	bne	81f
	ldrb	r3, [r9, #s_apu_length + 0]
	cmp	r3, #0
	subne	r3, r3, #1
	strneb	r3, [r9, #s_apu_length + 0]
81:
	tst	r2, #2
	beq	82f
	tst	r1, #2
	bne	82f
	ldrb	r3, [r9, #s_apu_length + 1]
	cmp	r3, #0
	subne	r3, r3, #1
	strneb	r3, [r9, #s_apu_length + 1]
82:
	tst	r2, #4
	beq	83f
	tst	r1, #4
	bne	83f
	ldrb	r3, [r9, #s_apu_length + 2]
	cmp	r3, #0
	subne	r3, r3, #1
	strneb	r3, [r9, #s_apu_length + 2]
83:
	tst	r2, #8
	beq	84f
	tst	r1, #8
	bne	84f
	ldrb	r3, [r9, #s_apu_length + 3]
	cmp	r3, #0
	subne	r3, r3, #1
	strneb	r3, [r9, #s_apu_length + 3]
84:
	pop	{r1, r2, r3}
	bx	lr
	.size apu_clock_length, .-apu_clock_length
