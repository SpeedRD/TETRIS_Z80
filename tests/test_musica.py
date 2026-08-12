#!/usr/bin/env python3
"""musica.asm: the note table, the melody, the driver's cost, and the hook.

WHAT THIS SUITE CANNOT DO: it cannot tell you whether the music is in tune or
whether it sounds like Korobeiniki. It measures T-states and compares bytes.
A half-period of 3968 T is 441.03 Hz whatever it sounds like through a speaker,
and nothing here proves the ULA is wired to one. Pitch and tune were confirmed
by a human listening to ZEsarUX; that confirmation is not automatable and is not
claimed below. What IS covered:

  * the note table really is what the two driver formulas say it should be,
    byte for byte, and every entry fits the 48,000 T budget;
  * the driver's MEASURED cost, for every note in the table, stays under budget
    -- worst case, not on average (MUSIC_DESIGN.md 7 rule 3);
  * musica_silencio is set on frames that clear lines and clear on every other
    frame, checked against LINEAS in a real running game;
  * the driver preserves the piece registers and never executes DI or EI.

The cost measurements use `cpu-step-over`, not `run N`. `run N` executes N
opcodes come what may, so the CPU spins on the DI/JR-$ trap for the remainder
and every note measures the same ~480,000 T -- the opcode limit, not the code.
"""
import math
import os
import re
import time

from tetris import BIN, matrix
from unit import Unit

CPU = 3_500_000
BUDGET = 48_000            # MUSIC_DESIGN.md 5: the tone fill's allowance
FRAME = 69_888             # a 48K frame
JUEGO_WORST = 8_366        # MUSIC_DESIGN.md 2: worst normal play, ROM ISR in

# Hand-counted from the two loops in musica.asm and confirmed by measurement.
# Deliberately NOT MUSIC_DESIGN.md 4.1's 51.81/75.55: those describe an external
# benchmark that was never in the tree, and these loops are shorter. See the
# header of musica.asm and MUSIC_DESIGN.md 4.5.
AGUDO_FIX, AGUDO_STEP = 33, 13      # mus_agudo, DJNZ delay
GRAVE_FIX, GRAVE_STEP = 42, 26      # mus_grave, 16-bit delay

NOTA_SIL, NOTA_FIN = 0xFE, 0xFF
LOW_MIDI = 57                       # table entry 0 is A3
N_NOTES = 28                        # A3..C6 chromatic
NAMES = ("A3 A#3 B3 C4 C#4 D4 D#4 E4 F4 F#4 G4 G#4 A4 A#4 B4 "
         "C5 C#5 D5 D#5 E5 F5 F#5 G5 G#5 A5 A#5 B5 C6").split()

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

u = Unit()
L = u.L
fails = []


def check(name, ok, detail=""):
    print(f"  {'ok  ' if ok else 'FAIL'} {name}{'  ' + detail if detail else ''}")
    if not ok:
        fails.append(name)


def half_period(drv, const):
    return (AGUDO_FIX + AGUDO_STEP * const) if drv else \
           (GRAVE_FIX + GRAVE_STEP * const)


def target_hz(i):
    return 440.0 * 2 ** ((LOW_MIDI + i - 69) / 12)


def cents(hz, i):
    return 1200 * math.log2(hz / target_hz(i))


def expected_entry(i):
    """Re-derive one table row from the formulas alone -- the same arithmetic
    that generated it, written out independently."""
    want = CPU / (2 * target_hz(i))                 # ideal half-period, T
    c = round((want - AGUDO_FIX) / AGUDO_STEP)
    if 1 <= c <= 255:
        drv, const = 1, c                           # DJNZ: finer, 13 T steps
    else:
        drv, const = 0, round((want - GRAVE_FIX) / GRAVE_STEP)
    return drv, const, BUDGET // half_period(drv, const)


# ---------------------------------------------------------------------------
print("the note table is what the two formulas say (28 entries x 4 bytes)")
tab = u.peek(L["tabla_notas"], N_NOTES * 4)

