/*
 * x2: report the entry CPU state, then reset.  (MMU-off-first variant)
 *
 * Two payloads behaved differently under the stock bootloader:
 *   minimal (PSCI reset only)                 -> works, phone reboots
 *   probe   (writes 0x915A0000, then resets)  -> hangs
 * The only difference is the memory access, so the state we are entered in
 * must make that access fault - the MMU is not off the way the arm64 boot
 * protocol requires.
 *
 * To get the data out in ONE run, turn the MMU and caches off FIRST (no
 * memory access before that), then store the record and reset. Nothing can
 * fault before the teardown, so this cannot hang like the old probe.
 *
 * Record written at 0x915A0000 (vendor console-ramoops area, plain DRAM):
 *   +0  magic 0x58583231  ("12XX" LE)
 *   +4  SCTLR_EL1 as inherited   (bit0 = MMU, bit2 = D-cache, bit12 = I-cache)
 *   +8  CurrentEL as inherited
 *   +12 low 32 bits of x0 (DTB pointer)
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
	/* capture the entry state before touching anything */
	mrs	x19, sctlr_el1
	mrs	x20, currentel
	mov	x21, x0			/* DTB pointer */

	/* ---- turn MMU + caches off (no memory access yet) ---- */
	bic	x22, x19, #(1 << 0)	/* M  */
	bic	x22, x22, #(1 << 2)	/* C  */
	bic	x22, x22, #(1 << 12)	/* I  */
	msr	sctlr_el1, x22
	isb
	dsb	sy
	tlbi	vmalle1
	dsb	sy
	isb

	/* ---- now every store is a plain physical write ---- */
	movz	x23, #0x915A, lsl #16
	movz	w24, #0x3231		/* "12" */
	movk	w24, #0x5858, lsl #16	/* "XX" */
	str	w24, [x23, #0]
	str	w19, [x23, #4]		/* SCTLR_EL1 as inherited */
	str	w20, [x23, #8]		/* CurrentEL as inherited */
	str	w21, [x23, #12]		/* DTB pointer (low word) */
	dsb	sy

	/* PSCI SYSTEM_RESET: SMC first, HVC fallback, else spin */
	mov	w0, #0x0009
	movk	w0, #0x8400, lsl #16
	smc	#0

	mov	w0, #0x0009
	movk	w0, #0x8400, lsl #16
	hvc	#0

1:	wfi
	b	1b
