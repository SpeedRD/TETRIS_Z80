#!/usr/bin/env python3
"""Exercise en_rango and leer_teclas on real hardware emulation."""
from unit import Unit

u = Unit()
L = u.L
fails = []


def check(name, got, want):
    ok = got == want
    print(f"  {'ok  ' if ok else 'FAIL'} {name}: got {got}, want {want}")
    if not ok:
        fails.append(name)


# ---------------------------------------------------------------- en_rango
# (ix+1) is the piece width. Point IX at real records so widths are genuine.
print("en_rango  (A=0 fits, A=1 outside; interior is columns 7..24)")
CASES = [
    # (record, width, column, expected)
    ("T_0",  2,  7, 0),   # flush left, 2 wide -> cells 7,8
    ("T_0",  2,  6, 1),   # on the left border
    ("T_0",  2,  5, 1),   # beyond the left border
    ("T_0",  2, 23, 0),   # cells 23,24 -> last legal
    ("T_0",  2, 24, 1),   # cells 24,25 -> 25 is the right border
    ("T_I2", 4,  7, 0),   # 4-wide bar flush left
    ("T_I2", 4, 21, 0),   # cells 21..24 -> last legal for a 4-wide
    ("T_I2", 4, 22, 1),   # cells 22..25 -> hits the border
    ("T_I1", 1, 24, 0),   # 1-wide flush right
    ("T_I1", 1, 25, 1),   # 1-wide on the border
    ("T_L1", 2, 15, 0),   # mid-well
    ("T_0",  2,  0, 1),   # column 0
    ("T_0",  2, 31, 1),   # far right of the screen
]
for rec, w, col, want in CASES:
    r = u.call("en_rango", regs={"IX": L[rec], "BC": col})  # C = low byte of BC
    assert r["_returned"], f"{rec}@{col} did not return"
    check(f"{rec} (w={w}) at column {col:2d}", r["AF"] >> 8, want)

# en_rango must not disturb the piece position or pointer
r = u.call("en_rango", regs={"IX": L["T_L1"], "BC": 0x0A0F, "DE": 0x1234, "HL": 0x5678})
check("preserves BC", r["BC"], 0x0A0F)
check("preserves DE", r["DE"], 0x1234)
check("preserves HL", r["HL"], 0x5678)
check("preserves IX", r["IX"], L["T_L1"])

# -------------------------------------------------------------- leer_teclas
# bit0=K right, bit1=J left, bit2=Q rot-left, bit3=W rot-right
print("\nleer_teclas  (edge detected: reports only up->down transitions)")
TA = L["teclas_ant"]

def press(keys):
    return u.call("leer_teclas", keys=keys)["AF"] >> 8

u.poke(TA, [0])
check("nothing held -> 0", press([]), 0)
check("K first read -> bit0", press(["K"]), 0b0001)
check("K still held -> 0 (no repeat)", press(["K"]), 0)
check("K released -> 0", press([]), 0)
check("K pressed again -> bit0", press(["K"]), 0b0001)
u.poke(TA, [0])
check("J -> bit1", press(["J"]), 0b0010)
u.poke(TA, [0])
check("Q -> bit2", press(["Q"]), 0b0100)
u.poke(TA, [0])
check("W -> bit3", press(["W"]), 0b1000)
u.poke(TA, [0])
check("J+W together -> bits1,3", press(["J", "W"]), 0b1010)
u.poke(TA, [0])
check("all four -> bits0-3", press(["K", "J", "Q", "W"]), 0b1111)
u.poke(TA, [0])
# keys on the same half-rows that the game must ignore
check("H,L,ENTER,E,R,T ignored", press(["H", "L", "ENTER", "E", "R", "T"]), 0)
u.poke(TA, [0])
check("K held, then J added -> only bit1 is new", (press(["K"]), press(["K", "J"]))[1], 0b0010)

# ---------------------------------------------- leer_teclas: SPACE (bit4)
# SPACE is LEVEL triggered (soft drop), unlike K/J/Q/W: it must read 1 on
# EVERY call while held, not just the first, and drop to 0 the instant it is
# released -- gravity in juego.asm relies on this to speed up while held and
# return to normal immediately on release.
print("\nleer_teclas  (SPACE / bit4: level state, not edge -- soft drop)")
u.poke(TA, [0])
check("SPACE first read -> bit4", press(["SPACE"]), 0b10000)
check("SPACE still held -> bit4 AGAIN (no repeat suppression)", press(["SPACE"]), 0b10000)
check("SPACE still held -> bit4 a third time", press(["SPACE"]), 0b10000)
check("SPACE released -> 0 immediately", press([]), 0)
check("SPACE pressed again -> bit4", press(["SPACE"]), 0b10000)
u.poke(TA, [0])
# SPACE must not disturb, or be disturbed by, the edge-triggered bits
check("K+SPACE together -> bit0 (new) and bit4 (held)", press(["K", "SPACE"]), 0b10001)
check("K held, SPACE held -> only bit4 (K is not new any more)",
      press(["K", "SPACE"]), 0b10000)
check("K released, SPACE still held -> only bit4", press(["SPACE"]), 0b10000)
check("K pressed again while SPACE held -> bit0 and bit4", press(["K", "SPACE"]), 0b10001)
u.poke(TA, [0])
check("Q+SPACE together -> bit2 (new) and bit4 (held)", press(["Q", "SPACE"]), 0b10100)
u.poke(TA, [0])
check("all four plus SPACE -> bits0-4", press(["K", "J", "Q", "W", "SPACE"]), 0b11111)

# register preservation
u.poke(TA, [0])
r = u.call("leer_teclas", keys=[], regs={"BC": 0x0A0F, "DE": 0x1234, "HL": 0x5678, "IX": L["T_L1"]})
check("preserves BC", r["BC"], 0x0A0F)
check("preserves DE", r["DE"], 0x1234)
check("preserves HL", r["HL"], 0x5678)
check("preserves IX", r["IX"], L["T_L1"])

u.z.cmd("set-ui-io-ports " + "1f" * 8 + "00")
u.close()
print("\n" + ("ALL PASS" if not fails else f"FAILURES: {fails}"))