wrong, over, worst_c, worst_fill = [], [], 0.0, 0
for i, nm in enumerate(NAMES):
    drv, lo, hi, cnt = tab[i * 4:i * 4 + 4]
    const = lo | hi << 8
    e_drv, e_const, e_cnt = expected_entry(i)
    if (drv, const, cnt) != (e_drv, e_const, e_cnt):
        wrong.append(f"{nm}: got {(drv, const, cnt)} want {(e_drv, e_const, e_cnt)}")
    hp = half_period(drv, const)
    fill = cnt * hp - 5                # N half-periods end on a not-taken branch
    worst_fill = max(worst_fill, fill)
    worst_c = max(worst_c, abs(cents(CPU / (2 * hp), i)))
    if fill > BUDGET:
        over.append(f"{nm}={fill}")

check("every entry matches the formulas byte for byte", wrong == [],
      f"({len(wrong)} wrong)" + ("  " + "; ".join(wrong[:3]) if wrong else ""))
check("no entry's tone fill exceeds the 48,000 T budget", over == [],
      f"(worst {worst_fill} T)" + ("  " + ", ".join(over) if over else ""))

# The DJNZ delay is one byte wide and the 16-bit one must never be zero: a zero
# HL wraps to 65536 iterations, 1.7 million T-states, a frame and a half of one
# note. A zero DJNZ constant means 256 iterations, which merely detunes.
bad_range = []
for i, nm in enumerate(NAMES):
    drv, lo, hi, cnt = tab[i * 4:i * 4 + 4]
    const = lo | hi << 8
    if drv not in (0, 1):
        bad_range.append(f"{nm}: selector {drv}")
    if drv and (hi != 0 or not 1 <= lo <= 255):
        bad_range.append(f"{nm}: DJNZ const {const} does not fit a byte")
    if not drv and const < 1:
        bad_range.append(f"{nm}: 16-bit const {const} would wrap to 65536")
    if cnt < 1:
        bad_range.append(f"{nm}: count {cnt}")
check("delay constants are in range for their driver", bad_range == [],
      f"({len(bad_range)} bad)" + ("  " + "; ".join(bad_range[:3]) if bad_range else ""))

# The split between the two drivers is a consequence, not a hand-written column.
split = [(NAMES[i], tab[i * 4]) for i in range(N_NOTES)]
grave = [n for n, d in split if not d]
agudo = [n for n, d in split if d]
check("the driver split falls where MUSIC_DESIGN 4.1 puts it",
      grave[-1] == "B4" and agudo[0] == "C5",
      f"(16-bit {grave[0]}..{grave[-1]}, DJNZ {agudo[0]}..{agudo[-1]})")

# Not a tuning claim -- a bound. This says the arithmetic did not slip a
# semitone, not that the result sounds right.
check("every entry lands within 6 cents of equal temperament", worst_c < 6.0,
      f"(worst {worst_c:.2f} cents)")

# ---------------------------------------------------------------------------
print("\nthe melody is well formed")
mel = u.peek(L["melodia"], 256)
end = mel.index(NOTA_FIN) if NOTA_FIN in mel else -1
check("terminated by NOTA_FIN", end > 0 and end % 2 == 0,
      f"(at offset {end}, {end // 2} notes)")

pairs = [(mel[i], mel[i + 1]) for i in range(0, end, 2)]
bad_note = [f"{n}" for n, _ in pairs if not (n < N_NOTES or n == NOTA_SIL)]
check("every note index is in the table (or NOTA_SIL)", bad_note == [],
      f"({len(bad_note)} bad)")
# Duration 1 would be swallowed whole by the articulation gap: the driver
# always silences a note's last frame, so a 1-frame note never sounds.
bad_dur = [d for _, d in pairs if d < 2]
check("no duration is 0 or 1 (the last frame is the articulation gap)",
      bad_dur == [], f"({len(bad_dur)} bad)")
# A sentinel sitting in a duration slot means the pairs are off by one -- a
# "DB N_E5" written without its duration shifts every byte after it, turning
# notes into durations. The bar-sum check below is the general guard for that;
# this one names the specific way it happens.
stray = [i for i, (_, d) in enumerate(pairs) if d in (NOTA_SIL, NOTA_FIN)]
check("no sentinel byte landed in a duration slot", stray == [],
      f"(pairs {stray} -- the table is misaligned)")

total = sum(d for _, d in pairs)
cum = set()
run = 0
for _, d in pairs:
    run += d
    cum.add(run)
