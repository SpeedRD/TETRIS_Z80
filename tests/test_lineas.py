#!/usr/bin/env python3
"""Exercise limpiar_lineas / fila_llena / bajar_filas against built board states."""
from unit import Unit

ATTR = 0x5800
WALL = 0x37          # 6*8+7, the border attribute
COL_L, COL_R = 7, 24
u = Unit()
fails = []


def blank_board():
    """Well as dibujar_tablero draws it: walls col 6 and 25 rows 0-21, floor row 22."""
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


def put(b):
    for off in range(0, 768, 64):
        u.poke(ATTR + off, b[off:off + 64])


def get():
    return u.peek(ATTR, 768)


def row_of(b, r):
    return list(b[r * 32 + COL_L: r * 32 + COL_R + 1])


def check(name, got, want):
    ok = got == want
    print(f"  {'ok  ' if ok else 'FAIL'} {name}")
    if not ok:
        print(f"       got  {got}\n       want {want}")
        fails.append(name)


def borders_intact(b):
    for r in range(22):
        if b[r * 32 + 6] != WALL or b[r * 32 + 25] != WALL:
            return False
    return all(b[22 * 32 + c] == WALL for c in range(6, 26))


print("fila_llena  (A=1 when all 18 interior cells are non-zero)")
b = blank_board(); fill(b, 21, 0x10); put(b)
check("row 21 full -> 1", u.call("fila_llena", regs={"BC": 21 << 8})["AF"] >> 8, 1)
b = blank_board(); fill(b, 21, 0x10, holes=(15,)); put(b)
check("row 21 with one hole -> 0", u.call("fila_llena", regs={"BC": 21 << 8})["AF"] >> 8, 0)
b = blank_board(); put(b)
check("empty row -> 0 (walls alone must not count)",
      u.call("fila_llena", regs={"BC": 21 << 8})["AF"] >> 8, 0)
b = blank_board(); fill(b, 21, 0x10, holes=(7,)); put(b)
check("hole at the left edge -> 0", u.call("fila_llena", regs={"BC": 21 << 8})["AF"] >> 8, 0)
b = blank_board(); fill(b, 21, 0x10, holes=(24,)); put(b)
check("hole at the right edge -> 0", u.call("fila_llena", regs={"BC": 21 << 8})["AF"] >> 8, 0)

print("\nlimpiar_lineas  (returns the number of rows cleared)")

# --- single clear at the bottom, with a marker row above it
b = blank_board()
fill(b, 21, 0x10)                     # full
b[20 * 32 + 9] = 0x28                 # lone marker cell above
put(b)
r = u.call("limpiar_lineas", limit=400000)
out = get()
check("one full row -> A=1", r["AF"] >> 8, 1)
check("marker fell from row 20 to row 21", out[21 * 32 + 9], 0x28)
check("row 20 is now empty", row_of(out, 20), [0] * 18)
check("borders intact", borders_intact(out), True)

# --- two adjacent full rows
b = blank_board()
fill(b, 20, 0x10); fill(b, 21, 0x20)
b[19 * 32 + 11] = 0x28
put(b)
r = u.call("limpiar_lineas", limit=400000)
out = get()
check("two full rows -> A=2", r["AF"] >> 8, 2)
check("marker fell from 19 to 21", out[21 * 32 + 11], 0x28)
check("rows 19 and 20 empty", row_of(out, 19) + row_of(out, 20), [0] * 36)

# --- a tetris: four full rows at once
b = blank_board()
for row in (18, 19, 20, 21):
    fill(b, row, 0x38)
b[17 * 32 + 20] = 0x08
put(b)
r = u.call("limpiar_lineas", limit=400000)
out = get()
check("four full rows -> A=4", r["AF"] >> 8, 4)
check("marker fell from 17 to 21", out[21 * 32 + 20], 0x08)

# --- non-adjacent full rows (the re-test must not skip one)
b = blank_board()
fill(b, 21, 0x10)
fill(b, 19, 0x20)
b[20 * 32 + 8] = 0x28                 # a single cell between the two full rows
put(b)
r = u.call("limpiar_lineas", limit=400000)
out = get()
check("two separated full rows -> A=2", r["AF"] >> 8, 2)
check("the cell between them survived, now at row 21", out[21 * 32 + 8], 0x28)

# --- nothing to clear
b = blank_board(); fill(b, 21, 0x10, holes=(15,)); put(b)
r = u.call("limpiar_lineas", limit=400000)
out = get()
check("no full row -> A=0", r["AF"] >> 8, 0)
check("board untouched", row_of(out, 21), row_of(b, 21))

# --- a full row at the very top
b = blank_board(); fill(b, 0, 0x10); put(b)
r = u.call("limpiar_lineas", limit=400000)
out = get()
check("full row 0 -> A=1", r["AF"] >> 8, 1)
check("row 0 blanked", row_of(out, 0), [0] * 18)

# --- full stack: every interior row full
b = blank_board()
for row in range(22):
    fill(b, row, 0x10)
put(b)
r = u.call("limpiar_lineas", limit=1500000)
out = get()
check("all 22 rows full -> A=22", r["AF"] >> 8, 22)
check("board completely empty", [x for row in range(22) for x in row_of(out, row)], [0] * (22 * 18))
check("borders still intact", borders_intact(out), True)

# --- register preservation
b = blank_board(); fill(b, 21, 0x10); put(b)
r = u.call("limpiar_lineas", limit=400000, regs={"BC": 0x0A0F, "DE": 0x1234, "HL": 0x5678, "IX": u.L["T_L1"]})
check("preserves BC", r["BC"], 0x0A0F)
check("preserves DE", r["DE"], 0x1234)
check("preserves HL", r["HL"], 0x5678)
check("preserves IX", r["IX"], u.L["T_L1"])

u.close()
print("\n" + ("ALL PASS" if not fails else f"FAILURES: {fails}"))
