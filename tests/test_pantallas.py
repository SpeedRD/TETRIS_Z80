#!/usr/bin/env python3
"""The three redesigned screens: their frames, their text, and what they must
not touch.

Two things make these checkable without a human at the keyboard:

  * the panels are drawn with attribute cells only, so the attribute file at
    $5800 carries the whole frame -- no glyphs are involved in a border;
  * the drawing is split from the keyboard wait (pintar_ini / pintar_final /
    pintar_gracias just paint and return), so a screen can be rendered by a
    plain call instead of by pressing keys at it.

Text is read back out of the PIXEL file and matched against charset.bin. That
is deliberately the hard way round: it is the only check that proves the
best-score digits actually reach the screen, rather than merely being computed.
"""
import os

from tetris import REPO
from unit import Unit

u = Unit()
L = u.L
fails = []

MARCO = 6 * 8 + 7           # 55: the frame byte, the same one the well uses
CURSOR = 6 + 0x80           # flashing yellow: the cell that follows a prompt
ROTULO = 6                  # yellow ink, as the scoreboard labels
TEXTO = 7                   # white ink, as the scoreboard values
ALTO = 5                    # marco / hueco / texto / hueco / marco

CHARSET = open(os.path.join(REPO, "charset.bin"), "rb").read()

# The whole variables.asm block plus eight bytes of margin either side. Any
# screen that scribbles outside the screen files shows up here.
VAR_LO = L["PUNTOS"] - 8
VAR_HI = L["Medio"] + 9


def check(name, got, want):
    ok = got == want
    print(f"  {'ok  ' if ok else 'FAIL'} {name}: got {got}, want {want}")
    if not ok:
        fails.append(name)


def zero_attrs():
    u.z.cmd("write-memory-raw 5800H " + "00" * 768)


def render(routine):
    """Run one screen-drawing routine; return (attributes, pixels)."""
    u.call(routine, limit=200000)
    return u.peek(0x5800, 768), u.peek(0x4000, 6144)


def frame_cells(*tops):
    """The cells pintar_marco paints for panels with these top rows."""
    out = set()
    for top in tops:
        for c in range(32):
            out.add((top, c))
            out.add((top + ALTO - 1, c))
        for r in range(top + 1, top + ALTO - 1):
            out.add((r, 0))
            out.add((r, 31))
    return out