bars = total // 80
check("bars are 80 frames and no note straddles a bar line",
      total % 80 == 0 and all(b * 80 in cum for b in range(1, bars + 1)),
      f"({bars} bars, {total} frames, {total / 50.08:.1f} s per loop)")

# ---------------------------------------------------------------------------
print("\nthe driver never disables interrupts (MUSIC_DESIGN 7 rule 2)")
# Checked in the source, not the opcodes: a byte scan would trip over jump
# displacements -- "jr nz, mg_espera" assembles to 20 FB, and $FB is EI.
src = open(os.path.join(REPO, "musica.asm"), encoding="utf8").read()
stripped = "\n".join(l.split(";")[0] for l in src.splitlines())
di_ei = re.findall(r"(?im)^\s*(di|ei)\s*(?:$|:)", stripped)
check("musica.asm contains no DI and no EI", di_ei == [], f"({di_ei})")
# It also must not touch IY, or it would need a bracket of its own.
check("musica.asm never writes IY",
      not re.search(r"(?im)^\s*ld\s+iy\s*,", stripped))

# ---------------------------------------------------------------------------
print("\nmeasured cost of musica_frame, every note in the table")
CALL_SITE = 0xFE20
mf = L["musica_frame"]
u.poke(CALL_SITE, [0xCD, mf & 0xFF, mf >> 8])


def cost(nota, frames, silencio, tries=3):
    """One musica_frame call, in T-states, measured over a real CALL.

    Sampled `tries` times and the SMALLEST kept. The emulator is stopped
    between ZRCP commands, so nothing can make a call measure *short* -- but a
    sample can come out long, by ULA I/O contention on the OUTs and by
    cpu-step-over occasionally being read a beat late (which once put a single
    note 900 T over its neighbours). The minimum is the uncontended truth; the
    inflation is what the 13,000 T of frame slack is there to absorb anyway.
    """
    u.poke(L["musica_nota"], [nota & 0xFF])
    u.poke(L["musica_frames"], [frames])
    u.poke(L["musica_silencio"], [silencio])
    best = None
    for _ in range(tries):
        u.z.cmd("set-register SP=FF00H")
        u.z.cmd(f"set-register PC={CALL_SITE:04X}H")
        u.z.cmd("reset-tstates-partial")
        u.z.cmd("cpu-step-over")
        # Read PC first: in step mode the CPU is stopped between commands, so
        # confirming the call finished costs no T-states and cannot perturb the
        # counter we are about to sample.
        pc = u.regs().get("PC")
        if pc != CALL_SITE + 3:
            raise AssertionError(f"musica_frame did not return (PC={pc:04X})")
        raw = u.z.cmd("get-tstates-partial").strip().split()
        if not raw or not raw[-1].isdigit():
            continue                                # flaky response: resample
        t = int(raw[-1]) - 17                       # the CALL itself
        best = t if best is None else min(best, t)
    if best is None:
        raise AssertionError("get-tstates-partial never returned a number")
    return best


# frames=5 keeps every note off both the reload path and the articulation frame,
# so what is measured is one full tone fill plus the fixed management cost.
measured = {nm: cost(i, 5, 0) for i, nm in enumerate(NAMES)}
worst_nm = max(measured, key=measured.get)
worst = measured[worst_nm]
# The frame gate is the real ceiling: the pass must reach HALT before the next
# 50 Hz interrupt, so worst game pass + music must fit one frame.
ceiling = FRAME - JUEGO_WORST
check("every note's whole call fits beside the worst game pass in one frame",
      worst < ceiling,
      f"(worst {worst} T in {worst_nm}, ceiling {ceiling} T, "
      f"{ceiling - worst} T spare)")
# And the fill itself -- the part the budget is written about -- stays inside it.
# The gap between call and fill is the driver's own bookkeeping.
fills = {nm: (lambda d, lo, hi, c: c * half_period(d, lo | hi << 8) - 5)
         (*tab[i * 4:i * 4 + 4]) for i, nm in enumerate(NAMES)}
