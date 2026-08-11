#!/usr/bin/env python3
"""The game-over fill animation: does it finish, how long does it take, and
what does it leave alone.

relleno_pozo paces itself with HALT, so it runs through Unit.call_free rather
than Unit.call -- see the note there on why `run N` cannot host a HALT.

The timing assertion is the point of this suite. Post-game there is no frame
budget to blow: the game loop has already ended, so nothing competes for the
frame. What is left is a duration the player has to sit through on every single
loss, so the check is a ceiling on that, measured in real 50 Hz frames.
"""
from unit import Unit

u = Unit()
L = u.L
fails = []

WALL = 0x37                 # the well border and floor
COLORES = {n * 8 for n in range(1, 8)}   # the seven tetromino PAPER values

# relleno.asm: 22 rows x 3 frames + a 25-frame hold = 91 frames, ~1.8 s.
ESPERADO = 22 * 3 + 25
TECHO = 150                 # 3 s. Nobody should sit through more than this.


def check(name, got, want):
    ok = got == want
    print(f"  {'ok  ' if ok else 'FAIL'} {name}: got {got}, want {want}")
    if not ok:
        fails.append(name)


def check_range(name, got, lo, hi):
    ok = lo <= got <= hi
    print(f"  {'ok  ' if ok else 'FAIL'} {name}: got {got}, want {lo}..{hi}")
    if not ok:
        fails.append(name)


def draw_board():
    """The well as dibujar_tablero leaves it, poked straight in: borders at
    columns 6 and 25 for rows 0-21, floor along row 22."""
    a = bytearray(768)
    for r in range(22):
        a[r * 32 + 6] = WALL
        a[r * 32 + 25] = WALL
    for c in range(6, 26):
        a[22 * 32 + c] = WALL
    # a handful of settled blocks, so the fill has something to paint over
    for c in (7, 8, 12, 20, 24):
        a[21 * 32 + c] = 4 * 8
    u.z.cmd("write-memory-raw 5800H " + a.hex())


def attrs():
    return u.peek(0x5800, 768)


def interior(a):
    return [a[r * 32 + c] for r in range(22) for c in range(7, 25)]


# Every mutable byte in the program, plus eight of margin either side.
VAR_LO = L["PUNTOS"] - 8
VAR_HI = L["Medio"] + 9

u.poke(L["PUNTOS"], [0x34, 0x12, 0x00])      # 001234
u.poke(L["MEJOR"], [0x00, 0x45, 0x00])       # 004500
u.poke(L["LINEAS"], [37])
u.poke(L["NIVEL"], [3])
before = u.peek(VAR_LO, VAR_HI - VAR_LO)

draw_board()
print("relleno_pozo -- one run, from a real board")
frames, regs = u.call_free("relleno_pozo", timeout=8.0,
                           regs={"BC": 0x0A0F, "DE": 0x1234,
                                 "HL": 0x5678, "IX": L["T_L1"]})
a = attrs()

check("it returns instead of hanging", regs["_returned"], True)
check_range("it finishes inside the 3 s ceiling", frames, 1, TECHO)
check_range("and takes about the designed 91 frames", frames,
            ESPERADO - 6, ESPERADO + 6)

print("\nwhat it paints")
check("every interior cell is filled", sum(1 for v in interior(a) if not v), 0)
check("only tetromino colours are used",
      sorted(set(interior(a)) - COLORES), [])

print("\nwhat it must not touch")
check("left border intact",
      sum(1 for r in range(22) if a[r * 32 + 6] != WALL), 0)
check("right border intact",
      sum(1 for r in range(22) if a[r * 32 + 25] != WALL), 0)
check("floor intact",
      sum(1 for c in range(6, 26) if a[22 * 32 + c] != WALL), 0)
check("nothing painted left of the well",
      sum(1 for r in range(24) for c in range(6) if a[r * 32 + c]), 0)
check("nothing painted right of the well",
      sum(1 for r in range(24) for c in range(26, 32) if a[r * 32 + c]), 0)
check("row 23 stays clear",
      sum(1 for c in range(32) if a[23 * 32 + c]), 0)

print("\nthe numbers that are about to be displayed")
check("no variable changed",
      sum(1 for x, y in zip(u.peek(VAR_LO, VAR_HI - VAR_LO), before) if x != y),
      0)
b = u.peek(L["PUNTOS"], 3)
check("PUNTOS survives", f"{b[2]:02x}{b[1]:02x}{b[0]:02x}", "001234")
b = u.peek(L["MEJOR"], 3)
check("MEJOR survives", f"{b[2]:02x}{b[1]:02x}{b[0]:02x}", "004500")
check("LINEAS survives", u.peek(L["LINEAS"], 1)[0], 37)
check("NIVEL survives", u.peek(L["NIVEL"], 1)[0], 3)

print("\nregisters (fin_partida runs with the piece state still live)")
check("preserves BC", regs["BC"], 0x0A0F)
check("preserves DE", regs["DE"], 0x1234)
check("preserves HL", regs["HL"], 0x5678)
check("preserves IX", regs["IX"], L["T_L1"])
check("leaves IY at the system-variable base", regs["IY"], 0x5C3A)

print("\nrunning it twice must be idempotent (a restart redraws anyway)")
draw_board()
frames2, _ = u.call_free("relleno_pozo", timeout=8.0)
check_range("second run takes the same time", frames2,
            ESPERADO - 6, ESPERADO + 6)
check("second run fills the well too",
      sum(1 for v in interior(attrs()) if not v), 0)

# The animation runs on HALT, which only comes back while interrupts are
# enabled -- so a non-zero frame count is also proof the interrupt state
# survived the whole run.
check("the 50 Hz tick was alive throughout", frames2 > 0, True)

u.close()
print("\n" + ("ALL PASS" if not fails else f"FAILURES: {fails}"))