def cells_equal(a, value):
    return {(i // 32, i % 32) for i, v in enumerate(a) if v == value}


def lit_rows(a):
    return sorted({i // 32 for i, v in enumerate(a) if v})


def glyph(pix, row, col):
    base = ((row & 0x18) << 8) | ((row & 7) << 5) | col
    return bytes(pix[base + 0x100 * line] for line in range(8))


def text_at(pix, row, col, s):
    """Read the string back off the screen, one glyph at a time."""
    out = ""
    for i, ch in enumerate(s):
        want = CHARSET[(ord(ch) - 32) * 8:(ord(ch) - 32) * 8 + 8]
        out += ch if glyph(pix, row, col + i) == want else "?"
    return out


def variables():
    return u.peek(VAR_LO, VAR_HI - VAR_LO)


def set_bcd(label, digits):
    """digits is a 6-character decimal string, e.g. '012345'."""
    u.poke(L[label], [int(digits[4:6], 16), int(digits[2:4], 16),
                      int(digits[0:2], 16)])


def get_bcd(label):
    b = u.peek(L[label], 3)
    return f"{b[2]:02x}{b[1]:02x}{b[0]:02x}"


print("pintar_marco -- the frame, and nothing but the frame")
for top in (0, 1, 9, 19):
    zero_attrs()
    u.call("pintar_marco", limit=8000, regs={"BC": top << 8})
    a = u.peek(0x5800, 768)
    check(f"panel at row {top}: frame cells", cells_equal(a, MARCO),
          frame_cells(top))
    check(f"panel at row {top}: nothing else drawn",
          sum(1 for v in a if v), len(frame_cells(top)))

zero_attrs()
r = u.call("pintar_marco", limit=8000,
           regs={"BC": 0x0A0F, "DE": 0x1234, "HL": 0x5678, "IX": L["T_L1"]})
check("preserves BC", r["BC"], 0x0A0F)
check("preserves DE", r["DE"], 0x1234)
check("preserves HL", r["HL"], 0x5678)
check("preserves IX", r["IX"], L["T_L1"])

print("\npintar_ini -- tipo de juego / mejor puntuacion / prompt")
set_bcd("MEJOR", "012345")
before = variables()
a, pix = render("pintar_ini")
check("three panels at rows 1, 8, 15", cells_equal(a, MARCO),
      frame_cells(1, 8, 15))
check("nothing drawn outside the panel rows", lit_rows(a),
      [1, 2, 3, 4, 5, 8, 9, 10, 11, 12, 15, 16, 17, 18, 19])
check("title text unchanged", text_at(pix, 3, 5, "Tipo de Juego: Tipo-A"),
      "Tipo de Juego: Tipo-A")
check("title is yellow, as the scoreboard labels", a[3 * 32 + 5], ROTULO)
check("best-score label", text_at(pix, 10, 4, "MEJOR PUNTUACION"),
      "MEJOR PUNTUACION")
check("best-score value renders", text_at(pix, 10, 22, "012345"), "012345")
check("best-score value is white, as the scoreboard values",
      a[10 * 32 + 22], TEXTO)
check("prompt text unchanged",
      text_at(pix, 17, 1, "Empezamos una partida (S/N)?"),
      "Empezamos una partida (S/N)?")
check("flashing cursor cell after the prompt", a[17 * 32 + 30], CURSOR)
check("variables untouched by the render", variables(), before)
check("MEJOR is read, never written", get_bcd("MEJOR"), "012345")

print("\npintar_final -- juego terminado / mejor puntuacion / prompt")
set_bcd("MEJOR", "099980")
before = variables()
a, pix = render("pintar_final")
check("three panels at rows 3, 10, 17", cells_equal(a, MARCO),
      frame_cells(3, 10, 17))
check("nothing drawn outside the panel rows", lit_rows(a),
      [3, 4, 5, 6, 7, 10, 11, 12, 13, 14, 17, 18, 19, 20, 21])
check("game-over text unchanged", text_at(pix, 5, 8, "Juego Terminado!"),
      "Juego Terminado!")
check("game-over text is yellow", a[5 * 32 + 8], ROTULO)
check("best-score label", text_at(pix, 12, 4, "MEJOR PUNTUACION"),
      "MEJOR PUNTUACION")
check("best-score value renders (second read site)",
      text_at(pix, 12, 22, "099980"), "099980")
check("restart text unchanged",
      text_at(pix, 19, 3, "Reiniciar el juego (S/N)?"),
      "Reiniciar el juego (S/N)?")
check("restart text is white", a[19 * 32 + 3], TEXTO)
check("flashing cursor cell after the prompt", a[19 * 32 + 28], CURSOR)
check("variables untouched by the render", variables(), before)
check("MEJOR is read, never written", get_bcd("MEJOR"), "099980")

print("\npintar_gracias -- one centred panel")
before = variables()
a, pix = render("pintar_gracias")
check("one panel at row 9", cells_equal(a, MARCO), frame_cells(9))
check("nothing drawn outside the panel rows", lit_rows(a), [9, 10, 11, 12, 13])
check("thank-you text unchanged", text_at(pix, 11, 7, "Gracias por jugar"),
      "Gracias por jugar")
check("thank-you text is yellow", a[11 * 32 + 7], ROTULO)
check("variables untouched by the render", variables(), before)

print("\nActualizarMejor -- the one and only writer of MEJOR")
cases = [
    # (best before, score, best after, why)
    ("000000", "001234", "001234", "first score of the session"),
    ("001234", "000500", "001234", "a worse game does not overwrite"),
    ("001234", "001234", "001234", "an exact tie changes nothing"),
    ("009999", "010000", "010000", "carry into the top pair"),
    ("010000", "009999", "010000", "top pair decides against a big low pair"),
    ("010000", "010001", "010001", "only the low pair differs"),
    ("012300", "012299", "012300", "only the middle pair differs"),
]
for best, score, want, why in cases:
    set_bcd("MEJOR", best)
    set_bcd("PUNTOS", score)
    u.call("ActualizarMejor", limit=4000)
    check(f"{best} vs {score} -> {why}", get_bcd("MEJOR"), want)
    check(f"{best} vs {score}: PUNTOS untouched", get_bcd("PUNTOS"), score)

print("\nthe two read sites agree")
set_bcd("MEJOR", "000000")
set_bcd("PUNTOS", "004500")
u.call("ActualizarMejor", limit=4000)
_, pix_final = render("pintar_final")
_, pix_ini = render("pintar_ini")
check("game-over screen shows the new best",
      text_at(pix_final, 12, 22, "004500"), "004500")
check("pre-game screen shows the same number",
      text_at(pix_ini, 10, 22, "004500"), "004500")

u.close()
print("\n" + ("ALL PASS" if not fails else f"FAILURES: {fails}"))
