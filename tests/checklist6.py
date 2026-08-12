#!/usr/bin/env python3
"""build-and-verify section 6: the full manual checklist, driven end to end."""
import time
from tetris import Z, matrix, resolve, BIN

WALL = 0x37
z = Z()
fails = []


def check(n, ok, detail=""):
    print(f"  {'ok  ' if ok else 'FAIL'} {n}{'  ' + detail if detail else ''}")
    if not ok:
        fails.append(n)


def keys(*names):
    z.cmd(f"set-ui-io-ports {matrix(list(names))}")


def tap(name, ms=140):
    keys(name); time.sleep(ms / 1000); keys(); time.sleep(0.10)


def attrs():
    return z.read_mem(0x5800, 768)


def pixels_nonblank():
    return sum(1 for b in z.read_mem(0x4000, 6144) if b)


def borders_ok(a):
    bad = []
    for r in range(22):
        if a[r * 32 + 6] != WALL:
            bad.append(("left", r))
        if a[r * 32 + 25] != WALL:
            bad.append(("right", r))
    for c in range(6, 26):
        if a[22 * 32 + c] != WALL:
            bad.append(("floor", c))
    return bad


def cells_in_well(a):
    return [(i // 32, i % 32) for i, v in enumerate(a)
            if v and 7 <= i % 32 <= 24 and i // 32 <= 21]


def outside_junk(a):
    """Anything drawn left of the well, or below the floor."""
    out = []
    for i, v in enumerate(a):
        r, c = i // 32, i % 32
        if not v:
            continue
        if c < 6 or (r == 23):
            out.append((r, c))
    return out


def boot():
    z.cmd("enter-cpu-step"); z.cmd("hard-reset-cpu")
    z.cmd(f'load-binary "{BIN}" 8000H 0')
    z.cmd("set-register PC=8000H"); z.cmd("exit-cpu-step")


print("build-and-verify section 6 -- final pass\n")
keys()
boot(); time.sleep(1.2)

# 1 -----------------------------------------------------------------
check("1. title picture fills the screen", pixels_nonblank() > 3000,
      f"({pixels_nonblank()} non-blank pixel bytes)")

# 2 -----------------------------------------------------------------
tap("Q", 250); time.sleep(0.7)
a = attrs()
check("2. Q dismisses the title screen", pixels_nonblank() < 3000)

# 3 -----------------------------------------------------------------
txt = sum(1 for v in a if v)
check("3. start menu is drawn", txt > 40, f"({txt} attribute cells lit)")

# 4 -----------------------------------------------------------------
# The thank-you screen is now one bordered panel (rows 9-13) in the same
# visual language as the scoreboard: a frame of attribute-55 cells -- the
# same byte the well border uses -- around yellow text. It used to be bare
# cyan text with no frame.
tap("N", 250); time.sleep(0.8)
a = attrs()
lit_rows = sorted({i // 32 for i, v in enumerate(a) if v})
frame_top = [a[9 * 32 + c] for c in range(32)]
frame_bot = [a[13 * 32 + c] for c in range(32)]
sides = [a[r * 32 + c] for r in (10, 11, 12) for c in (0, 31)]
text = [v for i, v in enumerate(a) if v and 1 <= i % 32 <= 30 and i // 32 == 11]
check("4. N quits to the thank-you screen",
      lit_rows == [9, 10, 11, 12, 13]
      and frame_top == [WALL] * 32 and frame_bot == [WALL] * 32
      and sides == [WALL] * 6
      and len(text) == len("Gracias por jugar")
      and all(v & 7 == 6 for v in text),
      f"(panel rows {lit_rows}, {len(text)} cells of yellow text)")

# 5 -----------------------------------------------------------------
boot(); time.sleep(1.0); tap("Q", 250); time.sleep(0.6)
tap("S", 250); time.sleep(0.8)
a = attrs()
check("5. the well is drawn with intact borders", borders_ok(a) == [],
      f"({len(borders_ok(a))} bad border cells)")

# 6 -----------------------------------------------------------------
r0 = z.cmd("get-registers"); row0 = int(r0.split("BC=")[1][:2], 16)
time.sleep(2.2)
r1 = z.cmd("get-registers"); row1 = int(r1.split("BC=")[1][:2], 16)
check("6. a piece appears and descends on its own", row1 > row0,
      f"(row {row0} -> {row1})")

# 7 -----------------------------------------------------------------
def col():
    return int(z.cmd("get-registers").split("BC=")[1][2:4], 16)

c0 = col()
for _ in range(3):
    tap("J", 60)
cJ = col()
for _ in range(3):
    tap("K", 60)
cK = col()
check("7. J moves left and K moves right", cJ < c0 and cK > cJ,
      f"(column {c0} -> {cJ} -> {cK})")

# 8 -----------------------------------------------------------------
def ix():
    return int(z.cmd("get-registers").split("IX=")[1][:4], 16)

# T_0 (the O-piece) is rotationally symmetric and its record points at
# itself both ways (piezas.asm: "T_0: ... DW T_0, T_0"), so if the O-piece
# happens to be the one on screen, IX legitimately does not move when Q/W
# is pressed -- that is correct 4-fold-symmetry behaviour, not a failed
# rotation. Only require i1 != i0 when a different piece spawned.
T_0 = resolve("T_0")
i0 = ix(); tap("Q", 60); i1 = ix(); tap("W", 60); i2 = ix()
check("8. Q and W rotate the piece", (i0 == T_0 or i1 != i0) and i2 == i0,
      f"(IX {i0:04X} -> {i1:04X} -> {i2:04X}, and back)")

# 8b-8d: soft drop (SPACE) -- still on the default, unmodified gravity speed
# (the FRAMES_POR_FILA poke for tests 9/10 happens further down), so a
# genuine speed difference is unmistakable: default level 0 is 48
# frames/row (~0.96 s/row); FRAMES_CAIDA_RAPIDA is 4 (~0.08 s/row).
def row():
    return int(z.cmd("get-registers").split("BC=")[1][:2], 16)

r0 = row(); time.sleep(1.0); r1 = row()
baseline_rows = r1 - r0
check("8b. baseline gravity with SPACE not held", baseline_rows <= 2,
      f"({baseline_rows} rows in 1.0s)")

keys("SPACE")                       # hold SPACE, do not release yet
r0 = row(); time.sleep(0.5); r1 = row()
held_rows = r1 - r0
check("8c. holding SPACE falls faster than normal gravity",
      held_rows > baseline_rows and held_rows >= 3,
      f"({held_rows} rows in 0.5s held vs {baseline_rows} rows in 1.0s baseline)")

keys()                               # release SPACE
r0 = row(); time.sleep(1.0); r1 = row()
after_rows = r1 - r0
check("8d. releasing SPACE returns to normal gravity immediately",
      after_rows <= 2, f"({after_rows} rows in 1.0s right after release)")

# 8e-8f: a movement/rotation key pressed AT THE SAME TIME as SPACE must
# still register. Each burst holds SPACE only for the tap itself (not
# continuously across both sub-checks) so the fast gravity it triggers
# cannot run long enough to lock the piece mid-check and confuse the result.
c0 = col()
keys("SPACE", "J"); time.sleep(0.06); keys(); time.sleep(0.10)
c1 = col()
keys("SPACE", "K"); time.sleep(0.06); keys(); time.sleep(0.10)
c2 = col()
check("8e. J/K still move the piece sideways while SPACE is held",
      c1 < c0 and c2 > c1, f"(column {c0} -> {c1} -> {c2})")

i0b = ix()
keys("SPACE", "Q"); time.sleep(0.06); keys(); time.sleep(0.10)
i1b = ix()
keys("SPACE", "W"); time.sleep(0.06); keys(); time.sleep(0.10)
i2b = ix()
# Same O-piece exception as check 8 above: T_0 points at itself both ways,
# so no IX change is the correct outcome when the O-piece is on screen.
check("8f. Q/W still rotate the piece while SPACE is held",
      (i0b == T_0 or i1b != i0b) and i2b == i0b,
      f"(IX {i0b:04X} -> {i1b:04X} -> {i2b:04X}, and back)")

# 9 & 10 -------------------------------------------------------------
z.cmd(f"write-memory-raw {resolve('FRAMES_POR_FILA'):04X}H 03")
z.cmd(f"write-memory-raw {resolve('contador_frames'):04X}H 03")
settled_seen = 0
worst_border = []
junk = []
games = 0
samples = 0
t_end = time.time() + 30
last = -1
while time.time() < t_end:
    # nudge the pieces around so they do not just stack in one column
    tap("K", 40); tap("Q", 40); tap("J", 40)
    a = attrs()
    bad = borders_ok(a)
    # A game-over screen CLEARS the display, so every border cell reads bad at
    # once. Real erosion chips away one or two cells. Tell them apart, restart,
    # and only judge the border while a game is actually on screen.
    if len(bad) > 20:
        games += 1
        tap("S", 250); time.sleep(0.8)      # game over -> restart menu
        tap("S", 250); time.sleep(0.8)      # menu -> new game
        z.cmd(f"write-memory-raw {resolve('FRAMES_POR_FILA'):04X}H 03")
        z.cmd(f"write-memory-raw {resolve('contador_frames'):04X}H 03")
        last = -1
        continue
    samples += 1
    worst_border += bad
    junk += outside_junk(a)
    n = len(cells_in_well(a))
    if n > last:
        settled_seen = max(settled_seen, n)
    last = n
a = attrs()
print(f"       ({samples} in-play samples across {games + 1} game(s))")
check("9. pieces settle and new ones keep spawning", settled_seen >= 8,
      f"(peak {settled_seen} occupied cells in the well)")
check("10. borders stay unbroken through sustained play",
      worst_border == [], f"({len(worst_border)} bad border samples)")
check("10b. nothing is ever drawn outside the well",
      junk == [], f"({len(junk)} stray cells)")

keys()
z.cmd("exit")
print("\n" + ("SECTION 6: ALL PASS" if not fails else f"FAILURES: {fails}"))
