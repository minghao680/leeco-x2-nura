/*
 * lk2nd handoff probe ("black box recorder") for LeEco Le Max 2 (x2).
 *
 * Problem: the mainline kernel dies within ~3-5s when booted via lk2nd,
 * before ramoops/pstore init, so we can never see what lk2nd actually
 * handed to it (memory map, cmdline, patched DTB).
 *
 * This tiny bare-metal arm64 payload is booted by lk2nd EXACTLY like a
 * real kernel (same decompress/DTB-select/patch/jump path). At entry the
 * boot protocol gives us x0 = physical address of the DTB that lk2nd
 * prepared. We dump x0 + the first 4 KiB of whatever x0 points at into
 * the stock 3.18 kernel's pstore console-ramoops buffer (which survives
 * a warm reset), then reset via PSCI. Back on Android:
 *     /sys/fs/pstore/console-ramoops
 * contains our record, parseable offline.
 *
 * Layout requirements (verified against the vendor 3.18 sources in
 * android_kernel_leeco_msm8996/fs/pstore/{ram.c,ram_core.c}):
 *   - ramoops region 0x91500000..0x91600000, allocation order:
 *       dmesg record przs : 0x91500000, 10 x 0x10000 = 0xA0000
 *       console      prz  : 0x915A0000, 0x40000
 *       ftrace            : 0 size
 *       pmsg         prz  : 0x915E0000, 0x20000
 *   - struct persistent_ram_buffer { u32 sig; u32 start; u32 size; u8 data[]; }
 *   - console zone sig param is 0, stored sig = 0 ^ 0x43474244 = 0x43474244
 *   - ecc = 0 (module param), so data starts right after the 12-byte header
 *
 * Image header: lk2nd's IS_ARM64() requires the "ARM\x64" magic at offset
 * 0x38, and it applies  (kernel_addr & ~0x1fffff) + text_offset  before
 * loading, so we present a minimal arm64 Image header with text_offset 0.
 * Entry is at image start (the branch below).
 */

.text
.globl _start
_start:
	b	code

	/* --- minimal arm64 Image header (64 bytes) --- */
	.balign	8
	.quad	0			/* 0x08 text_offset */
	.quad	0x100000		/* 0x10 image_size (nonzero) */
	.quad	0			/* 0x18 flags */
	.quad	0			/* 0x20 */
	.quad	0			/* 0x28 res2 */
	.quad	0			/* 0x30 res3 */
	.ascii	"ARM\x64"		/* 0x38 magic */
	.balign	8
code:
	/* x0 = DTB pointer from lk2nd */
	mov	x19, x0

	/* console buffer @ 0x915A0000 */
	movz	x20, #0x915A, lsl #16

	/* sig = 0x43474244 */
	mov	w21, #0x4244
	movk	w21, #0x4347, lsl #16
	str	w21, [x20]
	str	wzr, [x20, #4]		/* start = 0 */
	mov	w21, #(12 + 8 + 8 + 8 + 4096)
	str	w21, [x20, #8]		/* size = 4132 */

	/* data[0..7]  = "LKPROBE1" */
	mov	x21, #0x4B4C		/* "LK"   */
	movk	x21, #0x5250, lsl #16	/* "PR"   */
	movk	x21, #0x454F, lsl #32	/* "OE"   */
	movk	x21, #0x3131, lsl #48	/* "11"   */
	str	x21, [x20, #12]

	/* data[8..15] = x0 (DTB pointer) */
	str	x19, [x20, #20]

	/* data[16..23] = CurrentEL (diag: where did lk2nd drop us?) */
	mrs	x21, CurrentEL
	str	x21, [x20, #28]

	/* data[24..31] = SCTLR (diag: MMU state at entry) */
	mrs	x21, sctlr_el1
	str	x21, [x20, #36]

	/* data[32..4155] = first 4096 bytes at [x0] */
	add	x22, x20, #44
	mov	x23, #4096
1:	ldr	x24, [x19], #8
	str	x24, [x22], #8
	subs	x23, x23, #8
	b.ne	1b

	/* clean dcache over the written window, then barrier */
	mov	x23, #0x2000
	add	x24, x20, #0
2:	dc	cvac, x24
	add	x24, x24, #64
	subs	x23, x23, #64
	b.gt	2b
	dsb	sy
	isb

	/* PSCI SYSTEM_RESET (0x84000009): SMC first, HVC fallback, else spin */
	mov	w0, #0x0009
	movk	w0, #0x8400, lsl #16
	smc	#0

	mov	w0, #0x0009
	movk	w0, #0x8400, lsl #16
	hvc	#0

3:	wfi
	b	3b