mgmt = {nm: measured[nm] - fills[nm] for nm in NAMES}
# This is what says the two formulas describe the code rather than merely
# bounding it: subtract the modelled fill from the measured call and what is
# left must be the driver's own bookkeeping -- 362 T, hand-counted from
# musica_frame's opcodes. Asserted on the MINIMUM across the table, because
# contention can only push a sample up (see cost()); and on the floor of every
# note, because a note measuring *below* fill + bookkeeping would mean the model
# overstates that note's tone and the pitch in the table is not what plays.
check("subtracting the modelled fill leaves the hand-counted 362 T of bookkeeping",
      350 <= min(mgmt.values()) <= 380,
      f"(min {min(mgmt.values())} T, max {max(mgmt.values())} T)")
check("no note measures below its modelled fill plus bookkeeping",
      min(mgmt.values()) >= 300,
      f"(lowest {min(mgmt, key=mgmt.get)} at {min(mgmt.values())} T)")
check("worst tone fill is inside the 48,000 T budget", max(fills.values()) <= BUDGET,
      f"({max(fills.values())} T in {max(fills, key=fills.get)})")

print("\ncheap frames stay cheap")
muted = cost(19, 5, 3)
check("a frame muted by limpiar_lineas emits nothing", muted < 400, f"({muted} T)")
check("musica_frame always clears musica_silencio",
      u.peek(L["musica_silencio"], 1)[0] == 0)
rest = cost(NOTA_SIL, 5, 0)
check("a NOTA_SIL rest emits nothing", rest < 400, f"({rest} T)")
artic = cost(19, 1, 0)
check("a note's last frame is the articulation gap", artic < 400, f"({artic} T)")
reload_ = cost(19, 0, 0)
check("the frame that loads the next note still fits", reload_ < ceiling,
      f"({reload_} T)")

print("\nthe driver keeps the piece (register-protocol)")
u.poke(L["musica_nota"], [19])
u.poke(L["musica_frames"], [5])
u.poke(L["musica_silencio"], [0])
r = u.call("musica_frame",
           regs={"BC": 0x0A0F, "DE": 0x1234, "HL": 0x5678,
                 "IX": 0xA16A, "IY": 0x5C3A, "AF": 0x4200})
for nm, want in (("BC", 0x0A0F), ("DE", 0x1234), ("HL", 0x5678),
                 ("IX", 0xA16A), ("IY", 0x5C3A)):
    check(f"preserves {nm}", r.get(nm) == want,
          f"(got {r.get(nm):04X}, want {want:04X})")
check("preserves A", r["AF"] >> 8 == 0x42, f"(got {r['AF'] >> 8:02X})")

# ---------------------------------------------------------------------------
print("\nthe juego.asm hook is where MUSIC_DESIGN 7 rule 1 puts it")
img = open(os.path.join(REPO, "main.bin"), "rb").read()


def at(addr, n):
    return img[addr - 0x8000:addr - 0x8000 + n]


def call_to(label):
    return bytes([0xCD, L[label] & 0xFF, L[label] >> 8])


# The fill goes AFTER the render: erase/redraw must stay in the border window.
check("dibujar renders first, then calls musica_frame",
      at(L["dibujar"], 3) == call_to("pintar_tetromino")
      and at(L["dibujar"] + 3, 3) == call_to("musica_frame"),
      f"(at {L['dibujar'] + 3:04X})")
# ...and nothing else was inserted between the render and the loop-back.
check("nothing sits between the music call and JP paso",
      at(L["dibujar"] + 6, 1) == b"\xc3")

# The flag is taken straight from limpiar_lineas' return value, before
# anotar_lineas consumes the same A. LD (nn),A touches neither A nor the flags.
seq = (call_to("limpiar_lineas")
       + bytes([0x32, L["musica_silencio"] & 0xFF, L["musica_silencio"] >> 8])
       + call_to("anotar_lineas"))
check("limpiar_lineas -> LD (musica_silencio),A -> anotar_lineas, adjacent",
      img.count(seq) == 1, f"({img.count(seq)} occurrences)")

