/*
 * x2: paint the panel from a bare-metal payload, then reset.
 *
 * Purpose: decide whether the stock bootloader really jumps into the image
 * we hand it. The panel framebuffer is at 0x83400000 (continuous splash,
 * stride 4320 bytes, 1440x2560, 3 bytes per pixel - confirmed from lk2nd's
 * own log). Filling the top third with a solid colour is unambiguous: if
 * the screen changes colour, our code ran.
 *
 * It also encodes the entry CPU state as coloured bars, so we can read
 * SCTLR/CurrentEL with our eyes and no log channel:
 *
 *   MMU bit   (SCTLR_EL1 bit 0)    -> RED bar present  = MMU was ON
 *   D-cache   (SCTLR_EL1 bit 2)    -> GREEN bar        = D-cache was ON
 *   I-cache   (SCTLR_EL1 bit 12)   -> BLUE bar         = I-cache was ON
 *   CurrentEL == EL2               -> WHITE bar        = entered at EL2
 *
 * Layout: full-width horizontal bars, 200 px tall, from the top of frame:
 *   y   0..199  : MAGENTA - "payload ran"
 *   y 200..399  : RED     - MMU on at entry
 *   y 400..599  : GREEN   - D-cache on at entry
 *   y 600..799  : BLUE    - I-cache on at entry
 *   y 800..999  : WHITE   - entered at EL2
 * A bar is only painted when the corresponding bit is set, so the pattern
 * itself is the answer.
 */

.equ FB_BASE,   0x83400000
.equ FB_STRIDE, 4320		/* bytes per line */
.equ FB_BPL,    4320

.text
.globl _start
_start:
	b	code

	.balign	8
	.quad	0			/* 0x08 text_offset */
	.quad	0x100000		/* 0x10 image_size (nonzero => ARM64) */
	.quad	0			/* 0x18 flags */
	.quad	0			/* 0x20 */
	.quad	0			/* 0x28 */
	.quad	0			/* 0x30 */
	.ascii	"ARM\x64"		/* 0x38 magic */
	.balign	8

code:
	/* capture entry state */
	mrs	x19, sctlr_el1
	mrs	x20, currentel

	/* ---- paint: x21 = row, x22 = pixel ptr ---- */
	movz	x21, #0			/* row counter */

	/* MAGENTA bar: payload ran (always) */
	mov	w24, #0x00FF00FF	/* 0xAARRGGBB-ish; RGB888 little endian */
	mov	x25, #200
	bl	paint_rows

	/* RED bar if MMU was on (bit 0) */
	tst	x19, #1
	b.eq	1f
	mov	w24, #0x000000FF	/* red */
	add	x21, x21, #200
	mov	x25, #200
	bl	paint_rows
1:
	/* GREEN bar if D-cache was on (bit 2) */
	tst	x19, #4
	b.eq	2f
	mov	w24, #0x0000FF00	/* green */
	add	x21, x21, #200
	mov	x25, #200
	bl	paint_rows
2:
	/* BLUE bar if I-cache was on (bit 12) */
	tst	x19, #(1 << 12)
	b.eq	3f
	mov	w24, #0x00FF0000	/* blue */
	add	x21, x21, #200
	mov	x25, #200
	bl	paint_rows
3:
	/* WHITE bar if entered at EL2 (CurrentEL bits 3:2 == 2) */
	and	x26, x20, #0xc
	cmp	x26, #0x8
	b.ne	4f
	mov	w24, #0x00FFFFFF	/* white */
	add	x21, x21, #200
	mov	x25, #200
	bl	paint_rows
4:
	dsb	sy

	/* PSCI SYSTEM_RESET */
	mov	w0, #0x0009
	movk	w0, #0x8400, lsl #16
	smc	#0
	mov	w0, #0x0009
	movk	w0, #0x8400, lsl #16
	hvc	#0
5:	wfi
	b	5b

/*
 * paint_rows: fill x25 rows starting at row x21 with colour w24
 * clobbers x22, x23, x27
 */
paint_rows:
	/* pixel address = FB_BASE + row * FB_STRIDE */
	movz	x22, #0x8340, lsl #16
	mov	x23, x21
	mov	x27, #FB_STRIDE
	mul	x23, x23, x27
	add	x22, x22, x23
	/* 1440 pixels * 3 bytes = 4320 bytes per row */
	/* one row = 4320 bytes; write 1080 32-bit words = 4320 bytes */
6:	mov	x23, #1080		/* words remaining in row */
7:	str	w24, [x22], #4
	subs	x23, x23, #1
	b.ne	7b
	add	x21, x21, #1
	subs	x25, x25, #1
	b.ne	6b
	ret
