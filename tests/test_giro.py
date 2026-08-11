#!/usr/bin/env python3
"""piece-rotation section 7: rotate every shape both ways, everywhere in the well."""
from unit import Unit

ATTR = 0x5800
WALL = 0x37
u = Unit()
L = u.L
fails = []
NAME = {L[n]: n for n in (
    "T_0", "T_L1", "T_L2", "T_L3", "T_L4", "T_J1", "T_J2", "T_J3", "T_J4",
    "T_T1", "T_T2", "T_T3", "T_T4", "T_I1", "T_I2", "T_Z1", "T_Z2",
    "T_S1", "T_S2")}
SHAPES = {"O": "T_0", "L": "T_L1", "J": "T_J1", "T": "T_T1",
          "I": "T_I1", "Z": "T_Z1", "S": "T_S1"}
STATES = {"O": 1, "L": 4, "J": 4, "T": 4, "I": 2, "Z": 2, "S": 2}


def check(name, got, want):
    ok = got == want
    print(f"  {'ok  ' if ok else 'FAIL'} {name}: got {got}, want {want}")
    if not ok:
        fails.append(name)


def empty_well():
    b = bytearray(768)
    for r in range(22):
        b[r * 32 + 6] = WALL
        b[r * 32 + 25] = WALL
    for c in range(6, 26):
        b[22 * 32 + c] = WALL
    for off in range(0, 768, 64):
        u.poke(ATTR + off, b[off:off + 64])


def girar(ix, row, col, direction):
    """direction 0 = left (Q), 1 = right (W). Returns (new_ix, new_col)."""
    u.poke(L["Medio"], [col])
    r = u.call("GIRAR", regs={"IX": ix, "BC": (row << 8) | col,
                              "AF": direction << 8}, limit=4000)
    return r["IX"], r["BC"] & 0xFF, (r["BC"] >> 8)


def rec(ix):
    """(rows, cols) of a piece record."""
    b = u.peek(ix, 2)
    return b[0], b[1]


empty_well()

print("rotation cycles close, and left/right are exact inverses")
for shape, start in SHAPES.items():
    ix0 = L[start]
    for direction, label in ((0, "left"), (1, "right")):
        ix, col = ix0, 15
        seen = []
        for _ in range(STATES[shape]):
            ix, col, _ = girar(ix, 10, col, direction)
            seen.append(NAME.get(ix, f"{ix:04X}"))
        check(f"{shape}: {STATES[shape]} x {label} returns to {start} at column 15",
              (NAME.get(ix), col), (start, 15))
    # one step each way must be a no-op overall
    ix, col, _ = girar(ix0, 10, 15, 0)
    ix, col, _ = girar(ix, 10, col, 1)
    check(f"{shape}: left then right is a no-op", (NAME.get(ix), col), (start, 15))

print("\nafter ANY rotation the piece is still legal (this is what stopped the")
print("well border being eaten: nothing is committed unless it fits)")
illegal = []
unchanged = 0
attempts = 0
for shape, start in SHAPES.items():
    ix_state = L[start]
    for _ in range(STATES[shape]):                 # visit every rotation state
        for col in range(5, 28):                   # including outside the well
            for direction in (0, 1):
                attempts += 1
                nix, ncol, nrow = girar(ix_state, 10, col, direction)
                rows, cols = rec(nix)
                fits = (7 <= ncol) and (ncol + cols - 1 <= 24)
                if nix == ix_state and ncol == col:
                    unchanged += 1                 # rejected outright: fine
                elif not fits:
                    illegal.append((shape, col, direction, NAME.get(nix), ncol))
        ix_state, _, _ = girar(ix_state, 10, 15, 0)
check(f"no rotation ever lands outside columns 7-24 ({attempts} attempts)",
      illegal[:5], [])
print(f"       {attempts} rotations tried, {unchanged} correctly refused")

print("\na rotation that cannot fit leaves IX, C and Medio completely untouched")
# box the piece in: fill everything except a 1-wide column so nothing can turn
empty_well()
col_libre = 15
b = bytearray(768)
for r in range(22):
    for c in range(7, 25):
        b[r * 32 + c] = 0x10 if c != col_libre else 0
    b[r * 32 + 6] = WALL
    b[r * 32 + 25] = WALL
for c in range(6, 26):
    b[22 * 32 + c] = WALL
for off in range(0, 768, 64):
    u.poke(ATTR + off, b[off:off + 64])
ix0 = L["T_I1"]                                   # 4x1 bar in a 1-wide shaft
u.poke(L["Medio"], [col_libre])
nix, ncol, _ = girar(ix0, 10, col_libre, 0)
check("blocked rotation keeps IX", NAME.get(nix), "T_I1")
check("blocked rotation keeps C", ncol, col_libre)
check("blocked rotation keeps Medio", u.peek(L["Medio"], 1)[0], col_libre)

print("\nGIRAR never writes to the screen (drawing is the caller's job)")
empty_well()
before = u.peek(ATTR, 768)
for shape, start in SHAPES.items():
    girar(L[start], 10, 15, 0)
    girar(L[start], 10, 15, 1)
check("attribute file untouched by GIRAR", u.peek(ATTR, 768) == before, True)

u.close()
print("\n" + ("ALL PASS" if not fails else f"FAILURES: {fails}"))