# ---------------------------------------------------------------------------
# A game over does not clear RAM -- Pantalla_Final does `jp inicializar`, which
# only re-sets SP -- so the melody used to carry straight over into the next
# game and start mid-phrase. reiniciar_marcador is the one per-game reset point
# (memory-map 6a), and it now rewinds the player. Note mus_cargar is NOT what
# does this: it ADVANCES the melody, so calling it here would eat a note per
# game instead of rewinding, and would leave musica_silencio alone.
print("\nmusica_reiniciar rewinds the player from any prior state")
MELODIA = L["melodia"]
INITIAL = {"musica_puntero": MELODIA, "musica_nota": NOTA_SIL,
           "musica_frames": 0, "musica_silencio": 0}


def music_state():
    p = u.peek(L["musica_puntero"], 2)
    return {"musica_puntero": p[0] | p[1] << 8,
            "musica_nota": u.peek(L["musica_nota"], 1)[0],
            "musica_frames": u.peek(L["musica_frames"], 1)[0],
            "musica_silencio": u.peek(L["musica_silencio"], 1)[0]}


def scramble():
    """Mid-melody, mid-note, with a mute flag pending -- i.e. what a game that
    just ended on a line clear actually leaves behind."""
    deep = MELODIA + 40
    u.poke(L["musica_puntero"], [deep & 0xFF, deep >> 8])
    u.poke(L["musica_nota"], [24])          # A5, nothing like the initial rest
    u.poke(L["musica_frames"], [33])
    u.poke(L["musica_silencio"], [4])


def diff_from_initial(got):
    return {k: (got[k], INITIAL[k]) for k in INITIAL if got[k] != INITIAL[k]}


scramble()
before = music_state()
check("the scrambled state really is different to start with",
      len(diff_from_initial(before)) == 4, f"({before})")
u.call("musica_reiniciar")
d = diff_from_initial(music_state())
check("musica_reiniciar restores all four to their initial values", d == {},
      "(all back to initial)" if not d else f"(got/want {d})")

# Idempotent, and correct from the already-initial state too.
u.call("musica_reiniciar")
check("musica_reiniciar is idempotent", diff_from_initial(music_state()) == {})

r = u.call("musica_reiniciar",
           regs={"BC": 0x0A0F, "DE": 0x1234, "HL": 0x5678,
                 "IX": 0xA16A, "IY": 0x5C3A, "AF": 0x4200})
check("musica_reiniciar preserves every register",
      (r.get("BC"), r.get("DE"), r.get("HL"), r.get("IX"), r.get("IY"),
       r["AF"] >> 8) == (0x0A0F, 0x1234, 0x5678, 0xA16A, 0x5C3A, 0x42))

print("\nthe new-game reset point drives it -- and still spares MEJOR")
# reiniciar_marcador is what iniciar calls at the top of every game.
scramble()
u.poke(L["PUNTOS"], [0x12, 0x34, 0x56])
u.poke(L["LINEAS"], [7])
u.poke(L["NIVEL"], [3])
u.poke(L["MEJOR"], [0x99, 0x88, 0x77])      # a session best worth protecting
u.call("reiniciar_marcador", limit=400000)
check("reiniciar_marcador resets all four music variables",
      diff_from_initial(music_state()) == {},
      f"({diff_from_initial(music_state()) or 'all initial'})")
check("...and really did run (score and lines zeroed)",
      list(u.peek(L["PUNTOS"], 3)) == [0, 0, 0]
      and u.peek(L["LINEAS"], 1)[0] == 0 and u.peek(L["NIVEL"], 1)[0] == 0)
# The whole point of MEJOR is that it survives this. Asserted here rather than
# only in test_pantallas, because this edit added a writer to the routine.
check("...and did NOT touch MEJOR", list(u.peek(L["MEJOR"], 3)) == [0x99, 0x88, 0x77],
      f"(MEJOR = {u.peek(L['MEJOR'], 3).hex(' ')})")

# Static: the call is inside reiniciar_marcador, not bolted onto a call site,
# so a future third reset point cannot forget it (memory-map 6a).
img_now = open(os.path.join(REPO, "main.bin"), "rb").read()
check("the call lives inside reiniciar_marcador",
      bytes([0xCD, L["musica_reiniciar"] & 0xFF, L["musica_reiniciar"] >> 8])
      in img_now[L["reiniciar_marcador"] - 0x8000:
                 L["reiniciar_marcador"] - 0x8000 + 64])

