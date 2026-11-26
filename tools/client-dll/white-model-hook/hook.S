/* Multi-path probe. GNU as, i386, PE (symbols get a leading underscore).
 *
 * Each stub replays the exact instructions displaced by its patch, then resumes. The prologue is
 * written with explicit opcode bytes wherever GNU as would otherwise pick an equivalent encoding
 * (`89 e5` for `8b ec`, `89 ce` for `8b f1`, `31 d2` for `33 d2`), so check_anchor.py can compare
 * the assembled replay to the image byte for byte. Every `jmp`/`call` is still a symbol reference.
 *
 * No C calls inside a stub: nothing here can re-enter the game or allocate.
 *
 * Probe 3 needs FOURTEEN bytes. Its `cmp [ecx+0xe0],edx` is six bytes (`39 91 e0 00 00 00`), so a
 * nine-byte window would resume inside that instruction and crash on the first hit.
 *
 *   probe0  0x5975e0  record -> display    9 bytes   resume +9
 *   probe1  0x597700  display build        9 bytes   resume +9
 *   probe2  0x5977e0  SetCreature (GUID)   9 bytes   resume +9
 *   probe3  0x597840  set display id      14 bytes   resume +14
 *   probe4  0x84f280  model setter         9 bytes   resume +9
 */

    .text

/* ---- 0x5975e0 (9): 55 8b ec 51 53 8b 5d 08 57 */
    .globl _probe0
_probe0:
    lock incl _g_count0
    .byte 0x55, 0x8b, 0xec, 0x51, 0x53, 0x8b, 0x5d, 0x08, 0x57
    jmp *_g_resume0

/* ---- 0x597700 (9): 55 8b ec 51 8b 45 08 85 c0 */
    .globl _probe1
_probe1:
    lock incl _g_count1
    .byte 0x55, 0x8b, 0xec, 0x51, 0x8b, 0x45, 0x08, 0x85, 0xc0
    jmp *_g_resume1

/* ---- 0x5977e0 (9): 55 8b ec 8b 45 08 56 8b f1 */
    .globl _probe2
_probe2:
    lock incl _g_count2
    .byte 0x55, 0x8b, 0xec, 0x8b, 0x45, 0x08, 0x56, 0x8b, 0xf1
    jmp *_g_resume2

/* ---- 0x597840 (14): 55 8b ec 8b 45 08 33 d2 39 91 e0 00 00 00 */
    .globl _probe3
_probe3:
    lock incl _g_count3
    .byte 0x55, 0x8b, 0xec, 0x8b, 0x45, 0x08, 0x33, 0xd2
    .byte 0x39, 0x91, 0xe0, 0x00, 0x00, 0x00
    jmp *_g_resume3

/* ---- 0x84f280 (9): 55 8b ec 56 8b 75 08 6a 01 */
    .globl _probe4
_probe4:
    lock incl _g_count4
    .byte 0x55, 0x8b, 0xec, 0x56, 0x8b, 0x75, 0x08, 0x6a, 0x01
    jmp *_g_resume4
