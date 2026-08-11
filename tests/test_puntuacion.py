#!/usr/bin/env python3
"""Exercise the scoring / level arithmetic."""
from unit import Unit

u = Unit()
L = u.L
fails = []


def check(name, got, want):
    ok = got == want
    print(f"  {'ok  ' if ok else 'FAIL'} {name}: got {got}, want {want}")
    if not ok:
        fails.append(name)


def score():
    """PUNTOS is 3 packed-BCD bytes, least significant first."""
    b = u.peek(L["PUNTOS"], 3)
    return f"{b[2]:02x}{b[1]:02x}{b[0]:02x}"


def var(n):
    return u.peek(L[n], 1)[0]


def reset():
    u.call("reiniciar_marcador", limit=40000)


print("anotar_lineas -- points per simultaneous clear (1/2/3/4 -> 100/300/500/800)")
for rows, want in ((1, "000100"), (2, "000300"), (3, "000500"), (4, "000800")):
    reset()
    u.call("anotar_lineas", limit=25000, regs={"AF": rows << 8})
    check(f"{rows} row(s)", score(), want)

reset()
u.call("anotar_lineas", limit=25000, regs={"AF": 0 << 8})
check("0 rows scores nothing", score(), "000000")
check("0 rows counts no line", var("LINEAS"), 0)

print("\nBCD accumulation across digit boundaries")
reset()
for _ in range(10):
    u.call("anotar_lineas", limit=25000, regs={"AF": 4 << 8})
check("10 x 800 = 8000", score(), "008000")
reset()
for _ in range(13):
    u.call("anotar_lineas", limit=25000, regs={"AF": 1 << 8})
check("13 x 100 = 1300", score(), "001300")

# force a carry out of the middle byte
reset()
u.poke(L["PUNTOS"], [0x99, 0x99, 0x00])          # 009999
u.call("anotar_lineas", limit=25000, regs={"AF": 1 << 8})
check("009999 + 100 = 010099", score(), "010099")

print("\nline counter and level")
reset()
u.call("anotar_lineas", limit=25000, regs={"AF": 3 << 8})
check("LINEAS after a triple", var("LINEAS"), 3)
check("PROX_NIVEL counts down 10->7", var("PROX_NIVEL"), 7)
check("still level 0", var("NIVEL"), 0)
check("speed still 48", var("FRAMES_POR_FILA"), 48)

reset()
for _ in range(5):
    u.call("anotar_lineas", limit=25000, regs={"AF": 2 << 8})   # 10 lines
check("10 lines -> LINEAS=10", var("LINEAS"), 10)
check("10 lines -> level 1", var("NIVEL"), 1)
check("PROX_NIVEL reloaded to 10", var("PROX_NIVEL"), 10)
check("speed table applied (level 1 = 40)", var("FRAMES_POR_FILA"), 40)

# a 4-row clear that straddles a level boundary must still land correctly
reset()
u.call("anotar_lineas", limit=25000, regs={"AF": 4 << 8})
u.call("anotar_lineas", limit=25000, regs={"AF": 4 << 8})
u.call("anotar_lineas", limit=25000, regs={"AF": 4 << 8})       # 12 lines
check("12 lines -> level 1", var("NIVEL"), 1)
check("12 lines -> PROX_NIVEL=8", var("PROX_NIVEL"), 8)
check("LINEAS=12", var("LINEAS"), 12)

print("\nlevel cap and speed table")
reset()
for _ in range(60):                                 # 120 lines -> level 12 raw
    u.call("anotar_lineas", limit=25000, regs={"AF": 2 << 8})
check("level caps at 10", var("NIVEL"), 10)
check("speed floors at 6 frames", var("FRAMES_POR_FILA"), 6)

# every table entry reachable and non-zero
reset()
speeds = []
for lvl in range(11):
    u.poke(L["NIVEL"], [lvl])
    u.call("ActualizarVelocidad", limit=2000)
    speeds.append(var("FRAMES_POR_FILA"))
check("speed table by level", speeds, [48, 40, 33, 27, 22, 18, 15, 12, 10, 8, 6])
u.poke(L["NIVEL"], [200])                           # out of range must clamp
u.call("ActualizarVelocidad", limit=2000)
check("out-of-range level clamps to the last entry", var("FRAMES_POR_FILA"), 6)

print("\nregister preservation (anotar_lineas runs while a piece is live)")
reset()
r = u.call("anotar_lineas", limit=25000, regs={"AF": 2 << 8, "BC": 0x0A0F,
                                  "DE": 0x1234, "HL": 0x5678, "IX": L["T_L1"]})
check("preserves BC", r["BC"], 0x0A0F)
check("preserves DE", r["DE"], 0x1234)
check("preserves HL", r["HL"], 0x5678)
check("preserves IX", r["IX"], L["T_L1"])

u.close()
print("\n" + ("ALL PASS" if not fails else f"FAILURES: {fails}"))
