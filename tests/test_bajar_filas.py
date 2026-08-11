#!/usr/bin/env python3
"""Guard bajar_filas' row-copy count against the CRtoATTR A-clobber regression.

bajar_filas puts its copy count in A, then calls CRtoATTR to turn (B,7) into an
attribute address. CRtoATTR ends in `LD A,L` (L30.3 - printat.asm), so without a
push/pop around the call the count becomes the LOW BYTE OF THE ADDRESS: for row
21 that is $5AA7 & $FF = 167 copies instead of 21.

The board still ended up correct -- bf_cero rewrites row 0 afterwards -- so no
board-state assertion in test_lineas.py could see it. What the extra 146 passes
did was walk HL/DE 50 bytes lower each time, straight down through the pixel
display file, corrupting 230 bytes of the 3D background per line cleared and
costing 119,000 T-states on the clearing frame instead of 38,000.

So this suite asserts the two things a board comparison cannot:
  * the loop runs EXACTLY B times, counted opcode by opcode, for every row, and
  * a real clear leaves the pixel display file byte-for-byte untouched.
"""
from unit import Unit

ATTR = 0x5800
PIXELS, PIXELS_LEN = 0x4000, 6144
WALL = 0x37
COL_L, COL_R = 7, 24

u = Unit()
fails = []


def check(name, got, want):
    ok = got == want
    print(f"  {'ok  ' if ok else 'FAIL'} {name}")
    if not ok:
        print(f"       got  {got}\n       want {want}")
        fails.append(name)


def blank_board():
    b = bytearray(768)
    for r in range(22):
        b[r * 32 + 6] = WALL
        b[r * 32 + 25] = WALL
    for c in range(6, 26):
        b[22 * 32 + c] = WALL
    return b


def fill(b, row, colour, holes=()):
    for c in range(COL_L, COL_R + 1):
        b[row * 32 + c] = 0 if c in holes else colour


def put_board(b):
    for off in range(0, 768, 64):
        u.poke(ATTR + off, b[off:off + 64])


def paint_pixels():
    """A distinctive pattern, so any stray copy shows up as a difference.

    Zeroed memory would hide the bug: the runaway loop copies whatever it finds,
    and copying zeros over zeros is invisible.
    """
    pat = bytes(((a * 37 + (a >> 5) * 11) & 0xFF) or 0xA5
                for a in range(PIXELS_LEN))
    for off in range(0, PIXELS_LEN, 128):
        u.poke(PIXELS + off, pat[off:off + 128])
    return pat


def copy_iterations(row, cap=20000):
    """Call bajar_filas for `row` and count bf_copiar iterations exactly.

    Steps one opcode at a time and tallies arrivals at the top of the copy
    loop. This is the assertion the bug needed: the board came out right either
    way, so only the iteration count itself distinguishes 21 from 167.
    """
    top = u.L["bf_copiar"]
    u.z.cmd(f"write-memory-raw FF00H {u.TRAP & 0xFF:02X}{u.TRAP >> 8:02X}")
    u.z.cmd("set-register SP=FF00H")
    u.z.cmd(f"set-register BC={row << 8:04X}H")
    u.z.cmd(f"set-register PC={u.L['bajar_filas']:04X}H")
    hits = 0
    for _ in range(cap):
        u.z.cmd("run 1")
        pc = u.regs().get("PC")
        if pc == top:
            hits += 1
        if pc in (u.TRAP, u.PARKED):
            return hits
    raise AssertionError(f"bajar_filas(row={row}) did not return in {cap} steps")


print("bajar_filas: the copy loop runs exactly B times")
# Row 21 is the case the bug actually hit in play, and the one whose wrong
# answer (167) is furthest from the right one (21).
check("row 21 -> 21 copies", copy_iterations(21), 21)
check("row 20 -> 20 copies", copy_iterations(20), 20)
check("row 1  -> 1 copy", copy_iterations(1), 1)
check("row 0  -> 0 copies (nothing above it)", copy_iterations(0), 0)

# Every row, so no single value can be special-cased into passing.
bad = [r for r in range(0, 22) if copy_iterations(r) != r]
check("rows 0-21 all copy exactly B rows", bad, [])

print("\nbajar_filas: the documented AF contract still holds")
# Contract check, NOT a guard on the bug: the entry `push af` / exit `pop af`
# preserve the caller's AF whether or not the inner count survives, so this
# passes against the broken build too. The iteration counts above are the only
# assertions that actually discriminate 21 from 167 -- which is the whole reason
# this file exists rather than another board comparison in test_lineas.py.
r = u.call("bajar_filas", regs={"BC": 21 << 8, "AF": 0x1500})
check("preserves AF for the caller", r["AF"] >> 8, 0x15)

print("\na real line clear leaves the pixel display file alone")
pat = paint_pixels()
b = blank_board()
fill(b, 21, 0x10)
b[20 * 32 + 9] = 0x28
put_board(b)
u.call("limpiar_lineas", limit=400000)
after = u.peek(PIXELS, PIXELS_LEN)
diff = [i for i, (x, y) in enumerate(zip(pat, after)) if x != y]
check("single clear corrupts 0 pixel bytes", len(diff), 0)

pat = paint_pixels()
b = blank_board()
for row in (18, 19, 20, 21):
    fill(b, row, 0x38)
b[17 * 32 + 20] = 0x08
put_board(b)
u.call("limpiar_lineas", limit=400000)
after = u.peek(PIXELS, PIXELS_LEN)
diff = [i for i, (x, y) in enumerate(zip(pat, after)) if x != y]
check("four-row clear corrupts 0 pixel bytes", len(diff), 0)

print("\nthe shift is still correct (the bug did not break this, keep it that way)")
b = blank_board()
fill(b, 21, 0x10)
b[20 * 32 + 9] = 0x28
put_board(b)
u.call("limpiar_lineas", limit=400000)
out = u.peek(ATTR, 768)
check("marker fell from row 20 to row 21", out[21 * 32 + 9], 0x28)
check("row 0 blanked", list(out[COL_L:COL_R + 1]), [0] * 18)

u.close()
print("\n" + ("ALL PASS" if not fails else f"FAILURES: {fails}"))