# ---------------------------------------------------------------------------
# Live game: the flag must be non-zero exactly on the frames that cleared rows.
# A stub spliced over the CALL logs the flag as the hook sees it, then tail-jumps
# into the real musica_frame, so the game (and the music) runs normally.
print("\nlive game: musica_silencio tracks limpiar_lineas frame by frame")
LOGP, LOG, STUB = 0xFE00, 0xF000, 0xFE30
sil = L["musica_silencio"]
STUB_CODE = [0xF5, 0xE5,                               # push af : push hl
             0x3A, sil & 0xFF, sil >> 8,               # ld a,(musica_silencio)
             0x2A, LOGP & 0xFF, LOGP >> 8,             # ld hl,(LOGP)
             0x77, 0x23,                               # ld (hl),a : inc hl
             0x22, LOGP & 0xFF, LOGP >> 8,             # ld (LOGP),hl
             0xE1, 0xF1,                               # pop hl : pop af
             0xC3, mf & 0xFF, mf >> 8]                 # jp musica_frame


def keys(*names):
    u.z.cmd(f"set-ui-io-ports {matrix(list(names))}")


def tap(name, ms=200):
    keys(name); time.sleep(ms / 1000); keys(); time.sleep(0.15)


def start_game():
    keys()
    u.z.cmd("enter-cpu-step")
    u.z.cmd("hard-reset-cpu")
    u.z.cmd(f'load-binary "{BIN}" 8000H 0')
    u.z.cmd("set-register PC=8000H")
    u.z.cmd("exit-cpu-step")
    time.sleep(1.2)
    tap("Q", 250); time.sleep(0.7)
    tap("S", 250); time.sleep(0.9)
    # Splice the logger in AFTER load-binary, which would overwrite the CALL.
    u.z.cmd("enter-cpu-step")
    u.poke(STUB, STUB_CODE)
    u.poke(L["dibujar"] + 3, [0xCD, STUB & 0xFF, STUB >> 8])
    u.poke(LOGP, [LOG & 0xFF, LOG >> 8])
    u.z.cmd(f"write-memory-raw {L['FRAMES_POR_FILA']:04X}H 03")
    u.z.cmd(f"write-memory-raw {L['contador_frames']:04X}H 03")
    u.z.cmd("exit-cpu-step")


def read_log():
    p = u.peek(LOGP, 2)
    n = (p[0] | p[1] << 8) - LOG
    return list(u.peek(LOG, n)) if n > 0 else []


def lineas():
    return u.peek(L["LINEAS"], 1)[0]


# -- negative control: a game with no clears must log nothing but zeros -------
start_game()
time.sleep(4.0)
log, lin = read_log(), lineas()
check("a game with no line clears logs only zeros",
      log and set(log) == {0} and lin == 0,
      f"({len(log)} frames logged, LINEAS={lin})")

# -- positive: pre-fill two rows, so the next lock clears both ----------------
# The piece does not have to complete the row itself: limpiar_lineas runs on
# every lock and scans the whole well, so two pre-filled rows go on the next one.
before = lineas()
u.poke(LOGP, [LOG & 0xFF, LOG >> 8])
for row in (20, 21):
    u.poke(0x5800 + row * 32 + 7, [0x10] * 18)
time.sleep(4.0)
log, after = read_log(), lineas()
cleared = (after - before) & 0xFF
nonzero = [(i, v) for i, v in enumerate(log) if v]

check("some frame was flagged, and LINEAS moved", nonzero and cleared,
      f"(LINEAS {before} -> {after}, flags {[v for _, v in nonzero]})")
# The flag carries the row COUNT, and anotar_lineas adds that same count to
# LINEAS. So the flags must sum to exactly the rows cleared -- which also proves
# the flag never sticks: a flag left set would be logged again next frame.
check("the flags sum to exactly the rows cleared",
      sum(v for _, v in nonzero) == cleared,
      f"(flags sum {sum(v for _, v in nonzero)}, LINEAS moved {cleared})")
check("every other frame is clear", len(nonzero) <= cleared,
      f"({len(nonzero)} flagged frames of {len(log)})")
check("a double clear reports 2 on one frame", 2 in [v for _, v in nonzero],
      f"(flags {[v for _, v in nonzero]})")

keys()
u.close()
print("\n" + ("ALL PASS" if not fails else f"FAILURES: {fails}"))
