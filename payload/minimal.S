/*
 * Minimal "does the jump work at all?" probe for x2.
 *
 * Does nothing but issue PSCI SYSTEM_RESET. If the phone comes back to
 * fastboot/Android within a few seconds, the lk2nd -> ARM64 handoff is
 * fully working and any kernel failure is the kernel's own.
 *
 * Also writes a 4-byte signature + the EL it was entered at into the
 * vendor console-ramoops buffer (0x915A0000) so we can tell afterwards
 * whether memory writes from the payload are landing at all.
 */

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
	/* remember x0 (DTB pointer) in x19 */
	mov	x19, x0

	/* write "X2RDY1" + CurrentEL into 0x915A0000 (ramoops console prz) */
	movz	x20, #0x915A, lsl #16
	str	x20, [x20]		/* marker: address low word first */
	movz	x21, #0x3258		/* "X2" */
	movk	x21, #0x4452, lsl #16	/* "RD" */
	movk	x21, #0x3159, lsl #32	/* "Y1" */
	str	x21, [x20, #8]
	mrs	x21, CurrentEL
	str	x21, [x20, #16]
	str	x19, [x20, #24]		/* DTB pointer we were given */
	dc	cvac, x20
	dsb	sy

	/* PSCI SYSTEM_RESET */
	mov	w0, #0x0009
	movk	w0, #0x8400, lsl #16
	smc	#0

	/* SMC returned => reset unsupported; try HVC then spin */
	mov	w0, #0x0009
	movk	w0, #0x8400, lsl #16
	hvc	#0

1:	wfi
	b	1b
